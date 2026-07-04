#import <Foundation/Foundation.h>
@class APDDisplayView;

/* Owns the UxPlay libairplay RAOP server + Bonjour advertisement, and routes
 * decoded-stream callbacks to the display view. Start once at app launch. */
@interface APDReceiver : NSObject
@property (nonatomic, weak) APDDisplayView *display;
@property (nonatomic, copy) NSString *serverName;      // AirPlay name shown on the Mac
- (BOOL)startWithError:(NSString **)err;
- (void)stop;
@end
