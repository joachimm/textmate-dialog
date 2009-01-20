//
//  MenuWindowView.mm
//  MenuWindow
//
//  Created by Ciarán Walsh on 10/07/2008.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "MenuWindowView.h"
#import "../../Dialog2.h"
#include <Carbon/Carbon.h>
#import <algorithm>

#define TEXT_INDENT 25

CGRect NSRectToCGRect(NSRect nsrect) {
	return (*(CGRect *)&(nsrect));
}
NSRect NSRectFromCGRect(CGRect cgrect) {
	return (*(NSRect *)&(cgrect));
}

int cap (int min, int val, int max)
{
	return std::min(max, std::max(val, min));
}

@interface NSBezierPath (BezierPathQuartzUtilities)
- (CGPathRef)quartzPath;
@end

@implementation NSBezierPath (BezierPathQuartzUtilities)
// This method works only in Mac OS X v10.2 and later.
- (CGPathRef)quartzPath
{
	int i, numElements;
	
	// Need to begin a path here.
	CGPathRef           immutablePath = NULL;
	
	// Then draw the path elements.
	numElements = [self elementCount];
	if (numElements > 0)
	{
		CGMutablePathRef    path = CGPathCreateMutable();
		NSPoint             points[3];
		BOOL                didClosePath = YES;
		
		for (i = 0; i < numElements; i++)
		{
			switch ([self elementAtIndex:i associatedPoints:points])
			{
				case NSMoveToBezierPathElement:
					CGPathMoveToPoint(path, NULL, points[0].x, points[0].y);
					break;
					
				case NSLineToBezierPathElement:
					CGPathAddLineToPoint(path, NULL, points[0].x, points[0].y);
					didClosePath = NO;
					break;
					
				case NSCurveToBezierPathElement:
					CGPathAddCurveToPoint(path, NULL, points[0].x, points[0].y,
										  points[1].x, points[1].y,
										  points[2].x, points[2].y);
					didClosePath = NO;
					break;
					
				case NSClosePathBezierPathElement:
					CGPathCloseSubpath(path);
					didClosePath = YES;
					break;
			}
		}
		
		// Be sure the path is closed or Quartz may not do valid hit detection.
		if (!didClosePath)
			CGPathCloseSubpath(path);
		
		immutablePath = CGPathCreateCopy(path);
		CGPathRelease(path);
	}
	
	return immutablePath;
}
@end

@interface NSBezierPath (RoundedRectangle)
+ (NSBezierPath *)bezierPathWithRoundedRect: (NSRect) aRect cornerRadius: (double) cRadius;
@end

@implementation NSBezierPath (RoundedRectangle)
+ (NSBezierPath *)bezierPathWithRoundedRect: (NSRect) aRect cornerRadius: (double) cRadius
{
	double left = aRect.origin.x, bottom = aRect.origin.y, width = aRect.size.width, height = aRect.size.height;
	
	//now, crop the radius so we don't get weird effects
	double lesserDim = width < height ? width : height;
	if ( cRadius > lesserDim / 2 )
	{
		cRadius = lesserDim / 2;
	}
	
	//these points describe the rectangle as start and stop points of the
	//arcs making up its corners --points c, e, & g are implicit endpoints of arcs
	//and are unnecessary
	NSPoint a = NSMakePoint( 0, cRadius ), b = NSMakePoint( 0, height - cRadius ),
	d = NSMakePoint( width - cRadius, height ), f = NSMakePoint( width, cRadius ),
	h = NSMakePoint( cRadius, 0 );
	
	//these points describe the center points of the corner arcs
	NSPoint cA = NSMakePoint( cRadius, height - cRadius ),
	cB = NSMakePoint( width - cRadius, height - cRadius ),
	cC = NSMakePoint( width - cRadius, cRadius ),
	cD = NSMakePoint( cRadius, cRadius );
	
	//start
	NSBezierPath *bp = [NSBezierPath bezierPath];
	[bp moveToPoint: a ];
	[bp lineToPoint: b ];
	[bp appendBezierPathWithArcWithCenter: cA radius: cRadius startAngle:180 endAngle:90 clockwise: YES];
	[bp lineToPoint: d ];
	[bp appendBezierPathWithArcWithCenter: cB radius: cRadius startAngle:90 endAngle:0 clockwise: YES];
	[bp lineToPoint: f ];
	[bp appendBezierPathWithArcWithCenter: cC radius: cRadius startAngle:0 endAngle:270 clockwise: YES];
	[bp lineToPoint: h ];
	[bp appendBezierPathWithArcWithCenter: cD radius: cRadius startAngle:270 endAngle:180 clockwise: YES];	
	[bp closePath];
	
	//Transform path to rectangle's origin
	NSAffineTransform *transform = [NSAffineTransform transform];
	[transform translateXBy: left yBy: bottom];
	[bp transformUsingAffineTransform: transform];
	
	return bp; //it's already been autoreleased
}
@end

