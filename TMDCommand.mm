#import "TMDCommand.h"
#import "Dialog2.h"
#import <vector>
static NSMutableDictionary* Commands = nil;

@implementation TMDCommand
+ (void)registerObject:(id)anObject forCommand:(NSString*)aCommand
{
	if(!Commands)
		Commands = [NSMutableDictionary new];
	[Commands setObject:anObject forKey:aCommand];
}

+ (NSDictionary *)registeredCommands
{
	return [[Commands copy] autorelease];
}

+ (id)objectForCommand:(NSString*)aCommand
{
	return [Commands objectForKey:aCommand];
}

+ (id)readPropertyList:(NSFileHandle*)aFileHandle error:(NSString**)error;
{
	//NSData* data = [aFileHandle readDataToEndOfFile];
  NSData* data = [TMDCommand readDataUntilNullTerminator:aFileHandle];
	if([data length] == 0)
		return nil;

	id plist = [NSPropertyListSerialization propertyListFromData:data mutabilityOption:NSPropertyListMutableContainersAndLeaves format:nil errorDescription:error];

	return plist;
}

+(NSData*)readDataUntilNullTerminator:(NSFileHandle*)aFileHandle
{
	NSMutableData* mutableData= [NSMutableData data];
	NSData* data;
	while((data = [aFileHandle availableData]) && ([data length] > 0)) 
	{
		[mutableData appendData:data];
		int length = [data length];
		if(( (char*) [data bytes] )[length - 1] == 0) {
			break;
		} 
	}
	return mutableData;
}

+ (void)writePropertyList:(id)aPlist toFileHandle:(NSFileHandle*)aFileHandle
{
	NSString* error = nil;
	if(NSData* data = [NSPropertyListSerialization dataFromPropertyList:aPlist format:NSPropertyListXMLFormat_v1_0 errorDescription:&error])
	{
		[aFileHandle writeData:data];
	}
	else
	{
		fprintf(stderr, "%s\n", [error UTF8String] ?: "unknown error serializing returned property list");
		fprintf(stderr, "%s\n", [[aPlist description] UTF8String]);
	}
}

- (NSString *)commandDescription
{
	return @"No information available for this command";
}

- (NSString *)usageForInvocation:(NSString *)invocation;
{
	return @"No usage information available for this command";
}
@end

@implementation NSFileHandle (WriteString)
- (void)writeString:(NSString *)string;
{
	[self writeData:[string dataUsingEncoding:NSUTF8StringEncoding]];
}
@end