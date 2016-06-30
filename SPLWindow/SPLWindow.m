//
//  SPLWindow.m
//
//  The MIT License (MIT)
//  Copyright (c) 2014 Oliver Letterer, Sparrow-Labs
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

#import <SPLWindow.h>
#import <SPLWindowTouchIndicator.h>
#import <SPLWindowAnnotateScreenshotViewController.h>

#import <objc/message.h>
#import <MessageUI/MessageUI.h>
#import <AVFoundation/AVFoundation.h>
#import <ReplayKit/ReplayKit.h>

#include <dlfcn.h>

@interface FBTweakStore : NSObject
+ (instancetype)sharedInstance;
@end

@interface FBTweakViewController : UINavigationController
- (instancetype)initWithStore:(FBTweakStore *)store;
@end

static CGFloat recordIndicatorSize = 14.0;

@interface SPLWindowScreenCaptureButton : UIControl

@property (nonatomic, assign) CFTimeInterval videoDuration;
@property (nonatomic, strong) UIView *recordIndicator;

@end

@implementation SPLWindowScreenCaptureButton

- (void)setVideoDuration:(CFTimeInterval)videoDuration
{
    if (videoDuration != _videoDuration) {
        _videoDuration = videoDuration;
        [self setNeedsDisplay];
    }
}

- (instancetype)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
        self.layer.needsDisplayOnBoundsChange = YES;
        self.backgroundColor = [UIColor clearColor];

        _recordIndicator = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, recordIndicatorSize, recordIndicatorSize)];
        _recordIndicator.backgroundColor = [UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:0.5];
        _recordIndicator.layer.cornerRadius = recordIndicatorSize / 2.0;
        [self addSubview:_recordIndicator];

        CABasicAnimation *fadeAnimation = [CABasicAnimation animationWithKeyPath:@"opacity"];
        fadeAnimation.fromValue = @0.0;
        fadeAnimation.toValue = @1.0;
        fadeAnimation.autoreverses = YES;
        fadeAnimation.duration = 1.0;
        fadeAnimation.repeatDuration = CGFLOAT_MAX;
        [_recordIndicator.layer addAnimation:fadeAnimation forKey:@"opacity"];
    }
    return self;
}

- (CGSize)sizeThatFits:(CGSize)size
{
    return CGSizeMake(95.0, 34.0);
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    _recordIndicator.center = CGPointMake(14.0 + recordIndicatorSize / 2.0, CGRectGetMidY(self.bounds));
}

- (void)drawRect:(CGRect)rect
{
    CGFloat lineWidth = 1.0 / [UIScreen mainScreen].scale;
    UIBezierPath *borderPath = [UIBezierPath bezierPathWithRoundedRect:UIEdgeInsetsInsetRect(rect, UIEdgeInsetsMake(lineWidth, lineWidth, lineWidth, lineWidth))
                                                          cornerRadius:CGRectGetHeight(rect) / 2.0];
    borderPath.lineWidth = lineWidth;

    [[UIColor colorWithWhite:0.0 alpha:0.5] setFill];
    [borderPath fill];

    [[UIColor colorWithWhite:1.0 alpha:1.0] setStroke];
    [borderPath stroke];

    NSInteger minutes = floor(self.videoDuration / 60.0);
    NSInteger seconds = floor(fmod(self.videoDuration, 60.0));

    NSString *durationText = [NSString stringWithFormat:@"%02ld:%02ld", (long)minutes, (long)seconds];
    NSDictionary *attirbutes = @{
                                 NSForegroundColorAttributeName: [UIColor whiteColor],
                                 NSFontAttributeName: [UIFont boldSystemFontOfSize:17.0],
                                 };
    NSAttributedString *attributedText = [[NSAttributedString alloc] initWithString:durationText attributes:attirbutes];

    CGSize size = [attributedText size];
    CGRect frame = CGRectMake(CGRectGetMaxX(rect) - size.width - 14.0, CGRectGetMidY(rect) - size.height / 2.0 - 1.0,
                              size.width, size.height);
    [attributedText drawInRect:frame];
}

@end

