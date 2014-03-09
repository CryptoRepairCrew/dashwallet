//
//  ZNRestoreViewController.m
//  ZincWallet
//
//  Created by Aaron Voisine on 6/13/13.
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

#import "ZNRestoreViewController.h"
#import "ZNWalletManager.h"
#import "NSString+Base58.h"
#import "ZNKeySequence.h"
#import "ZNZincMnemonic.h"
#import <QuartzCore/QuartzCore.h>

#define SHFT @"\xE2\x87\xA7" // upwards white arrow (utf-8)
#define BKSP @"\xE2\x8C\xAB" // erase to the left (backspace) (utf-8)

@interface ZNRestoreViewController ()

@property (nonatomic, strong) IBOutlet UITextView *textView;
@property (nonatomic, strong) IBOutlet UILabel *label;
@property (nonatomic, strong) IBOutletCollection(UIButton) NSArray *keys;

@property (nonatomic, strong) id<ZNMnemonic> mnemonic;
@property (nonatomic, strong) NSSet *adjs, *nouns, *advs, *verbs;

@end

@implementation ZNRestoreViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.
 
    // TODO: create secure versions of keyboard and UILabel and use in place of UITextView
    // TODO: autocomplete based on 4 letter prefixes of mnemonic words
    
    self.textView.layer.cornerRadius = 5.0;
    
    if (self.navigationController.viewControllers[0] != self) return;
    
    self.textView.layer.borderColor = [[UIColor colorWithWhite:0.0 alpha:0.25] CGColor];
    self.textView.layer.borderWidth = 0.5;
    self.textView.textColor = [UIColor blackColor];

    self.mnemonic = [ZNZincMnemonic new];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    [self.textView becomeFirstResponder];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    self.adjs = [NSSet setWithArray:[NSArray arrayWithContentsOfFile:[[NSBundle mainBundle]
                 pathForResource:@"MnemonicAdjs" ofType:@"plist"]]];
    self.nouns = [NSSet setWithArray:[NSArray arrayWithContentsOfFile:[[NSBundle mainBundle]
                  pathForResource:@"MnemonicNouns" ofType:@"plist"]]];
    self.advs = [NSSet setWithArray:[NSArray arrayWithContentsOfFile:[[NSBundle mainBundle]
                 pathForResource:@"MnemonicAdvs" ofType:@"plist"]]];
    self.verbs = [NSSet setWithArray:[NSArray arrayWithContentsOfFile:[[NSBundle mainBundle]
                  pathForResource:@"MnemonicVerbs" ofType:@"plist"]]];
}

- (void)viewWillDisappear:(BOOL)animated
{
    self.adjs = self.nouns = self.advs = self.verbs = nil;
    
    [super viewWillDisappear:animated];
}

#pragma mark - IBAction

