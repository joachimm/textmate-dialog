//
//  TMDIncrementalPopUpMenu.mm
//
//  Created by Joachim Mårtensson on 2007-08-10.
//

#import "TMDIncrementalPopUpMenu.h"
#import "../Utilities/TextMate.h" // -insertSnippetWithOptions
#import "../../TMDCommand.h" // -writeString:
#import "../../Dialog2.h"
#import "MenuWindowView.h"
#import "Fallback.h"




@interface TMDIncrementalPopUpMenu (Private)
- (NSRect)rectOfMainScreen;
- (NSString*)filterString;
- (void)setupInterface;
- (void)filter;
- (void)insertCommonPrefix;
- (void)completeAndInsertSnippet;
- (void)setFiltered:(NSArray*)array;
- (void)handleReceivedString;
- (void)displayDocumentationPopup:(NSString*)html;
-(void)closeDocumentationPopup;
@end

NSString* const DOCUMENTATION = @"documentation";
NSString* const INSERT = @"insert";
NSString* const FALLBACK = @"fallback";
NSString* const INDEX = @"index";
NSString* const MATCH = @"match";
NSString* const DISPLAY = @"display";

@implementation TMDIncrementalPopUpMenu

// =============================
// = Setup/tear-down functions =
// =============================
- (id)init
{
	if(self = [super initWithContentRect:NSZeroRect styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO])
	{
		mutablePrefix = [NSMutableString new];
		textualInputCharacters = [[NSMutableCharacterSet alphanumericCharacterSet] retain];
		caseSensitive = YES;
		
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleItemChange:) name:TMDItemChangedNotification object:nil];
		
		[self setupInterface];	
	}
	return self;
}

- (void)dealloc
{
	[staticPrefix release];
	[mutablePrefix release];
	[textualInputCharacters release];
	
	[outputHandle release];
	[suggestions release];
	
	[filtered release];
	
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	[super dealloc];
}

- (id)initWithItems:(NSArray*)someSuggestions alreadyTyped:(NSString*)aUserString staticPrefix:(NSString*)aStaticPrefix additionalWordCharacters:(NSString*)someAdditionalWordCharacters caseSensitive:(BOOL)isCaseSensitive writeChoiceToFileDescriptor:(NSFileHandle*)aFileDescriptor
{
	if(self = [self init])
	{
		suggestions = [someSuggestions retain];
		int i = 0;
		for(NSMutableDictionary* item in suggestions)
		{
			[item setObject:[NSNumber numberWithInt:i] forKey:INDEX];
			i++;
		}
		if(aUserString)
			[mutablePrefix appendString:aUserString];
		
		if(aStaticPrefix)
			staticPrefix = [aStaticPrefix retain];
		
		if(someAdditionalWordCharacters)
			[textualInputCharacters addCharactersInString:someAdditionalWordCharacters];
		
		caseSensitive = isCaseSensitive;
		outputHandle = [aFileDescriptor retain];

	}
	return self;
}

- (void)setCaretPos:(NSPoint)aPos
{
	caretPos = aPos;
	isAbove = NO;
	
	NSRect mainScreen = [self rectOfMainScreen];
	[[self contentView] reloadData];
	
	int offx = (caretPos.x/mainScreen.size.width) + 1;
	if((caretPos.x + [self frame].size.width) > (mainScreen.size.width*offx))
		caretPos.x = caretPos.x - [self frame].size.width;
	
	if(caretPos.y>=0 && caretPos.y<[self frame].size.height)
	{
		caretPos.y = caretPos.y + ([self frame].size.height + [[NSUserDefaults standardUserDefaults] integerForKey:@"OakTextViewNormalFontSize"]*1.5);
		isAbove = YES;
	}
	if(caretPos.y<0 && (mainScreen.size.height-[self frame].size.height)<(caretPos.y*-1))
	{
		caretPos.y = caretPos.y + ([self frame].size.height + [[NSUserDefaults standardUserDefaults] integerForKey:@"OakTextViewNormalFontSize"]*1.5);
		isAbove = YES;
	}
	caretPos.x -= 25;
	[self setFrameTopLeftPoint:caretPos];
}