static CGAffineTransform videoTransformFromInterfaceOrientation(UIInterfaceOrientation interfaceOrientation)
{
    switch (interfaceOrientation) {
        case UIInterfaceOrientationLandscapeLeft:
            return CGAffineTransformMakeRotation(M_PI_2);
            break;
        case UIInterfaceOrientationLandscapeRight:
            return CGAffineTransformMakeRotation(- M_PI_2);
            break;
#ifdef __IPHONE_8_0
        case UIInterfaceOrientationUnknown:
#endif
        case UIInterfaceOrientationPortrait:
            return CGAffineTransformIdentity;
            break;
        case UIInterfaceOrientationPortraitUpsideDown:
            return CGAffineTransformMakeRotation(M_PI);
            break;
    }
}

@interface SPLWindow () <SPLWindowAnnotateScreenshotViewControllerDelegate, MFMailComposeViewControllerDelegate, RPPreviewViewControllerDelegate>

@property (nonatomic, strong) NSMutableArray *customRageShakes;
@property (nonatomic, strong) NSMutableArray *customRageShakeHandlers;

@property (nonatomic, strong) UIImage *capturedScreenshot;
@property (nonatomic, strong) NSString *hierarchyDescription;

@property (nonatomic, assign) BOOL airPlayScreenIsConnected;
@property (nonatomic, strong) NSMapTable *touchIndicatorLookup;

@property (nonatomic, strong) UIViewController *topViewController;
@property (nonatomic, assign) BOOL isCapturingScreenshot;

@property (atomic, assign) BOOL isRecordingVideo;

@property (nonatomic, strong) NSDate *videoRecordingStartTime;
@property (nonatomic, strong) NSTimer *videoRecordingTimer;
@property (nonatomic, strong) SPLWindowScreenCaptureButton *screenCaptureButton;

@end



static BOOL tweakAvailable = NO;

@implementation SPLWindow

#pragma mark - setters and getters

- (UIViewController *)topViewController
{
    UIViewController *rootViewController = [UIApplication sharedApplication].delegate.window.rootViewController;
    while (rootViewController.presentedViewController) {
        rootViewController = rootViewController.presentedViewController;
    }

    return rootViewController;
}

- (NSMapTable *)touchIndicatorLookup
{
    if (!_touchIndicatorLookup) {
        _touchIndicatorLookup = [NSMapTable strongToStrongObjectsMapTable];
    }

    return _touchIndicatorLookup;
}

#pragma mark - Initialization

+ (void)initialize
{
    if (self != [SPLWindow class]) {
        return;
    }

    Class FBTweakViewControllerClass = NSClassFromString(@"FBTweakViewController");
    Class FBTweakStoreClass = NSClassFromString(@"FBTweakStore");

    if (FBTweakStoreClass && FBTweakViewControllerClass) {
        SEL initWithStore = NSSelectorFromString([@[ @"init", @"With", @"Store:" ] componentsJoinedByString:@""]);
        BOOL respondsToInitWithStore = class_respondsToSelector(FBTweakViewControllerClass, initWithStore);
        BOOL respondsToSharedInstance = class_respondsToSelector(objc_getMetaClass(NSStringFromClass(FBTweakStoreClass).UTF8String), @selector(sharedInstance));

        tweakAvailable = respondsToInitWithStore && respondsToSharedInstance;
    }
}

- (id)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
        for (UIScreen *screen in [UIScreen screens]) {
            if (screen.mirroredScreen) {
                _airPlayScreenIsConnected = YES;
            }
        }

        _frameInterval = 1;

        _customRageShakes = [NSMutableArray array];
        _customRageShakeHandlers = [NSMutableArray array];

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_screensDidChangeNotificationCallback:) name:UIScreenDidConnectNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_screensDidChangeNotificationCallback:) name:UIScreenDidDisconnectNotification object:nil];
    }
    return self;
}

#pragma mark - UIResponder

