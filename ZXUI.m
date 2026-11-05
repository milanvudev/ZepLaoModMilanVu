#import "ZXUI.h"
#import "ZXConfig.h"
#import "ZXLog.h"
#import "ZXHookEngine.h"
#import "ZXScanner.h"
#import "ZXAntiRecall.h"
#import "ZXRecallMarker.h"
#import "ZXBubble.h"
#import <objc/runtime.h>

static UIWindow *ZXKeyWindow(void)
{
    if (@available(iOS 13.0, *)) {
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
            if (![s isKindOfClass:[UIWindowScene class]]) continue;
            if (s.activationState != UISceneActivationStateForegroundActive) continue;
            for (UIWindow *w in ((UIWindowScene *)s).windows)
                if (w.isKeyWindow) return w;
        }
    }
    UIWindow *w = UIApplication.sharedApplication.keyWindow;
    return w ?: UIApplication.sharedApplication.windows.firstObject;
}

static UIViewController *ZXTopVC(void)
{
    UIViewController *v = ZXKeyWindow().rootViewController;
    while (v.presentedViewController) v = v.presentedViewController;
    return v;
}

// ---------------------------------------------------------------- text viewer/editor

@interface ZXTextViewController : UIViewController
@property (nonatomic, copy) NSString *initialText;
@property (nonatomic, assign) BOOL editable;
@property (nonatomic, copy) BOOL (^onSave)(NSString *text, NSString **error);
@property (nonatomic, strong) UITextView *textView;
@end

@implementation ZXTextViewController
- (void)viewDidLoad
{
    [super viewDidLoad];
    if (@available(iOS 13.0, *)) self.view.backgroundColor = UIColor.systemBackgroundColor;
    else self.view.backgroundColor = UIColor.whiteColor;
    self.textView = [[UITextView alloc] initWithFrame:self.view.bounds];
    self.textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.textView.font = [UIFont fontWithName:@"Menlo" size:11] ?: [UIFont systemFontOfSize:11];
    self.textView.text = self.initialText;
    self.textView.editable = self.editable;
    self.textView.autocorrectionType = UITextAutocorrectionTypeNo;
    self.textView.autocapitalizationType = UITextAutocapitalizationTypeNone;
    [self.view addSubview:self.textView];
    if (self.editable)
        self.navigationItem.rightBarButtonItem =
            [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(save)];
    else
        self.navigationItem.rightBarButtonItem =
            [[UIBarButtonItem alloc] initWithTitle:@"Sao chép" style:UIBarButtonItemStylePlain target:self action:@selector(copyAll)];
}
- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    // plain white text page: give the bar an opaque dark background so white titles/buttons stay readable
    UINavigationBar *bar = self.navigationController.navigationBar;
    bar.prefersLargeTitles = NO;
    bar.tintColor = UIColor.whiteColor;
    if (@available(iOS 13.0, *)) {
        UINavigationBarAppearance *ap = [UINavigationBarAppearance new];
        [ap configureWithOpaqueBackground];
        ap.backgroundColor = [UIColor colorWithRed:0.08 green:0.16 blue:0.34 alpha:1];
        ap.titleTextAttributes = @{ NSForegroundColorAttributeName: UIColor.whiteColor };
        bar.standardAppearance = ap;
        bar.scrollEdgeAppearance = ap;
        bar.compactAppearance = ap;
    }
}
- (void)copyAll
{
    [UIPasteboard generalPasteboard].string = self.textView.text ?: @"";
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Đã sao chép" message:@"Dán vào chat để gửi." preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)save
{
    NSString *err = nil;
    if (self.onSave && !self.onSave(self.textView.text, &err)) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Lỗi" message:err ?: @"Không lưu được" preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }
    [self.navigationController popViewControllerAnimated:YES];
}
@end


// ---------------------------------------------------------------- visual theme (landscape background, rounded cards, animated toggle)

static UIImage *ZXLandscapeImage(CGSize size)
{
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGContextRef c = ctx.CGContext;
        CGFloat w = size.width, h = size.height;
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();

        // sky: night teal -> dawn orange -> pink haze
        NSArray *sky = @[(id)[UIColor colorWithRed:0.08 green:0.20 blue:0.42 alpha:1].CGColor,
                         (id)[UIColor colorWithRed:0.26 green:0.38 blue:0.64 alpha:1].CGColor,
                         (id)[UIColor colorWithRed:0.93 green:0.52 blue:0.42 alpha:1].CGColor,
                         (id)[UIColor colorWithRed:1.00 green:0.78 blue:0.55 alpha:1].CGColor];
        CGFloat locs[] = {0.0, 0.38, 0.66, 0.85};
        CGGradientRef g = CGGradientCreateWithColors(cs, (__bridge CFArrayRef)sky, locs);
        CGContextDrawLinearGradient(c, g, CGPointMake(0, 0), CGPointMake(0, h), 0);
        CGGradientRelease(g);

        // sun glow
        CGPoint sun = CGPointMake(w * 0.72, h * 0.50);
        NSArray *glow = @[(id)[UIColor colorWithRed:1 green:0.95 blue:0.75 alpha:0.95].CGColor,
                          (id)[UIColor colorWithRed:1 green:0.75 blue:0.45 alpha:0.35].CGColor,
                          (id)[UIColor colorWithRed:1 green:0.6 blue:0.4 alpha:0.0].CGColor];
        CGFloat gl[] = {0.0, 0.25, 1.0};
        CGGradientRef sg = CGGradientCreateWithColors(cs, (__bridge CFArrayRef)glow, gl);
        CGContextDrawRadialGradient(c, sg, sun, 0, sun, w * 0.7, 0);
        CGGradientRelease(sg);

        // stars
        srand(7);
        for (int i = 0; i < 40; i++) {
            CGFloat x = (rand() % 1000) / 1000.0 * w, y = (rand() % 1000) / 1000.0 * h * 0.32;
            CGFloat a = 0.25 + (rand() % 60) / 100.0, d = 1 + (rand() % 20) / 10.0;
            CGContextSetFillColorWithColor(c, [UIColor colorWithWhite:1 alpha:a].CGColor);
            CGContextFillEllipseInRect(c, CGRectMake(x, y, d, d));
        }

        // mountain ranges, far -> near
        struct { CGFloat base, a1, f1, p1, a2, f2, p2; CGFloat r, g, b; } L[] = {
            {0.55, 26, 0.010, 0.4, 10, 0.031, 1.1, 0.62, 0.48, 0.62},
            {0.64, 34, 0.008, 2.0, 12, 0.026, 0.3, 0.36, 0.40, 0.60},
            {0.74, 30, 0.012, 4.1, 14, 0.034, 2.2, 0.16, 0.36, 0.42},
            {0.85, 26, 0.009, 1.3, 10, 0.040, 3.5, 0.06, 0.22, 0.26},
        };
        for (int i = 0; i < 4; i++) {
            CGMutablePathRef p = CGPathCreateMutable();
            CGPathMoveToPoint(p, NULL, 0, h);
            for (CGFloat x = 0; x <= w + 4; x += 4) {
                CGFloat y = h * L[i].base + sin(x * L[i].f1 + L[i].p1) * L[i].a1 + sin(x * L[i].f2 + L[i].p2) * L[i].a2;
                CGPathAddLineToPoint(p, NULL, x, y);
            }
            CGPathAddLineToPoint(p, NULL, w, h);
            CGPathCloseSubpath(p);
            CGContextAddPath(c, p);
            CGContextSetFillColorWithColor(c, [UIColor colorWithRed:L[i].r green:L[i].g blue:L[i].b alpha:1].CGColor);
            CGContextFillPath(c);
            CGPathRelease(p);
        }
        CGColorSpaceRelease(cs);
    }];
}

static UIView *ZXMakeCloud(CGFloat w)
{
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, w * 0.36)];
    CGFloat h = v.bounds.size.height;
    CGRect parts[] = {CGRectMake(0, h * 0.35, w * 0.55, h * 0.65), CGRectMake(w * 0.22, 0, w * 0.5, h * 0.9),
                      CGRectMake(w * 0.45, h * 0.3, w * 0.55, h * 0.7)};
    for (int i = 0; i < 3; i++) {
        UIView *p = [[UIView alloc] initWithFrame:parts[i]];
        p.backgroundColor = [UIColor colorWithWhite:1 alpha:0.20];
        p.layer.cornerRadius = parts[i].size.height / 2;
        [v addSubview:p];
    }
    return v;
}

static UIColor *ZXAccent(void) { return [UIColor colorWithRed:0.05 green:0.55 blue:0.40 alpha:1]; } // 3.9:1 on white
static BOOL ZXReduceMotion(void) { return UIAccessibilityIsReduceMotionEnabled(); }
static BOOL ZXReduceTransparency(void) { return UIAccessibilityIsReduceTransparencyEnabled(); }

@interface ZXToggle : UIControl
@property (nonatomic, assign) BOOL on;
- (void)setOn:(BOOL)on animated:(BOOL)animated;
@end

