#import "APDForeground.h"
#import "APDPrefs.h"
#import <UIKit/UIKit.h>
#import <dlfcn.h>

/* SBSLaunchApplicationWithIdentifier lives in the private SpringBoardServices framework.
 * We resolve it at runtime rather than link it so the build needs no private headers.
 *   int SBSLaunchApplicationWithIdentifier(CFStringRef displayId, Boolean suspended); */
typedef int (*SBSLaunch_t)(CFStringRef, Boolean);

static NSString *const kBundleID = @"com.wawtor.airplayd";

@implementation APDForeground

+ (BOOL)autoConnectEnabled {
    return [APDPrefs autoConnect];
}

+ (void)bringToFront {
    void *h = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_LAZY);
    if (!h) { NSLog(@"[APD] SpringBoardServices dlopen failed: %s", dlerror()); return; }
    SBSLaunch_t launch = (SBSLaunch_t)dlsym(h, "SBSLaunchApplicationWithIdentifier");
    if (!launch) { NSLog(@"[APD] SBSLaunchApplicationWithIdentifier missing"); return; }
    int r = launch((__bridge CFStringRef)kBundleID, false /*not suspended => foreground*/);
    NSLog(@"[APD] bringToFront -> %d", r);
}

+ (void)sendToBack {
    // -[UIApplication suspend] is private but stable: it animates the app out to
    // SpringBoard exactly as the Home button would, leaving us running in the background.
    UIApplication *app = [UIApplication sharedApplication];
    SEL sel = @selector(suspend);
    if ([app respondsToSelector:sel]) {
        // Small delay so the last teardown frame clears before we leave.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [app performSelector:sel];
            #pragma clang diagnostic pop
            NSLog(@"[APD] sendToBack (suspended)");
        });
    }
}

@end
