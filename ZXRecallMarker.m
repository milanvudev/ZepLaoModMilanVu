#import "ZXRecallMarker.h"
#import "ZXConfig.h"
#import "ZXLog.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static NSMutableSet<NSString *> *gIds;
static NSMutableDictionary<NSString *, NSNumber *> *gAppClassCache;
static NSObject *gLock;
static NSUInteger gVersion = 1;
static BOOL gSaveScheduled;
static const NSInteger kLabelTag = 0x5A58;

static NSString *ZXIdsPath(void) { return [[ZXConfig dataDir] stringByAppendingPathComponent:@"recalled_ids.json"]; }

static void ZXStoreInit(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gLock = [NSObject new];
        gIds = [NSMutableSet new];
        gAppClassCache = [NSMutableDictionary new];
        NSData *d = [NSData dataWithContentsOfFile:ZXIdsPath()];
        id j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
        if ([j isKindOfClass:[NSArray class]]) [gIds addObjectsFromArray:j];
    });
}

static void ZXSaveSoon(void)
{
    if (gSaveScheduled) return;
    gSaveScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSData *out = nil;
        @synchronized (gLock) {
            gSaveScheduled = NO;
            NSArray *all = gIds.allObjects;
            if (all.count > 5000) all = [all subarrayWithRange:NSMakeRange(all.count - 5000, 5000)];
            out = [NSJSONSerialization dataWithJSONObject:all options:0 error:nil];
        }
        [out writeToFile:ZXIdsPath() atomically:YES];
    });
}

static BOOL ZXIsAppClass(Class c)
{
    if (!c) return NO;
    NSString *name = NSStringFromClass(c);
    @synchronized (gLock) {
        NSNumber *hit = gAppClassCache[name];
        if (hit) return hit.boolValue;
    }
    const char *img = class_getImageName(c);
    NSString *app = [[NSBundle mainBundle] bundlePath];
    BOOL ok = img && strncmp(img, app.UTF8String, app.length) == 0;
    @synchronized (gLock) { gAppClassCache[name] = @(ok); }
    return ok;
}

static BOOL ZXNameLooksLikeId(NSString *name)
{
    NSString *l = name.lowercaseString;
    if ([l hasPrefix:@"_"]) l = [l substringFromIndex:1];
    if (![l containsString:@"id"]) return NO;
    for (NSString *bad in @[@"thread", @"group", @"user", @"fromuid", @"touid", @"sender", @"owner", @"peer", @"valid", @"hidden", @"identifier"])
        if ([l containsString:bad]) return NO;
    for (NSString *kw in @[@"message", @"msg", @"global", @"client", @"cli", @"undo", @"org"])
        if ([l containsString:kw]) return YES;
    return NO;
}