- (void)setupInterface
{
	[self setBackgroundColor:[NSColor clearColor]];
	[self setAlphaValue:1.0];
	[self setOpaque:NO];
	[self setAcceptsMouseMovedEvents:YES];
	[self setReleasedWhenClosed:YES];
	[self setLevel:NSStatusWindowLevel];
	[self setHidesOnDeactivate:YES];
	[self setHasShadow:YES];
	
	MenuWindowView* view = [[[MenuWindowView alloc] initWithDataSource:self] autorelease];
	[view setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
	[view setDelegate:self];
	[self setContentView:view];
}

// =========================
// = Menu delegate methods =
// =========================

- (void)viewDidChangeSelection
{
	NSMutableDictionary* selectedItem = (NSMutableDictionary*)[[self contentView] selectedItem];
	
	if(selectedItem == nil)
		return;
	// unless we have an input handle, writing on the outputHandle is pointless, 
	// since we won't get anything in return.
	[self closeDocumentationPopup];

	  if(NSString* documentation = [selectedItem objectForKey:DOCUMENTATION]){
	      [self displayDocumentationPopup:documentation];
	  } else if ([selectedItem objectForKey:FALLBACK]) {
		  [Fallback startLookupForItem:selectedItem];
	  }

}

// ================================
// = Documentation Popup handling =
// ================================

-(void)closeDocumentationPopup
{
	if(htmlTooltip != nil){
		[htmlTooltip close];
		htmlTooltip = nil;
	}	
}

- (void)displayDocumentationPopup:(NSString*)html
{
	[html retain];
	NSPoint pos = caretPos;
	pos.x = pos.x + [self frame].size.width + 5;
	[self closeDocumentationPopup];
	htmlTooltip = [DocPopup showWithContent:html atLocation:pos transparent: NO];
	[html release];
}

- (void)handleItemChange:(NSNotification*)notification;
{
	Fallback* fallback = (Fallback*)[notification object];
    NSMutableDictionary* dictionary = [fallback item];
	[fallback release];
	

	if(NSString* documentation = [dictionary valueForKey:DOCUMENTATION]){
		NSMutableDictionary* selectedItem = (NSMutableDictionary*)[[self contentView] selectedItem];
		// if the currently selected item is the same as the received string then display the documentation
		if(selectedItem != nil && [[dictionary objectForKey:INDEX] isEqualToNumber:[selectedItem valueForKey:INDEX]]){
			[self displayDocumentationPopup:documentation];
		}		
	}	

}

// ====================
// = Filter the items =
// ====================

- (void)filter
{
	NSRect mainScreen = [self rectOfMainScreen];
	
	NSArray* newFiltered;
	if([mutablePrefix length] > 0)
	{
		NSPredicate* predicate;
		if(caseSensitive)
			predicate = [NSPredicate predicateWithFormat:@"match BEGINSWITH %@ OR (match == NULL AND display BEGINSWITH %@)", [self filterString], [self filterString]];
		else
			predicate = [NSPredicate predicateWithFormat:@"match BEGINSWITH[c] %@ OR (match == NULL AND display BEGINSWITH[c] %@)", [self filterString], [self filterString]];
		newFiltered = [suggestions filteredArrayUsingPredicate:predicate];
	}
	else
	{
		newFiltered = suggestions;
	}

	[self setFiltered:newFiltered];
	//[theTableView reloadData];
	[[self contentView] reloadData];
}

- (void)setFiltered:(NSArray*)array
{
	id oldThing = filtered;
	filtered = [array retain];
	[oldThing release];
}
// =========================
// = Convenience functions =
// =========================

- (NSString*)filterString
{
	return staticPrefix ? [staticPrefix stringByAppendingString:mutablePrefix] : mutablePrefix;
}

- (NSRect)rectOfMainScreen
{
	NSRect mainScreen = [[NSScreen mainScreen] frame];
	enumerate([NSScreen screens], NSScreen* candidate)
	{
		if(NSMinX([candidate frame]) == 0.0f && NSMinY([candidate frame]) == 0.0f)
			mainScreen = [candidate frame];
	}
	return mainScreen;
}

// =============================
// = Run the actual popup-menu =
// =============================

- (void)orderFront:(id)sender
{
	[self filter];
	[super orderFront:sender];
	[self performSelector:@selector(watchUserEvents) withObject:nil afterDelay:0.05];
}

- (void)watchUserEvents
{
	closeMe = NO;
	while(!closeMe)
	{
		NSEvent* event = [NSApp nextEventMatchingMask:NSAnyEventMask
											untilDate:[NSDate distantFuture]
											   inMode:NSDefaultRunLoopMode
											  dequeue:YES];
		
		if(!event)
			continue;
		
		NSEventType t = [event type];
		if([(MenuWindowView*)[self contentView] TMDcanHandleEvent:event])
		{
			// skip the rest
		}
		else if(t == NSKeyDown)
		{
			unsigned int flags = [event modifierFlags];
			unichar key        = [[event characters] length] == 1 ? [[event characters] characterAtIndex:0] : 0;
			if((flags & NSControlKeyMask) || (flags & NSAlternateKeyMask) || (flags & NSCommandKeyMask))
			{
				[NSApp sendEvent:event];
				break;
			}
			else if([event keyCode] == 53) // escape
			{
				break;
			}
			else if(key == NSCarriageReturnCharacter)
			{
				[self completeAndInsertSnippet];
			}
			else if(key == NSBackspaceCharacter || key == NSDeleteCharacter)
			{
				[NSApp sendEvent:event];
				if([mutablePrefix length] == 0)
					break;
				
				[mutablePrefix deleteCharactersInRange:NSMakeRange([mutablePrefix length]-1, 1)];
				[self filter];
			}
			else if(key == NSTabCharacter)
			{
				if([filtered count] == 0)
				{
					[NSApp sendEvent:event];
					break;
				}
				else if([filtered count] == 1)
				{
					[self completeAndInsertSnippet];
				}
				else
				{
					[self insertCommonPrefix];
				}
			}
			else if([textualInputCharacters characterIsMember:key])
			{
				[NSApp sendEvent:event];
				[mutablePrefix appendString:[event characters]];
				[self filter];
			}
			else
			{
				[NSApp sendEvent:event];
				break;
			}
		}
		else if(t == NSRightMouseDown || t == NSLeftMouseDown)
		{
			[NSApp sendEvent:event];
			if(!NSPointInRect([NSEvent mouseLocation], [self frame]))
				break;
		}
		else
		{
			[NSApp sendEvent:event];
		}
	}
	[self closeDocumentationPopup];
	[self close];
	
}

// ==================
// = Action methods =
// ==================

- (void)insertCommonPrefix
{
	int row = [[self contentView] selectedRow];
	if(row == -1)
		return;
	
	id cur = [filtered objectAtIndex:row];
	NSString* curMatch = [cur objectForKey:MATCH] ?: [cur objectForKey:DISPLAY];
	if([[self filterString] length] + 1 < [curMatch length])
	{
		NSString* prefix = [curMatch substringToIndex:[[self filterString] length] + 1];
		NSMutableArray* candidates = [NSMutableArray array];
		for(int i = row; i < [filtered count]; ++i)
		{
			id candidate = [filtered objectAtIndex:i];
			NSString* candidateMatch = [candidate objectForKey:MATCH] ?: [candidate objectForKey:DISPLAY];
			if([candidateMatch hasPrefix:prefix])
				[candidates addObject:candidateMatch];
		}
		
		NSString* commonPrefix = curMatch;
		enumerate(candidates, NSString* candidateMatch)
		commonPrefix = [commonPrefix commonPrefixWithString:candidateMatch options:NSLiteralSearch];
		
		if([[self filterString] length] < [commonPrefix length])
		{
			NSString* toInsert = [commonPrefix substringFromIndex:[[self filterString] length]];
			[mutablePrefix appendString:toInsert];
			insert_text(toInsert);
			[self filter];
		}
	}
	else
	{
		[self completeAndInsertSnippet];
	}
}

- (void)completeAndInsertSnippet
{
	NSMutableDictionary* selectedItem = [[(NSMutableDictionary*)[[self contentView] selectedItem] mutableCopy] autorelease];
	
	if(selectedItem == nil)
		return;
	
	NSString* candidateMatch = [selectedItem objectForKey:MATCH] ?: [selectedItem objectForKey:DISPLAY];
	if([[self filterString] length] < [candidateMatch length])
		insert_text([candidateMatch substringFromIndex:[[self filterString] length]]);
	
	if(NSString* toInsert = [selectedItem objectForKey:INSERT])
	{
		insert_snippet(toInsert);
		closeMe = YES;
	} else if(outputHandle)
	{
			[outputHandle writeString:[selectedItem description]];
			closeMe = YES;
	} 
	
}
@end
