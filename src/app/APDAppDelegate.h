#import <UIKit/UIKit.h>
@interface APDAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
- (void)applyPrefs;   // reconcile the receiver with Settings.app prefs (server on/off, name)
@end
