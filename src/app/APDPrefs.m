#import "APDPrefs.h"

static NSString *const kPath = @"/var/mobile/Library/Preferences/com.wawtor.airplayd.plist";

@implementation APDPrefs

+ (NSDictionary *)dict {
    return [NSDictionary dictionaryWithContentsOfFile:kPath] ?: @{};
}

+ (BOOL)boolFor:(NSString *)key default:(BOOL)def {
    id v = [self dict][key];
    return v ? [v boolValue] : def;
}

+ (BOOL)serverEnabled { return [self boolFor:@"ServerEnabled" default:YES]; }
+ (BOOL)autoConnect   { return [self boolFor:@"AutoConnect"   default:YES]; }

+ (NSString *)receiverNameOrNil {
    id v = [self dict][@"ReceiverName"];
    if ([v isKindOfClass:[NSString class]] && [(NSString *)v length]) return v;
    return nil;
}

@end