- (void)motionBegan:(UIEventSubtype)motion withEvent:(UIEvent *)event
{
    [super motionBegan:motion withEvent:event];

    if (self.isRecordingVideo || self.isCapturingScreenshot) {
        return;
    }

    if (self.isRageShakeEnabled && motion == UIEventSubtypeMotionShake) {
        UIGraphicsBeginImageContextWithOptions(self.bounds.size, NO, 0.0);
        [self drawViewHierarchyInRect:self.bounds afterScreenUpdates:NO];

        UIImage *screenshot = UIGraphicsGetImageFromCurrentImageContext();

        screenshot = [[UIImage alloc] initWithCGImage:screenshot.CGImage
                                                scale:[UIScreen mainScreen].scale
                                          orientation:UIImageOrientationUp];
        UIGraphicsEndImageContext();

        NSString *recursiveDescription = [self valueForKey:[@[ @"recursive", @"Description" ] componentsJoinedByString:@""]];

        self.capturedScreenshot = screenshot;
        self.hierarchyDescription = recursiveDescription;

        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Rage Shake" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"") style:UIAlertActionStyleCancel handler:nil]];

        if (tweakAvailable) {
            [alert addAction:[UIAlertAction actionWithTitle:@"Tweak" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                SEL initWithStore = NSSelectorFromString([@[ @"init", @"With", @"Store:" ] componentsJoinedByString:@""]);
                FBTweakViewController *viewController = ((id(*)(id, SEL, id))objc_msgSend)([NSClassFromString(@"FBTweakViewController") alloc], initWithStore, [NSClassFromString(@"FBTweakStore") sharedInstance]);
                [viewController setValue:self forKeyPath:@"tweaksDelegate"];

                [self.topViewController presentViewController:viewController animated:YES completion:NULL];
            }]];
        }

        [alert addAction:[UIAlertAction actionWithTitle:@"Capture Screenshot" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            UIImage *capturedScreenshot = self.capturedScreenshot;
            NSString *recursiveDescription = self.hierarchyDescription;

            self.capturedScreenshot = nil;
            self.hierarchyDescription = nil;

            SPLWindowAnnotateScreenshotViewController *viewController = [[SPLWindowAnnotateScreenshotViewController alloc] initWithScreenshot:capturedScreenshot];
            viewController.hierarchyDescription = recursiveDescription;
            viewController.delegate = self;

            UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:viewController];
            [self.topViewController presentViewController:navigationController animated:YES completion:NULL];
        }]];

        if (NSClassFromString(@"RPScreenRecorder") != Nil) {
            [alert addAction:[UIAlertAction actionWithTitle:@"Record Video" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                [[RPScreenRecorder sharedRecorder] startRecordingWithMicrophoneEnabled:NO handler:^(NSError * __nullable error) {
                    if (error) {
                        [self endScreenRecording];
                        NSLog(@"[SPLWindow] startRecording failed: %@", error);
                        return;
                    }

                    self.isRecordingVideo = YES;
                    self.videoRecordingStartTime = [NSDate date];
                    self.videoRecordingTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(_videoCaptureTick:) userInfo:nil repeats:YES];

                    self.screenCaptureButton = [[SPLWindowScreenCaptureButton alloc] initWithFrame:CGRectZero];
                    [self.screenCaptureButton addTarget:self action:@selector(_userWantsToEndScreenCapture) forControlEvents:UIControlEventTouchUpInside];
                    [self.screenCaptureButton sizeToFit];
                    [self addSubview:self.screenCaptureButton];
                }];
            }]];
        }

        [self.customRageShakes enumerateObjectsUsingBlock:^(NSString *rageShake, NSUInteger idx, BOOL * _Nonnull stop) {
            [alert addAction:[UIAlertAction actionWithTitle:rageShake style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                dispatch_block_t handler = self.customRageShakeHandlers[idx];
                handler();
            }]];
        }];

        alert.popoverPresentationController.sourceView = self.topViewController.view;

        [self.topViewController presentViewController:alert animated:YES completion:nil];
    }
}

#pragma mark - SPLWindowAnnotateScreenshotViewControllerDelegate

- (void)screenshotViewControllerDidCancel:(SPLWindowAnnotateScreenshotViewController *)screenshotViewController
{
    [screenshotViewController dismissViewControllerAnimated:YES completion:NULL];

    self.isCapturingScreenshot = NO;
}