@implementation ZXToggle {
    UIView *_knob;
}
- (instancetype)init
{
    self = [super initWithFrame:CGRectMake(0, 0, 58, 32)];
    if (self) {
        self.layer.cornerRadius = 16;
        _knob = [[UIView alloc] initWithFrame:CGRectMake(3, 3, 26, 26)];
        _knob.backgroundColor = UIColor.whiteColor;
        _knob.layer.cornerRadius = 13;
        _knob.layer.shadowColor = UIColor.blackColor.CGColor;
        _knob.layer.shadowOpacity = 0.28;
        _knob.layer.shadowRadius = 3;
        _knob.layer.shadowOffset = CGSizeMake(0, 2);
        _knob.userInteractionEnabled = NO;
        [self addSubview:_knob];
        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitButton;
        [self applyState];
    }
    return self;
}
- (CGSize)intrinsicContentSize { return CGSizeMake(58, 32); }
- (NSString *)accessibilityValue { return self.on ? @"Bật" : @"Tắt"; }
- (BOOL)accessibilityActivate
{
    [self setOn:!self.on animated:YES];
    [self sendActionsForControlEvents:UIControlEventValueChanged];
    return YES;
}
- (void)applyState
{
    self.backgroundColor = self.on ? ZXAccent() : [UIColor colorWithRed:0.45 green:0.47 blue:0.52 alpha:1];
    CGFloat kw = _knob.bounds.size.width;
    _knob.frame = CGRectMake(self.on ? self.bounds.size.width - kw - 3 : 3, 3, kw, 26);
}
- (void)setOn:(BOOL)on { [self setOn:on animated:NO]; }
- (void)setOn:(BOOL)on animated:(BOOL)animated
{
    _on = on;
    if (!animated) { [self applyState]; return; }
    if (ZXReduceMotion()) {
        [UIView animateWithDuration:0.15 animations:^{ [self applyState]; self.transform = CGAffineTransformIdentity; }];
        return;
    }
    [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.58 initialSpringVelocity:0.9
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        [self applyState];
        self.transform = CGAffineTransformIdentity;
    } completion:nil];
}
- (BOOL)beginTrackingWithTouch:(UITouch *)t withEvent:(UIEvent *)e
{
    [UIView animateWithDuration:0.15 animations:^{
        self->_knob.frame = CGRectMake(self->_knob.frame.origin.x - (self.on ? 6 : 0), 3, 32, 26);
        self.transform = CGAffineTransformMakeScale(0.94, 0.94);
    }];
    return YES;
}
- (void)endTrackingWithTouch:(UITouch *)t withEvent:(UIEvent *)e
{
    CGPoint pt = [t locationInView:self];
    CGRect hit = CGRectInset(self.bounds, -12, -12);
    CGRect kf = _knob.frame; kf.size.width = 26; _knob.frame = kf;
    if (CGRectContainsPoint(hit, pt)) {
        UIImpactFeedbackGenerator *h = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [h impactOccurred];
        [self setOn:!self.on animated:YES];
        [self sendActionsForControlEvents:UIControlEventValueChanged];
    } else {
        [self setOn:self.on animated:YES];
    }
}
- (void)cancelTrackingWithEvent:(UIEvent *)e
{
    CGRect kf = _knob.frame; kf.size.width = 26; _knob.frame = kf;
    [self setOn:self.on animated:YES];
}
@end

#define ZXK_LIQUID_GLASS @"liquid_glass_menu"

static NSString *ZXBackgroundPath(void)
{
    return [[ZXConfig dataDir] stringByAppendingPathComponent:@"menu_bg.jpg"];
}

static UIVisualEffect *ZXGlassEffect(void);
static BOOL ZXGlassOn(void);
static void ZXHookFloatingTabBar(void);
static BOOL ZXFloatingTabBarOn(void);

@interface ZXCardCell : UITableViewCell
- (void)applyCardStyle;
@end

@implementation ZXCardCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid
{
    self = [super initWithStyle:style reuseIdentifier:rid];
    if (self) {
        self.contentView.backgroundColor = UIColor.clearColor;
        self.layer.cornerRadius = 18;
        if (@available(iOS 13.0, *)) self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.masksToBounds = YES;
        self.selectedBackgroundView = [UIView new];
        self.selectedBackgroundView.backgroundColor = [UIColor colorWithRed:0.05 green:0.55 blue:0.40 alpha:0.14];
        self.textLabel.textColor = [UIColor colorWithWhite:0.08 alpha:1];                 // ~17:1 on the card
        self.textLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[UIFont systemFontOfSize:17 weight:UIFontWeightSemibold]];
        self.textLabel.adjustsFontForContentSizeCategory = YES;
        self.detailTextLabel.textColor = [UIColor colorWithWhite:0.33 alpha:1];           // ~7:1 on the card
        self.detailTextLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[UIFont systemFontOfSize:13]];
        self.detailTextLabel.adjustsFontForContentSizeCategory = YES;
        [self applyCardStyle];
    }
    return self;
}
/// UITableView resets cell.backgroundColor right before display, so this is called again from willDisplayCell.
/// Liquid Glass on: UIGlassEffect behind the row, white text. Off (or Reduce Transparency): near-opaque white card, dark text.
- (void)applyCardStyle
{
    if (ZXGlassOn()) {
        self.backgroundColor = UIColor.clearColor;
        if (![self.backgroundView isKindOfClass:[UIVisualEffectView class]]) {
            UIVisualEffectView *ev = [[UIVisualEffectView alloc] initWithEffect:ZXGlassEffect()];
            ev.layer.cornerRadius = 18;
            if (@available(iOS 13.0, *)) ev.layer.cornerCurve = kCACornerCurveContinuous;
            ev.clipsToBounds = YES;
            self.backgroundView = ev;
        }
        self.textLabel.textColor = UIColor.whiteColor;
        self.detailTextLabel.textColor = [UIColor colorWithWhite:1 alpha:0.82];
    } else {
        self.backgroundView = nil;
        self.backgroundColor = [UIColor colorWithWhite:1 alpha:ZXReduceTransparency() ? 1.0 : 0.92];
        self.textLabel.textColor = [UIColor colorWithWhite:0.08 alpha:1];
        self.detailTextLabel.textColor = [UIColor colorWithWhite:0.33 alpha:1];
    }
}
- (void)setFrame:(CGRect)frame
{
    [super setFrame:CGRectInset(frame, 14, 4)];
}
- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated
{
    [super setHighlighted:highlighted animated:animated];
    if (ZXReduceMotion()) return;
    [UIView animateWithDuration:0.18 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0
                        options:UIViewAnimationOptionAllowUserInteraction animations:^{
        self.transform = highlighted ? CGAffineTransformMakeScale(0.97, 0.97) : CGAffineTransformIdentity;
    } completion:nil];
}
@end

// ---------------------------------------------------------------- settings table

static NSArray<NSDictionary *> *ZXCategories(void)
{
    return @[
        @{ @"title": @"Quyền riêng tư", @"icon": @"eye.slash", @"desc": @"Ẩn đã xem, đang nhập", @"items": @[
            @{ @"key": ZXK_BLOCK_SEEN, @"title": @"Chặn trạng thái \"Đã xem\"", @"sub": @"Người gửi không thấy bạn đã đọc tin", @"kw": @"seen ghost đã đọc xem" },
            @{ @"key": ZXK_SILENT_TYPING, @"title": @"Ẩn trạng thái \"Đang nhập\"", @"sub": @"Người nhận không thấy bạn đang soạn tin", @"kw": @"typing đang soạn gõ" },
        ]},
        @{ @"title": @"Tin thu hồi & xóa", @"icon": @"arrow.uturn.backward.circle", @"desc": @"Giữ lại tin bị thu hồi", @"items": @[
            @{ @"key": ZXK_ANTI_RECALL, @"title": @"Giữ tin bị thu hồi", @"sub": @"Tin vẫn hiện khi người khác thu hồi", @"kw": @"anti recall chống thu hồi" },
            @{ @"key": ZXK_SHOW_CONTENT, @"title": @"Hiện nội dung tin bị thu hồi/xóa", @"sub": @"Lưu tạm nội dung tin nhận được trên máy" },
            @{ @"key": ZXK_RECALL_NOTE, @"title": @"Nhãn \"đã thu hồi\" trên tin", @"sub": @"Hiện chữ nhỏ mờ trong khung tin được giữ lại" },
            @{ @"key": ZXK_ANTI_RECALL_INCLUDE_ME, @"title": @"Áp dụng cả tin do mình thu hồi" },
            @{ @"key": ZXK_ANTI_DELETE, @"title": @"Giữ tin bị xóa", @"sub": @"Cần xác nhận hoạt động trên máy bạn", @"kw": @"anti delete chống xóa" },
            @{ @"key": ZXK_ANTI_DELETE_INCLUDE_ME, @"title": @"Áp dụng cả tin do mình xóa" },
            @{ @"action": @"history", @"title": @"Lịch sử tin bị thu hồi / xóa" },
            @{ @"action": @"clearmarks", @"title": @"Xóa danh sách tin đã đánh dấu" },
            @{ @"action": @"clearcache", @"title": @"Xóa bộ nhớ đệm tin nhắn" },
            @{ @"action": @"uid", @"title": @"User ID của bạn", @"sub": @"Dùng để phân biệt tin của mình" },
        ]},
        @{ @"title": @"Quảng cáo & theo dõi", @"icon": @"shield.lefthalf.filled", @"desc": @"Chặn quảng cáo, log", @"items": @[
            @{ @"key": ZXK_BLOCK_ADS, @"title": @"Chặn quảng cáo", @"sub": @"Chặn các máy chủ quảng cáo của Zalo", @"kw": @"ads ad" },
            @{ @"key": ZXK_DISABLE_TRACKING, @"title": @"Tắt theo dõi (tracking)", @"sub": @"Không gửi log hành vi về Zalo" },
            @{ @"key": ZXK_BLOCK_QOS, @"title": @"Chặn log chất lượng (QoS)" },
            @{ @"key": ZXK_DISABLE_FIREBASE, @"title": @"Tắt Firebase logging" },
        ]},
        @{ @"title": @"Ảnh, file & tự hủy", @"icon": @"photo.on.rectangle", @"desc": @"Original, file lớn, TTL", @"items": @[
            @{ @"key": ZXK_DEFAULT_ORIGINAL, @"title": @"Gửi ảnh Original mặc định", @"sub": @"Chọn sẵn chất lượng gốc khi mở bảng chế độ gửi", @"kw": @"hd chất lượng ảnh" },
            @{ @"key": ZXK_VIDEO_ORIGINAL, @"title": @"Gửi video giữ nguyên gốc (thử nghiệm)", @"sub": @"Bỏ bước nén lại video. Tắt nếu gửi video bị lỗi. Cần thoát app để áp dụng", @"kw": @"video hd chất lượng" },
            @{ @"key": ZXK_UNLIMITED_MEDIA, @"title": @"Nâng giới hạn dung lượng gửi", @"sub": @"Gửi file/ảnh lớn hơn mức mặc định", @"kw": @"file size không giới hạn" },
            @{ @"key": ZXK_TTL_OVERRIDE, @"title": @"Đặt thời gian tự hủy (TTL)", @"sub": @"Áp dụng cho tin bạn gửi", @"kw": @"ttl tự hủy" },
            @{ @"action": @"ttl", @"title": @"Giá trị TTL (ms)" },
        ]},
        @{ @"title": @"Giao diện", @"icon": @"paintbrush", @"desc": @"Nền, kính, hiệu ứng", @"items": @[
            @{ @"key": ZXK_LIQUID_GLASS, @"title": @"Liquid Glass", @"sub": @"Ô menu, nút Thu gọn/Xong và các hàng tính năng dùng kính trong suốt", @"kw": @"kính glass" },
            @{ @"key": ZXK_FLOATING_TABBAR, @"title": @"Thanh tab nổi, kính lỏng (thử nghiệm)", @"sub": @"Biến thanh Tin nhắn/Danh bạ/… dưới cùng thành thanh nổi bo tròn, kính trong suốt. Có thể chưa đổi ngay, quay lại màn hình chính hoặc thoát app để thấy", @"kw": @"tabbar floating pill kính lỏng" },
            @{ @"action": @"bgpick", @"title": @"Đổi ảnh nền", @"sub": @"Chọn ảnh từ thư viện, kéo và thu phóng để cắt", @"kw": @"background wallpaper" },
            @{ @"action": @"bgreset", @"title": @"Dùng lại nền phong cảnh" },
        ]},
        @{ @"title": @"Công cụ nâng cao", @"icon": @"wrench.and.screwdriver", @"desc": @"Quét, rules, log", @"footer": @YES, @"items": @[
            @{ @"action": @"scan", @"title": @"Quét class/method", @"sub": @"Tìm hàm có thể hook" },
            @{ @"action": @"viewscan", @"title": @"Xem / chia sẻ kết quả quét" },
            @{ @"action": @"rules", @"title": @"Sửa rules.json" },
            @{ @"action": @"log", @"title": @"Xem log" },
            @{ @"action": @"exit", @"title": @"Thoát app để áp dụng rules mới" },
        ]},
    ];
}

