#import "ZXAntiRecall.h"
#import "ZXConfig.h"
#import "ZXLog.h"

static NSString *const kSignature =
    @"{\"properties\":{\"color\":0,\"size\":0,\"type\":0,\"subType\":0,"
    @"\"ext\":\"{\\\"shouldParseLinkOrContact\\\":0}\"},\"msgBubbleLayoutType\":0,"
    @"\"generatedBy\":\"AntiRecallDeleteHook\"}";


// ------------------------------------------------------------ message cache
// Normal incoming messages are remembered (text only) so that when a recall/delete
// packet arrives we can show what was removed. Stored locally in Documents/ZaloXposed.

static NSMutableDictionary<NSString *, NSDictionary *> *gCache;
static NSMutableArray<NSString *> *gOrder;
static NSObject *gLock;
static BOOL gDirty;
static const NSUInteger kMaxCache = 3000;

static NSString *ZXCachePath(void) { return [[ZXConfig dataDir] stringByAppendingPathComponent:@"msgcache.json"]; }

static void ZXCacheInit(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gLock = [NSObject new];
        gCache = [NSMutableDictionary new];
        gOrder = [NSMutableArray new];
        NSData *d = [NSData dataWithContentsOfFile:ZXCachePath()];
        id j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
        if ([j isKindOfClass:[NSDictionary class]]) {
            NSDictionary *m = j[@"map"]; NSArray *o = j[@"order"];
            if ([m isKindOfClass:[NSDictionary class]] && [o isKindOfClass:[NSArray class]]) {
                [gCache addEntriesFromDictionary:m];
                [gOrder addObjectsFromArray:o];
            }
        }
    });
}

static void ZXCacheFlushSoon(void)
{
    if (gDirty) return;
    gDirty = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSData *out = nil;
        @synchronized (gLock) {
            gDirty = NO;
            out = [NSJSONSerialization dataWithJSONObject:@{ @"map": gCache, @"order": gOrder } options:0 error:nil];
        }
        [out writeToFile:ZXCachePath() atomically:YES];
    });
}

static NSString *ZXIdStr(id v)
{
    if ([v isKindOfClass:[NSNumber class]]) return [NSString stringWithFormat:@"%lld", [v longLongValue]];
    if ([v isKindOfClass:[NSString class]] && [v length] > 0) return v;
    return nil;
}

static NSArray<NSString *> *ZXIdsFrom(NSDictionary *d)
{
    NSMutableArray *ids = [NSMutableArray new];
    for (NSString *k in @[@"cliMsgId", @"globalMsgId", @"msgId", @"realMsgId", @"clientDelMsgId", @"globalDelMsgId"]) {
        NSString *v = ZXIdStr(d[k]);
        if (v && ![v isEqualToString:@"0"] && ![ids containsObject:v]) [ids addObject:v];
    }
    return ids;
}

static void ZXCacheMessage(NSDictionary *data)
{
    NSString *text = data[@"msg"];
    if (![text isKindOfClass:[NSString class]] || text.length == 0 || text.length > 4000) return;
    NSArray *ids = ZXIdsFrom(data);
    if (ids.count == 0) return;
    ZXCacheInit();
    NSDictionary *entry = @{ @"text": [text copy],
                             @"from": ZXIdStr(data[@"fromU"] ?: data[@"uidFrom"]) ?: @"",
                             @"ts": ZXIdStr(data[@"ts"]) ?: @"" };
    @synchronized (gLock) {
        for (NSString *i in ids) {
            if (!gCache[i]) [gOrder addObject:i];
            gCache[i] = entry;
        }
        while (gOrder.count > kMaxCache) { [gCache removeObjectForKey:gOrder.firstObject]; [gOrder removeObjectAtIndex:0]; }
    }
    ZXCacheFlushSoon();
}

static NSDictionary *ZXCacheLookup(NSDictionary *idSource)
{
    ZXCacheInit();
    @synchronized (gLock) {
        for (NSString *i in ZXIdsFrom(idSource)) if (gCache[i]) return gCache[i];
    }
    return nil;
}

static void ZXRecordHistory(NSString *kind, NSString *from, NSString *text)
{
    NSDateFormatter *f = [NSDateFormatter new];
    f.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    NSString *line = [NSString stringWithFormat:@"%@ | %@ | từ: %@ | %@\n", [f stringFromDate:[NSDate date]], kind,
                      from.length ? from : @"?", text.length ? text : @"(không có nội dung trong bộ nhớ đệm)"];
    NSString *path = [ZXAntiRecall historyPath];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) { [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]; return; }
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:path];
    [h seekToEndOfFile];
    [h writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [h closeFile];
}

