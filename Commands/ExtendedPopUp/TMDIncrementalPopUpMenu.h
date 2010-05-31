//
//  TMDIncrementalPopUpMenu.h
//
//  Created by Joachim Mårtensson on 2007-08-10.
//

#import <Cocoa/Cocoa.h>
#import "CLIProxy.h"
#import "DocPopup.h"

#define MAX_ROWS 15
#define START_DOCUMENTATION 1
#define START_INSERTION 2
#define SEPARATOR '\0'
@interface TMDIncrementalPopUpMenu : NSWindow
{
	NSFileHandle* outputHandle;
	NSArray* suggestions;
	NSMutableString* mutablePrefix;
	NSString* staticPrefix;
	NSArray* filtered;
	DocPopup* htmlTooltip;
	//NSTableView* theTableView;
	NSPoint caretPos;
	BOOL isAbove;
	BOOL closeMe;
	BOOL caseSensitive;

	NSMutableCharacterSet* textualInputCharacters;	
}
- (id)initWithItems:(NSArray*)someSuggestions alreadyTyped:(NSString*)aUserString staticPrefix:(NSString*)aStaticPrefix additionalWordCharacters:(NSString*)someAdditionalWordCharacters caseSensitive:(BOOL)isCaseSensitive writeChoiceToFileDescriptor:(NSFileHandle*)aFileDescriptor;
- (void)setCaretPos:(NSPoint)aPos;
@end
