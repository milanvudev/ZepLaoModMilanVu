#import <Foundation/Foundation.h>

/// Blocks ads / QoS / tracking / Firebase-logging HTTP requests made through NSURLSession.
@interface ZXNetwork : NSObject
+ (void)install;
+ (BOOL)shouldBlockURL:(NSURL *)url;
@end
