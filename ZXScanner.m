#import "ZXScanner.h"
#import "ZXConfig.h"
#import "ZXLog.h"
#import <objc/runtime.h>

@implementation ZXScanner

+ (NSString *)scanPath
{
    return [[ZXConfig dataDir] stringByAppendingPathComponent:@"scan.txt"];
}

+ (NSString *)runScan
{
    // Scan 2: effects, media quality, chat background, font/text style, profile music
    NSArray<NSString *> *keywords = @[@"emitter", @"particle", @"lottie", @"magicword", @"keywordeffect", @"texteffect",
                                      @"chateffect", @"messageeffect", @"effectview", @"snow", @"firework", @"confetti",
                                      @"wallpaper", @"chatskin", @"chatbackground", @"chatbg", @"backgroundimage", @"themeitem",
                                      @"filesizelimit", @"maxfilesize", @"filelimit", @"maxsizefile", @"limitsend", @"checkfilesize",
                                      @"maxupload", @"sendfile", @"uploadlimit", @"qualitypicker", @"sendhd", @"originalquality",
                                      @"customfont", @"fontstyle", @"profilemusic", @"musicprofile",
                                      @"sendsticker", @"stickersend", @"sendgif", @"sendstickerto", @"stickermessage"];
    // Scan 3: video quality. A method counts only if its selector has "video" AND one of these words.
    NSArray<NSString *> *videoWords = @[@"quality", @"compress", @"export", @"preset", @"bitrate", @"resolution", @"hd", @"original",
                                        @"maxsize", @"upload", @"encode", @"convert", @"transcode", @"send", @"pickerquality"];
    NSArray<NSString *> *noise = @[@"tracking", @"banner", @"constraint", @"analytics", @"reddot"];
    NSString *appPath = [[NSBundle mainBundle] bundlePath];
    unsigned count = 0;
    Class *classes = objc_copyClassList(&count);
    NSMutableString *out = [NSMutableString stringWithFormat:@"# ZaloXposed scan - %u classes total\n# format: [+/-][Class sel] returnType args | image\n", count];
    NSUInteger lines = 0;

    for (unsigned i = 0; i < count && lines < 2500; i++) {
        Class c = classes[i];
        const char *image = class_getImageName(c);
        if (!image || strncmp(image, appPath.UTF8String, appPath.length) != 0) continue;
        NSString *cname = NSStringFromClass(c);
        NSString *imageName = [[NSString stringWithUTF8String:image] lastPathComponent];

        for (int meta = 0; meta < 2; meta++) {
            Class k = meta ? object_getClass(c) : c;
            unsigned mc = 0;
            Method *ms = class_copyMethodList(k, &mc);
            for (unsigned j = 0; j < mc; j++) {
                NSString *sel = NSStringFromSelector(method_getName(ms[j]));
                NSString *lower = sel.lowercaseString;
                NSString *lowerClass = cname.lowercaseString;
                BOOL hit = NO;
                for (NSString *kw in keywords)
                    if ([lower containsString:kw] || [lowerClass containsString:kw]) { hit = YES; break; }
                if (!hit && ([lower containsString:@"video"] || [lower containsString:@"pickerquality"])) {
                    for (NSString *vw in videoWords)
                        if ([lower containsString:vw]) { hit = YES; break; }
                }
                if (!hit) continue;
                for (NSString *nz in noise)
                    if ([lower containsString:nz] || [lowerClass containsString:nz]) { hit = NO; break; }
                if (!hit) continue;
                char *ret = method_copyReturnType(ms[j]);
                NSMutableString *args = [NSMutableString new];
                for (unsigned a = 2; a < method_getNumberOfArguments(ms[j]); a++) {
                    char *t = method_copyArgumentType(ms[j], a);
                    [args appendFormat:@"%s ", t ?: "?"];
                    free(t);
                }
                [out appendFormat:@"%c[%@ %@] ret=%s args=%@| %@\n", meta ? '+' : '-', cname, sel, ret ?: "?", args, imageName];
                free(ret);
                lines++;
            }
            free(ms);
        }
    }
    free(classes);
    [out writeToFile:[self scanPath] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    ZXLog(@"scan done: %lu matches", (unsigned long)lines);
    return [self scanPath];
}

@end
