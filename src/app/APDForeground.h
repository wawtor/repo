#import <Foundation/Foundation.h>

/* Auto-connect behaviour: when a Mac starts a mirror session while airplayd is running
 * in the background, bring airplayd to the front so the picture is actually on screen;
 * when the session ends, drop back to the background so the user's iPad returns to
 * whatever they were doing. Gated on the "AutoConnect" preference (default YES). */
@interface APDForeground : NSObject

+ (BOOL)autoConnectEnabled;          // reads NSUserDefaults "AutoConnect" (default YES)

+ (void)bringToFront;                // self-launch airplayd into the foreground
+ (void)sendToBack;                  // suspend airplayd back to the background

@end
