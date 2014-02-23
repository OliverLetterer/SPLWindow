//
//  SPLWindowAnnotateScreenshotViewController.m
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

#import "SPLWindowAnnotateScreenshotViewController.h"



@interface SPLWindowAnnotationView : UIView

@property (nonatomic, strong) UIBezierPath *annotationPath;
@property (nonatomic, strong) UIPanGestureRecognizer *panGestureRecognizer;

@property (nonatomic, strong) UIBezierPath *currentDrawingPath;

@property (nonatomic, assign) CGPoint lastTrackedPoint;
@property (nonatomic, assign) BOOL hasTrackedControlPoint;

@end

@implementation SPLWindowAnnotationView

- (void)setAnnotationPath:(UIBezierPath *)annotationPath
{
    if (annotationPath != _annotationPath) {
        _annotationPath = annotationPath;
        [self setNeedsDisplay];
    }
}

- (void)setFrame:(CGRect)frame
{
    CGRect bounds = self.bounds;

    [super setFrame:frame];
    if (!CGRectEqualToRect(bounds, self.bounds)) {
        self.annotationPath = [UIBezierPath bezierPath];
    }
}

- (instancetype)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = [UIColor clearColor];
        _annotationPath = [UIBezierPath bezierPath];
        _panGestureRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(_panGestureRecognized:)];
        _panGestureRecognizer.maximumNumberOfTouches = 1;
        [self addGestureRecognizer:_panGestureRecognizer];
    }
    return self;
}

- (void)drawRect:(CGRect)rect
{
    [[UIColor redColor] setStroke];

    self.annotationPath.lineJoinStyle = kCGLineJoinRound;
    self.annotationPath.lineWidth = 2.0;
    [self.annotationPath stroke];

    if (self.currentDrawingPath) {
        self.currentDrawingPath.lineJoinStyle = kCGLineJoinRound;
        self.currentDrawingPath.lineWidth = 2.0;
        [self.currentDrawingPath stroke];
    }
}

- (void)_panGestureRecognized:(UIPanGestureRecognizer *)recognizer
{
    switch (recognizer.state) {
        case UIGestureRecognizerStateBegan: {
            CGPoint location = [recognizer locationInView:self];
            _lastTrackedPoint = location;

            self.currentDrawingPath = [UIBezierPath bezierPath];
            [self.currentDrawingPath moveToPoint:location];
            self.hasTrackedControlPoint = NO;
            break;
        }
        case UIGestureRecognizerStateChanged: {
            CGPoint location = [recognizer locationInView:self];
            if (sqrt(pow(location.x - _lastTrackedPoint.x, 2.0) + pow(location.y - _lastTrackedPoint.y, 2.0)) >= 2.0) {
                if (self.hasTrackedControlPoint) {
                    [self.currentDrawingPath addQuadCurveToPoint:location controlPoint:self.lastTrackedPoint];
                    self.hasTrackedControlPoint = NO;

                    [self setNeedsDisplayInRect:UIEdgeInsetsInsetRect(self.currentDrawingPath.bounds, UIEdgeInsetsMake(-2.0, -2.0, -2.0, -2.0))];
                } else {
                    self.hasTrackedControlPoint = YES;
                }

                self.lastTrackedPoint = location;
            }
            break;
        }
        case UIGestureRecognizerStateCancelled: {
            self.currentDrawingPath = nil;
            [self setNeedsDisplay];
            break;
        }
        case UIGestureRecognizerStateEnded: {
            CGPoint location = [recognizer locationInView:self];
            [self.currentDrawingPath addLineToPoint:location];

            [self.annotationPath appendPath:self.currentDrawingPath];
            [self setNeedsDisplayInRect:UIEdgeInsetsInsetRect(self.currentDrawingPath.bounds, UIEdgeInsetsMake(-2.0, -2.0, -2.0, -2.0))];
            self.currentDrawingPath = nil;
            break;
        }
        default:
            break;
    }
}

@end



@interface SPLWindowAnnotateScreenshotViewController ()

@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) SPLWindowAnnotationView *annotationView;

@end



@implementation SPLWindowAnnotateScreenshotViewController

- (instancetype)initWithScreenshot:(UIImage *)screenshot
{
    if (self = [super init]) {
        _screenshot = screenshot;
    }
    return self;
}

- (void)loadView
{
    [super loadView];

    self.view.backgroundColor = [UIColor whiteColor];

    _imageView = [[UIImageView alloc] initWithFrame:self.view.bounds];
    _imageView.image = self.screenshot;
    _imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _imageView.contentMode = UIViewContentModeScaleAspectFill;
    [self.view addSubview:_imageView];

    _annotationView = [[SPLWindowAnnotationView alloc] initWithFrame:self.view.bounds];
    _annotationView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_annotationView];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.toolbarItems = @[
                          [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(_cancelButtonClicked:)],
                          [[UIBarButtonItem alloc] initWithTitle:@"Reset" style:UIBarButtonItemStylePlain target:self action:@selector(_resetButtonClicked:)],
                          [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL],
                          [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(_doneButtonClicked:)],
                          ];

    [self.navigationController setNavigationBarHidden:YES animated:NO];
    [self.navigationController setToolbarHidden:NO animated:NO];

    self.navigationController.toolbar.barTintColor = [UIColor yellowColor];
    self.navigationController.toolbar.tintColor = [UIColor blackColor];
}

- (void)_doneButtonClicked:(UIBarButtonItem *)sender
{
    UIGraphicsBeginImageContextWithOptions(self.view.bounds.size, YES, 0.0);
    [self.view drawViewHierarchyInRect:self.view.bounds afterScreenUpdates:NO];

    @try {
        UIView *statusBarView = [[UIApplication sharedApplication] valueForKey:[@[@"status", @"Bar"] componentsJoinedByString:@""]];
        [statusBarView drawViewHierarchyInRect:statusBarView.bounds afterScreenUpdates:NO];
    } @catch (NSException *exception) { }

    UIImage *screenshot = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    [self.delegate screenshotViewController:self didAnnotateScreenshotWithResultingImage:screenshot];
}

- (void)_resetButtonClicked:(UIBarButtonItem *)sender
{
    self.annotationView.annotationPath = [UIBezierPath bezierPath];
}

- (void)_cancelButtonClicked:(UIBarButtonItem *)sender
{
    [self.delegate screenshotViewControllerDidCancel:self];
}

@end
