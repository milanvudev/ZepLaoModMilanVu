#import "ZXBubble.h"
#import "ZXUI.h"
#import "ZXLog.h"
#import "ZXRecallMarker.h"
#import <objc/runtime.h>

extern NSData *ZXCapybaraIconData(void);

static NSString *const kActiveKey = @"zx_bubble_active";
static NSString *const kPosKey = @"zx_bubble_pos";
static const CGFloat kSize = 62;

static UIWindow *gWindow;

@interface ZXBubbleHost : NSObject
+ (void)onTap:(UITapGestureRecognizer *)g;
+ (void)onPan:(UIPanGestureRecognizer *)g;
+ (void)onLongPress:(UILongPressGestureRecognizer *)g;
@end

static UIWindowScene *ZXActiveScene(void)
{
    if (@available(iOS 13.0, *)) {
        UIWindowScene *fallback = nil;
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
            if (![s isKindOfClass:[UIWindowScene class]]) continue;
            if (s.activationState == UISceneActivationStateForegroundActive) return (UIWindowScene *)s;
            if (!fallback) fallback = (UIWindowScene *)s;
        }
        return fallback;
    }
    return nil;
}

static CGRect ZXScreenBounds(void)
{
    UIWindowScene *sc = ZXActiveScene();
    if (@available(iOS 13.0, *)) if (sc) return sc.coordinateSpace.bounds;
    return UIScreen.mainScreen.bounds;
}

static CGPoint ZXSavedOrigin(void)
{
    CGRect b = ZXScreenBounds();
    NSArray *p = [[NSUserDefaults standardUserDefaults] arrayForKey:kPosKey];
    CGFloat fx = p.count == 2 ? [p[0] doubleValue] : 1.0;   // 1 = right edge
    CGFloat fy = p.count == 2 ? [p[1] doubleValue] : 0.55;
    CGFloat x = fx < 0.5 ? 4 : b.size.width - kSize - 4;
    CGFloat y = MAX(60, MIN(b.size.height - kSize - 60, fy * b.size.height));
    return CGPointMake(x, y);
}

static void ZXSavePosition(CGRect frame)
{
    CGRect b = ZXScreenBounds();
    CGFloat fx = (frame.origin.x + kSize / 2) < b.size.width / 2 ? 0.0 : 1.0;
    CGFloat fy = frame.origin.y / MAX(1, b.size.height);
    [[NSUserDefaults standardUserDefaults] setObject:@[@(fx), @(fy)] forKey:kPosKey];
}

@implementation ZXBubbleHost

+ (void)onTap:(UITapGestureRecognizer *)g
{
    [ZXBubble hide];
    [ZXUI show];
}

+ (void)onLongPress:(UILongPressGestureRecognizer *)g
{
    if (g.state != UIGestureRecognizerStateBegan) return;
    [[UIImpactFeedbackGenerator new] impactOccurred];
    [ZXRecallMarker dumpViewHierarchy];
    UIView *v = g.view;
    [UIView animateWithDuration:0.12 animations:^{ v.transform = CGAffineTransformMakeScale(1.25, 1.25); }
                     completion:^(BOOL d) { [UIView animateWithDuration:0.15 animations:^{ v.transform = CGAffineTransformIdentity; }]; }];
}

+ (void)onPan:(UIPanGestureRecognizer *)g
{
    UIWindow *w = gWindow;
    if (!w) return;
    CGRect b = ZXScreenBounds();
    CGPoint t = [g translationInView:w];
    [g setTranslation:CGPointZero inView:w];
    CGRect f = w.frame;
    f.origin.x = MAX(0, MIN(b.size.width - kSize, f.origin.x + t.x));
    f.origin.y = MAX(40, MIN(b.size.height - kSize - 20, f.origin.y + t.y));
    w.frame = f;
    if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled) {
        CGFloat x = (f.origin.x + kSize / 2) < b.size.width / 2 ? 4 : b.size.width - kSize - 4;
        [UIView animateWithDuration:0.22 animations:^{ CGRect nf = w.frame; nf.origin.x = x; w.frame = nf; }
                         completion:^(BOOL done) { ZXSavePosition(w.frame); }];
    }
}

@end

@implementation ZXBubble

+ (void)show
{
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kActiveKey];
    if (gWindow) { gWindow.hidden = NO; return; }

    CGPoint o = ZXSavedOrigin();
    CGRect frame = CGRectMake(o.x, o.y, kSize, kSize);
    UIWindow *w = nil;
    if (@available(iOS 13.0, *)) {
        UIWindowScene *sc = ZXActiveScene();
        w = sc ? [[UIWindow alloc] initWithWindowScene:sc] : [[UIWindow alloc] initWithFrame:frame];
    } else {
        w = [[UIWindow alloc] initWithFrame:frame];
    }
    w.frame = frame;
    w.windowLevel = UIWindowLevelAlert + 100;
    w.backgroundColor = UIColor.clearColor;
    UIViewController *root = [UIViewController new];
    root.view.backgroundColor = UIColor.clearColor;
    w.rootViewController = root;

    UIView *circle = [[UIView alloc] initWithFrame:CGRectMake(1, 1, kSize - 2, kSize - 2)];
    circle.backgroundColor = [UIColor colorWithRed:0.93 green:0.97 blue:1.0 alpha:0.96];
    circle.layer.cornerRadius = (kSize - 2) / 2;
    circle.layer.borderWidth = 2;
    circle.layer.borderColor = [UIColor colorWithRed:0.0 green:0.55 blue:1.0 alpha:0.9].CGColor;
    circle.layer.shadowColor = UIColor.blackColor.CGColor;
    circle.layer.shadowOpacity = 0.28;
    circle.layer.shadowRadius = 4;
    circle.layer.shadowOffset = CGSizeMake(0, 2);

    NSData *d = ZXCapybaraIconData();
    UIImage *img = d ? [UIImage imageWithData:d scale:3.0] : nil;
    UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectInset(circle.bounds, 5, 5)];
    iv.contentMode = UIViewContentModeScaleAspectFit;
    iv.image = img;
    [circle addSubview:iv];
    if (!img) {
        UILabel *l = [[UILabel alloc] initWithFrame:circle.bounds];
        l.text = @"Z"; l.textAlignment = NSTextAlignmentCenter; l.font = [UIFont boldSystemFontOfSize:26];
        [circle addSubview:l];
    }
    [root.view addSubview:circle];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:[ZXBubbleHost class] action:@selector(onTap:)];
    [root.view addGestureRecognizer:tap];
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:[ZXBubbleHost class] action:@selector(onLongPress:)];
    lp.minimumPressDuration = 0.7;
    [root.view addGestureRecognizer:lp];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:[ZXBubbleHost class] action:@selector(onPan:)];
    [root.view addGestureRecognizer:pan];

    w.hidden = NO; // not key: does not steal focus from Zalo
    gWindow = w;
    ZXLog(@"bubble shown");
}

+ (void)hide
{
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kActiveKey];
    gWindow.hidden = YES;
    gWindow = nil;
}

+ (void)restoreIfNeeded
{
    if (!gWindow && [[NSUserDefaults standardUserDefaults] boolForKey:kActiveKey]) [self show];
}

@end
