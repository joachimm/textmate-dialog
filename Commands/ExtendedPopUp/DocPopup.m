//
//  DocPopup.m
//  Dialog2
//
//  Created by Joachim Mårtensson on 2009-01-11.
//  Copyright 2009 Chalmers. All rights reserved.
//

#import "DocPopup.h"


@implementation DocPopup
+ (id)showWithContent:(NSString*)content atLocation:(NSPoint)point transparent:(BOOL)transparent
{
	DocPopup* tip = [DocPopup new];
	[tip setFrameTopLeftPoint:point];
	[tip setContent:content transparent:transparent];
	return tip;
}

- (id)init
{
    if( (self = [super init]) ) {

    }
    return self;
}
- (void)runUntilUserActivity
{
	return;
}
- (BOOL)shouldCloseForMousePosition:(NSPoint)aPoint
{
	return NO;
}
- (void) close 
{
	[webView setFrameLoadDelegate:nil];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:NSViewFrameDidChangeNotification object:self];
	[super close];
}
@end
