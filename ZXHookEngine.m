#import <UIKit/UIKit.h>
#import "ZXHookEngine.h"
#import "ZXConfig.h"
#import "ZXLog.h"
#import "ZXAntiRecall.h"
#import "ZXRecallMarker.h"
#import <objc/runtime.h>

typedef uintptr_t ZXWord;

static NSMutableSet<NSString *> *gInstalled;
static NSMutableArray<NSDictionary *> *gPending;

// ---- helpers: trace logging and argument matching -------------------------

static NSString *ZXDescribeWord(ZXWord w, BOOL isObj)
{
    if (!isObj) return [NSString stringWithFormat:@"%lu", (unsigned long)w];
    if (w == 0) return @"nil";
    @try {
        id o = (__bridge id)(void *)w;
        NSString *d = [o description];
        if (d.length > 400) d = [[d substringToIndex:400] stringByAppendingString:@"..."];
        d = [d stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
        return [NSString stringWithFormat:@"<%@> %@", NSStringFromClass([o class]), d];
    } @catch (NSException *e) {
        return @"<?>";
    }
}

static void ZXTraceCall(NSString *tag, NSArray<NSNumber *> *objKinds, const ZXWord *args)
{
    NSMutableString *out = [NSMutableString stringWithFormat:@"TRACE %@", tag];
    for (NSUInteger i = 0; i < objKinds.count; i++)
        [out appendFormat:@"\n    arg%lu = %@", (unsigned long)(i + 1), ZXDescribeWord(args[i], [objKinds[i] boolValue])];
    ZXLogImpl(out);
}

static void ZXMarkArgs(NSArray<NSNumber *> *objKinds, const ZXWord *args)
{
    NSMutableArray *objs = [NSMutableArray new];
    for (NSUInteger i = 0; i < objKinds.count; i++)
        if ([objKinds[i] boolValue] && args[i]) [objs addObject:(__bridge id)(void *)args[i]];
    [ZXRecallMarker markObjects:objs];
}

static BOOL ZXArgMatches(NSInteger matchArg, NSString *matchText, const ZXWord *args)
{
    if (matchArg < 1 || matchArg > 6 || matchText.length == 0) return YES;
    NSString *d = ZXDescribeWord(args[matchArg - 1], YES);
    return [d rangeOfString:matchText options:NSCaseInsensitiveSearch].location != NSNotFound;
}

/// Raises the export configuration of an HD video to the source's own resolution / bitrate ("original").
/// cfg = ZAVideoExportConfiguration, info = ZVEAssetInfo (both read/written via KVC, failures ignored).
static void ZXApplyVideoOriginal(id cfg, id info)
{
    if (!cfg || !info) return;
    @try {
        double curDim = [[cfg valueForKey:@"dimension"] doubleValue];
        double curBR = [[cfg valueForKey:@"videoBitrate"] doubleValue];
        if (curDim < 700) return; // "Standard" quality keeps its own limits
        double srcBR = 0;
        id v = [info valueForKey:@"videoBitrate"];
        if ([v respondsToSelector:@selector(doubleValue)]) srcBR = [v doubleValue];
        CGSize rs = CGSizeZero;
        id r = [info valueForKey:@"resolution"];
        if ([r isKindOfClass:[NSValue class]]) rs = [r CGSizeValue];
        double side = MAX(rs.width, rs.height);
        double newDim = curDim, newBR = curBR;
        if (side > curDim) newDim = side;
        if (srcBR > curBR) newBR = MIN(srcBR, 40000000.0);
        if (newDim != curDim) [cfg setValue:@(newDim) forKey:@"dimension"];
        if (newBR != curBR) [cfg setValue:@(newBR) forKey:@"videoBitrate"];
        ZXLog(@"video original: dimension %.0f -> %.0f, bitrate %.0f -> %.0f (source %.0fx%.0f @ %.0f)",
              curDim, newDim, curBR, newBR, rs.width, rs.height, srcBR);
    } @catch (NSException *e) {
        ZXLog(@"video original failed: %@", e.reason);
    }
}

@implementation ZXHookEngine

+ (NSString *)rulesPath
{
    return [[ZXConfig dataDir] stringByAppendingPathComponent:@"rules.json"];
}

#define ZX_RULES_VERSION_MARK @"// zx-rules-version: 9"

+ (NSString *)defaultRulesJSON
{
    return
    @"[\n"
    @"  {\n"
    @"    \"id\": \"firebase_analytics_log\",\n"
    @"    \"enabled\": true,\n"
    @"    \"class\": \"FIRAnalytics\",\n"
    @"    \"selector\": \"logEventWithName:parameters:\",\n"
    @"    \"classMethod\": true,\n"
    @"    \"action\": \"skip\",\n"
    @"    \"configKey\": \"logging_disable_firebase\"\n"
    @"  },\n"
    @"  {\n"
    @"    \"id\": \"anti_recall_socket\",\n"
    @"    \"enabled\": true,\n"
    @"    \"class\": \"ChatUIManager\",\n"
    @"    \"selector\": \"processUndoWithSocketChatEntity:\",\n"
    @"    \"classMethod\": true,\n"
    @"    \"action\": \"skip\",\n"
    @"    \"configKey\": \"enable_anti_recall\",\n"
    @"    \"mark\": true\n"
    @"  },\n"
    @"  {\n"
    @"    \"id\": \"anti_recall_operation\",\n"
    @"    \"enabled\": true,\n"
    @"    \"class\": \"ChatOperationProcessor\",\n"
    @"    \"selector\": \"_processUndoMessageWithOperationItem:\",\n"
    @"    \"action\": \"skip\",\n"
    @"    \"configKey\": \"enable_anti_recall\",\n"
    @"    \"mark\": true\n"
    @"  },\n"
    @"  {\n"
    @"    \"id\": \"block_seen_send_server\",\n"
    @"    \"enabled\": true,\n"
    @"    \"class\": \"ChatSendSeenDataManager\",\n"
    @"    \"selector\": \"sendSeenServer\",\n"
    @"    \"action\": \"skip\",\n"
    @"    \"configKey\": \"block_send_seen\"\n"
    @"  },\n"
    @"  {\n"
    @"    \"id\": \"block_seen_force_send\",\n"
    @"    \"enabled\": true,\n"
    @"    \"class\": \"ChatSendSeenDataManager\",\n"
    @"    \"selector\": \"forceSendSeenServer\",\n"
    @"    \"action\": \"skip\",\n"
    @"    \"configKey\": \"block_send_seen\"\n"
    @"  },\n"
    @"  {\n"
    @"    \"id\": \"block_seen_send_message\",\n"
    @"    \"enabled\": true,\n"
    @"    \"class\": \"ChatSendSeenDataManager\",\n"
    @"    \"selector\": \"_sendSeenMessageWithSeenData:messageType:\",\n"
    @"    \"action\": \"skip\",\n"
    @"    \"configKey\": \"block_send_seen\"\n"
    @"  },\n"
    @"  {\n"
    @"    \"id\": \"block_seen_last_message\",\n"
    @"    \"enabled\": true,\n"
    @"    \"class\": \"ChatSendSeenDataManager\",\n"
    @"    \"selector\": \"sendSeenLastMessageWithThreadIds:withMessageType:\",\n"
    @"    \"action\": \"skip\",\n"
    @"    \"configKey\": \"block_send_seen\"\n"
    @"  },\n"
    @"  {\n"
    @"    \"id\": \"silent_typing\",\n"
    @"    \"enabled\": true,\n"
    @"    \"class\": \"ChatSocketCmdHelper\",\n"
    @"    \"selector\": \"sendStatusTyping:withCommand:withSubCommand:withDestType:withGlobalMessageId:\",\n"
    @"    \"classMethod\": true,\n"
    @"    \"action\": \"skip\",\n"
    @"    \"returnValue\": 0,\n"
    @"    \"configKey\": \"enable_silent_typing\"\n"
    @"  },\n"
    @"  {\n"
    @"    \"id\": \"block_seen_check\",\n"
    @"    \"enabled\": true,\n"
    @"    \"class\": \"ChatDataManager\",\n"
    @"    \"selector\": \"checkCanSendSeenInboxEntity:messageType:withToUserId:\",\n"
    @"    \"action\": \"skip\",\n"
    @"    \"configKey\": \"block_send_seen\"\n"
    @"  },\n"
    @"  {\n"
    @"    \"id\": \"block_seen_entity\",\n"
    @"    \"enabled\": true,\n"
    @"    \"class\": \"ChatSendSeenDataManager\",\n"
    @"    \"selector\": \"sendSeenWithChatEntity:\",\n"
    @"    \"action\": \"skip\",\n"
    @"    \"configKey\": \"block_send_seen\"\n"
    @"  },\n"
    @"  {\n"
    @"    \"id\": \"typing_feature_flag\",\n"
    @"    \"enabled\": true,\n"
    @"    \"class\": \"FeatureManager\",\n"
    @"    \"selector\": \"isEnableTypingMessage\",\n"
    @"    \"action\": \"return\",\n"
    @"    \"returnValue\": 0,\n"
    @"    \"configKey\": \"enable_silent_typing\"\n"
    @"  },\n"
    @"  {\n"
    @"    \"id\": \"custom_ttl\",\n"
    @"    \"enabled\": true,\n"
    @"    \"class\": \"ChatDataManager\",\n"
    @"    \"selector\": \"attachTTLValueForMessageIfNeed:\",\n"
    @"    \"action\": \"setttl\",\n"
    @"    \"argIndex\": 1,\n"
    @"    \"configKey\": \"enable_msg_ttl_override\"\n"
    @"  },\n"
    @"  {\n"
    @"    \"id\": \"unlimited_file_size\",\n"
    @"    \"enabled\": true,\n"
    @"    \"class\": \"ChatDataManager\",\n"
    @"    \"selector\": \"getMaxFileSizeWithPickerQuality:\",\n"
    @"    \"classMethod\": true,\n"
    @"    \"action\": \"return\",\n"
    @"    \"returnValue\": 10737418240,\n"
    @"    \"configKey\": \"enable_unlimited_media\"\n"
    @"  },\n"
    @"  {\n"
    @"    \"id\": \"picker_open_original\",\n"
    @"    \"enabled\": true,\n"
    @"    \"class\": \"UXMediaPickerUnities\",\n"
    @"    \"selector\": \"showQualityPickerWithCurrentQuality:entryPoint:animatingPromote:changeBlock:\",\n"
    @"    \"classMethod\": true,\n"
    @"    \"action\": \"setarg\",\n"
    @"    \"argIndex\": 1,\n"
    @"    \"returnValue\": 2,\n"
    @"    \"configKey\": \"default_original_quality\"\n"
    @"  },\n"
    @"  {\n"
    @"    \"id\": \"can_upload_original\",\n"
    @"    \"enabled\": true,\n"
    @"    \"class\": \"ZCFPickerConfig\",\n"
    @"    \"selector\": \"canUploadOriginalQuality\",\n"
    @"    \"classMethod\": true,\n"
    @"    \"action\": \"return\",\n"
    @"    \"returnValue\": 1,\n"
    @"    \"configKey\": \"default_original_quality\"\n"
    @"  },\n"
    @"  {\n"
    @"    \"id\": \"enable_send_original\",\n"
    @"    \"enabled\": true,\n"
    @"    \"class\": \"CommFeatureBase.ZCFQualityPickerConfig\",\n"
    @"    \"selector\": \"enableSendOriginal\",\n"
    @"    \"classMethod\": true,\n"
    @"    \"action\": \"return\",\n"
    @"    \"returnValue\": 1,\n"
    @"    \"configKey\": \"default_original_quality\"\n"
    @"  },\n"
    @"  {\n"
    @"    \"id\": \"zcloud_file_limit\",\n"
    @"    \"enabled\": true,\n"
    @"    \"class\": \"ZCloudFoundation.ZCloudFileSetting\",\n"
    @"    \"selector\": \"zCloudFileLimitInBytes\",\n"
    @"    \"classMethod\": true,\n"
    @"    \"action\": \"return\",\n"
    @"    \"returnValue\": 100000000000,\n"
    @"    \"configKey\": \"enable_unlimited_media\"\n"
    @"  },\n"
    @"  {\n"
    @"    \"id\": \"file_error_bypass\",\n"
    @"    \"enabled\": true,\n"
    @"    \"class\": \"FilePickerObject\",\n"
    @"    \"selector\": \"sendFileErrorWithFileObject:\",\n"
    @"    \"classMethod\": true,\n"
    @"    \"action\": \"return\",\n"
    @"    \"returnValue\": 0,\n"
    @"    \"configKey\": \"enable_unlimited_media\"\n"
    @"  },\n"
    @"  {\n"
    @"    \"id\": \"video_bypass_transcode\",\n"
    @"    \"enabled\": true,\n"
    @"    \"class\": \"ZAVideoExportHelper\",\n"
    @"    \"selector\": \"shouldByPassVideoSize:withDimensionMax:\",\n"
    @"    \"classMethod\": true,\n"
    @"    \"action\": \"return_size\",\n"
    @"    \"returnValue\": 1,\n"
    @"    \"configKey\": \"video_original\"\n"
    @"  },\n"
    @"  {\n"
    @"    \"id\": \"video_max_upload\",\n"
    @"    \"enabled\": true,\n"
    @"    \"class\": \"UXSessionContext\",\n"
    @"    \"selector\": \"maxUploadVideoSize\",\n"
    @"    \"action\": \"return\",\n"
    @"    \"returnValue\": 10737418240,\n"
    @"    \"configKey\": \"enable_unlimited_media\"\n"
    @"  },\n"
    @"  {\n"
    @"    \"id\": \"trace_video_id\",\n"
    @"    \"enabled\": true,\n"
    @"    \"class\": \"ZAChatVideoExporter\",\n"
    @"    \"selector\": \"createVideoIdWithAssetUrl:isHighQuality:\",\n"
    @"    \"classMethod\": true,\n"
    @"    \"action\": \"log\"\n"
    @"  },\n"
    @"  {\n"
    @"    \"id\": \"video_original_config\",\n"
    @"    \"enabled\": true,\n"
    @"    \"class\": \"ZAVideoExportManager\",\n"
    @"    \"selector\": \"_reconfigBitrateForConfiguration:assetInfo:videoID:source:\",\n"
    @"    \"action\": \"videocfg\",\n"
    @"    \"argIndex\": 1,\n"
    @"    \"configKey\": \"video_original\"\n"
    @"  },\n"
    @"  {\n"
    @"    \"id\": \"trace_pre_send_file\",\n"
    @"    \"enabled\": true,\n"
    @"    \"class\": \"FilePickerObject\",\n"
    @"    \"selector\": \"generatePreSendFileObjectWithURL:completion:\",\n"
    @"    \"classMethod\": true,\n"
    @"    \"action\": \"log\"\n"
    @"  },\n"
    @"  {\n"
    @"    \"id\": \"trace_handle_send_file\",\n"
    @"    \"enabled\": true,\n"
    @"    \"class\": \"ChatDataManager\",\n"
    @"    \"selector\": \"handleSendFileAtURLs:toThreadId:isGroupCSC:referenceSrc:completion:\",\n"
    @"    \"action\": \"log\"\n"
    @"  },\n"
    @"  {\n"
    @"    \"id\": \"trace_file_error_ui\",\n"
    @"    \"enabled\": true,\n"
    @"    \"class\": \"ZaloTableViewController\",\n"
    @"    \"selector\": \"_handleSendFileErrorWithInfo:\",\n"
    @"    \"action\": \"log\"\n"
    @"  }\n"
    @"]\n"
    @"// zx-rules-version: 9\n";
}

+ (void)ensureRulesFile
{
    NSString *path = [self rulesPath];
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:path]) {
        NSString *cur = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
        if ([cur containsString:ZX_RULES_VERSION_MARK]) return;
        // older rules file: keep a backup and install the current rules
        NSString *bak = [path stringByAppendingString:@".bak"];
        [fm removeItemAtPath:bak error:nil];
        [fm moveItemAtPath:path toPath:bak error:nil];
        ZXLog(@"rules.json cũ đã được sao lưu thành rules.json.bak và thay bằng bản mới");
    }
    [[self defaultRulesJSON] writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

+ (NSArray *)loadRules
{
    [self ensureRulesFile];
    NSString *path = [self rulesPath];
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (!text) return @[];
    // allow full-line // comments
    NSMutableArray *lines = [NSMutableArray new];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        NSString *t = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([t hasPrefix:@"//"]) continue;
        [lines addObject:line];
    }
    NSData *data = [[lines componentsJoinedByString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
    NSError *err = nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
    if (![json isKindOfClass:[NSArray class]]) {
        ZXLog(@"rules.json invalid: %@", err.localizedDescription ?: @"root must be an array");
        return @[];
    }
    return json;
}

+ (void)installFromRules
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gInstalled = [NSMutableSet new];
        gPending = [NSMutableArray new];
    });
    for (id r in [self loadRules]) {
        if (![r isKindOfClass:[NSDictionary class]]) continue;
        if ([r[@"enabled"] respondsToSelector:@selector(boolValue)] && ![r[@"enabled"] boolValue]) continue;
        if (![self installRule:r]) [gPending addObject:r];
    }
    ZXLog(@"rules installed: %lu, pending: %lu", (unsigned long)gInstalled.count, (unsigned long)gPending.count);
}