@interface MenuWindowView ()
- (float)rowHeight;
- (void)newSelectionOccured;
@end

@interface NSObject (MenuWindowView)
- (void)viewDidChangeSelection;
@end


@implementation MenuWindowView
- (id)initWithDataSource:(id)theDataSource
{
	dataSource = theDataSource;
	
	if(self = [self initWithFrame:NSZeroRect])
	{
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(viewFrameDidChange:) name:NSViewFrameDidChangeNotification object:self];
	}
	return self;
}

- (BOOL)showUpArrow;
{
	return visibleItemsCount < [[self items] count];
}

- (BOOL)showDownArrow;
{
	return visibleItemsCount < [[self items] count];
}

- (float)rowHeight
{
	return 17.0f;
}

- (float)maxItemWidth
{
	if(maxWidth == 0)
	{
		// The width is only set once, to avoid the window jumping around
		HIThemeTextInfo tinfo;
		tinfo.version             = 1;
		tinfo.state               = kThemeMenuActive;
		tinfo.fontID              = kThemeMenuItemFont;
		tinfo.horizontalFlushness = kHIThemeTextHorizontalFlushLeft;
		tinfo.verticalFlushness   = kHIThemeTextVerticalFlushCenter;
		tinfo.options             = kHIThemeTextBoxOptionNone;
		tinfo.truncationPosition  = kHIThemeTextTruncationEnd;
		tinfo.truncationMaxLines  = 1;
		
		if([[self items] count]>0)
		{
			for(int i=0; i<[[self items] count]; i++)
			{
				NSString* text = [[[self items] objectAtIndex:i] objectForKey:@"display"];
				float width;
				HIThemeGetTextDimensions((CFStringRef)text, 600, &tinfo, &width, NULL, NULL);
				
				if(width > maxWidth)
					maxWidth = width;
			}
		}
	}
	return maxWidth;
}

- (void)reloadData
{
	NSRect frame      = [[self window] frame];
	frame.size.width  = [self maxItemWidth] + TEXT_INDENT;
	visibleItemsCount = std::min([[self items] count], (unsigned int)MAX_VISIBLE_ROWS);
	frame.size.height = visibleItemsCount * [self rowHeight];
	if([self showUpArrow])
		frame.size.height += [self rowHeight];
	if([self showDownArrow])
		frame.size.height += [self rowHeight];
	frame.origin.y += [self frame].size.height - frame.size.height;
	[self setFrameSize:frame.size];
	[[self window] setFrame:frame display:YES animate:NO];
	int i = [self selectedRow];
	if( (i < visibleOffset) || i > (visibleOffset + visibleItemsCount)){
		selectedItem = nil;
	}
	[self setNeedsDisplay:YES];
}

- (NSArray*)items
{
	return [dataSource valueForKey:@"filtered"];
}

