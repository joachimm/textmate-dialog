#import "CLIProxy.h"

@interface TMDCommand : NSObject
+ (void)registerObject:(id)anObject forCommand:(NSString*)aCommand;
+ (NSDictionary *)registeredCommands;

+ (id)objectForCommand:(NSString*)aCommand;

+ (id)readPropertyList:(NSFileHandle*)aFileHandle error:(NSString**)error;
+ (void)writePropertyList:(id)aPlist toFileHandle:(NSFileHandle*)aFileHandle;
+ (NSData*)readDataUntilNullTerminator:(NSFileHandle*)aFileHandle;
- (NSString *)commandDescription;
- (NSString *)usageForInvocation:(NSString *)invocation;
@end

@interface NSFileHandle (WriteString)
- (void)writeString:(NSString *)string;
@end