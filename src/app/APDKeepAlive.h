#import <Foundation/Foundation.h>

/* Keeps airplayd alive in the background (so Bonjour + the RAOP server keep running
 * when the user leaves the app) by holding an active audio session playing silence. */
@interface APDKeepAlive : NSObject
+ (instancetype)shared;
- (void)start;
- (void)stop;
@end