- (void)drawRect:(NSRect)rect
{		
	
	CGContextRef cgContext = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
	HIRect bounds          = NSRectToCGRect([self bounds]);
	
	// TODO switch to HIThemeGetMenuBackgroundShape() for this
	CGPathRef menuPath = [[NSBezierPath bezierPathWithRoundedRect:[self bounds] cornerRadius:5.0] quartzPath];
	
	// Draw the menu background, clipped to the rounded rectangle
	HIThemeMenuDrawInfo drawInfo;
	drawInfo.version = 0;
	drawInfo.menuType = kThemeMenuTypePullDown;
	CGContextAddPath(cgContext, menuPath);
	CGContextClip(cgContext);
	HIThemeDrawMenuBackground(&bounds, &drawInfo, cgContext, kHIThemeOrientationNormal);
	
	// Add a border around the menu
	CGContextAddPath(cgContext, menuPath);
	CGContextSetRGBStrokeColor(cgContext, 0.8, 0.8, 0.8, 1.0);
	CGContextSetLineWidth(cgContext, 1.0);
	CGContextStrokePath(cgContext);
	
	float y = [self bounds].size.height - [self rowHeight];
	
	if([self showUpArrow])
	{
		HIRect arrowBounds      = bounds;
		arrowBounds.origin.y    = y;
		arrowBounds.size.height = [self rowHeight];
		HIThemeMenuItemDrawInfo aMenuItemDrawInfo;
		aMenuItemDrawInfo.itemType = kThemeMenuItemScrollDownArrow;
		aMenuItemDrawInfo.state    = kThemeMenuActive;
		HIThemeDrawMenuItem(&arrowBounds, &arrowBounds, &aMenuItemDrawInfo, cgContext, kHIThemeOrientationNormal, NULL);
		y -= [self rowHeight];
	}
	if(selectedItem == nil) {
		selectedItem = [[self items] objectAtIndex:visibleOffset];
	}
	for(int i = visibleOffset; i < visibleOffset + visibleItemsCount; ++i)
	{
		NSDictionary* item = [[self items] objectAtIndex:i];
		NSString* text     = [item objectForKey:@"display"];
		HIRect hiRowRect   = CGRectMake(0, y, [self bounds].size.width, [self rowHeight]);
		HIThemeMenuItemDrawInfo aMenuItemDrawInfo;
		aMenuItemDrawInfo.itemType = kThemeMenuItemPlain; //  + kThemeMenuItemPopUpBackground
		aMenuItemDrawInfo.state    = item == selectedItem ? kThemeMenuSelected : kThemeMenuActive;
		
		HIThemeDrawMenuItem(&hiRowRect, &hiRowRect, &aMenuItemDrawInfo, cgContext, kHIThemeOrientationNormal, NULL);
		hiRowRect.origin.x   += TEXT_INDENT;
		hiRowRect.size.width -= TEXT_INDENT;
		
		HIThemeTextInfo tinfo;
		tinfo.version             = 1;
		tinfo.state               = kThemeMenuActive;
		tinfo.fontID              = kThemeMenuItemFont;
		tinfo.horizontalFlushness = kHIThemeTextHorizontalFlushLeft;
		tinfo.verticalFlushness   = kHIThemeTextVerticalFlushCenter;
		tinfo.options             = kHIThemeTextBoxOptionNone;
		tinfo.truncationPosition  = kHIThemeTextTruncationEnd;
		tinfo.truncationMaxLines  = 1;
		
		NSFont* font = [NSFont fontWithName:[[NSUserDefaults standardUserDefaults] stringForKey:@"OakTextViewNormalFontName"]  ?: [[NSFont userFixedPitchFontOfSize:12.0] fontName]
									   size:[[NSUserDefaults standardUserDefaults] integerForKey:@"OakTextViewNormalFontSize"] ?: 12 ];
		[text drawInRect:NSRectFromCGRect(hiRowRect)
		  withAttributes:[NSDictionary dictionaryWithObjectsAndKeys:
						  ((aMenuItemDrawInfo.state == kThemeMenuSelected) ? [NSColor selectedMenuItemTextColor] : [NSColor blackColor]), NSForegroundColorAttributeName,
						  font, NSFontAttributeName,
						  nil]];
		
		y -= [self rowHeight];
	}
	
	if([self showDownArrow])
	{
		HIRect arrowBounds      = bounds;
		arrowBounds.origin.y    = y;
		arrowBounds.size.height = [self rowHeight];
		HIThemeMenuItemDrawInfo aMenuItemDrawInfo;
		aMenuItemDrawInfo.itemType = kThemeMenuItemScrollUpArrow;
		aMenuItemDrawInfo.state    = kThemeMenuActive;
		HIThemeDrawMenuItem(&arrowBounds, &arrowBounds, &aMenuItemDrawInfo, cgContext, kHIThemeOrientationNormal, NULL);
	}
	
	CGPathRelease(menuPath);
	menuPath = NULL;
	[self newSelectionOccured];
	
}

- (int)selectedRow {
	return [[self items] indexOfObject:selectedItem];
}
// - (void)viewDidMoveToWindow
// {
// 	[self reloadData];
// }