static NSString *ZXNormalizeId(id v)
{
    if ([v isKindOfClass:[NSNumber class]]) {
        long long n = [v longLongValue];
        return n >= 1000 ? [NSString stringWithFormat:@"%lld", n] : nil;
    }
    if ([v isKindOfClass:[NSString class]]) {
        NSString *s = [(NSString *)v stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        return (s.length >= 3 && s.length <= 80) ? s : nil;
    }
    return nil;
}

static NSArray<NSString *> *ZXKeyNames(Class k)
{
    NSMutableArray *names = [NSMutableArray new];
    unsigned n = 0;
    objc_property_t *props = class_copyPropertyList(k, &n);
    for (unsigned i = 0; i < n; i++) [names addObject:@(property_getName(props[i]))];
    free(props);
    Ivar *ivars = class_copyIvarList(k, &n);
    for (unsigned i = 0; i < n; i++) { const char *nm = ivar_getName(ivars[i]); if (nm) [names addObject:@(nm)]; }
    free(ivars);
    return names;
}

/// Collect id-like values (message ids) from obj, recursing once into app-defined objects.
static void ZXCollect(id obj, int depth, NSMutableSet *out, NSMutableArray *debug)
{
    if (!obj || depth < 0) return;
    Class c = [obj class];
    if (!ZXIsAppClass(c)) return;
    for (Class k = c; k && k != [NSObject class] && ZXIsAppClass(k); k = class_getSuperclass(k)) {
        for (NSString *name in ZXKeyNames(k)) {
            id v = nil;
            @try { v = [obj valueForKey:name]; } @catch (NSException *e) { continue; }
            if (!v) continue;
            if (ZXNameLooksLikeId(name)) {
                NSString *norm = ZXNormalizeId(v);
                if (norm) [out addObject:norm];
                if (debug && debug.count < 24) {
                    NSString *d = [[v description] length] > 48 ? [[[v description] substringToIndex:48] stringByAppendingString:@"..."] : [v description];
                    [debug addObject:[NSString stringWithFormat:@"%@.%@=%@:%@%@", NSStringFromClass(c), name, NSStringFromClass([v class]), d, norm ? @"" : @" (bỏ)"]];
                }
                if (norm) continue;
            }
            if (depth > 0 && ![v isKindOfClass:[NSNumber class]] && ![v isKindOfClass:[NSString class]] &&
                ![v isKindOfClass:[NSArray class]] && ![v isKindOfClass:[NSDictionary class]] &&
                ![v isKindOfClass:[UIView class]] && ![v isKindOfClass:[UIViewController class]]) {
                ZXCollect(v, depth - 1, out, debug);
            }
        }
    }
}

// ------------------------------------------------------------------ cell note

static const char kCacheKey;

static UIView *ZXContent(UIView *cell)
{
    if ([cell respondsToSelector:@selector(contentView)]) {
        UIView *c = [(id)cell contentView];
        if ([c isKindOfClass:[UIView class]]) return c;
    }
    return cell;
}


static void ZXRemoveLabel(UIView *cell)
{
    UIView *old = [ZXContent(cell) viewWithTag:kLabelTag];
    if (old) [old removeFromSuperview];
}

static id ZXCellItem(UIView *cell, NSString **keyOut)
{
    static NSArray *keys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ keys = @[@"chatEntity", @"item", @"chatItem", @"entity", @"model", @"messageItem", @"viewModel", @"data", @"object", @"chatObject"]; });
    for (NSString *key in keys) {
        if (![cell respondsToSelector:NSSelectorFromString(key)]) continue;
        id v = nil;
        @try { v = [cell valueForKey:key]; } @catch (NSException *e) { continue; }
        if (v && ZXIsAppClass([v class])) { if (keyOut) *keyOut = key; return v; }
    }
    return nil;
}

static void ZXDiagnoseCell(UIView *cell, id item, NSString *key)
{
    static NSMutableSet *seen;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ seen = [NSMutableSet new]; });
    NSString *cn = NSStringFromClass([cell class]);
    NSString *tag = [NSString stringWithFormat:@"%@|%@", cn, key ?: @"-"];
    @synchronized (seen) {
        if (seen.count >= 40 || [seen containsObject:tag]) return;
        [seen addObject:tag];
    }
    if (!item) {
        NSMutableArray *props = [NSMutableArray new];
        for (Class k = [cell class]; k && ZXIsAppClass(k); k = class_getSuperclass(k)) [props addObjectsFromArray:ZXKeyNames(k)];
        if (props.count > 30) [props removeObjectsInRange:NSMakeRange(30, props.count - 30)];
        ZXLog(@"CELL? %@ khong thay item. props: %@", cn, [props componentsJoinedByString:@","]);
        return;
    }
    NSMutableSet *ids = [NSMutableSet new];
    NSMutableArray *debug = [NSMutableArray new];
    ZXCollect(item, 1, ids, debug);
    ZXLog(@"CELL %@ key=%@ item=%@ ids: %@", cn, key, NSStringFromClass([item class]), [debug componentsJoinedByString:@", "]);
}

static void ZXBubbleSearch(UIView *v, UIView **best, CGFloat *bestArea)
{
    for (UIView *sub in v.subviews) {
        if (sub.tag == kLabelTag || sub.hidden || sub.alpha < 0.05) continue;
        CGSize sz = sub.bounds.size;
        if (sub.layer.cornerRadius >= 8 && sz.width >= 40 && sz.height >= 24 &&
            ![sub isKindOfClass:[UIImageView class]] && ![sub isKindOfClass:[UIButton class]]) {
            CGFloat area = sz.width * sz.height;
            if (area > *bestArea) { *bestArea = area; *best = sub; }
        }
        ZXBubbleSearch(sub, best, bestArea);
    }
}

