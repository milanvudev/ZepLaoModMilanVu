#import "ZXNetwork.h"
#import "ZXConfig.h"
#import "ZXLog.h"
#import <objc/runtime.h>

// Endpoint fragments taken from the Android module (HideAdsHook / DisableZaloTrackingHook).
static NSArray<NSString *> *ZXAdsFragments(void)      { return @[@"/group/ads", @"/zpads/"]; }
static NSArray<NSString *> *ZXQoSFragments(void)      { return @[@"/api/qos/", @"/zalocloudqos"]; }
static NSArray<NSString *> *ZXTrackingFragments(void) { return @[@"/tracking"]; }
static NSArray<NSString *> *ZXFirebaseHosts(void)     { return @[@"firebaselogging", @"app-measurement.com", @"crashlytics.com"]; }

static BOOL ZXContainsAny(NSString *s, NSArray<NSString *> *needles)
{
    for (NSString *n in needles)
        if ([s rangeOfString:n options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    return NO;
}

@interface ZXBlockProtocol : NSURLProtocol
@end

@implementation ZXBlockProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return [ZXNetwork shouldBlockURL:request.URL]; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading
{
    ZXLog(@"blocked %@%@", self.request.URL.host, self.request.URL.path);
    NSError *err = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil];
    [self.client URLProtocol:self didFailWithError:err];
}
- (void)stopLoading {}
@end

static void ZXAddProtocol(NSURLSessionConfiguration *cfg)
{
    if (!cfg) return;
    NSMutableArray *list = [(cfg.protocolClasses ?: @[]) mutableCopy];
    if ([list containsObject:[ZXBlockProtocol class]]) return;
    [list insertObject:[ZXBlockProtocol class] atIndex:0];
    cfg.protocolClasses = list;
}

static void ZXWrapConfigFactory(SEL s)
{
    Class meta = object_getClass([NSURLSessionConfiguration class]);
    Method m = class_getInstanceMethod(meta, s);
    if (!m) return;
    IMP orig = method_getImplementation(m);
    IMP n = imp_implementationWithBlock(^id(id self_) {
        NSURLSessionConfiguration *c = ((id (*)(id, SEL))orig)(self_, s);
        ZXAddProtocol(c);
        return c;
    });
    method_setImplementation(m, n);
}

@implementation ZXNetwork

+ (BOOL)shouldBlockURL:(NSURL *)url
{
    NSString *s = url.absoluteString;
    if (s.length == 0) return NO;
    if ([ZXConfig boolForKey:ZXK_BLOCK_ADS] && ZXContainsAny(s, ZXAdsFragments())) return YES;
    if ([ZXConfig boolForKey:ZXK_BLOCK_QOS] && ZXContainsAny(s, ZXQoSFragments())) return YES;
    if ([ZXConfig boolForKey:ZXK_DISABLE_TRACKING] && ZXContainsAny(url.path ?: @"", ZXTrackingFragments())) return YES;
    if ([ZXConfig boolForKey:ZXK_DISABLE_FIREBASE] && ZXContainsAny(url.host ?: @"", ZXFirebaseHosts())) return YES;
    return NO;
}

+ (void)install
{
    [NSURLProtocol registerClass:[ZXBlockProtocol class]]; // NSURLSession.sharedSession
    ZXWrapConfigFactory(@selector(defaultSessionConfiguration));
    ZXWrapConfigFactory(@selector(ephemeralSessionConfiguration));
    ZXLog(@"network filter installed");
}

@end