- (void)viewFrameDidChange:(NSNotification*)notification
{
	// This resets the CoreGraphics window shadow (calculated around our custom window shape content)
	// so it's recalculated for the new shape, etc.  The API to do this was introduced in 10.2.
	if(floor(NSAppKitVersionNumber) <= NSAppKitVersionNumber10_1)
	{
		[[self window] setHasShadow:NO];
		[[self window] setHasShadow:YES];
	}
	else
		[[self window] invalidateShadow];
}

- (id)selectedItem;
{
	return selectedItem;
}

- (void)arrangeInitialSelection
{
	selectedItem = [[self items] objectAtIndex:0];
	[self setNeedsDisplay:YES];
}

// =========
// = Mouse =
// =========

- (void)mouseMoved:(NSEvent*)event
{
	NSPoint cursor = [self convertPoint:[[self window] mouseLocationOutsideOfEventStream] fromView:nil];
	if(cursor.x >= [self bounds].origin.x && cursor.x < [self bounds].origin.x + [self bounds].size.width)
	{
		id newSelectedItem   = nil;
		int newVisibleOffset = visibleOffset;
		int index            = ([self bounds].size.height - cursor.y) / [self rowHeight];
		if(index < 0) return;
		
		if([self showUpArrow])
		{
			if(index == 0)
			{
				newVisibleOffset = std::max(0, newVisibleOffset-1);
				index = NSNotFound;
			}
			else
				index--;
		}
		if(index < visibleItemsCount)
		{
			newSelectedItem = [[self items] objectAtIndex:visibleOffset + index];
		}
		else if([self showDownArrow])
		{
			if(index == visibleItemsCount)
			{
				newVisibleOffset = std::min((int)[[self items] count] - MAX_VISIBLE_ROWS, newVisibleOffset+1);
				index = NSNotFound;
			}
		}
		if(newSelectedItem != selectedItem || newVisibleOffset != visibleOffset)
		{
			visibleOffset = newVisibleOffset;
			selectedItem  = newSelectedItem;
			[self setNeedsDisplay:YES];
		}
	}
}

- (BOOL)TMDcanHandleEvent:(NSEvent*)anEvent
{
	struct { unichar key; int rows; } const key_movements[] =
	{
		{ NSUpArrowFunctionKey,                    -1 },
		{ NSDownArrowFunctionKey,                  +1 },
		{ NSPageUpFunctionKey,     -visibleItemsCount },
		{ NSPageDownFunctionKey,   +visibleItemsCount },
		{ NSHomeFunctionKey,          -(INT_MAX >> 1) },
		{ NSEndFunctionKey,           +(INT_MAX >> 1) },
	};
	
	unichar keyCode = 0;
	if([anEvent type] == NSScrollWheel)
		keyCode = [anEvent deltaY] >= 0.0 ? NSUpArrowFunctionKey : NSDownArrowFunctionKey;
	else if([anEvent type] == NSKeyDown && [[anEvent characters] length] == 1)
		keyCode = [[anEvent characters] characterAtIndex:0];
	else if([anEvent type] == NSMouseMoved)
	{
		[self mouseMoved:anEvent];
		return YES;
	}
	
	for(size_t i = 0; i < sizeofA(key_movements); ++i)
	{
		if(keyCode == key_movements[i].key)
		{
			int selectedIndex = [[self items] indexOfObject:selectedItem];
			if(selectedIndex == NSNotFound)
				selectedIndex = key_movements[i].rows > 0 ? -1 : [[self items] count];
			selectedIndex = cap(0, selectedIndex + key_movements[i].rows, (int)[[self items] count]-1);
			selectedItem  = [[self items] objectAtIndex:selectedIndex];
			if(selectedIndex >= visibleOffset + visibleItemsCount)
				visibleOffset = selectedIndex - visibleItemsCount + 1;
			else if(selectedIndex < visibleOffset)
				visibleOffset = selectedIndex;
			visibleOffset = cap(0, visibleOffset, (int)[[self items] count]-1);
			[self setNeedsDisplay:YES];
			return YES;
		}
	}
	
	return NO;
}
- (void)newSelectionOccured{
	if([[self delegate] respondsToSelector:@selector(viewDidChangeSelection)])
		[[self delegate] viewDidChangeSelection];
}
- (id)delegate { return delegate; }
- (void)setDelegate:(id)del { delegate = del; }

- (void)mouseDown:(NSEvent*)event
{
	NSLog(@"[%@ mouseDown:%@]", [self class], event);
}
@end
