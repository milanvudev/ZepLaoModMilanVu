// ZaloXposed iOS - port of https://github.com/ElectroHeavenVN/ZaloXposed (AGPL-3.0)
// Pure Objective-C runtime; no Logos needed.
#import <UIKit/UIKit.h>
#import "ZXConfig.h"
#import "ZXLog.h"
#import "ZXNetwork.h"
#import "ZXHookEngine.h"
#import "ZXUI.h"
#import "ZXRecallMarker.h"

#define ZX_VERSION @"0.1.0"

__attribute__((constructor)) static void ZXInit(void)
{
    @autoreleasepool {
        [ZXConfig registerDefaults];
        ZXLog(@"ZaloXposed iOS %@ loaded in %@", ZX_VERSION, [[NSBundle mainBundle] bundleIdentifier]);
        [ZXNetwork install];
        [ZXHookEngine installFromRules];
        [ZXUI install];
        [ZXRecallMarker install];

        // Retry rules whose classes live in frameworks loaded later.
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                          object:nil queue:nil
                                                      usingBlock:^(NSNotification *n) { [ZXHookEngine retryPending]; }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [ZXHookEngine retryPending];
        });
    }
}
