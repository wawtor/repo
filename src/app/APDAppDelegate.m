#import "APDAppDelegate.h"
#import "APDDisplayView.h"
#import "APDReceiver.h"

@interface APDRootViewController : UIViewController
@property (nonatomic, strong) APDDisplayView *display;
@end
@implementation APDRootViewController
- (void)loadView {
    self.display = [[APDDisplayView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.display.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = self.display;
}
- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }
@end

@implementation APDAppDelegate {
    APDReceiver *_receiver;
    APDRootViewController *_root;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)opts {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    _root = [[APDRootViewController alloc] init];
    self.window.rootViewController = _root;
    [self.window makeKeyAndVisible];

    // Never sleep while acting as a display.
    application.idleTimerDisabled = YES;

    _receiver = [[APDReceiver alloc] init];
    _receiver.display = _root.display;
    _receiver.serverName = [NSString stringWithFormat:@"%@ (Display)", [UIDevice currentDevice].name];

    NSString *err = nil;
    if (![_receiver startWithError:&err]) {
        [_root.display showStatus:[NSString stringWithFormat:@"Failed to start:\n%@", err]];
        NSLog(@"[APD] start failed: %@", err);
    }
    return YES;
}

- (void)applicationWillTerminate:(UIApplication *)application { [_receiver stop]; }
@end
