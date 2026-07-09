#import <Foundation/Foundation.h>

/* Reads the shared preferences the Settings.app pane writes
 * (/var/mobile/Library/Preferences/com.wawtor.airplayd.plist). Read fresh each call so
 * a live change picked up via the "com.wawtor.airplayd.prefschanged" Darwin notification
 * is always current — no cfprefsd caching surprises. */
@interface APDPrefs : NSObject
+ (BOOL)serverEnabled;                 // default YES
+ (BOOL)autoConnect;                   // default YES
+ (NSString *)receiverNameOrNil;       // nil/empty => caller uses "<device> (Display)"
@end