- (IBAction)cancel:(id)sender
{
    [self.navigationController.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - UITextViewDelegate

- (void)textViewDidChange:(UITextView *)textView
{
    static NSCharacterSet *charset = nil;
    static dispatch_once_t onceToken = 0;
    
    dispatch_once(&onceToken, ^{
        charset = [[NSCharacterSet
                    characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz., "]
                   invertedSet];
    });
    
    NSRange selected = textView.selectedRange;
    NSString *s = textView.text;
    BOOL done = ([s rangeOfString:@"\n"].location != NSNotFound);
    
    while ([s rangeOfCharacterFromSet:charset].location != NSNotFound) {
        NSRange r = [s rangeOfCharacterFromSet:charset];

        s = [[s substringToIndex:r.location] stringByAppendingString:[s substringFromIndex:r.location + 1]];
    }

    while ([s rangeOfString:@"  "].location != NSNotFound) {
        NSRange r = [s rangeOfString:@".  "];
    
        if (r.location != NSNotFound) {
            if (r.location + 2 == selected.location) selected.location++;
            s = [[s substringToIndex:r.location + 1] stringByAppendingString:[s substringFromIndex:r.location + 2]];
        }
        else s = [s stringByReplacingOccurrencesOfString:@"  " withString:@". "];
    }
    
    if ([s hasPrefix:@" "]) s = [s substringFromIndex:1];

    selected.location -= textView.text.length - s.length;
    textView.text = s;
    textView.selectedRange = selected;
    
    if (! done) return;
    
    s = [[[[s stringByReplacingOccurrencesOfString:@"." withString:@" "]
           stringByReplacingOccurrencesOfString:@"," withString:@" "]
          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]
         lowercaseString];
        
    while ([s rangeOfString:@"  "].location != NSNotFound) {
        s = [s stringByReplacingOccurrencesOfString:@"  " withString:@" "];
    }
    
    NSArray *a = [s componentsSeparatedByString:@" "];
    NSString *incorrect = nil;
        
    for (NSUInteger i = 0; i < SEQUENCE_SEED_LENGTH*3/4; i += 6) {
        if (i < a.count && ! [self.adjs containsObject:a[i]]) incorrect = a[i];
        else if (i + 1 < a.count && ! [self.nouns containsObject:a[i + 1]]) incorrect = a[i + 1];
        else if (i + 2 < a.count && ! [self.advs containsObject:a[i + 2]]) incorrect = a[i + 2];
        else if (i + 3 < a.count && ! [self.verbs containsObject:a[i + 3]]) incorrect = a[i + 3];
        else if (i + 4 < a.count && ! [self.adjs containsObject:a[i + 4]]) incorrect = a[i + 4];
        else if (i + 5 < a.count && ! [self.nouns containsObject:a[i + 5]]) incorrect = a[i + 5];
    }

    if ([s isEqual:@"wipe"]) { // shortcut word to force the wipe option to appear
        [[[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:@"cancel"
          destructiveButtonTitle:@"wipe" otherButtonTitles:nil]
         showInView:[[UIApplication sharedApplication] keyWindow]];
    }
    else if (incorrect) {
        //BUG: the range should be set by word count, not string match
        textView.selectedRange = [[textView.text lowercaseString] rangeOfString:incorrect];
        
        [[[UIAlertView alloc] initWithTitle:nil
          message:[incorrect stringByAppendingString:@" is not the correct backup phrase word"] delegate:nil
          cancelButtonTitle:@"ok" otherButtonTitles:nil] show];
    }
    else if (a.count != SEQUENCE_SEED_LENGTH*3/4) {
        [[[UIAlertView alloc] initWithTitle:nil
          message:[NSString stringWithFormat:@"backup phrase must be %d words", SEQUENCE_SEED_LENGTH*3/4] delegate:nil
          cancelButtonTitle:@"ok" otherButtonTitles:nil] show];
    }
    else if ([[ZNWalletManager sharedInstance] seed]) {
        if ([[[ZNWalletManager sharedInstance] seed] isEqual:[self.mnemonic decodePhrase:textView.text]]) {
            [[[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:@"cancel"
              destructiveButtonTitle:@"wipe" otherButtonTitles:nil]
             showInView:[[UIApplication sharedApplication] keyWindow]];
        }
        else {
            [[[UIAlertView alloc] initWithTitle:nil message:@"backup phrase doesn't match" delegate:nil
              cancelButtonTitle:@"ok" otherButtonTitles:nil] show];
        }
    }
    else {
        [[ZNWalletManager sharedInstance] setSeedPhrase:textView.text];
        
        textView.text = nil;
        
        [self.navigationController.presentingViewController dismissViewControllerAnimated:YES completion:nil];
    }
}

#pragma mark - UIActionSheetDelegate

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex != actionSheet.destructiveButtonIndex) return;
    
    [[ZNWalletManager sharedInstance] setSeed:nil];

    self.textView.text = nil;
    
    UIViewController *p = self.navigationController.presentingViewController.presentingViewController;
    
    [p dismissViewControllerAnimated:NO completion:^{
        [p presentViewController:[self.storyboard instantiateViewControllerWithIdentifier:@"ZNNewWalletNav"]
         animated:NO completion:nil];
    }];
}

@end