- (void)screenshotViewController:(SPLWindowAnnotateScreenshotViewController *)screenshotViewController didAnnotateScreenshotWithResultingImage:(UIImage *)screenshot
{
    [screenshotViewController dismissViewControllerAnimated:YES completion:^{
        NSString *recursiveDescription = screenshotViewController.hierarchyDescription;
        MFMailComposeViewController *viewController = [[MFMailComposeViewController alloc] init];

        [viewController setSubject:[NSString stringWithFormat:@"Rage Shake - %@", [NSDateFormatter localizedStringFromDate:[NSDate date] dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterShortStyle]]];

        [viewController addAttachmentData:UIImageJPEGRepresentation(screenshot, 1.0) mimeType:@"image/jpg" fileName:@"screenshot.jpg"];
        [viewController addAttachmentData:[recursiveDescription dataUsingEncoding:NSUTF8StringEncoding] mimeType:@"plain/text" fileName:@"recursive-description.txt"];

        viewController.mailComposeDelegate = self;

        [self.topViewController presentViewController:viewController animated:YES completion:NULL];
    }];
}

#pragma mark - Instance methods

- (void)addRageShake:(NSString *)rageShakeName withHandler:(dispatch_block_t)handler
{
    NSParameterAssert(rageShakeName);
    NSParameterAssert(handler);

    [self.customRageShakes addObject:rageShakeName];
    [self.customRageShakeHandlers addObject:handler];
}

#pragma mark - UIView

- (void)layoutSubviews
{
    [super layoutSubviews];

    if (!self.screenCaptureButton) {
        return;
    }

    self.screenCaptureButton.transform = CGAffineTransformInvert(videoTransformFromInterfaceOrientation([UIApplication sharedApplication].statusBarOrientation));
    [self.screenCaptureButton sizeToFit];
    CGRect frame = self.screenCaptureButton.frame;

    switch ([UIApplication sharedApplication].statusBarOrientation) {
#ifdef __IPHONE_8_0
        case UIInterfaceOrientationUnknown:
#endif
        case UIInterfaceOrientationPortrait:
            frame.origin.x = CGRectGetWidth(self.bounds) - CGRectGetWidth(frame) - 14.0;
            frame.origin.y = CGRectGetHeight(self.bounds) - CGRectGetHeight(frame) - 14.0;
            break;
        case UIInterfaceOrientationPortraitUpsideDown:
            frame.origin.x = 14.0;
            frame.origin.y = 14.0;
            break;
        case UIInterfaceOrientationLandscapeLeft:
            frame.origin.x = CGRectGetWidth(self.bounds) - CGRectGetWidth(frame) - 14.0;
            frame.origin.y = 14.0;
            break;
        case UIInterfaceOrientationLandscapeRight:
            frame.origin.x = 14.0;
            frame.origin.y = CGRectGetHeight(self.bounds) - CGRectGetHeight(frame) - 14.0;;
            break;
    }

    self.screenCaptureButton.frame = frame;
}

#pragma mark - UIWindow

- (void)sendEvent:(UIEvent *)event
{
    [super sendEvent:event];

    BOOL highlightAirPlayTouches = self.highlightsTouchesDuringAirPlayMirroring && self.airPlayScreenIsConnected;
    BOOL highlightScreenRecordingTouches = self.highlightsTouchesDuringScreenRecording && self.isRecordingVideo;

    if (highlightAirPlayTouches || highlightScreenRecordingTouches) {
        if (event.type == UIEventTypeTouches) {
            for (UITouch *touch in event.allTouches) {
                switch (touch.phase) {
                    case UITouchPhaseBegan: {
                        [self airPlayTouchBegan:touch withEvent:event];
                        break;
                    } case UITouchPhaseMoved: {
                        [self airPlayTouchMoved:touch withEvent:event];
                        break;
                    } case UITouchPhaseCancelled: {
                        [self airPlayTouchCancelled:touch withEvent:event];
                        break;
                    } case UITouchPhaseEnded: {
                        [self airPlayTouchEnded:touch withEvent:event];
                        break;
                    } default: {
                        break;
                    }
                }
            }
        }
    } else if (self.touchIndicatorLookup.count > 0) {
        for (UITouch *touch in self.touchIndicatorLookup) {
            SPLWindowTouchIndicator *touchIndicator = [self.touchIndicatorLookup objectForKey:touch];
            [touchIndicator removeFromSuperview];
        }

        [self.touchIndicatorLookup removeAllObjects];
    }
}

#pragma mark - AirplayMirroring

