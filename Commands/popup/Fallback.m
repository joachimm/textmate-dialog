//
//  Fallback.m
//  Dialog2
//
//  Created by Joachim Mårtensson on 2010-05-25.
//  Copyright 2010 Chalmers. All rights reserved.
//

#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#import "Fallback.h"

NSString* const TMDItemChangedNotification = @"TMDItemChanged";

@interface NSObject (MenuWindowView)
- (void)itemDidUpdate:(NSMutableDictionary*)dictionary;
@end


@interface Fallback (Private)
-initWithItem:(NSMutableDictionary*)dict;
@end

@implementation Fallback

+(void)startLookupForItem:(NSMutableDictionary*)dict
{
	Fallback* server = [[Fallback alloc] initWithItem:dict];
	[NSThread detachNewThreadSelector:@selector(bgThread:) toTarget:server withObject:[dict objectForKey:@"fallback"]];
}

-(id)initWithItem:(NSMutableDictionary*)dict
{
	if(self = [super init])
	{
		dictionary = [dict retain];
	}
	return self;
}

-(void)dealloc
{
	[dictionary release];
	[super dealloc];
}

-(NSMutableDictionary*)item
{
	return dictionary;
}	

- (void)bgThread:(NSString*)urlString
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	NSURL* url = [NSURL URLWithString:urlString];

	NSString* string = [[[NSString alloc] initWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil] autorelease];
    NSDictionary* reply;
	if(string != nil) {
	  reply = [NSPropertyListSerialization propertyListFromData:[string dataUsingEncoding:NSUTF8StringEncoding] mutabilityOption:NSPropertyListImmutable format:nil errorDescription:NULL];
	} else {
	  reply = [NSDictionary dictionary];
	}
	[self performSelectorOnMainThread:@selector(bgThreadIsDone:) withObject:reply waitUntilDone:NO];
	[pool release];
}

- (void)bgThreadIsDone:(NSDictionary*)reply
{
	NSEnumerator* enumerator = [reply keyEnumerator];
	NSString* key;
	// update the dictionary with the reply
	while ((key = [enumerator nextObject])) {
		[dictionary setObject:[reply objectForKey:key] forKey:key];
	}
	[[NSNotificationCenter defaultCenter] postNotificationName:TMDItemChangedNotification object:self];
}
@end