/// Landscape (or user-chosen) backdrop shared by every screen of the menu.
static UIView *ZXMakeBackdrop(void)
{
    UIImage *custom = [UIImage imageWithContentsOfFile:ZXBackgroundPath()];
    if (custom) {
        UIImageView *bg = [[UIImageView alloc] initWithImage:custom];
        bg.contentMode = UIViewContentModeScaleAspectFill;
        bg.clipsToBounds = YES;
        UIView *dim = [[UIView alloc] initWithFrame:UIScreen.mainScreen.bounds];
        dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        dim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.22];
        [bg addSubview:dim];
        return bg;
    }
    UIImageView *bg = [[UIImageView alloc] initWithImage:ZXLandscapeImage(UIScreen.mainScreen.bounds.size)];
    bg.contentMode = UIViewContentModeScaleAspectFill;
    bg.clipsToBounds = YES;
    CGFloat cw[] = {150, 110, 190};
    CGFloat cy[] = {0.14, 0.26, 0.38};
    CGFloat dur[] = {26, 34, 42};
    CGFloat sw = UIScreen.mainScreen.bounds.size.width, sh = UIScreen.mainScreen.bounds.size.height;
    for (int i = 0; i < 3; i++) {
        UIView *cloud = ZXMakeCloud(cw[i]);
        cloud.center = CGPointMake(sw * (0.2 + 0.3 * i), sh * cy[i]);
        [bg addSubview:cloud];
        CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"transform.translation.x"];
        a.fromValue = @(-50); a.toValue = @(70); a.duration = dur[i];
        a.autoreverses = YES; a.repeatCount = HUGE_VALF;
        a.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        if (!ZXReduceMotion()) [cloud.layer addAnimation:a forKey:@"drift"];
    }
    return bg;
}

static void ZXStyleNavBar(UINavigationBar *bar)
{
    bar.tintColor = UIColor.whiteColor;
    if (@available(iOS 13.0, *)) {
        NSDictionary *big = @{ NSForegroundColorAttributeName: UIColor.whiteColor };
        NSDictionary *small = @{ NSForegroundColorAttributeName: UIColor.whiteColor,
                                 NSFontAttributeName: [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold] };
        UINavigationBarAppearance *std = [UINavigationBarAppearance new];   // scrolled: blurred so content never runs under the title
        if (ZXReduceTransparency()) {
            [std configureWithOpaqueBackground];
            std.backgroundColor = [UIColor colorWithRed:0.08 green:0.16 blue:0.34 alpha:1];
        } else {
            [std configureWithTransparentBackground];
            std.backgroundEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark];
        }
        std.titleTextAttributes = small;
        std.largeTitleTextAttributes = big;
        UINavigationBarAppearance *edge = [UINavigationBarAppearance new]; // at rest: transparent over the landscape
        [edge configureWithTransparentBackground];
        edge.titleTextAttributes = small;
        edge.largeTitleTextAttributes = big;
        bar.standardAppearance = std;
        bar.scrollEdgeAppearance = edge;
        bar.compactAppearance = std;
    }
}

static UIColor *ZXAccentText(void) { return [UIColor colorWithRed:0.02 green:0.38 blue:0.28 alpha:1]; } // 6.8:1 on white



@interface ZXSettingsViewController : UITableViewController <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, strong) NSArray<NSDictionary *> *sections;
@property (nonatomic, strong) NSMutableSet<NSIndexPath *> *shownRows;
@property (nonatomic, assign) BOOL showHeaders;   // search results show one chip per category
@property (nonatomic, assign) BOOL showFooter;    // credits, on the tools page
- (instancetype)initWithSections:(NSArray<NSDictionary *> *)sections title:(NSString *)title;
@end

@implementation ZXSettingsViewController

- (instancetype)initWithSections:(NSArray<NSDictionary *> *)sections title:(NSString *)title
{
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        self.title = title;
        self.sections = sections ?: @[];
    }
    return self;
}

- (void)buildBackground
{
    self.tableView.backgroundView = ZXMakeBackdrop();
}

- (void)pickBackground
{
    UIImagePickerController *pk = [UIImagePickerController new];
    pk.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    pk.allowsEditing = YES; // crop / move / zoom
    pk.delegate = self;
    [self presentViewController:pk animated:YES completion:nil];
}
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)info
{
    UIImage *img = info[UIImagePickerControllerEditedImage] ?: info[UIImagePickerControllerOriginalImage];
    if (img) {
        CGFloat maxSide = 1800, m = MAX(img.size.width, img.size.height);
        if (m > maxSide) {
            CGFloat k = maxSide / m;
            CGSize ns = CGSizeMake(img.size.width * k, img.size.height * k);
            UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:ns];
            img = [r imageWithActions:^(UIGraphicsImageRendererContext *c) { [img drawInRect:CGRectMake(0, 0, ns.width, ns.height)]; }];
        }
        [UIImageJPEGRepresentation(img, 0.88) writeToFile:ZXBackgroundPath() atomically:YES];
    }
    [picker dismissViewControllerAnimated:YES completion:^{ [self buildBackground]; }];
}
- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker
{
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.shownRows = [NSMutableSet new];
    if (@available(iOS 13.0, *)) self.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
    [self buildBackground];
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
}
- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    ZXStyleNavBar(self.navigationController.navigationBar);
    if (self.title.length) {
        self.navigationController.navigationBar.prefersLargeTitles = YES;
        self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return self.sections.count; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return [self.sections[s][@"items"] count]; }
