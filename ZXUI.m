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
- (void)applyCardStyle
{
    self.backgroundColor = [UIColor colorWithWhite:1 alpha:ZXReduceTransparency() ? 1.0 : 0.92];
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

@interface ZXSettingsViewController : UITableViewController <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, strong) NSArray<NSDictionary *> *sections;
@property (nonatomic, strong) NSMutableSet<NSIndexPath *> *shownRows;
@end

@implementation ZXSettingsViewController

- (instancetype)init
{
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        self.title = @"ZépLàoModMilanVu";
        self.sections = @[
            @{ @"title": @"Giao diện", @"items": @[
                @{ @"key": ZXK_LIQUID_GLASS, @"title": @"Liquid Glass", @"sub": @"Thanh tiêu đề và nhãn nhóm dùng kính (iOS 26 dùng kính thật, bản cũ dùng làm mờ). Thẻ nội dung giữ nền đặc để dễ đọc." },
                @{ @"action": @"bgpick", @"title": @"Chỉnh sửa ảnh nền", @"sub": @"Chọn ảnh từ thư viện, kéo/thu phóng để cắt" },
                @{ @"action": @"bgreset", @"title": @"Dùng lại ảnh nền mặc định" },
            ]},
            @{ @"title": @"Quyền riêng tư", @"items": @[
                @{ @"key": ZXK_BLOCK_SEEN, @"title": @"Chặn gửi trạng thái \"Đã xem\"", @"sub": @"Cần rule 'block_send_seen' trong rules.json" },
                @{ @"key": ZXK_SILENT_TYPING, @"title": @"Không gửi trạng thái \"Đang nhập\"", @"sub": @"Cần rule 'silent_typing' trong rules.json" },
            ]},
            @{ @"title": @"Chống thu hồi / xóa tin nhắn", @"items": @[
                @{ @"key": ZXK_ANTI_RECALL, @"title": @"Xem tin nhắn bị thu hồi", @"sub": @"Giữ lại tin khi người khác thu hồi" },
                @{ @"key": ZXK_SHOW_CONTENT, @"title": @"Hiện nội dung tin bị thu hồi/xóa", @"sub": @"Lưu tạm nội dung tin nhận được trên máy" },
                @{ @"key": ZXK_RECALL_NOTE, @"title": @"Ghi chú mờ \"đã thu hồi\" trên tin", @"sub": @"Hiện nhãn nhỏ trên tin được giữ lại" },
                @{ @"action": @"clearmarks", @"title": @"Xóa danh sách tin đã đánh dấu" },
                @{ @"action": @"history", @"title": @"Lịch sử tin bị thu hồi / xóa" },
                @{ @"action": @"clearcache", @"title": @"Xóa bộ nhớ đệm tin nhắn" },
                @{ @"key": ZXK_ANTI_RECALL_INCLUDE_ME, @"title": @"Áp dụng cả tin do mình thu hồi" },
                @{ @"key": ZXK_ANTI_DELETE, @"title": @"Xem tin nhắn bị xóa", @"sub": @"Giữ lại tin khi bị xóa (cần rule phù hợp)" },
                @{ @"key": ZXK_ANTI_DELETE_INCLUDE_ME, @"title": @"Áp dụng cả tin do mình xóa" },
                @{ @"action": @"uid", @"title": @"User ID của bạn", @"sub": @"Dùng để phân biệt tin của mình" },
            ]},
            @{ @"title": @"Quảng cáo & theo dõi", @"items": @[
                @{ @"key": ZXK_BLOCK_ADS, @"title": @"Chặn endpoint quảng cáo" },
                @{ @"key": ZXK_DISABLE_TRACKING, @"title": @"Tắt tracking của Zalo" },
                @{ @"key": ZXK_BLOCK_QOS, @"title": @"Chặn QoS / log chất lượng" },
                @{ @"key": ZXK_DISABLE_FIREBASE, @"title": @"Tắt Firebase logging" },
            ]},
            @{ @"title": @"Ảnh/file & tin tự hủy (TTL)", @"items": @[
                @{ @"key": ZXK_DEFAULT_ORIGINAL, @"title": @"Mặc định gửi ảnh chất lượng Original", @"sub": @"Chọn sẵn Original khi mở bảng chế độ gửi" },
                @{ @"key": ZXK_UNLIMITED_MEDIA, @"title": @"Gửi file/ảnh không giới hạn dung lượng", @"sub": @"Nâng giới hạn kích thước gửi đi" },
                @{ @"key": ZXK_TTL_OVERRIDE, @"title": @"Ghi đè TTL", @"sub": @"Cần rule action 'ttl'" },
                @{ @"action": @"ttl", @"title": @"Giá trị TTL (ms)" },
            ]},
            @{ @"title": @"Công cụ", @"items": @[
                @{ @"action": @"scan", @"title": @"Quét class/method để tìm target hook" },
                @{ @"action": @"viewscan", @"title": @"Xem / chia sẻ kết quả quét" },
                @{ @"action": @"rules", @"title": @"Sửa rules.json" },
                @{ @"action": @"log", @"title": @"Xem log" },
                @{ @"action": @"exit", @"title": @"Thoát app để áp dụng rules mới" },
            ]},
        ];
    }
    return self;
}

