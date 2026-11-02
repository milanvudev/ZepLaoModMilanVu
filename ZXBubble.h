#import <UIKit/UIKit.h>

/// Floating draggable capybara bubble shown when the menu is collapsed.
@interface ZXBubble : NSObject
+ (void)show;      // show bubble (and remember it)
+ (void)hide;      // hide bubble (and forget it)
+ (void)restoreIfNeeded; // re-show after app launch if it was visible
@end
