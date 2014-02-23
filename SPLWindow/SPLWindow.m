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

#include <dlfcn.h>

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

    NSString *durationText = [NSString stringWithFormat:@"%02d:%02d", minutes, seconds];
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

static UIImageOrientation imageOrientationFromInterfaceOrientation(UIInterfaceOrientation interfaceOrientation)
{
    switch (interfaceOrientation) {
        case UIInterfaceOrientationLandscapeLeft:
            return UIImageOrientationRight;
            break;
        case UIInterfaceOrientationLandscapeRight:
            return UIImageOrientationLeft;
            break;
        case UIInterfaceOrientationPortrait:
            return UIImageOrientationUp;
            break;
        case UIInterfaceOrientationPortraitUpsideDown:
            return UIImageOrientationDown;
            break;
    }
}

static CGAffineTransform videoTransformFromInterfaceOrientation(UIInterfaceOrientation interfaceOrientation)
{
    switch (interfaceOrientation) {
        case UIInterfaceOrientationLandscapeLeft:
            return CGAffineTransformMakeRotation(M_PI_2);
            break;
        case UIInterfaceOrientationLandscapeRight:
            return CGAffineTransformMakeRotation(- M_PI_2);
            break;
        case UIInterfaceOrientationPortrait:
            return CGAffineTransformIdentity;
            break;
        case UIInterfaceOrientationPortraitUpsideDown:
            return CGAffineTransformMakeRotation(M_PI);
            break;
    }
}

@interface SPLWindow () <MFMailComposeViewControllerDelegate, SPLWindowAnnotateScreenshotViewControllerDelegate, UIActionSheetDelegate>

@property (nonatomic, strong) UIImage *capturedScreenshot;
@property (nonatomic, strong) NSString *hierarchyDescription;

@property (nonatomic, assign) BOOL airPlayScreenIsConnected;
@property (nonatomic, strong) NSMapTable *touchIndicatorLookup;

@property (nonatomic, strong) UIViewController *topViewController;
@property (nonatomic, assign) BOOL isCapturingScreenshot;

@property (atomic, assign) BOOL isRecordingVideo;
@property (atomic, strong) dispatch_queue_t screenCaptureProcessingQueue;

@property (atomic, strong) AVAssetWriter *assetWriter;
@property (atomic, strong) AVAssetWriterInput *assetWriterInput;
@property (atomic, strong) AVAssetWriterInputPixelBufferAdaptor *pixelBufferAdaptor;

@property (atomic, strong) CADisplayLink *displayLink;
@property (atomic, assign) CFTimeInterval videoDuration;
@property (atomic, assign) CGAffineTransform videoTransform;
@property (atomic, strong) NSURL *videoURL;
@property (nonatomic, assign) BOOL hasCapturedFirstVideoFrame;

@property (nonatomic, strong) SPLWindowScreenCaptureButton *screenCaptureButton;

@end



static BOOL isVideoCapturingAvailable;

typedef CVReturn(*CVPixelBufferCreateWithIOSurfaceFunction)(CFAllocatorRef allocator, CFTypeRef surface, CFDictionaryRef pixelBufferAttributes, CVPixelBufferRef *pixelBufferOut);
static CVPixelBufferCreateWithIOSurfaceFunction CVPixelBufferCreateWithIOSurface;

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

    BOOL isIOCaptureAvailable = class_respondsToSelector(objc_getMetaClass("UIWindow"), NSSelectorFromString([NSString stringWithFormat:@"create%@Surface", @"ScreenIO"]));
    CVPixelBufferCreateWithIOSurface = (CVPixelBufferCreateWithIOSurfaceFunction)dlsym((void *)RTLD_NEXT, [NSString stringWithFormat:@"CVPixelBufferCreateWith%@%@", @"IO", @"Surface"].UTF8String);

    isVideoCapturingAvailable = isIOCaptureAvailable && CVPixelBufferCreateWithIOSurface != NULL;
}