- (UIView *)tableView:(UITableView *)tv viewForHeaderInSection:(NSInteger)s
{
    if (!self.showHeaders) return nil;
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tv.bounds.size.width, 44)];
    UILabel *l = [UILabel new];
    l.text = [self.sections[s][@"title"] uppercaseString];
    l.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[UIFont systemFontOfSize:12 weight:UIFontWeightHeavy]];
    l.adjustsFontForContentSizeCategory = YES;
    l.textColor = UIColor.whiteColor;
    l.numberOfLines = 0;
    CGFloat maxW = tv.bounds.size.width - 40 - 24;
    CGSize ls = [l sizeThatFits:CGSizeMake(maxW, CGFLOAT_MAX)];
    CGRect chip = CGRectMake(20, 10, MIN(ls.width, maxW) + 24, ls.height + 12);
    UIView *bgv;
    if (ZXReduceTransparency()) {
        bgv = [[UIView alloc] initWithFrame:chip];
        bgv.backgroundColor = [UIColor colorWithRed:0.05 green:0.10 blue:0.22 alpha:1];
    } else if ([ZXConfig boolForKey:ZXK_LIQUID_GLASS]) {
        UIVisualEffect *eff = nil;
        Class gc = NSClassFromString(@"UIGlassEffect");   // iOS 26+
        if (gc) eff = [[gc alloc] init];
        if (!eff) eff = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark];
        UIVisualEffectView *ev = [[UIVisualEffectView alloc] initWithEffect:eff];
        ev.frame = chip;
        bgv = ev;
    } else {
        bgv = [[UIView alloc] initWithFrame:chip];
        bgv.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];                      // white on this chip ≥ 7:1
    }
    bgv.layer.cornerRadius = chip.size.height / 2;
    if (@available(iOS 13.0, *)) bgv.layer.cornerCurve = kCACornerCurveContinuous;
    bgv.clipsToBounds = YES;
    l.frame = CGRectMake(12, 6, chip.size.width - 24, ls.height);
    if ([bgv isKindOfClass:[UIVisualEffectView class]]) [((UIVisualEffectView *)bgv).contentView addSubview:l];
    else [bgv addSubview:l];
    v.frame = CGRectMake(0, 0, tv.bounds.size.width, chip.size.height + 20);
    [v addSubview:bgv];
    v.accessibilityTraits = UIAccessibilityTraitHeader;
    return v;
}
- (CGFloat)tableView:(UITableView *)tv heightForHeaderInSection:(NSInteger)s
{
    if (!self.showHeaders) return 8;
    UILabel *l = [UILabel new];
    l.text = [self.sections[s][@"title"] uppercaseString];
    l.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[UIFont systemFontOfSize:12 weight:UIFontWeightHeavy]];
    l.numberOfLines = 0;
    CGSize ls = [l sizeThatFits:CGSizeMake(tv.bounds.size.width - 64, CGFLOAT_MAX)];
    return ls.height + 12 + 20;
}
- (UIView *)tableView:(UITableView *)tv viewForFooterInSection:(NSInteger)s
{
    if (!self.showFooter || s != (NSInteger)self.sections.count - 1) return nil;
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(20, 8, tv.bounds.size.width - 40, 60)];
    l.numberOfLines = 0;
    l.textAlignment = NSTextAlignmentCenter;
    l.text = @"Zép Lào Mod của MilanVu\nDựa trên ZaloXposed của ElectroHeavenVN (AGPL-3.0)";
    l.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    l.textColor = [UIColor colorWithWhite:1 alpha:0.85];
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tv.bounds.size.width, 80)];
    [v addSubview:l];
    return v;
}
- (CGFloat)tableView:(UITableView *)tv heightForFooterInSection:(NSInteger)s
{
    if (self.showFooter && s == (NSInteger)self.sections.count - 1) return 84;
    return 6;
}
- (void)tableView:(UITableView *)tv willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)ip
{
    if ([cell isKindOfClass:[ZXCardCell class]]) [(ZXCardCell *)cell applyCardStyle];
    if ([self.shownRows containsObject:ip]) return;
    [self.shownRows addObject:ip];
    if (ZXReduceMotion()) return;
    cell.alpha = 0;
    cell.transform = CGAffineTransformConcat(CGAffineTransformMakeTranslation(0, 26), CGAffineTransformMakeScale(0.95, 0.95));
    NSTimeInterval delay = MIN(ip.row, 8) * 0.035;
    [UIView animateWithDuration:0.5 delay:delay usingSpringWithDamping:0.78 initialSpringVelocity:0.4
                        options:UIViewAnimationOptionAllowUserInteraction animations:^{
        cell.alpha = 1;
        cell.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip
{
    NSDictionary *item = self.sections[ip.section][@"items"][ip.row];
    UITableViewCell *cell = [[ZXCardCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.text = item[@"title"];
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = 0;
    NSString *action = item[@"action"];
    if (item[@"key"]) {
        cell.detailTextLabel.text = item[@"sub"];
        ZXToggle *sw = [ZXToggle new];
        sw.on = [ZXConfig boolForKey:item[@"key"]];
        sw.tag = ip.section * 100 + ip.row;
        sw.accessibilityLabel = item[@"title"];
        [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else {
        if ([action isEqualToString:@"uid"])
            cell.detailTextLabel.text = [ZXConfig currentUserID].length ? [ZXConfig currentUserID] : item[@"sub"];
        else if ([action isEqualToString:@"ttl"])
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%lld", [ZXConfig ttl]];
        else
            cell.detailTextLabel.text = item[@"sub"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.tintColor = ZXAccent();
    }
    return cell;
}

- (void)switchChanged:(ZXToggle *)sw
{
    NSDictionary *item = self.sections[sw.tag / 100][@"items"][sw.tag % 100];
    [ZXConfig setBool:sw.on forKey:item[@"key"]];
    if ([item[@"key"] isEqualToString:ZXK_LIQUID_GLASS]) {
        [self.shownRows removeAllObjects];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [UIView transitionWithView:self.tableView duration:0.45 options:UIViewAnimationOptionTransitionCrossDissolve
                            animations:^{ [self.tableView reloadData]; } completion:nil];
        });
    } else if ([item[@"key"] isEqualToString:ZXK_FLOATING_TABBAR]) {
        ZXHookFloatingTabBar();
    }
}

- (void)alert:(NSString *)title message:(NSString *)msg
{
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)prompt:(NSString *)title text:(NSString *)text numeric:(BOOL)numeric done:(void (^)(NSString *))done
{
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = text;
        tf.keyboardType = numeric ? UIKeyboardTypeNumberPad : UIKeyboardTypeDefault;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Lưu" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        done(a.textFields.firstObject.text ?: @"");
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)pushText:(NSString *)text editable:(BOOL)editable title:(NSString *)title save:(BOOL (^)(NSString *, NSString **))save
{
    ZXTextViewController *vc = [ZXTextViewController new];
    vc.title = title;
    vc.initialText = text ?: @"";
    vc.editable = editable;
    vc.onSave = save;
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip
{
    [tv deselectRowAtIndexPath:ip animated:YES];
    NSDictionary *item = self.sections[ip.section][@"items"][ip.row];
    NSString *action = item[@"action"];
    if (!action) return;
    __weak typeof(self) weak = self;

    if ([action isEqualToString:@"bgpick"]) { [self pickBackground]; return; }
    if ([action isEqualToString:@"bgreset"]) {
        [[NSFileManager defaultManager] removeItemAtPath:ZXBackgroundPath() error:nil];
        [self buildBackground];
        return;
    }
    if ([action isEqualToString:@"uid"]) {
        [self prompt:@"User ID Zalo của bạn" text:[ZXConfig currentUserID] numeric:YES done:^(NSString *t) {
            [ZXConfig setCurrentUserID:[t stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]];
            [weak.tableView reloadData];
        }];
    } else if ([action isEqualToString:@"ttl"]) {
        [self prompt:@"TTL (ms)" text:[NSString stringWithFormat:@"%lld", [ZXConfig ttl]] numeric:YES done:^(NSString *t) {
            [ZXConfig setTTL:t.longLongValue];
            [weak.tableView reloadData];
        }];
    } else if ([action isEqualToString:@"scan"]) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            [ZXScanner runScan];
            dispatch_async(dispatch_get_main_queue(), ^{
                [weak alert:@"Quét xong" message:@"Chọn 'Xem / chia sẻ kết quả quét' để xem danh sách."];
            });
        });
    } else if ([action isEqualToString:@"viewscan"]) {
        NSString *t = [NSString stringWithContentsOfFile:[ZXScanner scanPath] encoding:NSUTF8StringEncoding error:nil];
        if (!t) { [self alert:@"Chưa có dữ liệu" message:@"Hãy chạy 'Quét class/method' trước."]; return; }
        [self pushText:t editable:NO title:@"scan.txt" save:nil];
        ZXTextViewController *vc = (ZXTextViewController *)self.navigationController.topViewController;
        UIBarButtonItem *copyItem = vc.navigationItem.rightBarButtonItem;
        UIBarButtonItem *shareItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(shareScan:)];
        vc.navigationItem.rightBarButtonItems = copyItem ? @[shareItem, copyItem] : @[shareItem];
    } else if ([action isEqualToString:@"rules"]) {
        [ZXHookEngine ensureRulesFile];
        NSString *t = [NSString stringWithContentsOfFile:[ZXHookEngine rulesPath] encoding:NSUTF8StringEncoding error:nil];
        [self pushText:t editable:YES title:@"rules.json" save:^BOOL(NSString *text, NSString **error) {
            NSMutableArray *lines = [NSMutableArray new];
            for (NSString *l in [text componentsSeparatedByString:@"\n"])
                if (![[l stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] hasPrefix:@"//"]) [lines addObject:l];
            NSData *d = [[lines componentsJoinedByString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
            NSError *e = nil;
            id j = [NSJSONSerialization JSONObjectWithData:d options:0 error:&e];
            if (![j isKindOfClass:[NSArray class]]) {
                if (error) *error = e.localizedDescription ?: @"JSON phải là một mảng [ ... ]";
                return NO;
            }
            [text writeToFile:[ZXHookEngine rulesPath] atomically:YES encoding:NSUTF8StringEncoding error:nil];
            return YES;
        }];
    } else if ([action isEqualToString:@"history"]) {
        NSString *t = [NSString stringWithContentsOfFile:[ZXAntiRecall historyPath] encoding:NSUTF8StringEncoding error:nil];
        [self pushText:(t ?: @"(chưa có tin nhắn nào bị thu hồi/xóa)") editable:NO title:@"Lịch sử" save:nil];
    } else if ([action isEqualToString:@"clearmarks"]) {
        [ZXRecallMarker clearMarks];
        [self alert:@"Đã xóa" message:@"Đã xóa danh sách tin đánh dấu thu hồi."];
    } else if ([action isEqualToString:@"clearcache"]) {
        [ZXAntiRecall clearCache];
        [self alert:@"Đã xóa" message:@"Bộ nhớ đệm tin nhắn đã được xóa."];
    } else if ([action isEqualToString:@"log"]) {
        NSString *t = [NSString stringWithContentsOfFile:ZXLogPath() encoding:NSUTF8StringEncoding error:nil];
        [self pushText:(t ?: @"(trống)") editable:NO title:@"log.txt" save:nil];
    } else if ([action isEqualToString:@"exit"]) {
        exit(0);
    }
}

- (void)shareScan:(UIBarButtonItem *)sender
{
    NSURL *url = [NSURL fileURLWithPath:[ZXScanner scanPath]];
    UIActivityViewController *v = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    v.popoverPresentationController.barButtonItem = sender;
    [self presentViewController:v animated:YES completion:nil];
}

@end

// ---------------------------------------------------------------- home: category tiles + search

/// UIGlassEffect on iOS 26+ (looked up at runtime so older SDKs still build); thin dark blur on older systems.
static UIVisualEffect *ZXGlassEffect(void)
{
    Class gc = NSClassFromString(@"UIGlassEffect");
    if (gc) {
        id e = [[gc alloc] init];
        @try { [e setValue:@YES forKey:@"interactive"]; } @catch (__unused id x) {}
        @try { [e setValue:[UIColor colorWithWhite:0 alpha:0.32] forKey:@"tintColor"]; } @catch (__unused id x) {} // keeps white text ≥ 4.5:1
        return e;
    }
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark];
}

static BOOL ZXGlassOn(void) { return [ZXConfig boolForKey:ZXK_LIQUID_GLASS] && !ZXReduceTransparency(); }

/// Capsule bar button with a glass background (used for "Thu gọn" / "Xong" when Liquid Glass is on).
static UIBarButtonItem *ZXGlassBarButton(NSString *title, BOOL bold, id target, SEL action)
{
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    b.titleLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[UIFont systemFontOfSize:16 weight:bold ? UIFontWeightSemibold : UIFontWeightRegular]];
    b.titleLabel.adjustsFontForContentSizeCategory = YES;
    CGSize ts = [title sizeWithAttributes:@{ NSFontAttributeName: b.titleLabel.font }];
    b.frame = CGRectMake(0, 0, MAX(64, ceil(ts.width) + 32), 40);
    UIVisualEffectView *ev = [[UIVisualEffectView alloc] initWithEffect:ZXGlassEffect()];
    ev.frame = b.bounds;
    ev.userInteractionEnabled = NO;
    ev.layer.cornerRadius = 20;
    ev.clipsToBounds = YES;
    ev.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [b insertSubview:ev atIndex:0];
    [b addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    b.accessibilityLabel = title;
    return [[UIBarButtonItem alloc] initWithCustomView:b];
}

@interface ZXTileCell : UICollectionViewCell
- (void)configureWithCategory:(NSDictionary *)cat;
@end

@implementation ZXTileCell {
    UIView *_iconBG;
    UIImageView *_icon;
    UILabel *_title, *_sub, *_badge;
    UIVisualEffectView *_glass;
}
- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.contentView.backgroundColor = [UIColor colorWithWhite:1 alpha:ZXReduceTransparency() ? 1.0 : 0.92];
    self.contentView.layer.cornerRadius = 22;
    if (@available(iOS 13.0, *)) self.contentView.layer.cornerCurve = kCACornerCurveContinuous;
    self.contentView.layer.masksToBounds = YES;

    _iconBG = [UIView new];
    _iconBG.backgroundColor = [UIColor colorWithRed:0.05 green:0.55 blue:0.40 alpha:0.14];
    _iconBG.layer.cornerRadius = 22;
    _icon = [UIImageView new];
    _icon.tintColor = ZXAccentText();
    _icon.contentMode = UIViewContentModeScaleAspectFit;

    _badge = [UILabel new];
    _badge.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold]];
    _badge.adjustsFontForContentSizeCategory = YES;
    _badge.textColor = ZXAccentText();
    _badge.textAlignment = NSTextAlignmentCenter;
    _badge.backgroundColor = [UIColor colorWithRed:0.05 green:0.55 blue:0.40 alpha:0.14];
    _badge.layer.cornerRadius = 12;
    _badge.layer.masksToBounds = YES;

    _title = [UILabel new];
    _title.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[UIFont systemFontOfSize:17 weight:UIFontWeightSemibold]];
    _title.adjustsFontForContentSizeCategory = YES;
    _title.textColor = [UIColor colorWithWhite:0.08 alpha:1];
    _title.numberOfLines = 2;
    _sub = [UILabel new];
    _sub.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[UIFont systemFontOfSize:13]];
    _sub.adjustsFontForContentSizeCategory = YES;
    _sub.textColor = [UIColor colorWithWhite:0.33 alpha:1];
    _sub.numberOfLines = 2;

    for (UIView *v in @[_iconBG, _icon, _badge, _title, _sub]) {
        v.translatesAutoresizingMaskIntoConstraints = NO;
    }
    UIView *c = self.contentView;
    [c addSubview:_iconBG]; [c addSubview:_icon]; [c addSubview:_badge]; [c addSubview:_title]; [c addSubview:_sub];
    [NSLayoutConstraint activateConstraints:@[
        [_iconBG.topAnchor constraintEqualToAnchor:c.topAnchor constant:16],
        [_iconBG.leadingAnchor constraintEqualToAnchor:c.leadingAnchor constant:16],
        [_iconBG.widthAnchor constraintEqualToConstant:44],
        [_iconBG.heightAnchor constraintEqualToConstant:44],
        [_icon.centerXAnchor constraintEqualToAnchor:_iconBG.centerXAnchor],
        [_icon.centerYAnchor constraintEqualToAnchor:_iconBG.centerYAnchor],
        [_icon.widthAnchor constraintEqualToConstant:24],
        [_icon.heightAnchor constraintEqualToConstant:24],
        [_badge.trailingAnchor constraintEqualToAnchor:c.trailingAnchor constant:-14],
        [_badge.centerYAnchor constraintEqualToAnchor:_iconBG.centerYAnchor],
        [_badge.heightAnchor constraintGreaterThanOrEqualToConstant:24],
        [_badge.widthAnchor constraintGreaterThanOrEqualToConstant:40],
        [_title.topAnchor constraintEqualToAnchor:_iconBG.bottomAnchor constant:12],
        [_title.leadingAnchor constraintEqualToAnchor:c.leadingAnchor constant:16],
        [_title.trailingAnchor constraintEqualToAnchor:c.trailingAnchor constant:-14],
        [_sub.topAnchor constraintEqualToAnchor:_title.bottomAnchor constant:3],
        [_sub.leadingAnchor constraintEqualToAnchor:_title.leadingAnchor],
        [_sub.trailingAnchor constraintEqualToAnchor:_title.trailingAnchor],
        [_sub.bottomAnchor constraintLessThanOrEqualToAnchor:c.bottomAnchor constant:-12],
    ]];
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    return self;
}
- (void)applyStyleGlass:(BOOL)glass
{
    if (glass) {
        if (!_glass) {
            _glass = [[UIVisualEffectView alloc] initWithEffect:ZXGlassEffect()];
            _glass.frame = self.contentView.bounds;
            _glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            _glass.userInteractionEnabled = NO;
            [self.contentView insertSubview:_glass atIndex:0];
        }
        _glass.hidden = NO;
        self.contentView.backgroundColor = UIColor.clearColor;
        _title.textColor = UIColor.whiteColor;
        _sub.textColor = [UIColor colorWithWhite:1 alpha:0.86];
        _icon.tintColor = UIColor.whiteColor;
        _iconBG.backgroundColor = [UIColor colorWithWhite:1 alpha:0.22];
        _badge.textColor = UIColor.whiteColor;
        _badge.backgroundColor = [UIColor colorWithWhite:1 alpha:0.22];
    } else {
        _glass.hidden = YES;
        self.contentView.backgroundColor = [UIColor colorWithWhite:1 alpha:ZXReduceTransparency() ? 1.0 : 0.92];
        _title.textColor = [UIColor colorWithWhite:0.08 alpha:1];
        _sub.textColor = [UIColor colorWithWhite:0.33 alpha:1];
        _icon.tintColor = ZXAccentText();
        _iconBG.backgroundColor = [UIColor colorWithRed:0.05 green:0.55 blue:0.40 alpha:0.14];
        _badge.textColor = ZXAccentText();
        _badge.backgroundColor = [UIColor colorWithRed:0.05 green:0.55 blue:0.40 alpha:0.14];
    }
}
- (void)configureWithCategory:(NSDictionary *)cat
{
    [self applyStyleGlass:ZXGlassOn()];
    UIImage *img = nil;
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightSemibold];
        img = [UIImage systemImageNamed:cat[@"icon"] withConfiguration:cfg] ?: [UIImage systemImageNamed:@"circle.grid.2x2" withConfiguration:cfg];
    }
    _icon.image = img;
    _title.text = cat[@"title"];
    _sub.text = cat[@"desc"];
    NSInteger total = 0, on = 0;
    for (NSDictionary *it in cat[@"items"])
        if (it[@"key"]) { total++; if ([ZXConfig boolForKey:it[@"key"]]) on++; }
    _badge.hidden = (total == 0);
    _badge.text = total ? [NSString stringWithFormat:@"%ld/%ld", (long)on, (long)total] : nil;
    self.accessibilityLabel = total
        ? [NSString stringWithFormat:@"%@. %@. %ld trên %ld tính năng đang bật", cat[@"title"], cat[@"desc"], (long)on, (long)total]
        : [NSString stringWithFormat:@"%@. %@", cat[@"title"], cat[@"desc"]];
}
- (void)setHighlighted:(BOOL)highlighted
{
    [super setHighlighted:highlighted];
    if (ZXReduceMotion()) return;
    [UIView animateWithDuration:0.18 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0
                        options:UIViewAnimationOptionAllowUserInteraction animations:^{
        self.transform = highlighted ? CGAffineTransformMakeScale(0.96, 0.96) : CGAffineTransformIdentity;
    } completion:nil];
}
@end

