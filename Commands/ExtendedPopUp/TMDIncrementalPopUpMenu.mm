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
#import <vector>



@interface TMDIncrementalPopUpMenu (Private)
- (NSRect)rectOfMainScreen;
- (NSString*)filterString;
- (void)setupInterface;
- (void)filter;
- (void)insertCommonPrefix;
- (void)completeAndInsertSnippet;
- (void)startReadingDocs;
- (void)stopProcess;
- (void)closeHTMLPopup;
- (void)writeNullTerminatedString:(NSString*)string;
- (void)setFiltered:(NSArray*)array;
@end

@implementation TMDIncrementalPopUpMenu
// =============================
// = Setup/tear-down functions =
// =============================
- (id)init
{
	if(self = [super initWithContentRect:NSZeroRect styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO])
	{
		mutablePrefix = [NSMutableString new];
		htmlDocString = [NSMutableString new];
		textualInputCharacters = [[NSMutableCharacterSet alphanumericCharacterSet] retain];
		caseSensitive = YES;
		
		[self setupInterface];	
	}
	return self;
}

- (void)dealloc
{
	[staticPrefix release];
	[mutablePrefix release];
	[htmlDocString release];
	[textualInputCharacters release];
	
	[outputHandle release];
	[suggestions release];
	
	[filtered release];
	[inputHandle release];
	
	[super dealloc];
}

- (id)initWithItems:(NSArray*)someSuggestions alreadyTyped:(NSString*)aUserString staticPrefix:(NSString*)aStaticPrefix additionalWordCharacters:(NSString*)someAdditionalWordCharacters caseSensitive:(BOOL)isCaseSensitive writeChoiceToFileDescriptor:(NSFileHandle*)aFileDescriptor
readHTMLFromFileDescriptor:(NSFileHandle*)readFrom
{
	if(self = [self init])
	{
		suggestions = [someSuggestions retain];
		
		if(aUserString)
			[mutablePrefix appendString:aUserString];
		
		if(aStaticPrefix)
			staticPrefix = [aStaticPrefix retain];
		
		if(someAdditionalWordCharacters)
			[textualInputCharacters addCharactersInString:someAdditionalWordCharacters];
		
		caseSensitive = isCaseSensitive;
		outputHandle = [aFileDescriptor retain];
		if(readFrom) {
			inputHandle = [readFrom retain];
			[self startReadingDocs];
		}
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
	NSMutableDictionary* selectedItem = [[(NSMutableDictionary*)[[self contentView] selectedItem] mutableCopy] autorelease];
	
	if(selectedItem == nil)
		return;
	// unless we have an input handle, writing on the outputHandle is pointless, 
	// since we won't get anything in return.
	if(outputHandle && inputHandle)
	{
		[self writeNullTerminatedString:[selectedItem description]];
	}
}

// =======================
// = HTML Popup handling =
// =======================

- (void)displayHTMLPopup:(NSString*)html
{
	[html retain];
	NSPoint pos = caretPos;
	pos.x = pos.x + [self frame].size.width + 5;
	[self closeHTMLPopup];
	@synchronized(htmlTooltip){
	  htmlTooltip = [DocPopup showWithContent:html atLocation:pos transparent: NO];
	}
	[html release];
}

- (void)closeHTMLPopup
{
	@synchronized(htmlTooltip){
		if(htmlTooltip != nil){
			[htmlTooltip close];
		}
	}
}

// ===========
// = Pipeing =
// ===========

- (void)startReadingDocs
{
	[[NSNotificationCenter defaultCenter] addObserver:self 
											 selector:@selector(getData:) 
												 name: NSFileHandleReadCompletionNotification 
											   object: inputHandle];
	[inputHandle readInBackgroundAndNotify];
}

- (void)getData: (NSNotification*)aNotification
{
    NSData *data = [[aNotification userInfo] objectForKey:NSFileHandleNotificationDataItem];
	// assuming there is no way to get zero length data unless EOF?
    if ([data length])
    {
		int i = 0;
		int index = -1;
		int length = [data length]; 
		char ch;
		char* charArray = (char*) [data bytes];
		while(i < length - 1) {
			ch = charArray[i];
			// if the null terminator is not at the end, assume that new data
			// has been sent afterwards, and use that instead
			if(ch == 0 || ch == 1){
				index = i;
			}
			i++;
		}
        // data might not be null terminated so use
        // -initWithData:encoding: 
		
		if(index != -1) {
			index++; // we want to start at the positon after index
			data = [NSData dataWithBytes: (charArray + index ) length:length - index];
			[htmlDocString setString:@""];

		}
		// it seems that NSString#initWithData:encoding:
		// does not give an empty string when data is -> char* data[1]; data[0]=0;
		if([data length] == 1 && *charArray == 0 && [htmlDocString length] == 0){
			[self closeHTMLPopup];
		} else {
			NSString* html =  [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
			[htmlDocString appendString:html];
		
			// if the string is terminated with a 0 it is documentation
			// ch is the last char in the input
			if( charArray[length - 1] == 0 ){
				[self displayHTMLPopup:htmlDocString];
				[htmlDocString setString:@""];
				// if the string is terminated with a 1 it is a snippet
			} else if( charArray[length - 1] == 1 ){
				[self stopProcess];
				insert_snippet([htmlDocString substringToIndex:[data length]-1]);
			} 
			[html release];
		}
	}
	// read more data    
	[inputHandle readInBackgroundAndNotify];  
}

- (void)stopProcess
{
	[[NSNotificationCenter defaultCenter] removeObserver:self name:NSFileHandleReadCompletionNotification object: inputHandle];
	[self closeHTMLPopup];
	closeMe = YES;
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

- (void)writeNullTerminatedString:(NSString*)string
{
	@synchronized(outputHandle){
		[outputHandle writeString:string];
		char c = 0;
		[outputHandle writeData:[NSData dataWithBytes: &c length: sizeof(char)]];
	}
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
	[self closeHTMLPopup];
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
	NSString* curMatch = [cur objectForKey:@"match"] ?: [cur objectForKey:@"display"];
	if([[self filterString] length] + 1 < [curMatch length])
	{
		NSString* prefix = [curMatch substringToIndex:[[self filterString] length] + 1];
		NSMutableArray* candidates = [NSMutableArray array];
		for(int i = row; i < [filtered count]; ++i)
		{
			id candidate = [filtered objectAtIndex:i];
			NSString* candidateMatch = [candidate objectForKey:@"match"] ?: [candidate objectForKey:@"display"];
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
	
	NSString* candidateMatch = [selectedItem objectForKey:@"match"] ?: [selectedItem objectForKey:@"display"];
	if([[self filterString] length] < [candidateMatch length])
		insert_text([candidateMatch substringFromIndex:[[self filterString] length]]);
	
	if(outputHandle)
	{
		// We want to return the index of the selected item into the array which was passed in,
		// but we can’t use the selected row index as the contents of the tableview is filtered down.
		[selectedItem setObject:[NSNumber numberWithInt:[suggestions indexOfObject:[filtered objectAtIndex:[[self contentView] selectedRow]]]] forKey:@"index"];
		if(inputHandle){
			[selectedItem setObject:@"insertSnippet" forKey:@"callback"];
			[self writeNullTerminatedString:[selectedItem description]];
		} else {
			[outputHandle writeString:[selectedItem description]];
			closeMe = YES;
		}
		
		
	} else if(NSString* toInsert = [selectedItem objectForKey:@"insert"])
	{
		insert_snippet(toInsert);
		closeMe = YES;
	}
	
}
@end