static NSString *ZXNotice(NSString *base, NSString *text)
{
    if (![ZXConfig boolForKey:ZXK_SHOW_CONTENT] || text.length == 0) return base;
    return [NSString stringWithFormat:@"%@: %@", base, text];
}

static NSDictionary *ZXParamsExt(void)
{
    return @{ @"notifyActionCate": @0, @"containType": @0, @"forceNotify": @0, @"notifyTTL": @0,
              @"countUnread": @1, @"platformType": @0, @"refactorType": @0 };
}

static BOOL ZXIsMe(id uid)
{
    NSString *me = [ZXConfig currentUserID];
    if (me.length == 0 || ![uid respondsToSelector:@selector(longLongValue)]) return NO;
    return [[NSString stringWithFormat:@"%lld", [uid longLongValue]] isEqualToString:me];
}

static NSMutableDictionary *ZXFakeQuote(id ownerId, id cliMsgId, id globalMsgId, id ts, NSString *text)
{
    NSMutableDictionary *q = [NSMutableDictionary new];
    q[@"ownerId"] = ownerId ?: @0;
    q[@"gOwnerId"] = [NSNull null];
    q[@"cliMsgId"] = cliMsgId ?: @0;
    q[@"globalMsgId"] = globalMsgId ?: @0;
    q[@"cliMsgType"] = @1;
    q[@"ts"] = ts ?: @0;
    q[@"msg"] = text;
    q[@"attach"] = kSignature;
    q[@"fromD"] = @"ZaloXposed by ElectroHeavenVN";
    q[@"ttl"] = @0;
    return q;
}

/// Process one payload dict that has a "msg" array. Returns YES if modified.
static BOOL ZXProcessMsgPayload(NSMutableDictionary *payload)
{
    BOOL modified = NO;
    NSMutableArray *msgs = payload[@"msg"];
    if (![msgs isKindOfClass:[NSMutableArray class]]) return NO;

    for (id entry in msgs) {
        if (![entry isKindOfClass:[NSMutableDictionary class]]) continue;
        NSMutableDictionary *msgObject = entry[@"text"];
        if (![msgObject isKindOfClass:[NSMutableDictionary class]]) continue;
        NSString *type = msgObject[@"type"];
        NSMutableDictionary *data = msgObject[@"data"];
        if (![type isKindOfClass:[NSString class]] || ![data isKindOfClass:[NSMutableDictionary class]]) continue;

        if (![type isEqualToString:@"chat.undo"] && ![type isEqualToString:@"chat.delete"]) {
            ZXCacheMessage(data);
            continue;
        }

        if ([type isEqualToString:@"chat.undo"] && [ZXConfig boolForKey:ZXK_ANTI_RECALL]) {
            if (![ZXConfig boolForKey:ZXK_ANTI_RECALL_INCLUDE_ME] && ZXIsMe(data[@"fromU"])) continue;
            NSDictionary *attach = data[@"attach"];
            if (![attach isKindOfClass:[NSDictionary class]]) continue;
            NSDictionary *old = ZXCacheLookup(attach);
            ZXRecordHistory(@"THU HỒI", ZXIdStr(data[@"fromU"]), old[@"text"]);
            msgObject[@"type"] = @"webchat";
            data[@"msg"] = ZXNotice(@"Tin nhắn đã thu hồi", old[@"text"]);
            data[@"attach"] = @"";
            data[@"quote"] = ZXFakeQuote(data[@"fromU"], attach[@"cliMsgId"], attach[@"globalMsgId"],
                                         data[@"ts"], @"Jump to message");
            data[@"paramsExt"] = ZXParamsExt();
            modified = YES;
        }
        else if ([type isEqualToString:@"chat.delete"] && [ZXConfig boolForKey:ZXK_ANTI_DELETE]) {
            NSDictionary *attach = data[@"attach"];
            NSArray *contents = [attach isKindOfClass:[NSDictionary class]] ? attach[@"contents"] : nil;
            if (![contents isKindOfClass:[NSArray class]] || contents.count == 0) continue;
            NSDictionary *content = contents.lastObject;
            if (![content isKindOfClass:[NSDictionary class]]) continue;
            if (![ZXConfig boolForKey:ZXK_ANTI_DELETE_INCLUDE_ME] && ZXIsMe(data[@"fromU"])) continue;
            BOOL many = contents.count > 1;
            NSMutableArray *texts = [NSMutableArray new];
            for (id c in contents) {
                if (![c isKindOfClass:[NSDictionary class]]) continue;
                NSString *t = ZXCacheLookup(c)[@"text"];
                if (t) [texts addObject:t];
                if (texts.count >= 5) break;
            }
            NSString *joined = [texts componentsJoinedByString:@" | "];
            ZXRecordHistory(@"XÓA", ZXIdStr(content[@"uidFrom"]), joined);
            msgObject[@"type"] = @"webchat";
            data[@"msg"] = ZXNotice(many ? [NSString stringWithFormat:@"%lu tin nhắn đã xóa", (unsigned long)contents.count]
                                         : @"Tin nhắn đã xóa", joined);
            data[@"attach"] = @"";
            data[@"quote"] = ZXFakeQuote(content[@"uidFrom"], content[@"clientDelMsgId"],
                                         content[@"globalDelMsgId"], content[@"clientDelMsgId"],
                                         many ? @"Jump to first deleted message" : @"Jump to message");
            data[@"paramsExt"] = ZXParamsExt();
            modified = YES;
        }
    }
    return modified;
}

