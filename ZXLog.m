#import "ZXLog.h"
#import "ZXConfig.h"

NSString *ZXLogPath(void)
{
    return [[ZXConfig dataDir] stringByAppendingPathComponent:@"log.txt"];
}

void ZXLogImpl(NSString *msg)
{
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ q = dispatch_queue_create("zaloxposed.log", DISPATCH_QUEUE_SERIAL); });
    NSLog(@"[ZaloXposed] %@", msg);
    dispatch_async(q, ^{
        NSString *path = ZXLogPath();
        NSFileManager *fm = [NSFileManager defaultManager];
        NSDictionary *attr = [fm attributesOfItemAtPath:path error:nil];
        if ([attr fileSize] > 512 * 1024)
            [fm removeItemAtPath:path error:nil];
        NSDateFormatter *f = [NSDateFormatter new];
        f.dateFormat = @"yyyy-MM-dd HH:mm:ss";
        NSString *line = [NSString stringWithFormat:@"%@ %@\n", [f stringFromDate:[NSDate date]], msg];
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        if (![fm fileExistsAtPath:path]) {
            [data writeToFile:path atomically:YES];
            return;
        }
        NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:path];
        [h seekToEndOfFile];
        [h writeData:data];
        [h closeFile];
    });
}
