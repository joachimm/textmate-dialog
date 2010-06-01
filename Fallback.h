//
//  DocumentationServer.h
//  Dialog2
//
//  Created by Joachim Mårtensson on 2010-05-25.
//  Copyright 2010 Chalmers. All rights reserved.
//

#import <Foundation/Foundation.h>
extern NSString* const TMDItemChangedNotification;

@interface Fallback : NSObject {
	NSMutableDictionary* dictionary;
}
+(void)startLookupForItem:(NSMutableDictionary*)dict;
-(NSMutableDictionary*)item;
@end
