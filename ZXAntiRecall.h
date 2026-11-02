#import <Foundation/Foundation.h>

/// Port of AntiRecallDeleteHook.processMsgPayload (Android).
/// Rewrites "chat.undo" / "chat.delete" packets into normal "webchat" messages
/// so the client shows a notice instead of removing the message.
@interface ZXAntiRecall : NSObject
/// Accepts NSDictionary / NSString(JSON) / NSData(JSON).
/// Returns a replacement object when something was modified, otherwise nil.
+ (id)processObject:(id)obj;
+ (NSString *)historyPath;
+ (void)clearCache;
@end
