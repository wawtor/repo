#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

/* Settings.app pane for airplayd. Specifiers live in Root.plist inside the bundle.
 * Reads/writes the shared CFPreferences domain com.wawtor.airplayd (the same plist
 * airplayd itself reads); each change posts the Darwin notification
 * "com.wawtor.airplayd.prefschanged" so a running airplayd can apply it live. */

static NSString *const kDomain = @"com.wawtor.airplayd";
static NSString *const kChanged = @"com.wawtor.airplayd.prefschanged";

@interface APDPrefsListController : PSListController
@end

@implementation APDPrefsListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (NSString *)title { return @"airplayd"; }

/* Custom get/set so values land in our shared domain regardless of the pane's own
 * container, and so every write pokes airplayd via a Darwin notification. */
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:
        [NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.plist", kDomain]];
    id val = d[key];
    return val ?: [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    NSString *path = [NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.plist", kDomain];
    NSMutableDictionary *d = [NSMutableDictionary dictionaryWithContentsOfFile:path] ?: [NSMutableDictionary dictionary];
    if (value) d[key] = value; else [d removeObjectForKey:key];
    [d writeToFile:path atomically:YES];
    // Keep CFPreferences' cache in sync for any client that reads via the API.
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value,
                             (__bridge CFStringRef)kDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)kChanged, NULL, NULL, YES);
}

@end