- (id)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
        for (UIScreen *screen in [UIScreen screens]) {
            if (screen.mirroredScreen) {
                _airPlayScreenIsConnected = YES;
            }
        }

        if (!isVideoCapturingAvailable) {
            NSLog(@"[SPLWindow] video caturing has been disabled because the runtime doesn't supports SPLWindows screen capturing mechanismn anymore.");
        }

        _screenCaptureProcessingQueue = dispatch_queue_create("de.sparrow-labs.SPLWindow.screenCaptureProcessingQueue", DISPATCH_QUEUE_SERIAL);
        _frameInterval = 1;

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
                                          orientation:imageOrientationFromInterfaceOrientation(self.topViewController.interfaceOrientation)];
        UIGraphicsEndImageContext();

        NSString *recursiveDescription = [self valueForKey:[@[ @"recursive", @"Description" ] componentsJoinedByString:@""]];

        self.capturedScreenshot = screenshot;
        self.hierarchyDescription = recursiveDescription;

        UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:@"Rage Shake"
                                                                 delegate:self
                                                        cancelButtonTitle:@"Cancel"
                                                   destructiveButtonTitle:nil
                                                        otherButtonTitles:@"Capture Screenshot", @"Record Video", nil];
        [actionSheet showInView:self];
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

#pragma mark - UIView

- (void)layoutSubviews
{
    [super layoutSubviews];

    if (!self.screenCaptureButton) {
        return;
    }

    self.screenCaptureButton.transform = CGAffineTransformInvert(videoTransformFromInterfaceOrientation(self.topViewController.interfaceOrientation));
    [self.screenCaptureButton sizeToFit];
    CGRect frame = self.screenCaptureButton.frame;

    switch (self.topViewController.interfaceOrientation) {
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

+ (void)displayThreadEntryPoint:(id)object
{
    @autoreleasepool {
        [[NSThread currentThread] setName:@"SPLWindowDisplayThread"];

        NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
        [runLoop addPort:[NSMachPort port] forMode:NSDefaultRunLoopMode];
        [runLoop run];
    }
}

+ (NSThread *)displayThread
{
    static NSThread *displayThread = nil;
    static dispatch_once_t oncePredicate;
    dispatch_once(&oncePredicate, ^{
        displayThread = [[NSThread alloc] initWithTarget:self selector:@selector(displayThreadEntryPoint:) object:nil];
        [displayThread start];
    });

    return displayThread;
}

- (void)beginScreenRecording
{
    NSParameterAssert([NSThread currentThread] == [self.class displayThread]);

    NSString *filepath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"RageShake-%@.mp4", [NSDateFormatter localizedStringFromDate:[NSDate date] dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterMediumStyle]]];
    self.videoURL = [NSURL fileURLWithPath:filepath];

    NSError *error = nil;
    _assetWriter = [[AVAssetWriter alloc] initWithURL:self.videoURL fileType:AVFileTypeMPEG4 error:&error];
    NSParameterAssert(error == nil);
    NSParameterAssert(_assetWriter);

    CGFloat scale = [UIScreen mainScreen].scale;
    CGSize size = CGSizeApplyAffineTransform(self.bounds.size, CGAffineTransformMakeScale(scale, scale));
    NSDictionary *videoSettings = @{
                                    AVVideoCodecKey: AVVideoCodecH264,
                                    AVVideoWidthKey: @(size.width),
                                    AVVideoHeightKey: @(size.height),
                                    };

    _assetWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoSettings];
    NSParameterAssert(_assetWriterInput);

    _assetWriterInput.transform = self.videoTransform;
    _assetWriterInput.expectsMediaDataInRealTime = YES;
    NSParameterAssert([_assetWriter canAddInput:_assetWriterInput]);
    [_assetWriter addInput:_assetWriterInput];

    NSDictionary *bufferAttributes = @{
                                       (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),
                                       };
    _pixelBufferAdaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:_assetWriterInput
                                                                                           sourcePixelBufferAttributes:bufferAttributes];

    self.videoDuration = 0.0;
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(captureScreenshot:)];
    self.displayLink.frameInterval = self.frameInterval;
    [self.displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];

    [_assetWriter startWriting];
    [_assetWriter startSessionAtSourceTime:CMTimeMakeWithSeconds(0.0, 120.0)];
}