- (void)airPlayTouchBegan:(UITouch *)touch withEvent:(UIEvent *)event
{
    CGFloat dimension = [SPLWindowTouchIndicator dimension];

    SPLWindowTouchIndicator *touchIndicator = [[SPLWindowTouchIndicator alloc] init];
    touchIndicator.center = [touch locationInView:self];
    [self addSubview:touchIndicator];

    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"transform"];
    animation.duration = 0.1;
    animation.fromValue = [NSValue valueWithCATransform3D:CATransform3DMakeScale(1.0 / dimension, 1.0 / dimension, 1.0)];
    animation.toValue = [NSValue valueWithCATransform3D:CATransform3DIdentity];
    [touchIndicator.layer addAnimation:animation forKey:@"transform"];

    [self.touchIndicatorLookup setObject:touchIndicator forKey:touch];
}

- (void)airPlayTouchMoved:(UITouch *)touch withEvent:(UIEvent *)event
{
    SPLWindowTouchIndicator *touchIndicator = [self.touchIndicatorLookup objectForKey:touch];
    touchIndicator.center = [touch locationInView:self];
}

- (void)airPlayTouchEnded:(UITouch *)touch withEvent:(UIEvent *)event
{
    CGFloat dimension = [SPLWindowTouchIndicator dimension];

    SPLWindowTouchIndicator *touchIndicator = [self.touchIndicatorLookup objectForKey:touch];
    [self.touchIndicatorLookup removeObjectForKey:touch];

    touchIndicator.layer.transform = CATransform3DMakeScale(1.0 / dimension, 1.0 / dimension, 1.0);
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"transform"];
    animation.duration = 0.1;
    animation.fromValue = [NSValue valueWithCATransform3D:CATransform3DIdentity];
    animation.toValue = [NSValue valueWithCATransform3D:CATransform3DMakeScale(1.0 / dimension, 1.0 / dimension, 1.0)];
    [touchIndicator.layer addAnimation:animation forKey:@"transform"];

    double delayInSeconds = animation.duration;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        [touchIndicator removeFromSuperview];
    });
}

- (void)airPlayTouchCancelled:(UITouch *)touch withEvent:(UIEvent *)event
{
    SPLWindowTouchIndicator *touchIndicator = [self.touchIndicatorLookup objectForKey:touch];
    [touchIndicator removeFromSuperview];

    [self.touchIndicatorLookup removeObjectForKey:touch];
}

#pragma mark - Memory management

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - video capturing

- (void)_videoCaptureTick:(NSTimer *)sender
{
    self.screenCaptureButton.videoDuration = fabs(self.videoRecordingStartTime.timeIntervalSinceNow);
}

- (void)endScreenRecording
{
    self.isRecordingVideo = YES;

    [self.videoRecordingTimer invalidate], self.videoRecordingTimer = nil;
    [self.screenCaptureButton removeFromSuperview], self.screenCaptureButton = nil;

    if (![RPScreenRecorder sharedRecorder].isRecording) {
        return;
    }

    [[RPScreenRecorder sharedRecorder] stopRecordingWithHandler:^(RPPreviewViewController * __nullable previewViewController, NSError * __nullable error) {
        if (error) {
            NSLog(@"[SPLWindow] startRecording failed: %@", error);
        } else if (previewViewController != nil) {
            previewViewController.previewControllerDelegate = self;
            [self.topViewController presentViewController:previewViewController animated:YES completion:NULL];
        }
    }];
}

#pragma mark - FBTweakViewControllerDelegate

- (void)tweakViewControllerPressedDone:(FBTweakViewController *)tweakViewController
{
    [tweakViewController dismissViewControllerAnimated:YES completion:NULL];
}

#pragma mark - MFMailComposeViewControllerDelegate

- (void)mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result error:(nullable NSError *)error
{
    if (error != nil) {
        NSLog(@"[SPLWindow] mailComposeController failed: %@", error);
    }
}

#pragma mark - RPPreviewViewControllerDelegate

- (void)previewControllerDidFinish:(RPPreviewViewController *)previewController
{
    [previewController dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Private category implementation ()

- (void)_userWantsToEndScreenCapture
{
    [self endScreenRecording];
}

- (void)_screensDidChangeNotificationCallback:(NSNotification *)notification
{
    UIScreen *sender = notification.object;
    self.airPlayScreenIsConnected = sender.mirroredScreen != nil;
}

@end
