#import "ZXConfig.h"

static NSString *const kTTL = @"msg_ttl_value";
static NSString *const kUID = @"current_user_id";
static NSString *const kTabBarIdle = @"tabbar_idle_seconds";

static NSUserDefaults *ZXDefaults(void)
{
    static NSUserDefaults *d;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        d = [[NSUserDefaults alloc] initWithSuiteName:@"com.electroheavenvn.zaloxposed.ios"];
    });
    return d;
}

@implementation ZXConfig

+ (void)registerDefaults
{
    [ZXDefaults() registerDefaults:@{
        ZXK_ANTI_RECALL: @YES,
        ZXK_ANTI_DELETE: @YES,
        ZXK_ANTI_RECALL_INCLUDE_ME: @NO,
        ZXK_ANTI_DELETE_INCLUDE_ME: @NO,
        ZXK_SHOW_CONTENT: @YES,
        ZXK_RECALL_NOTE: @YES,
        ZXK_BLOCK_SEEN: @NO,
        ZXK_SILENT_TYPING: @NO,
        ZXK_BLOCK_ADS: @YES,
        ZXK_DISABLE_TRACKING: @YES,
        ZXK_BLOCK_QOS: @YES,
        ZXK_DISABLE_FIREBASE: @YES,
        ZXK_TTL_OVERRIDE: @NO,
        ZXK_UNLIMITED_MEDIA: @NO,
        ZXK_DEFAULT_ORIGINAL: @YES,
        ZXK_VIDEO_ORIGINAL: @YES,
        ZXK_FLOATING_TABBAR: @NO,
        kTTL: @0,
        kUID: @"",
        kTabBarIdle: @10,
    }];
}

+ (BOOL)boolForKey:(NSString *)key { return [ZXDefaults() boolForKey:key]; }
+ (void)setBool:(BOOL)value forKey:(NSString *)key { [ZXDefaults() setBool:value forKey:key]; }
+ (long long)ttl { return [[ZXDefaults() objectForKey:kTTL] longLongValue]; }
+ (void)setTTL:(long long)value { [ZXDefaults() setObject:@(value) forKey:kTTL]; }
+ (NSString *)currentUserID { return [ZXDefaults() stringForKey:kUID] ?: @""; }
+ (void)setCurrentUserID:(NSString *)value { [ZXDefaults() setObject:(value ?: @"") forKey:kUID]; }
+ (double)tabBarIdleSeconds { return [[ZXDefaults() objectForKey:kTabBarIdle] doubleValue]; }
+ (void)setTabBarIdleSeconds:(double)value { [ZXDefaults() setObject:@(value) forKey:kTabBarIdle]; }

+ (NSString *)dataDir
{
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *dir = [docs stringByAppendingPathComponent:@"ZaloXposed"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

@end