static NSString *ZXFold(NSString *t)
{
    NSString *f = [t ?: @"" stringByFoldingWithOptions:NSDiacriticInsensitiveSearch | NSCaseInsensitiveSearch locale:nil];
    f = [f stringByReplacingOccurrencesOfString:@"đ" withString:@"d"];
    f = [f stringByReplacingOccurrencesOfString:@"Đ" withString:@"d"];
    return f.lowercaseString;
}

@interface ZXHomeViewController : UIViewController <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UISearchResultsUpdating>
@property (nonatomic, strong) NSArray<NSDictionary *> *cats;
@property (nonatomic, strong) UICollectionView *cv;
@property (nonatomic, strong) UIView *backdrop;
@property (nonatomic, strong) UISearchController *search;
@property (nonatomic, strong) ZXSettingsViewController *results;
@property (nonatomic, strong) UIView *emptyView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) NSMutableSet<NSIndexPath *> *shown;
@end

@implementation ZXHomeViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Zép Lào Mod";
    // Liquid Glass starts ON once; after that the user's choice in "Giao diện" is respected
    if (![ZXConfig boolForKey:@"lg_default_applied"]) {
        [ZXConfig setBool:YES forKey:ZXK_LIQUID_GLASS];
        [ZXConfig setBool:YES forKey:@"lg_default_applied"];
    }
    self.cats = ZXCategories();
    self.shown = [NSMutableSet new];
    self.view.backgroundColor = [UIColor colorWithRed:0.08 green:0.16 blue:0.34 alpha:1];
    if (@available(iOS 13.0, *)) self.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
    [self refreshBackdrop];

    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
    layout.minimumLineSpacing = 12;
    layout.minimumInteritemSpacing = 12;
    layout.sectionInset = UIEdgeInsetsMake(8, 16, 28, 16);
    self.cv = [[UICollectionView alloc] initWithFrame:self.view.bounds collectionViewLayout:layout];
    self.cv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.cv.backgroundColor = UIColor.clearColor;
    self.cv.dataSource = self;
    self.cv.delegate = self;
    self.cv.alwaysBounceVertical = YES;
    self.cv.showsVerticalScrollIndicator = NO;
    self.cv.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.cv registerClass:[ZXTileCell class] forCellWithReuseIdentifier:@"tile"];
    [self.view addSubview:self.cv];

    // search results reuse the settings list, grouped by category
    self.results = [[ZXSettingsViewController alloc] initWithSections:@[] title:nil];
    self.results.showHeaders = YES;
    [self addChildViewController:self.results];
    self.results.view.frame = self.view.bounds;
    self.results.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.results.view.hidden = YES;
    [self.view addSubview:self.results.view];
    [self.results didMoveToParentViewController:self];

    // empty state
    self.emptyView = [UIView new];
    self.emptyView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
    self.emptyView.layer.cornerRadius = 16;
    self.emptyView.hidden = YES;
    self.emptyView.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyLabel = [UILabel new];
    self.emptyLabel.numberOfLines = 0;
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.textColor = UIColor.whiteColor;
    self.emptyLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[UIFont systemFontOfSize:15 weight:UIFontWeightMedium]];
    self.emptyLabel.adjustsFontForContentSizeCategory = YES;
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.emptyView addSubview:self.emptyLabel];
    [self.view addSubview:self.emptyView];
    [NSLayoutConstraint activateConstraints:@[
        [self.emptyLabel.topAnchor constraintEqualToAnchor:self.emptyView.topAnchor constant:14],
        [self.emptyLabel.bottomAnchor constraintEqualToAnchor:self.emptyView.bottomAnchor constant:-14],
        [self.emptyLabel.leadingAnchor constraintEqualToAnchor:self.emptyView.leadingAnchor constant:18],
        [self.emptyLabel.trailingAnchor constraintEqualToAnchor:self.emptyView.trailingAnchor constant:-18],
        [self.emptyView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.emptyView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:150],
        [self.emptyView.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:24],
        [self.emptyView.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-24],
    ]];

    // search field in its primary position (large-title navigation bar)
    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.searchResultsUpdater = self;
    self.search.obscuresBackgroundDuringPresentation = NO;
    UISearchBar *sb = self.search.searchBar;
    sb.placeholder = @"Tìm tính năng";
    sb.tintColor = UIColor.whiteColor;
    if (@available(iOS 13.0, *)) {
        sb.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        UISearchTextField *tf = sb.searchTextField;
        tf.backgroundColor = [UIColor colorWithWhite:0 alpha:0.32];
        tf.textColor = UIColor.whiteColor;
        tf.tintColor = UIColor.whiteColor;
        tf.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"Tìm tính năng"
            attributes:@{ NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:0.8] }];
        tf.leftView.tintColor = [UIColor colorWithWhite:1 alpha:0.8];
    }
    self.navigationItem.searchController = self.search;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;

    self.navigationItem.backButtonTitle = @"Menu";
    [self refreshBarButtons];
}

