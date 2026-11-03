#import <Foundation/Foundation.h>

// Config keys (same names as the Android module's config.json)
#define ZXK_ANTI_RECALL            @"enable_anti_recall"
#define ZXK_ANTI_DELETE            @"enable_anti_delete"
#define ZXK_ANTI_RECALL_INCLUDE_ME @"anti_recall_include_me"
#define ZXK_ANTI_DELETE_INCLUDE_ME @"anti_delete_include_my_deletion"
#define ZXK_SHOW_CONTENT           @"show_recalled_content"
#define ZXK_RECALL_NOTE            @"show_recall_note"
#define ZXK_BLOCK_SEEN             @"block_send_seen"
#define ZXK_SILENT_TYPING          @"enable_silent_typing"
#define ZXK_BLOCK_ADS              @"block_ads_endpoints"
#define ZXK_DISABLE_TRACKING       @"logging_disable_zalo_tracking"
#define ZXK_BLOCK_QOS              @"logging_block_zalo_qos"
#define ZXK_DISABLE_FIREBASE       @"logging_disable_firebase"
#define ZXK_UNLIMITED_MEDIA        @"enable_unlimited_media"
#define ZXK_DEFAULT_ORIGINAL       @"default_original_quality"
#define ZXK_VIDEO_ORIGINAL         @"video_original"
#define ZXK_TTL_OVERRIDE           @"enable_msg_ttl_override"

@interface ZXConfig : NSObject
+ (void)registerDefaults;
+ (BOOL)boolForKey:(NSString *)key;
+ (void)setBool:(BOOL)value forKey:(NSString *)key;
+ (long long)ttl;
+ (void)setTTL:(long long)value;
+ (NSString *)currentUserID;
+ (void)setCurrentUserID:(NSString *)value;
/// Documents/ZaloXposed (created on demand)
+ (NSString *)dataDir;
@end
