#import <Foundation/Foundation.h>

/// Remembers which messages were recalled (ids collected at runtime from the undo
/// objects) and draws a faint note on those chat cells.
@interface ZXRecallMarker : NSObject
+ (void)install;
+ (void)markObjects:(NSArray *)objects;
+ (void)clearMarks;
+ (void)dumpViewHierarchy;
@end