- (void)refreshBarButtons
{
    if (ZXGlassOn()) {
        self.navigationItem.rightBarButtonItem = ZXGlassBarButton(@"Xong", YES, self, @selector(close));
        self.navigationItem.leftBarButtonItem = ZXGlassBarButton(@"Thu gọn", NO, self, @selector(collapse));
    } else {
        self.navigationItem.rightBarButtonItem =
            [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];
        self.navigationItem.leftBarButtonItem =
            [[UIBarButtonItem alloc] initWithTitle:@"Thu gọn" style:UIBarButtonItemStylePlain target:self action:@selector(collapse)];
    }
    self.navigationItem.rightBarButtonItem.accessibilityLabel = @"Xong, đóng menu";
    self.navigationItem.leftBarButtonItem.accessibilityHint = @"Thu menu thành bong bóng";
}

- (void)refreshBackdrop
{
    [self.backdrop removeFromSuperview];
    self.backdrop = ZXMakeBackdrop();
    self.backdrop.frame = self.view.bounds;
    self.backdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view insertSubview:self.backdrop atIndex:0];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    UINavigationBar *bar = self.navigationController.navigationBar;
    ZXStyleNavBar(bar);
    bar.prefersLargeTitles = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    [self refreshBackdrop];
    [self refreshBarButtons];
    [self.cv reloadData];   // refresh the "n/m" counters after returning from a category
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)c
{
    [super viewWillTransitionToSize:size withTransitionCoordinator:c];
    [self.cv.collectionViewLayout invalidateLayout];
}

- (void)collapse { [self dismissViewControllerAnimated:YES completion:^{ [ZXBubble show]; }]; }
- (void)close { [ZXBubble hide]; [self dismissViewControllerAnimated:YES completion:nil]; }

// ---- collection view

- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)section { return self.cats.count; }
- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip
{
    ZXTileCell *cell = [cv dequeueReusableCellWithReuseIdentifier:@"tile" forIndexPath:ip];
    [cell configureWithCategory:self.cats[ip.item]];
    return cell;
}
- (CGSize)collectionView:(UICollectionView *)cv layout:(UICollectionViewLayout *)l sizeForItemAtIndexPath:(NSIndexPath *)ip
{
    CGFloat w = cv.bounds.size.width, inset = 16, gap = 12;
    BOOL big = UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory);
    if (big) return CGSizeMake(w - 2 * inset, 190);
    return CGSizeMake(floor((w - 2 * inset - gap) / 2), 172);
}
- (void)collectionView:(UICollectionView *)cv willDisplayCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)ip
{
    if ([self.shown containsObject:ip]) return;
    [self.shown addObject:ip];
    if (ZXReduceMotion()) return;
    cell.alpha = 0;
    cell.transform = CGAffineTransformConcat(CGAffineTransformMakeTranslation(0, 24), CGAffineTransformMakeScale(0.95, 0.95));
    [UIView animateWithDuration:0.5 delay:ip.item * 0.045 usingSpringWithDamping:0.78 initialSpringVelocity:0.4
                        options:UIViewAnimationOptionAllowUserInteraction animations:^{
        cell.alpha = 1;
        cell.transform = CGAffineTransformIdentity;
    } completion:nil];
}
- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip
{
    NSDictionary *cat = self.cats[ip.item];
    ZXSettingsViewController *vc = [[ZXSettingsViewController alloc] initWithSections:@[cat] title:cat[@"title"]];
    vc.showFooter = [cat[@"footer"] boolValue];
    [self.navigationController pushViewController:vc animated:YES];
}

// ---- search

