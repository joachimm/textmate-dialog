//
//  TMDIncrementalPopUpMenu.h
//
//  Created by Ciarán Walsh on 2007-08-19.
//

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@interface TMDHTMLTip : NSWindow
{
	WebView*	webView;
	WebPreferences*	webPreferences;
	NSTimer* animationTimer;
	NSDate* animationStart;

	NSDate* didOpenAtDate; // ignore mouse moves for the next second
	NSPoint mousePositionWhenOpened;
}
+ (TMDHTMLTip*)showWithContent:(NSString*)content atLocation:(NSPoint)point transparent:(BOOL)transparent;
@end
