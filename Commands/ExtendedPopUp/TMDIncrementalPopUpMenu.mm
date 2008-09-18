//
//  TMDIncrementalPopUpMenu.mm
//
//  Created by Joachim Mårtensson on 2007-08-10.
//

#import "TMDIncrementalPopUpMenu.h"
#import "../Utilities/TextMate.h" // -insertSnippetWithOptions
#import "../../TMDCommand.h" // -writeString:
#import "../../Dialog2.h"

@interface NSTableView (MovingSelectedRow)
- (BOOL)TMDcanHandleEvent:(NSEvent*)anEvent;
@end

@implementation NSTableView (MovingSelectedRow)
- (BOOL)TMDcanHandleEvent:(NSEvent*)anEvent
{
	int visibleRows = (int)floorf(NSHeight([self visibleRect]) / ([self rowHeight]+[self intercellSpacing].height)) - 1;
	struct { unichar key; int rows; } const key_movements[] =
	{
		{ NSUpArrowFunctionKey,              -1 },
		{ NSDownArrowFunctionKey,            +1 },
		{ NSPageUpFunctionKey,     -visibleRows },
		{ NSPageDownFunctionKey,   +visibleRows },
		{ NSHomeFunctionKey,    -(INT_MAX >> 1) },
		{ NSEndFunctionKey,     +(INT_MAX >> 1) },
	};

	unichar keyCode = 0;
	if([anEvent type] == NSScrollWheel)
		keyCode = [anEvent deltaY] >= 0.0 ? NSUpArrowFunctionKey : NSDownArrowFunctionKey;
	else if([anEvent type] == NSKeyDown && [[anEvent characters] length] == 1)
		keyCode = [[anEvent characters] characterAtIndex:0];

	for(size_t i = 0; i < sizeofA(key_movements); ++i)
	{
		if(keyCode == key_movements[i].key)
		{
			int row = std::max(0, std::min([self selectedRow] + key_movements[i].rows, [self numberOfRows]-1));
			[self selectRow:row byExtendingSelection:NO];
			[self scrollRowToVisible:row];

			return YES;
		}
	}

	return NO;
}
@end

@interface NSEvent (DeviceDelta)
- (float)deviceDeltaX;
- (float)deviceDeltaY;
@end

@interface TMDIncrementalPopUpMenu (Private)
- (NSRect)rectOfMainScreen;
- (NSString*)filterString;
- (void)setupInterface;
- (void)filter;
- (void)insertCommonPrefix;
- (void)completeAndInsertSnippet;
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
		textualInputCharacters = [[NSMutableCharacterSet alphanumericCharacterSet] retain];
		caseSensitive = YES;
		images = [NSMutableDictionary new];

		[self setupInterface];	
	}
	return self;
}

- (void)dealloc
{
	[staticPrefix release];
	[mutablePrefix release];
	[textualInputCharacters release];
	[images release];

	[outputHandle release];
	[suggestions release];

	[filtered release];

	[super dealloc];
}

- (id)initWithProxy:(CLIProxy*)proxy;
{
	if(self = [self init])
	{
		if(NSString* prefix = [proxy valueForOption:@"static-prefix"])
			staticPrefix = [prefix retain];

		if(NSString* filter = [proxy valueForOption:@"initial-filter"])
			[mutablePrefix appendString:filter];

		if(NSString* allow = [proxy valueForOption:@"extra-chars"])
			[textualInputCharacters addCharactersInString:allow];

		if([[proxy valueForOption:@"wait"] boolValue])
			outputHandle = [[proxy outputHandle] retain];

		if([[proxy valueForOption:@"case-insensitive"] boolValue])
			caseSensitive = NO;

		NSDictionary* initialValues = [proxy readPropertyListFromInput];
		suggestions = [[initialValues objectForKey:@"suggestions"] retain];

		// Convert image paths to NSImages
		NSDictionary* imagePaths = [initialValues objectForKey:@"images"];
		enumerate([imagePaths allKeys], NSString* imageName)
		{
			NSImage* image = [[[NSImage alloc] initByReferencingFile:[imagePaths objectForKey:imageName]] autorelease];
			if(image && [image isValid])
				[images setObject:image forKey:imageName];
		}
	}
	return self;
}

- (void)setCaretPos:(NSPoint)aPos
{
	caretPos = aPos;
	isAbove = NO;
	
	NSRect mainScreen = [self rectOfMainScreen];
	
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
	[self setFrameTopLeftPoint:caretPos];
}

- (void)setupInterface
{
	[self setReleasedWhenClosed:YES];
	[self setLevel:NSStatusWindowLevel];
	[self setHidesOnDeactivate:YES];
	[self setHasShadow:YES];

	NSScrollView* scrollView = [[[NSScrollView alloc] initWithFrame:NSZeroRect] autorelease];
	[scrollView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
	[scrollView setAutohidesScrollers:YES];
	[scrollView setHasVerticalScroller:YES];
	[[scrollView verticalScroller] setControlSize:NSSmallControlSize];

	theTableView = [[[NSTableView alloc] initWithFrame:NSZeroRect] autorelease];
	[theTableView setFocusRingType:NSFocusRingTypeNone];
	[theTableView setAllowsEmptySelection:NO];
	[theTableView setHeaderView:nil];

	NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:@"foo"] autorelease];
	[column setDataCell:[NSClassFromString(@"OakImageAndTextCell") new]];
	[column setEditable:NO];
	[theTableView addTableColumn:column];
	[column setWidth:[theTableView bounds].size.width];

	[theTableView setDataSource:self];
	[scrollView setDocumentView:theTableView];

	[self setContentView:scrollView];
}

