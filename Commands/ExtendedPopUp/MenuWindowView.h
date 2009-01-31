//
//  MenuWindowView.h
//  MenuWindow
//
//  Created by Ciarán Walsh on 10/07/2008.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#include <Carbon/Carbon.h>

#define MAX_VISIBLE_ROWS 10

@interface MenuWindowView : NSView
{
	int visibleItemsCount;
	int visibleOffset;

	float maxWidth;

	// Non-retained
	id dataSource;
	id selectedItem;
	id previousSelected;
  id delegate;
}
- (id)initWithDataSource:(id)theDataSource;
- (void)reloadData;
- (id)selectedItem;
- (int)selectedRow;
- (NSArray*)items;
- (id)delegate;
- (void)setDelegate:(id)del;
- (BOOL)TMDcanHandleEvent:(NSEvent*)anEvent;
- (void)arrangeInitialSelection;
@end