- (void)captureScreenshot:(CADisplayLink *)displayLink
{
    NSParameterAssert([NSThread currentThread] == [self.class displayThread]);

    CFTimeInterval timestamp = displayLink.timestamp;
    CFTypeRef surface = ((CFTypeRef(*)(id, SEL))objc_msgSend)([UIWindow class], NSSelectorFromString([NSString stringWithFormat:@"create%@Surface", @"ScreenIO"]));

    CVPixelBufferRef buffer = NULL;
    NSDictionary *bufferAttributes = @{
                                       (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),
                                       };

    CVPixelBufferCreateWithIOSurface(kCFAllocatorDefault, surface, (__bridge CFDictionaryRef)bufferAttributes, &buffer);
    NSParameterAssert(buffer);

    dispatch_async(self.screenCaptureProcessingQueue, ^{
        static CFTimeInterval lastTimestamp = 0.0;
        if (!self.hasCapturedFirstVideoFrame) {
            lastTimestamp = timestamp;
            self.hasCapturedFirstVideoFrame = YES;
        }

        CGFloat frameDuration = timestamp - lastTimestamp;
        lastTimestamp = timestamp;

        CGFloat currentTimestamp = self.videoDuration + frameDuration;
        self.videoDuration = currentTimestamp;

        CMTime time = CMTimeMakeWithSeconds(currentTimestamp, 120.0);

        dispatch_async(dispatch_get_main_queue(), ^{
            self.screenCaptureButton.videoDuration = currentTimestamp;
        });

        __unused BOOL success = [_pixelBufferAdaptor appendPixelBuffer:buffer withPresentationTime:time];
        NSParameterAssert(success);

        CVPixelBufferRelease(buffer);
    });

    CFRelease(surface);
}

- (void)endScreenRecording
{
    NSParameterAssert([NSThread currentThread] == [self.class displayThread]);

    if (!self.displayLink) {
        return;
    }

    [self.displayLink invalidate];
    self.displayLink = nil;

    dispatch_async(self.screenCaptureProcessingQueue, ^{
        self.hasCapturedFirstVideoFrame = NO;

        [_assetWriterInput markAsFinished];
        [_assetWriter finishWritingWithCompletionHandler:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.screenCaptureButton removeFromSuperview], self.screenCaptureButton = nil;

                MFMailComposeViewController *viewController = [[MFMailComposeViewController alloc] init];

                [viewController setSubject:[NSString stringWithFormat:@"Rage Shake - %@", [NSDateFormatter localizedStringFromDate:[NSDate date] dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterShortStyle]]];

                [viewController addAttachmentData:[NSData dataWithContentsOfURL:_assetWriter.outputURL] mimeType:@"video/mp4" fileName:@"video.mp4"];
                viewController.mailComposeDelegate = self;

                [self.topViewController presentViewController:viewController animated:YES completion:NULL];

                _assetWriter = nil;
                _assetWriterInput = nil;
                _pixelBufferAdaptor = nil;
            });
        }];
    });
}

#pragma mark - MFMailComposeViewControllerDelegate

- (void)mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError *)error
{
    [controller dismissViewControllerAnimated:YES completion:^{
        self.isRecordingVideo = NO;
        self.isCapturingScreenshot = NO;

        [[NSFileManager defaultManager] removeItemAtURL:self.videoURL error:NULL];
        self.videoURL = nil;
    }];
}

#pragma mark - UIActionSheetDelegate

- (void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex
{
    UIImage *capturedScreenshot = self.capturedScreenshot;
    NSString *recursiveDescription = self.hierarchyDescription;

    self.capturedScreenshot = nil;
    self.hierarchyDescription = nil;

    if (buttonIndex == 0) {
        // Capture Screenshot
        SPLWindowAnnotateScreenshotViewController *viewController = [[SPLWindowAnnotateScreenshotViewController alloc] initWithScreenshot:capturedScreenshot];
        viewController.hierarchyDescription = recursiveDescription;
        viewController.delegate = self;

        UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:viewController];
        [self.topViewController presentViewController:navigationController animated:YES completion:NULL];
    } else if (buttonIndex == 1) {
        // record video
        if (!isVideoCapturingAvailable) {
            return;
        }

        self.isRecordingVideo = YES;
        self.videoTransform = videoTransformFromInterfaceOrientation(self.topViewController.interfaceOrientation);

        self.screenCaptureButton = [[SPLWindowScreenCaptureButton alloc] initWithFrame:CGRectZero];
        [self.screenCaptureButton addTarget:self action:@selector(_userWantsToEndScreenCapture) forControlEvents:UIControlEventTouchUpInside];
        [self.screenCaptureButton sizeToFit];
        [self addSubview:self.screenCaptureButton];

        [self performSelector:@selector(beginScreenRecording) onThread:[self.class displayThread] withObject:nil waitUntilDone:NO];
    }
}

#pragma mark - Private category implementation ()

- (void)_userWantsToEndScreenCapture
{
    [self performSelector:@selector(endScreenRecording) onThread:[self.class displayThread] withObject:nil waitUntilDone:NO];
}

- (void)_screensDidChangeNotificationCallback:(NSNotification *)notification
{
    UIScreen *sender = notification.object;
    self.airPlayScreenIsConnected = sender.mirroredScreen != nil;
}

@end
