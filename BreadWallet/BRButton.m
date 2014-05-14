//
//  BRButton.m
//  BreadWallet
//
//  Created by Aaron Voisine on 6/14/13.
//  Copyright (c) 2013 Aaron Voisine <voisine@gmail.com>
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

#import "BRButton.h"
#import <QuartzCore/QuartzCore.h>

@implementation BRButton

- (instancetype)init
{
    if (! (self = [super init])) return nil;
    
    [self setStyle:0];
    
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    if (! (self = [super initWithCoder:aDecoder])) return nil;
    
    [self setStyle:0];
    
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    if (! (self = [super initWithFrame:frame])) return nil;

    [self setStyle:0];

    return self;
}

- (void)setStyle:(BRButtonStyle)style
{
    static UIImage *white = nil, *whitepressed = nil, *blue = nil, *bluepressed = nil, *disabled = nil;
    static dispatch_once_t onceToken = 0;
    
    dispatch_once(&onceToken, ^{
        white = [[UIImage imageNamed:@"button-bg-white.png"]
                 resizableImageWithCapInsets:UIEdgeInsetsMake(15.0, 5.0, 15.0, 5.0)];
        whitepressed = [[UIImage imageNamed:@"button-bg-white-pressed.png"]
                        resizableImageWithCapInsets:UIEdgeInsetsMake(22.0, 5.0, 22.0, 5.0)];
        blue = [[UIImage imageNamed:@"button-bg-blue.png"]
                resizableImageWithCapInsets:UIEdgeInsetsMake(22.0, 5.0, 22.0, 5.0)];
        bluepressed = [[UIImage imageNamed:@"button-bg-blue-pressed.png"]
                       resizableImageWithCapInsets:UIEdgeInsetsMake(38.0, 5.0, 5.0, 5.0)];
        disabled = [[UIImage imageNamed:@"button-bg-disabled.png"]
                    resizableImageWithCapInsets:UIEdgeInsetsMake(15.0, 5.0, 15.0, 5.0)];
    });
    
    switch (style) {
        case BRButtonStyleWhite:
            self.layer.shadowRadius = 3.0;
            self.layer.shadowOpacity = 0.15;
            self.layer.shadowOffset = CGSizeMake(0.0, 1.0);
            
            [self setBackgroundImage:white forState:UIControlStateNormal];
            [self setBackgroundImage:whitepressed forState:UIControlStateHighlighted];
            [self setBackgroundImage:disabled forState:UIControlStateDisabled];
            
            [self setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            [self setTitleColor:[UIColor lightGrayColor] forState:UIControlStateDisabled];

            self.titleLabel.shadowOffset = CGSizeMake(0.0, 0.0);

            break;

        case BRButtonStyleBlue:
            self.layer.shadowRadius = 2.0;
            self.layer.shadowOpacity = 0.1;
            self.layer.shadowOffset = CGSizeMake(0.0, 1.0);

            [self setBackgroundImage:blue forState:UIControlStateNormal];
            [self setBackgroundImage:bluepressed forState:UIControlStateHighlighted];
            [self setBackgroundImage:disabled forState:UIControlStateDisabled];

            [self setTitleColor:[UIColor colorWithRed:0.0 green:0.5 blue:1.0 alpha:1.0]
             forState:UIControlStateNormal];
            [self setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted];
            [self setTitleColor:[UIColor lightGrayColor] forState:UIControlStateDisabled];
            
            self.titleLabel.shadowOffset = CGSizeMake(0.0, 0.0);

            break;
                        
        case BRButtonStyleNone:
            self.layer.shadowOpacity = 0.0;
            [self setBackgroundImage:nil forState:UIControlStateNormal];
            [self setBackgroundImage:nil forState:UIControlStateHighlighted];
            [self setBackgroundImage:nil forState:UIControlStateDisabled];
            
            [self setTitleColor:[UIColor colorWithRed:0.0 green:0.5 blue:1.0 alpha:1.0] forState:UIControlStateNormal];
            [self setTitleColor:[UIColor colorWithRed:0.78 green:0.86 blue:0.96 alpha:1.0]
             forState:UIControlStateHighlighted];
            [self setTitleColor:[UIColor lightGrayColor] forState:UIControlStateDisabled];
            
            self.titleLabel.shadowOffset = CGSizeMake(0.0, 1.0);
    }

    self.titleLabel.font = [UIFont fontWithName:@"HelveticaNeue" size:17];
    self.titleLabel.adjustsFontSizeToFitWidth = YES;
    self.titleLabel.numberOfLines = 1;
    self.titleLabel.lineBreakMode = NSLineBreakByClipping;
    self.titleEdgeInsets = UIEdgeInsetsMake(0, 5, 0, 5);
}

@end
