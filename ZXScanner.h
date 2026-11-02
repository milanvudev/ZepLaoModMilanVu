#import <Foundation/Foundation.h>

/// Lists Objective-C classes/methods of the host app whose names look related to
/// recall / seen / typing / ttl / ads, so you can write rules.json entries.
@interface ZXScanner : NSObject
+ (NSString *)runScan;   // returns path of scan.txt
+ (NSString *)scanPath;
@end
