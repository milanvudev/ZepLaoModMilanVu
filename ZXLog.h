#import <Foundation/Foundation.h>

void ZXLogImpl(NSString *msg);
NSString *ZXLogPath(void);
#define ZXLog(fmt, ...) ZXLogImpl([NSString stringWithFormat:(fmt), ##__VA_ARGS__])