/// The rounded message bubble inside a chat cell (largest rounded view), or nil.
static UIView *ZXFindBubble(UIView *content)
{
    UIView *best = nil;
    CGFloat area = 0;
    ZXBubbleSearch(content, &best, &area);
    return best;
}

static void ZXUpdateCell(UIView *cell)
{
    ZXStoreInit();
    if (![ZXConfig boolForKey:ZXK_RECALL_NOTE]) { ZXRemoveLabel(cell); return; }
    if (!ZXIsAppClass([cell class])) return;

    NSString *usedKey = nil;
    id item = ZXCellItem(cell, &usedKey);
    ZXDiagnoseCell(cell, item, usedKey);

    NSUInteger count;
    @synchronized (gLock) { count = gIds.count; }
    if (count == 0) return;
    if (!item) { ZXRemoveLabel(cell); return; }

    NSDictionary *cache = objc_getAssociatedObject(cell, &kCacheKey);
    uintptr_t ptr = (uintptr_t)(__bridge void *)item;
    BOOL recalled;
    if (cache && [cache[@"p"] unsignedLongValue] == ptr && [cache[@"v"] unsignedLongValue] == gVersion) {
        recalled = [cache[@"r"] boolValue];
    } else {
        NSMutableSet *ids = [NSMutableSet new];
        ZXCollect(item, 1, ids, nil);
        recalled = NO;
        @synchronized (gLock) { for (NSString *i in ids) if ([gIds containsObject:i]) { recalled = YES; break; } }
        objc_setAssociatedObject(cell, &kCacheKey, @{ @"p": @(ptr), @"v": @(gVersion), @"r": @(recalled) }, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    UIView *content = ZXContent(cell);
    UILabel *lab = (UILabel *)[content viewWithTag:kLabelTag];
    if (!recalled) { if (lab) [lab removeFromSuperview]; return; }
    if (!lab) {
        lab = [UILabel new];
        lab.tag = kLabelTag;
        lab.font = [UIFont systemFontOfSize:8 weight:UIFontWeightMedium];
        lab.textColor = [UIColor colorWithWhite:0.4 alpha:0.85];
        lab.backgroundColor = [UIColor clearColor];
        lab.textAlignment = NSTextAlignmentRight;
        lab.text = @"↺ đã thu hồi";
        lab.userInteractionEnabled = NO;
    }
    // put the note inside the message bubble, bottom-right corner
    UIView *host = ZXFindBubble(content) ?: content;
    if (lab.superview != host) [host addSubview:lab];
    [lab sizeToFit];
    CGFloat w = lab.bounds.size.width, h = lab.bounds.size.height;
    CGFloat x = MAX(2, host.bounds.size.width - w - 8);
    CGFloat y = MAX(0, host.bounds.size.height - h - 2);
    lab.frame = CGRectMake(x, y, w, h);
    [host bringSubviewToFront:lab];
}

static void ZXRefreshVisibleCells(UIView *root)
{
    if ([root isKindOfClass:[UITableViewCell class]] || [root isKindOfClass:[UICollectionViewCell class]]) { [root setNeedsLayout]; return; }
    for (UIView *v in root.subviews) ZXRefreshVisibleCells(v);
}


// ------------------------------------------------------------------ diagnostics

static void ZXDumpView(UIView *v, int depth, NSMutableString *out, int *lines, NSMutableDictionary *cells)
{
    if (depth > 18 || *lines > 320) return;
    Class c = [v class];
    BOOL app = ZXIsAppClass(c);
    BOOL isList = [v isKindOfClass:[UITableView class]] || [v isKindOfClass:[UICollectionView class]];
    BOOL isCell = [v isKindOfClass:[UITableViewCell class]] || [v isKindOfClass:[UICollectionViewCell class]];
    if (app || isList || isCell) {
        [out appendFormat:@"\n%@%@%@ %.0fx%.0f", [@"" stringByPaddingToLength:(NSUInteger)depth withString:@" " startingAtIndex:0],
         NSStringFromClass(c), isCell ? @" [cell]" : (isList ? @" [list]" : @""), v.bounds.size.width, v.bounds.size.height];
        (*lines)++;
    }
    if (isCell && app && !cells[NSStringFromClass(c)] && cells.count < 8) cells[NSStringFromClass(c)] = v;
    for (UIView *sub in v.subviews) ZXDumpView(sub, depth + 1, out, lines, cells);
}

@implementation ZXRecallMarker

+ (void)install
{
    ZXStoreInit();
    for (Class base in @[[UITableViewCell class], [UICollectionViewCell class]]) {
        Method m = class_getInstanceMethod(base, @selector(layoutSubviews));
        if (!m) continue;
        IMP orig = method_getImplementation(m);
        method_setImplementation(m, imp_implementationWithBlock(^(UIView *self_) {
            ((void (*)(id, SEL))orig)(self_, @selector(layoutSubviews));
            @try { ZXUpdateCell(self_); } @catch (NSException *e) {}
        }));
    }
    ZXLog(@"recall marker installed (%lu ids)", (unsigned long)gIds.count);
}

+ (void)markObjects:(NSArray *)objects
{
    ZXStoreInit();
    NSMutableSet *ids = [NSMutableSet new];
    NSMutableArray *debug = [NSMutableArray new];
    for (id o in objects) ZXCollect(o, 1, ids, debug);
    if (ids.count == 0) {
        NSMutableArray *info = [NSMutableArray new];
        for (id o in objects) {
            Class c = [o class];
            [info addObject:[NSString stringWithFormat:@"%@{%@}", NSStringFromClass(c),
                             [[ZXKeyNames(c) subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)25, ZXKeyNames(c).count))] componentsJoinedByString:@","]]];
        }
        ZXLog(@"MARK: no ids found. objects: %@", [info componentsJoinedByString:@" | "]);
        return;
    }
    @synchronized (gLock) { [gIds unionSet:ids]; gVersion++; }
    ZXSaveSoon();
    ZXLog(@"MARK ids: %@", [debug componentsJoinedByString:@", "]);
    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIWindow *w in UIApplication.sharedApplication.windows) ZXRefreshVisibleCells(w);
    });
}