// ========================
// = TableView DataSource =
// ========================

- (int)numberOfRowsInTableView:(NSTableView *)aTableView
{
	return [filtered count];
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex
{
	NSImage* image = nil;
	
	NSString* imageName = [[filtered objectAtIndex:rowIndex] objectForKey:@"image"];
	if(imageName)
		image = [images objectForKey:imageName];
	
	[[aTableColumn dataCell] setImage:image];
	
	return [[filtered objectAtIndex:rowIndex] objectForKey:@"display"];
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
	NSPoint old = NSMakePoint([self frame].origin.x, [self frame].origin.y + [self frame].size.height);
	
	int displayedRows = [newFiltered count] < MAX_ROWS ? [newFiltered count] : MAX_ROWS;
	float newHeight   = ([theTableView rowHeight] + [theTableView intercellSpacing].height) * displayedRows;
	
	float maxLen = 1;
	NSString* item;
	int i;
	float maxWidth = [self frame].size.width;
	if([newFiltered count]>0)
	{
		for(i=0; i<[newFiltered count]; i++)
		{
			item = [[newFiltered objectAtIndex:i] objectForKey:@"display"];
			if([item length]>maxLen)
				maxLen = [item length];
		}
		maxWidth = maxLen*18;
		maxWidth = (maxWidth>340) ? 340 : maxWidth;
	}
	if(caretPos.y>=0 && (isAbove || caretPos.y<newHeight))
	{
		isAbove = YES;
		old.y = caretPos.y + (newHeight + [[NSUserDefaults standardUserDefaults] integerForKey:@"OakTextViewNormalFontSize"]*1.5);
	}
	if(caretPos.y<0 && (isAbove || (mainScreen.size.height-newHeight)<(caretPos.y*-1)))
	{
		old.y = caretPos.y + (newHeight + [[NSUserDefaults standardUserDefaults] integerForKey:@"OakTextViewNormalFontSize"]*1.5);
	}
	
	// newHeight is currently the new height for theTableView, but we need to resize the whole window
	// so here we use the difference in height to find the new height for the window
	// newHeight = [[self contentView] frame].size.height + (newHeight - [theTableView frame].size.height);
	[self setFrame:NSMakeRect(old.x,old.y-newHeight,maxWidth,newHeight) display:YES];
	[filtered release];
	filtered = [newFiltered retain];
	[theTableView reloadData];
}

// =========================
// = Convenience functions =
// =========================

- (NSString*)filterString
{
	return staticPrefix ? [staticPrefix stringByAppendingString:mutablePrefix] : mutablePrefix;
}

- (NSRect)rectOfMainScreen;
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
		if([theTableView TMDcanHandleEvent:event])
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
	[self close];
}

// ==================
// = Action methods =
// ==================

- (void)insertCommonPrefix
{
	int row = [theTableView selectedRow];
	if(row == -1 || row == [filtered count]-1)
		return;

	id cur = [filtered objectAtIndex:row];
	NSString* prefix = [cur objectForKey:@"match"] ?: [cur objectForKey:@"display"];
	for(int i = row+1; i < [filtered count]; ++i)
	{
		cur = [filtered objectAtIndex:i];
		prefix = [prefix commonPrefixWithString:([cur objectForKey:@"match"] ?: [cur objectForKey:@"display"]) options:NSLiteralSearch];
	}

	if([[self filterString] length] < [prefix length])
	{
		NSString* toInsert = [prefix substringFromIndex:[[self filterString] length]];
		[mutablePrefix appendString:toInsert];
		insert_text(toInsert);
		[self filter];
	}
}

- (void)completeAndInsertSnippet
{
	if([theTableView selectedRow] == -1)
		return;

	NSMutableDictionary* selectedItem = [[[filtered objectAtIndex:[theTableView selectedRow]] mutableCopy] autorelease];

	NSString* candidateMatch = [selectedItem objectForKey:@"match"] ?: [selectedItem objectForKey:@"display"];
	if([[self filterString] length] < [candidateMatch length])
		insert_text([candidateMatch substringFromIndex:[[self filterString] length]]);

	if(outputHandle)
	{
		// We want to return the index of the selected item into the array which was passed in,
		// but we can’t use the selected row index as the contents of the tablview is filtered down.
		[selectedItem setObject:[NSNumber numberWithInt:[suggestions indexOfObject:[filtered objectAtIndex:[theTableView selectedRow]]]] forKey:@"index"];
		[outputHandle writeString:[selectedItem description]];
	}
	else if(NSString* toInsert = [selectedItem objectForKey:@"insert"])
	{
		insert_snippet(toInsert);
	}

	closeMe = YES;
}
@end