- (void)updateSearchResultsForSearchController:(UISearchController *)sc
{
    NSString *raw = [(sc.searchBar.text ?: @"") stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (raw.length == 0) {
        self.results.view.hidden = YES;
        self.emptyView.hidden = YES;
        self.cv.hidden = NO;
        return;
    }
    NSArray<NSString *> *tokens = [[ZXFold(raw) componentsSeparatedByString:@" "] filteredArrayUsingPredicate:
                                   [NSPredicate predicateWithFormat:@"length > 0"]];
    NSMutableArray *secs = [NSMutableArray new];
    for (NSDictionary *cat in self.cats) {
        NSMutableArray *hits = [NSMutableArray new];
        for (NSDictionary *it in cat[@"items"]) {
            NSString *hay = ZXFold([NSString stringWithFormat:@"%@ %@ %@ %@", it[@"title"] ?: @"", it[@"sub"] ?: @"",
                                    it[@"kw"] ?: @"", cat[@"title"]]);
            BOOL all = YES;
            for (NSString *t in tokens) if ([hay rangeOfString:t].location == NSNotFound) { all = NO; break; }
            if (all) [hits addObject:it];
        }
        if (hits.count) [secs addObject:@{ @"title": cat[@"title"], @"items": hits }];
    }
    self.results.sections = secs;
    [self.results.shownRows removeAllObjects];
    [self.results.tableView reloadData];
    self.results.view.hidden = (secs.count == 0);
    self.cv.hidden = YES;
    self.emptyView.hidden = (secs.count > 0);
    self.emptyLabel.text = [NSString stringWithFormat:@"Không có tính năng nào khớp với “%@”.\nThử từ khác, ví dụ: đã xem, quảng cáo, ảnh, nền.", raw];
}

@end

// ---------------------------------------------------------------- button in Zalo's Settings screen

static const NSInteger kZXFooterTag = 0x5A59;
static BOOL gSettingsHooked;

static void ZXAddSettingsButton(UIViewController *vc)
{
    UITableView *tv = nil;
    @try { tv = [vc valueForKey:@"tableView"]; } @catch (NSException *e) { return; }
    if (![tv isKindOfClass:[UITableView class]]) return;
    UIView *footer = tv.tableFooterView;
    if (footer.tag == kZXFooterTag) return; // already added

    CGFloat width = tv.bounds.size.width;
    CGFloat oldH = 0;
    if (footer) {
        oldH = footer.frame.size.height;
        if (oldH < 1)
            oldH = [footer systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                         withHorizontalFittingPriority:UILayoutPriorityRequired
                               verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
    }
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, oldH + 76)];
    container.tag = kZXFooterTag;
    container.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    if (footer) {
        footer.frame = CGRectMake(0, 0, width, oldH);
        footer.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [container addSubview:footer];
    }
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = CGRectMake(16, oldH + 14, width - 32, 48);
    b.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [b setTitle:@"Zép Lào Mod của MilanVu" forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    b.backgroundColor = [UIColor colorWithRed:0.0 green:0.45 blue:1.0 alpha:0.12];
    b.layer.cornerRadius = 10;
    [b addTarget:[ZXUI class] action:@selector(show) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:b];
    tv.tableFooterView = container;
}

static void ZXHookSettingsButton(void)
{
    if (gSettingsHooked) return;
    Class cls = NSClassFromString(@"SettingUI40TableViewController");
    if (!cls) return;
    SEL sel = @selector(viewDidAppear:);
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    IMP orig = method_getImplementation(m);
    IMP newImp = imp_implementationWithBlock(^(id self_, BOOL animated) {
        ((void (*)(id, SEL, BOOL))orig)(self_, sel, animated);
        ZXAddSettingsButton(self_);
    });
    if (!class_addMethod(cls, sel, newImp, method_getTypeEncoding(m)))
        method_setImplementation(m, newImp);
    gSettingsHooked = YES;
    ZXLog(@"settings button hooked");
}

// ---------------------------------------------------------------- floating glass tab bar (experimental)
//
// Assumes Zalo's bottom bar (Tin nhắn / Danh bạ / Khám phá / Tường nhà / Cá nhân) is a real
// UITabBar, found by walking the key window's view hierarchy. If Zalo instead draws it with a
// fully custom view, ZXFindTabBar finds nothing and this whole feature silently does nothing.
// The float effect works by rewriting the frame UIKit itself assigns to the bar: we swizzle
// -setFrame: on the bar's own runtime class (not the static UITabBar class, in case Zalo
// subclasses it and overrides layoutSubviews/setFrame: itself), so the inset position survives
// every relayout (rotation, keyboard, safe-area changes) instead of being reset back to full width.

static const char kZXTabBarStyledKey;

/// Zalo's own tab bar is ZDSTabBar (its design-system library), so we match by class name
/// containing "tabbar" as well as isKindOfClass:[UITabBar class], in case it is not a real
/// UITabBar subclass. Requires more than one subview and a reasonably wide frame so we don't
/// grab an unrelated helper view that happens to share part of the name.
static UIView *ZXFindTabBar(UIView *root)
{
    if (!root) return nil;
    NSString *lc = NSStringFromClass(root.class).lowercaseString;
    if (([lc containsString:@"tabbar"] || [root isKindOfClass:[UITabBar class]])
        && root.subviews.count > 1 && root.bounds.size.width > 100)
        return root;
    for (UIView *v in root.subviews) {
        UIView *found = ZXFindTabBar(v);
        if (found) return found;
    }
    return nil;
}

static UIView *ZXFindTabBarInAnyWindow(void)
{
    for (UIWindow *w in UIApplication.sharedApplication.windows) {
        UIView *found = ZXFindTabBar(w);
        if (found) return found;
    }
    return nil;
}

static NSString *ZXClassChain(Class c)
{
    NSMutableString *s = [NSMutableString new];
    for (int i = 0; c && i < 6; i++, c = class_getSuperclass(c)) {
        if (s.length) [s appendString:@" < "];
        [s appendString:NSStringFromClass(c)];
    }
    return s;
}

/// Computes the floating/pill frame from `proposed`, the frame UIKit itself just tried to assign
/// (full width, pinned to the very bottom). We only use its width and bottom edge as a reference
/// so this keeps working across rotations and keyboard changes.
static CGRect ZXFloatingTabBarFrame(UIView *bar, CGRect proposed)
{
    CGFloat width = proposed.size.width > 0 ? proposed.size.width : bar.superview.bounds.size.width;
    CGFloat bottom = proposed.origin.y + proposed.size.height;
    if (width <= 0 || bottom <= 0) return proposed;
    UIWindow *w = bar.window ?: ZXKeyWindow();
    CGFloat safeBottom = w ? w.safeAreaInsets.bottom : 0;
    CGFloat margin = 14, height = 56;
    CGFloat y = bottom - height - MAX(safeBottom, 8) - 6;
    return CGRectMake(margin, y, width - margin * 2, height);
}

// ---- press-and-drag "liquid" blob -------------------------------------------------------
//
// A glass pill that tracks the finger while the person long-presses and drags across the tab
// bar, snapping to whichever item is nearest with a springy (slightly overshooting) animation
// so the motion reads as elastic/liquid rather than a plain slide. Lifting the finger over an
// item simulates a tap on that item's own button (UITabBarButton is a UIControl, so this is the
// same mechanism a real touch would trigger) so dragging actually switches tabs, the way sliding
// a finger across Control Center's own glass controls selects whatever is underneath it.

@interface ZXTabBarBlob : NSObject
@property (nonatomic, weak) UIView *bar;
@property (nonatomic, weak) UIVisualEffectView *blob;
@property (nonatomic, weak) UILongPressGestureRecognizer *gesture;
@end

@implementation ZXTabBarBlob

- (NSArray<UIView *> *)buttonsSortedByX
{
    NSMutableArray<UIView *> *btns = [NSMutableArray new];
    for (UIView *v in self.bar.subviews)
        if ([NSStringFromClass(v.class) containsString:@"TabBarButton"]) [btns addObject:v];
    [btns sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        if (a.frame.origin.x < b.frame.origin.x) return NSOrderedAscending;
        if (a.frame.origin.x > b.frame.origin.x) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    return btns;
}

- (UIView *)buttonNearestX:(CGFloat)x among:(NSArray<UIView *> *)btns
{
    UIView *best = nil;
    CGFloat bestDist = CGFLOAT_MAX;
    for (UIView *b in btns) {
        CGFloat cx = b.frame.origin.x + b.frame.size.width / 2;
        CGFloat d = fabs(cx - x);
        if (d < bestDist) { bestDist = d; best = b; }
    }
    return best;
}

- (void)moveBlobTo:(UIView *)button
{
    if (!button || !self.blob) return;
    CGRect target = CGRectInset(button.frame, -6, -6);
    [UIView animateWithDuration:0.42 delay:0 usingSpringWithDamping:0.55 initialSpringVelocity:0.6
                        options:UIViewAnimationOptionAllowUserInteraction animations:^{
        self.blob.frame = target;
        self.blob.alpha = 1;
    } completion:nil];
}

- (void)handlePress:(UILongPressGestureRecognizer *)g
{
    UIView *bar = self.bar;
    if (!bar || !ZXFloatingTabBarOn() || ZXReduceMotion()) { self.blob.alpha = 0; return; }
    CGPoint pt = [g locationInView:bar];
    NSArray<UIView *> *btns = [self buttonsSortedByX];
    UIView *target = [self buttonNearestX:pt.x among:btns];

    switch (g.state) {
        case UIGestureRecognizerStateBegan:
        case UIGestureRecognizerStateChanged:
            [self moveBlobTo:target];
            break;
        case UIGestureRecognizerStateEnded:
            if ([target isKindOfClass:[UIControl class]])
                [(UIControl *)target sendActionsForControlEvents:UIControlEventTouchUpInside];
            [UIView animateWithDuration:0.25 delay:0.12 options:0 animations:^{ self.blob.alpha = 0; } completion:nil];
            break;
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed:
            [UIView animateWithDuration:0.2 animations:^{ self.blob.alpha = 0; }];
            break;
        default:
            break;
    }
}
@end

static const char kZXTabBarBlobKey;

static void ZXAttachTabBarBlob(UIView *bar)
{
    if (objc_getAssociatedObject(bar, &kZXTabBarBlobKey)) return;
    UIVisualEffectView *blob = [[UIVisualEffectView alloc] initWithEffect:ZXGlassEffect()];
    blob.userInteractionEnabled = NO;
    blob.alpha = 0;
    blob.layer.cornerRadius = 20;
    if (@available(iOS 13.0, *)) blob.layer.cornerCurve = kCACornerCurveContinuous;
    blob.clipsToBounds = YES;
    [bar insertSubview:blob atIndex:1]; // above our background glass, below the tab buttons

    ZXTabBarBlob *h = [ZXTabBarBlob new];
    h.bar = bar;
    h.blob = blob;
    UILongPressGestureRecognizer *g = [[UILongPressGestureRecognizer alloc] initWithTarget:h action:@selector(handlePress:)];
    g.minimumPressDuration = 0.12;
    g.cancelsTouchesInView = NO; // let Zalo's own tap-to-switch keep working for a plain tap
    [bar addGestureRecognizer:g];
    h.gesture = g;
    objc_setAssociatedObject(bar, &kZXTabBarBlobKey, h, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void ZXDetachTabBarBlob(UIView *bar)
{
    ZXTabBarBlob *h = objc_getAssociatedObject(bar, &kZXTabBarBlobKey);
    if (!h) return;
    [h.blob removeFromSuperview];
    if (h.gesture) [bar removeGestureRecognizer:h.gesture];
    objc_setAssociatedObject(bar, &kZXTabBarBlobKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void ZXStyleTabBarOnce(UIView *bar)
{
    if (objc_getAssociatedObject(bar, &kZXTabBarStyledKey)) return;
    objc_setAssociatedObject(bar, &kZXTabBarStyledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    bar.layer.cornerRadius = 26;
    if (@available(iOS 13.0, *)) bar.layer.cornerCurve = kCACornerCurveContinuous;
    bar.layer.masksToBounds = NO; // the glass subview clips itself; the bar's own layer keeps the drop shadow
    bar.layer.borderWidth = 0.5;
    bar.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.2].CGColor;
    bar.layer.shadowColor = UIColor.blackColor.CGColor;
    bar.layer.shadowOpacity = 0.2;
    bar.layer.shadowRadius = 14;
    bar.layer.shadowOffset = CGSizeMake(0, 6);

    if ([bar isKindOfClass:[UITabBar class]]) {
        UITabBar *tb = (UITabBar *)bar;
        if (@available(iOS 13.0, *)) {
            UITabBarAppearance *ap = [UITabBarAppearance new];
            [ap configureWithTransparentBackground];
            ap.backgroundColor = UIColor.clearColor;
            ap.shadowColor = UIColor.clearColor;
            tb.standardAppearance = ap;
            if (@available(iOS 15.0, *)) tb.scrollEdgeAppearance = ap;
        } else {
            tb.backgroundImage = [UIImage new];
            tb.shadowImage = [UIImage new];
            tb.translucent = YES;
        }
    } else {
        // Not a real UITabBar (e.g. Zalo's own ZDSTabBar): best effort, just clear what we can.
        bar.backgroundColor = UIColor.clearColor;
        bar.opaque = NO;
        @try { [bar setValue:[UIImage new] forKey:@"backgroundImage"]; } @catch (__unused id e) {}
    }

    UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:ZXGlassEffect()];
    glass.frame = bar.bounds;
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    glass.layer.cornerRadius = 26;
    if (@available(iOS 13.0, *)) glass.layer.cornerCurve = kCACornerCurveContinuous;
    glass.clipsToBounds = YES;
    glass.userInteractionEnabled = NO;
    [bar insertSubview:glass atIndex:0];
}

static void ZXUnstyleTabBar(UIView *bar)
{
    if (!objc_getAssociatedObject(bar, &kZXTabBarStyledKey)) return;
    objc_setAssociatedObject(bar, &kZXTabBarStyledKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    bar.layer.cornerRadius = 0;
    bar.layer.borderWidth = 0;
    bar.layer.shadowOpacity = 0;
    for (UIView *v in bar.subviews.copy)
        if ([v isKindOfClass:[UIVisualEffectView class]]) [v removeFromSuperview];
    if ([bar isKindOfClass:[UITabBar class]]) {
        UITabBar *tb = (UITabBar *)bar;
        if (@available(iOS 13.0, *)) {
            UITabBarAppearance *def = [UITabBarAppearance new];
            [def configureWithDefaultBackground];
            tb.standardAppearance = def;
            if (@available(iOS 15.0, *)) tb.scrollEdgeAppearance = def;
        } else {
            tb.backgroundImage = nil;
            tb.shadowImage = nil;
        }
    }
}

static BOOL ZXFloatingTabBarOn(void) { return [ZXConfig boolForKey:ZXK_FLOATING_TABBAR] && !ZXReduceTransparency(); }

static void ZXApplyFloatingTabBarState(UIView *bar)
{
    if (!bar) return;
    if (ZXFloatingTabBarOn()) {
        ZXStyleTabBarOnce(bar);
        CGRect full = bar.superview ? bar.superview.bounds : bar.frame;
        bar.frame = ZXFloatingTabBarFrame(bar, full); // runs through our swizzled -setFrame: below
    } else {
        ZXUnstyleTabBar(bar);
        [bar setNeedsLayout];
    }
}

/// Finds the live tab bar (if Zalo uses one) and swizzles -setFrame: on its concrete runtime
/// class once, so every future relayout keeps honoring the floating position while the toggle is on.
/// Logs what it found the first time, even when the toggle is off, so a build's log says whether
/// the tab bar was located at all and what class it actually is.
static void ZXHookFloatingTabBar(void)
{
    UIView *bar = ZXFindTabBarInAnyWindow();
    if (!bar) return;
    Class cls = object_getClass(bar);
    static NSMutableSet<NSString *> *hooked;
    if (!hooked) hooked = [NSMutableSet new];
    NSString *clsName = NSStringFromClass(cls);
    if ([hooked containsObject:clsName]) { ZXApplyFloatingTabBarState(bar); return; }

    NSMutableString *subs = [NSMutableString new];
    for (UIView *v in bar.subviews) [subs appendFormat:@"%@(%@) ", NSStringFromClass(v.class), NSStringFromCGRect(v.frame)];
    ZXLog(@"tab bar candidate: %@ | chain: %@ | frame=%@ | subviews: %@",
          clsName, ZXClassChain(cls), NSStringFromCGRect(bar.frame), subs);

    SEL sel = @selector(setFrame:);
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    IMP orig = method_getImplementation(m);
    IMP newImp = imp_implementationWithBlock(^(UIView *self_, CGRect frame) {
        if (ZXFloatingTabBarOn()) frame = ZXFloatingTabBarFrame(self_, frame);
        ((void (*)(id, SEL, CGRect))orig)(self_, sel, frame);
    });
    if (!class_addMethod(cls, sel, newImp, method_getTypeEncoding(m)))
        method_setImplementation(m, newImp);
    [hooked addObject:clsName];
    ZXLog(@"floating tab bar hooked on %@", clsName);
    ZXApplyFloatingTabBarState(bar);
}

// ---------------------------------------------------------------- installer

@implementation ZXUI

+ (void)install
{
    ZXHookSettingsButton();
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                      object:nil queue:NSOperationQueue.mainQueue
                                                  usingBlock:^(NSNotification *n) { ZXHookSettingsButton(); }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ ZXHookSettingsButton(); });
    // The tab bar may not exist yet right after launch (splash/login screens first), so keep
    // trying every 3s for the first minute instead of relying on a single delayed check.
    for (int i = 1; i <= 20; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, i * 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ ZXHookFloatingTabBar(); });
    }
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                      object:nil queue:NSOperationQueue.mainQueue
                                                  usingBlock:^(NSNotification *n) { [self attachGesture]; [ZXBubble restoreIfNeeded]; ZXHookFloatingTabBar(); }];
}

+ (void)attachGesture
{
    UIWindow *w = ZXKeyWindow();
    if (!w) return;
    static const char kKey;
    if (objc_getAssociatedObject(w, &kKey)) return;
    UILongPressGestureRecognizer *g = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(onLongPress:)];
    g.numberOfTouchesRequired = 3;
    g.minimumPressDuration = 0.8;
    g.cancelsTouchesInView = NO;
    [w addGestureRecognizer:g];
    objc_setAssociatedObject(w, &kKey, g, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

+ (void)onLongPress:(UILongPressGestureRecognizer *)g
{
    if (g.state == UIGestureRecognizerStateBegan) [self show];
}

+ (void)show
{
    [ZXBubble hide];
    UIViewController *top = ZXTopVC();
    if (!top) return;
    if ([top isKindOfClass:[UINavigationController class]]) {
        UIViewController *first = ((UINavigationController *)top).viewControllers.firstObject;
        if ([first isKindOfClass:[ZXHomeViewController class]]) return;
    }
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[ZXHomeViewController new]];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [top presentViewController:nav animated:YES completion:nil];
}

@end
