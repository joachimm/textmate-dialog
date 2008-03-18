//
//  Dialog2.mm
//  Dialog2
//
//  Created by Ciaran Walsh on 19/11/2007.
//

#import "Dialog2.h"
#import "TMDCommand.h"
#import "CLIProxy.h"

@protocol TMPlugInController
- (float)version;
@end

@interface Dialog2 : NSObject <DialogServerProtocol>
{
}
- (id)initWithPlugInController:(id <TMPlugInController>)aController;
@end


@implementation Dialog2

- (id)initWithPlugInController:(id <TMPlugInController>)aController
{
	NSApp = [NSApplication sharedApplication];
	if(self = [self init])
	{
		NSConnection *connection = [NSConnection new];
		[connection setRootObject:self];

		NSString* portName = [NSString stringWithFormat:@"%@.%d", DialogServerConnectionName, getpid()];
		if([connection registerName:portName] == NO)
			NSLog(@"couldn't setup dialog server."), NSBeep();
		else if(NSString* path = [[NSBundle bundleForClass:[self class]] pathForResource:@"tm_dialog2" ofType:nil])
		{
			char* old_dialog = getenv("DIALOG");
			if(old_dialog == NULL || not [[NSString stringWithUTF8String:old_dialog] isEqualToString:path])
			{
				if(old_dialog)
					setenv("DIALOG_1", old_dialog, 1);
				setenv("DIALOG", [path UTF8String], 1);
			}

			setenv("DIALOG_PORT_NAME", [portName UTF8String], 1);
		}
	}

	return self;
}

- (void)dispatch:(id)options
{
	CLIProxy* interface = [CLIProxy proxyWithOptions:options];

	NSString* command = [interface numberOfArguments] <= 1 ? @"help" : [interface argumentAtIndex:1];

	if(id target = [TMDCommand objectForCommand:command])
		[target performSelector:@selector(handleCommand:) withObject:interface];
	else
		[interface writeStringToError:@"unknown command, try help.\n"];
}

- (void)hello:(id)options
{
	NSLog(@"%s %@", _cmd, options);
	[self performSelector:@selector(dispatch:) withObject:options afterDelay:0.0];
}

@end
/*
echo '{ menuItems = ({title = 'foo';});}' | "$DIALOG" menu
*/