- (void)buildBackground
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
        self.tableView.backgroundView = bg;
        return;
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
    self.tableView.backgroundView = bg;
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
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Thu gọn" style:UIBarButtonItemStylePlain target:self action:@selector(collapse)];
}
- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    UINavigationBar *bar = self.navigationController.navigationBar;
    bar.tintColor = UIColor.whiteColor;
    if (@available(iOS 13.0, *)) {
        NSDictionary *big = @{ NSForegroundColorAttributeName: UIColor.whiteColor };
        NSDictionary *small = @{ NSForegroundColorAttributeName: UIColor.whiteColor,
                                 NSFontAttributeName: [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold] };
        // scrolled: blurred bar so content never runs under the title (liquid-glass.md rule: blur lives on the bar layer)
        UINavigationBarAppearance *std = [UINavigationBarAppearance new];
        if (ZXReduceTransparency()) {
            [std configureWithOpaqueBackground];
            std.backgroundColor = [UIColor colorWithRed:0.08 green:0.16 blue:0.34 alpha:1];
        } else {
            [std configureWithTransparentBackground];
            std.backgroundEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark];
        }
        std.titleTextAttributes = small;
        std.largeTitleTextAttributes = big;
        // at rest: transparent over the landscape, white large title
        UINavigationBarAppearance *edge = [UINavigationBarAppearance new];
        [edge configureWithTransparentBackground];
        edge.titleTextAttributes = small;
        edge.largeTitleTextAttributes = big;
        bar.standardAppearance = std;
        bar.scrollEdgeAppearance = edge;
        bar.compactAppearance = std;
    }
}
- (void)collapse
{
    [self dismissViewControllerAnimated:YES completion:^{ [ZXBubble show]; }];
}
- (void)close { [ZXBubble hide]; [self dismissViewControllerAnimated:YES completion:nil]; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return self.sections.count; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return [self.sections[s][@"items"] count]; }
- (UIView *)tableView:(UITableView *)tv viewForHeaderInSection:(NSInteger)s
{
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
    UILabel *l = [UILabel new];
    l.text = [self.sections[s][@"title"] uppercaseString];
    l.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[UIFont systemFontOfSize:12 weight:UIFontWeightHeavy]];
    l.numberOfLines = 0;
    CGSize ls = [l sizeThatFits:CGSizeMake(tv.bounds.size.width - 64, CGFLOAT_MAX)];
    return ls.height + 12 + 20;
}
- (UIView *)tableView:(UITableView *)tv viewForFooterInSection:(NSInteger)s
{
    if (s != (NSInteger)self.sections.count - 1) return [UIView new];
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(20, 8, tv.bounds.size.width - 40, 60)];
    l.numberOfLines = 0;
    l.textAlignment = NSTextAlignmentCenter;
    l.text = @"ZépLàoModMilanVu\nDựa trên ZaloXposed của ElectroHeavenVN (AGPL-3.0)";
    l.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    l.textColor = [UIColor colorWithWhite:1 alpha:0.85];
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tv.bounds.size.width, 80)];
    [v addSubview:l];
    return v;
}
- (CGFloat)tableView:(UITableView *)tv heightForFooterInSection:(NSInteger)s
{
    return s == (NSInteger)self.sections.count - 1 ? 84 : 6;
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

// ---------------------------------------------------------------- installer

@implementation ZXUI

+ (void)install
{
    ZXHookSettingsButton();
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                      object:nil queue:NSOperationQueue.mainQueue
                                                  usingBlock:^(NSNotification *n) { ZXHookSettingsButton(); }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ ZXHookSettingsButton(); });
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                      object:nil queue:NSOperationQueue.mainQueue
                                                  usingBlock:^(NSNotification *n) { [self attachGesture]; [ZXBubble restoreIfNeeded]; }];
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
        if ([first isKindOfClass:[ZXSettingsViewController class]]) return;
    }
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[ZXSettingsViewController new]];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [top presentViewController:nav animated:YES completion:nil];
}

@end
