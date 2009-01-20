//
//  DocPopup.h
//  Dialog2
//
//  Created by Joachim Mårtensson on 2009-01-11.
//  Copyright 2009 Chalmers. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "../HTMLTips/TMDHTMLTips.h"


@interface DocPopup : TMDHTMLTip{

}
+ (id)showWithContent:(NSString*)content atLocation:(NSPoint)point transparent:(BOOL)transparent;
- (void)runUntilUserActivity;
- (BOOL)shouldCloseForMousePosition:(NSPoint)aPoint;
- (void)close;
@end