+ (void)retryPending
{
    if (gPending.count == 0) return;
    NSArray *todo = [gPending copy];
    [gPending removeAllObjects];
    for (NSDictionary *r in todo)
        if (![self installRule:r]) [gPending addObject:r];
}

static BOOL ZXWordArgType(char c)
{
    return c != 0 && strchr("cCsSiIlLqQB@#^*:", c) != NULL;
}

/// returns YES when done (installed, duplicate, or permanently invalid); NO to retry later.
+ (BOOL)installRule:(NSDictionary *)rule
{
    NSString *className = rule[@"class"], *selName = rule[@"selector"];
    NSString *action = rule[@"action"] ?: @"skip";
    if (![className isKindOfClass:[NSString class]] || ![selName isKindOfClass:[NSString class]]) {
        ZXLog(@"rule %@: missing class/selector", rule[@"id"]);
        return YES;
    }
    Class cls = NSClassFromString(className);
    if (!cls) return NO; // maybe not loaded yet
    BOOL isClassMethod = [rule[@"classMethod"] boolValue];
    Class target = isClassMethod ? object_getClass(cls) : cls;
    SEL sel = NSSelectorFromString(selName);
    Method m = class_getInstanceMethod(target, sel);
    if (!m) {
        ZXLog(@"rule %@: %c[%@ %@] not found", rule[@"id"], isClassMethod ? '+' : '-', className, selName);
        return YES;
    }
    NSString *key = [NSString stringWithFormat:@"%c%@ %@", isClassMethod ? '+' : '-', className, selName];
    if ([gInstalled containsObject:key]) return YES;

    // CGSize + integer args, integer return (e.g. +ZAVideoExportHelper shouldByPassVideoSize:withDimensionMax:)
    if ([action isEqualToString:@"return_size"]) {
        char *a0 = method_copyArgumentType(m, 2);
        BOOL okSig = method_getNumberOfArguments(m) == 4 && a0 && strncmp(a0, "{CGSize", 7) == 0;
        if (a0) free(a0);
        char *a1 = okSig ? method_copyArgumentType(m, 3) : NULL;
        okSig = okSig && a1 && ZXWordArgType(a1[0]);
        if (a1) free(a1);
        char *rt2 = method_copyReturnType(m);
        okSig = okSig && rt2 && ZXWordArgType(rt2[0]);
        if (rt2) free(rt2);
        if (!okSig) { ZXLog(@"rule %@: return_size needs (CGSize, integer) -> integer", rule[@"id"]); return YES; }
        NSString *scfg = [rule[@"configKey"] isKindOfClass:[NSString class]] ? rule[@"configKey"] : nil;
        ZXWord sval = (ZXWord)[rule[@"returnValue"] longLongValue];
        IMP sorig = method_getImplementation(m);
        const char *stypes = method_getTypeEncoding(m);
        id sblock = ^ZXWord(id self_, CGSize size, ZXWord a2) {
            if (!scfg || [ZXConfig boolForKey:scfg]) return sval;
            return ((ZXWord (*)(id, SEL, CGSize, ZXWord))sorig)(self_, sel, size, a2);
        };
        IMP simp = imp_implementationWithBlock(sblock);
        if (!class_addMethod(target, sel, simp, stypes)) method_setImplementation(m, simp);
        [gInstalled addObject:key];
        ZXLog(@"hooked %@ (%@) action=return_size", key, rule[@"id"] ?: key);
        return YES;
    }

    // validate signature: only integer-class args (<= 6) and void / integer-class return
    unsigned argc = method_getNumberOfArguments(m);
    if (argc < 2 || argc - 2 > 6) { ZXLog(@"rule %@: too many args", rule[@"id"]); return YES; }
    for (unsigned i = 2; i < argc; i++) {
        char *t = method_copyArgumentType(m, i);
        BOOL ok = t && ZXWordArgType(t[0] == 'r' || t[0] == 'n' || t[0] == 'N' || t[0] == 'o' || t[0] == 'O' || t[0] == 'R' || t[0] == 'V' ? t[1] : t[0]);
        if (t) free(t);
        if (!ok) { ZXLog(@"rule %@: unsupported arg type at %u", rule[@"id"], i - 2); return YES; }
    }
    char *rt = method_copyReturnType(m);
    char rc = rt ? rt[0] : '?';
    if (rt) free(rt);
    BOOL isVoid = (rc == 'v');
    if (rc == 'f' || rc == 'd') {
        // floating-point return: only argument-less methods with action "return"
        if (argc != 2 || ![action isEqualToString:@"return"]) { ZXLog(@"rule %@: float method needs action return and no args", rule[@"id"]); return YES; }
        NSString *fkey = [NSString stringWithFormat:@"%c%@ %@", isClassMethod ? '+' : '-', className, selName];
        if ([gInstalled containsObject:fkey]) return YES;
        NSString *fcfg = [rule[@"configKey"] isKindOfClass:[NSString class]] ? rule[@"configKey"] : nil;
        double fv = [rule[@"returnValue"] doubleValue];
        IMP forig = method_getImplementation(m);
        const char *ftypes = method_getTypeEncoding(m);
        id fblock;
        if (rc == 'f') {
            fblock = ^float(id self_) {
                if (!fcfg || [ZXConfig boolForKey:fcfg]) return (float)fv;
                return ((float (*)(id, SEL))forig)(self_, sel);
            };
        } else {
            fblock = ^double(id self_) {
                if (!fcfg || [ZXConfig boolForKey:fcfg]) return fv;
                return ((double (*)(id, SEL))forig)(self_, sel);
            };
        }
        IMP fimp = imp_implementationWithBlock(fblock);
        if (!class_addMethod(target, sel, fimp, ftypes)) method_setImplementation(m, fimp);
        [gInstalled addObject:fkey];
        ZXLog(@"hooked %@ (%@) action=return(float %g)", fkey, rule[@"id"] ?: fkey, fv);
        return YES;
    }
    if (!isVoid && !ZXWordArgType(rc)) { ZXLog(@"rule %@: unsupported return type %c", rule[@"id"], rc); return YES; }

    NSInteger argIndex = [rule[@"argIndex"] integerValue];
    BOOL antiRecall = [action isEqualToString:@"antirecall"];
    if (antiRecall) {
        if (argIndex < 1 || argIndex > (NSInteger)argc - 2) { ZXLog(@"rule %@: bad argIndex", rule[@"id"]); return YES; }
        char *t = method_copyArgumentType(m, (unsigned)argIndex + 1);
        BOOL isObj = t && (t[0] == '@');
        if (t) free(t);
        if (!isObj) { ZXLog(@"rule %@: argIndex is not an object", rule[@"id"]); return YES; }
    }
    BOOL isSetArg = [action isEqualToString:@"setarg"];
    if (isSetArg && (argIndex < 1 || argIndex > (NSInteger)argc - 2)) { ZXLog(@"rule %@: bad argIndex", rule[@"id"]); return YES; }
    BOOL isSetTTL = [action isEqualToString:@"setttl"];
    if (isSetTTL) {
        if (argIndex < 1 || argIndex > (NSInteger)argc - 2) { ZXLog(@"rule %@: bad argIndex", rule[@"id"]); return YES; }
        char *t = method_copyArgumentType(m, (unsigned)argIndex + 1);
        BOOL isObj = t && (t[0] == '@');
        if (t) free(t);
        if (!isObj) { ZXLog(@"rule %@: argIndex is not an object", rule[@"id"]); return YES; }
    }
    BOOL isVideoCfg = [action isEqualToString:@"videocfg"];
    if (isVideoCfg && (!isVoid || argc < 4)) { ZXLog(@"rule %@: videocfg needs a void method with (config, assetInfo, ...)", rule[@"id"]); return YES; }
    BOOL isTTL = [action isEqualToString:@"ttl"];
    if (isTTL && isVoid) { ZXLog(@"rule %@: ttl needs a non-void method", rule[@"id"]); return YES; }

    NSString *configKey = [rule[@"configKey"] isKindOfClass:[NSString class]] ? rule[@"configKey"] : nil;
    ZXWord retVal = (ZXWord)[rule[@"returnValue"] longLongValue];
    IMP orig = method_getImplementation(m);
    const char *types = method_getTypeEncoding(m);
    NSString *ruleId = rule[@"id"] ?: key;

    // trace support
    BOOL isLog = [action isEqualToString:@"log"];
    NSMutableArray<NSNumber *> *objKinds = [NSMutableArray new];
    for (unsigned i = 2; i < argc; i++) {
        char *t = method_copyArgumentType(m, i);
        [objKinds addObject:@(t && t[0] == '@' && t[1] != '?')];
        if (t) free(t);
    }
    NSString *traceTag = key;
    BOOL markFlag = [rule[@"mark"] boolValue];

    // optional condition: only act when description of argument N contains text
    NSInteger matchArg = [rule[@"matchArg"] integerValue];
    NSString *matchText = [rule[@"matchText"] isKindOfClass:[NSString class]] ? rule[@"matchText"] : nil;

    id block;
    if (isVoid) {
        block = ^(id self_, ZXWord a1, ZXWord a2, ZXWord a3, ZXWord a4, ZXWord a5, ZXWord a6) {
            ZXWord args[6] = {a1, a2, a3, a4, a5, a6};
            if (isLog) {
                ZXTraceCall(traceTag, objKinds, args);
            } else if ((!configKey || [ZXConfig boolForKey:configKey]) && ZXArgMatches(matchArg, matchText, args)) {
                if (markFlag) ZXMarkArgs(objKinds, args);
                if (isVideoCfg) {
                    ((void (*)(id, SEL, ZXWord, ZXWord, ZXWord, ZXWord, ZXWord, ZXWord))orig)(self_, sel, args[0], args[1], args[2], args[3], args[4], args[5]);
                    ZXApplyVideoOriginal((__bridge id)(void *)args[0], (__bridge id)(void *)args[1]);
                    return;
                }
                if (isSetArg) {
                    args[argIndex - 1] = retVal;
                    ((void (*)(id, SEL, ZXWord, ZXWord, ZXWord, ZXWord, ZXWord, ZXWord))orig)(self_, sel, args[0], args[1], args[2], args[3], args[4], args[5]);
                    return;
                }
                if (isSetTTL) {
                    id o = (__bridge id)(void *)args[argIndex - 1];
                    @try { [o setValue:@([ZXConfig ttl]) forKey:@"ttl"]; } @catch (__unused id e) {}
                } else if (!antiRecall) return; // skip
                if (isSetTTL) {
                    ((void (*)(id, SEL, ZXWord, ZXWord, ZXWord, ZXWord, ZXWord, ZXWord))orig)(self_, sel, args[0], args[1], args[2], args[3], args[4], args[5]);
                    return;
                }
                id replaced = [ZXAntiRecall processObject:(__bridge id)(void *)args[argIndex - 1]];
                CFTypeRef held = NULL;
                if (replaced) { held = CFBridgingRetain(replaced); args[argIndex - 1] = (ZXWord)held; }
                ((void (*)(id, SEL, ZXWord, ZXWord, ZXWord, ZXWord, ZXWord, ZXWord))orig)(self_, sel, args[0], args[1], args[2], args[3], args[4], args[5]);
                if (held) CFRelease(held);
                return;
            }
            ((void (*)(id, SEL, ZXWord, ZXWord, ZXWord, ZXWord, ZXWord, ZXWord))orig)(self_, sel, args[0], args[1], args[2], args[3], args[4], args[5]);
        };
    } else {
        block = ^ZXWord(id self_, ZXWord a1, ZXWord a2, ZXWord a3, ZXWord a4, ZXWord a5, ZXWord a6) {
            ZXWord args[6] = {a1, a2, a3, a4, a5, a6};
            if (isLog) {
                ZXTraceCall(traceTag, objKinds, args);
            } else if ((!configKey || [ZXConfig boolForKey:configKey]) && ZXArgMatches(matchArg, matchText, args)) {
                if (markFlag) ZXMarkArgs(objKinds, args);
                if (isTTL) return (ZXWord)[ZXConfig ttl];
                if (isSetArg) {
                    args[argIndex - 1] = retVal;
                    return ((ZXWord (*)(id, SEL, ZXWord, ZXWord, ZXWord, ZXWord, ZXWord, ZXWord))orig)(self_, sel, args[0], args[1], args[2], args[3], args[4], args[5]);
                }
                if (isSetTTL) {
                    id o = (__bridge id)(void *)args[argIndex - 1];
                    @try { [o setValue:@([ZXConfig ttl]) forKey:@"ttl"]; } @catch (__unused id e) {}
                    return ((ZXWord (*)(id, SEL, ZXWord, ZXWord, ZXWord, ZXWord, ZXWord, ZXWord))orig)(self_, sel, args[0], args[1], args[2], args[3], args[4], args[5]);
                }
                if (!antiRecall) return retVal; // skip / return
                id replaced = [ZXAntiRecall processObject:(__bridge id)(void *)args[argIndex - 1]];
                CFTypeRef held = NULL;
                if (replaced) { held = CFBridgingRetain(replaced); args[argIndex - 1] = (ZXWord)held; }
                ZXWord r = ((ZXWord (*)(id, SEL, ZXWord, ZXWord, ZXWord, ZXWord, ZXWord, ZXWord))orig)(self_, sel, args[0], args[1], args[2], args[3], args[4], args[5]);
                if (held) CFRelease(held);
                return r;
            }
            return ((ZXWord (*)(id, SEL, ZXWord, ZXWord, ZXWord, ZXWord, ZXWord, ZXWord))orig)(self_, sel, args[0], args[1], args[2], args[3], args[4], args[5]);
        };
    }

    IMP newImp = imp_implementationWithBlock(block);
    // Add as an override on this class; if the class already owns the method, replace it.
    if (!class_addMethod(target, sel, newImp, types))
        method_setImplementation(m, newImp);

    [gInstalled addObject:key];
    ZXLog(@"hooked %@ (%@) action=%@", key, ruleId, action);
    return YES;
}

@end
