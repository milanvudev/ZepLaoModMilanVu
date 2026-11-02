#import <Foundation/Foundation.h>

/// Data-driven runtime hooks (pure Objective-C runtime, no Substrate API needed).
///
/// rules.json = array of:
/// {
///   "id": "block_seen",            // free text
///   "enabled": true,
///   "class": "SomeClass",          // from class-dump / the in-app scanner
///   "selector": "sendSeen:",
///   "classMethod": false,          // true => +method
///   "action": "skip",              // skip | return | ttl | antirecall
///   "returnValue": 0,              // for skip/return on non-void methods
///   "configKey": "block_send_seen",// hook only active while this setting is ON (optional)
///   "argIndex": 1                  // antirecall: which argument (1-based, excluding self/_cmd)
/// }
@interface ZXHookEngine : NSObject
+ (NSString *)rulesPath;
+ (NSString *)defaultRulesJSON;
+ (void)installFromRules;
+ (void)ensureRulesFile;
+ (void)retryPending;
@end
