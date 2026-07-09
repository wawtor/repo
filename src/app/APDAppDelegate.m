#import "APDAppDelegate.h"
#import "APDDisplayView.h"
#import "APDReceiver.h"
#import "APDKeepAlive.h"
#import "APDForeground.h"
#import "APDPrefs.h"

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

/* Route the Darwin "prefs changed" notification back to the delegate. */
static __weak APDAppDelegate *gDelegate = nil;
static void APDPrefsChanged(CFNotificationCenterRef c, void *obs, CFStringRef name,
                            const void *o, CFDictionaryRef ui) {
    dispatch_async(dispatch_get_main_queue(), ^{ [gDelegate applyPrefs]; });
}

@implementation APDAppDelegate {
    APDReceiver *_receiver;
    APDRootViewController *_root;
    BOOL _serverRunning;
    NSString *_currentName;
}

- (NSString *)desiredName {
    NSString *custom = [APDPrefs receiverNameOrNil];
    if (custom) return custom;
    return [NSString stringWithFormat:@"%@ (Display)", [UIDevice currentDevice].name];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)opts {
    gDelegate = self;
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    _root = [[APDRootViewController alloc] init];
    self.window.rootViewController = _root;
    [self.window makeKeyAndVisible];

    // Never sleep while acting as a display.
    application.idleTimerDisabled = YES;

    // Hold a silent audio session so airplayd keeps advertising + serving in the
    // background — the AirPlay receiver stays discoverable without the app open.
    [[APDKeepAlive shared] start];

    _receiver = [[APDReceiver alloc] init];
    _receiver.display = _root.display;

    // Apply the Settings.app preferences (server on/off + receiver name), then keep
    // listening for live changes made in Settings while we're running.
    [self applyPrefs];
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge const void *)self, APDPrefsChanged,
        CFSTR("com.wawtor.airplayd.prefschanged"), NULL,
        CFNotificationSuspensionBehaviorCoalesce);

    // Boot auto-start: the LaunchDaemon drops a marker before uiopen'ing us at boot.
    // If we were launched that way (not a user tap), slip into the background once the
    // server is up so the iPad stays usable but airplayd keeps advertising.
    NSString *marker = @"/var/mobile/.apd-boot";
    if ([[NSFileManager defaultManager] fileExistsAtPath:marker]) {
        [[NSFileManager defaultManager] removeItemAtPath:marker error:nil];
        NSLog(@"[APD] boot-launched — backgrounding after server start");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [APDForeground sendToBack]; });
    }
    return YES;
}

/* Reconcile the running receiver with the current preferences. Safe to call repeatedly. */
- (void)applyPrefs {
    BOOL wantOn = [APDPrefs serverEnabled];
    NSString *wantName = [self desiredName];

    if (!wantOn) {
        if (_serverRunning) { [_receiver stop]; _serverRunning = NO; [_root.display reset]; }
        [_root.display showStatus:@"AirPlay server is off.\nEnable it in Settings › airplayd."];
        return;
    }

    // Server should be on. If the name changed, restart so Bonjour re-advertises it.
    if (_serverRunning && ![wantName isEqualToString:_currentName]) {
        [_receiver stop]; _serverRunning = NO;
    }
    if (!_serverRunning) {
        _receiver.serverName = wantName;
        _currentName = wantName;
        NSString *err = nil;
        if ([_receiver startWithError:&err]) {
            _serverRunning = YES;
        } else {
            [_root.display showStatus:[NSString stringWithFormat:@"Failed to start:\n%@", err]];
            NSLog(@"[APD] start failed: %@", err);
        }
    }
}

- (void)applicationWillTerminate:(UIApplication *)application {
    if (_serverRunning) [_receiver stop];
}
@end