+ (void)dumpViewHierarchy
{
    ZXStoreInit();
    NSMutableString *out = [NSMutableString stringWithString:@"DUMP khung hinh:"];
    int lines = 0;
    NSMutableDictionary *cells = [NSMutableDictionary new];
    for (UIWindow *w in UIApplication.sharedApplication.windows) {
        if (w.windowLevel > UIWindowLevelAlert) continue; // skip our bubble
        ZXDumpView(w, 0, out, &lines, cells);
    }
    ZXLogImpl(out);
    for (NSString *cn in cells) {
        UIView *cell = cells[cn];
        NSMutableArray *parts = [NSMutableArray new];
        for (Class k = [cell class]; k && ZXIsAppClass(k); k = class_getSuperclass(k)) {
            for (NSString *name in ZXKeyNames(k)) {
                if ([name hasPrefix:@"_"]) continue;
                id v = nil;
                @try { v = [cell valueForKey:name]; } @catch (NSException *e) { continue; }
                if (v && ZXIsAppClass([v class])) [parts addObject:[NSString stringWithFormat:@"%@:%@", name, NSStringFromClass([v class])]];
            }
        }
        ZXLog(@"DUMP cell %@ object-props: %@", cn, [parts componentsJoinedByString:@", "]);
    }
}

+ (void)clearMarks
{
    ZXStoreInit();
    @synchronized (gLock) { [gIds removeAllObjects]; gVersion++; }
    [[NSFileManager defaultManager] removeItemAtPath:ZXIdsPath() error:nil];
    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIWindow *w in UIApplication.sharedApplication.windows) ZXRefreshVisibleCells(w);
    });
}

@end
