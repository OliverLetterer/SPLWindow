//
//  SPLWindowTouchIndicator.m
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

#import "SPLWindowTouchIndicator.h"



@implementation SPLWindowTouchIndicator

+ (CGFloat)dimension
{
    return 24.0;
}

- (instancetype)init
{
    CGFloat dimension = [SPLWindowTouchIndicator dimension];

    if (self = [super initWithFrame:CGRectMake(0.0, 0.0, dimension, dimension)]) {
        self.userInteractionEnabled = NO;
        self.backgroundColor = [UIColor clearColor];
    }
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (void)drawRect:(CGRect)rect
{
    UIBezierPath *path = [UIBezierPath bezierPathWithOvalInRect:UIEdgeInsetsInsetRect(rect, UIEdgeInsetsMake(1.0, 1.0, 1.0, 1.0))];
    path.lineWidth = 1.0;

    [[UIColor colorWithWhite:0.0 alpha:0.25] setFill];
    [path fill];

    [[UIColor colorWithWhite:0.0 alpha:0.3] setStroke];
    [path stroke];

}

@end