/// Walk the tree; the real packet may be nested at a different depth on iOS.
static BOOL ZXWalk(id node)
{
    BOOL modified = NO;
    if ([node isKindOfClass:[NSMutableDictionary class]]) {
        NSMutableDictionary *d = node;
        if ([d[@"msg"] isKindOfClass:[NSArray class]])
            modified |= ZXProcessMsgPayload(d);
        for (id v in [d allValues])
            if ([v isKindOfClass:[NSDictionary class]] || [v isKindOfClass:[NSArray class]])
                modified |= ZXWalk(v);
    } else if ([node isKindOfClass:[NSMutableArray class]]) {
        for (id v in (NSArray *)node) modified |= ZXWalk(v);
    }
    return modified;
}

static id ZXMutableCopy(id obj)
{
    if (![NSJSONSerialization isValidJSONObject:obj]) return nil;
    NSData *d = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
    if (!d) return nil;
    return [NSJSONSerialization JSONObjectWithData:d
                                           options:NSJSONReadingMutableContainers | NSJSONReadingMutableLeaves
                                             error:nil];
}

@implementation ZXAntiRecall

+ (NSString *)historyPath
{
    return [[ZXConfig dataDir] stringByAppendingPathComponent:@"recalled.txt"];
}

+ (void)clearCache
{
    ZXCacheInit();
    @synchronized (gLock) { [gCache removeAllObjects]; [gOrder removeAllObjects]; }
    [[NSFileManager defaultManager] removeItemAtPath:ZXCachePath() error:nil];
}

+ (id)processObject:(id)obj
{
    if (!obj) return nil;
    if (![ZXConfig boolForKey:ZXK_ANTI_RECALL] && ![ZXConfig boolForKey:ZXK_ANTI_DELETE]) return nil;
    @try {
        if ([obj isKindOfClass:[NSDictionary class]] || [obj isKindOfClass:[NSArray class]]) {
            id copy = ZXMutableCopy(obj);
            if (copy && ZXWalk(copy)) return copy;
            return nil;
        }
        NSData *data = nil;
        BOOL wasString = NO;
        if ([obj isKindOfClass:[NSString class]]) {
            NSString *s = obj;
            if (![s containsString:@"chat.undo"] && ![s containsString:@"chat.delete"] && ![s containsString:@"webchat"]) return nil;
            data = [s dataUsingEncoding:NSUTF8StringEncoding];
            wasString = YES;
        } else if ([obj isKindOfClass:[NSData class]]) {
            NSData *raw = obj;
            if (raw.length > 4 * 1024 * 1024) return nil;
            BOOL found = NO;
            for (NSString *needle in @[@"chat.undo", @"chat.delete", @"webchat"]) {
                NSData *n = [needle dataUsingEncoding:NSUTF8StringEncoding];
                if ([raw rangeOfData:n options:0 range:NSMakeRange(0, raw.length)].location != NSNotFound) { found = YES; break; }
            }
            if (!found) return nil;
            data = raw;
        }
        if (!data) return nil;
        id tree = [NSJSONSerialization JSONObjectWithData:data
                                                  options:NSJSONReadingMutableContainers | NSJSONReadingMutableLeaves
                                                    error:nil];
        if (!tree || !ZXWalk(tree)) return nil;
        NSData *out = [NSJSONSerialization dataWithJSONObject:tree options:0 error:nil];
        if (!out) return nil;
        return wasString ? [[NSString alloc] initWithData:out encoding:NSUTF8StringEncoding] : out;
    } @catch (NSException *e) {
        ZXLog(@"AntiRecall exception: %@", e);
        return nil;
    }
}

@end
