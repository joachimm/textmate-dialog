//
//  CLIProxy.mm
//  Dialog2
//
//  Created by Ciaran Walsh on 16/02/2008.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "CLIProxy.h"
#import "TMDCommand.h"

@interface CLIProxy (Private)
- (NSArray*)arguments;
@end

@implementation CLIProxy
+ (id)proxyWithOptions:(NSDictionary*)options;
{
	return [[[[self class] alloc] initWithOptions:options] autorelease];
}

- (id)initWithOptions:(NSDictionary*)options
{
	if(self = [super init])
	{
		inputHandle      = [[NSFileHandle fileHandleForReadingAtPath:[options objectForKey:@"stdin"]] retain];
		outputHandle     = [[NSFileHandle fileHandleForWritingAtPath:[options objectForKey:@"stdout"]] retain];
		errorHandle      = [[NSFileHandle fileHandleForWritingAtPath:[options objectForKey:@"stderr"]] retain];
		arguments        = [[options objectForKey:@"arguments"] retain];
		environment      = [[options objectForKey:@"environment"] retain];
		workingDirectory = [[options objectForKey:@"cwd"] retain];
	}
	return self;
}

- (void)dealloc
{
	[inputHandle release];
	[outputHandle release];
	[errorHandle release];
	[arguments release];
	[environment release];
	[workingDirectory release];
	[super dealloc];
}

- (NSString*)workingDirectory
{
	return workingDirectory;
}

- (NSDictionary*)environment
{
	return environment;
}

- (NSArray*)arguments
{
	if(!parsedOptions)
		return arguments;
	return [parsedOptions objectForKey:@"literals"];
}

- (int)numberOfArguments;
{
	return [[self arguments] count];
}

- (NSString*)argumentAtIndex:(int)index;
{
	id argument = nil;
	if([[self arguments] count] > index)
		argument = [[self arguments] objectAtIndex:index];
	return argument;
}

- (id)valueForOption:(NSString*)option;
{
	if(!parsedOptions)
	{
		NSLog(@"Error: -valueForOption: called without first setting an option template");
		return nil;
	}
	return [[parsedOptions objectForKey:@"options"] objectForKey:option];
}

- (void)parseOptions
{
	parsedOptions = ParseOptions([self arguments], optionTemplate, optionCount);
}

- (void)setOptionTemplate:(option_t const*)options count:(size_t)count;
{
	optionTemplate = options;
	optionCount = count;
	[self parseOptions];
}

// ===================
// = Reading/Writing =
// ===================
- (void)writeStringToOutput:(NSString*)text;
{
	[[self outputHandle] writeString:text];
}

- (void)writeStringToError:(NSString*)text;
{
	[[self errorHandle] writeString:text];
}

- (id)readPropertyListFromInput;
{
	NSString* error = nil;
	id plist        = [TMDCommand readPropertyList:[self inputHandle] error:&error];

	if(error || !plist)
		[self writeStringToError:error ?: @"unknown error parsing property list\n"];

	return plist;
}

// ================
// = File handles =
// ================
- (NSFileHandle*)inputHandle;
{
	return inputHandle;
}

- (NSFileHandle*)outputHandle;
{
	return outputHandle;
}

- (NSFileHandle*)errorHandle;
{
	return errorHandle;
}
@end
