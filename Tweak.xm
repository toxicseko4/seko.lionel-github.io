// 26Safari by Seko - iOS 26 "Liquid Glass" bars for Safari on iOS 16  (v5)
//
// Layout: [back] [address pill] [...menu]   (the old bottom toolbar is hidden, its buttons are reused)
// Effects (glass, specular rim, finger glow, press-to-grow spring) are adapted from
// "Liquid (Gl)ass" by dylv (CC BY-NC 4.0, non commercial) - credit kept on purpose.

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <CoreImage/CoreImage.h>

// ---- glass look ----
#define LG_LOW_BLUR 1       // 1 = thin backdrop blur (see-through liquid glass), 0 = Apple's stock material blur
#define LG_BLUR_RADIUS 2.0  // smaller = clearer glass (liquidass uses the same private backdrop filter)
#define LG_BLUR_SCALE 0.6   // backdrop capture scale (blur is radius/scale points)
#define LG_SATURATION 1.35  // colors behind the glass pop a little, like iOS 26

// ---- layout ----
// 0 = compact like iOS 26 "Compact": [back] [address pill] [...]  (Safari's old bottom toolbar is hidden; its buttons live in the "..." menu)
// 1 = iOS 26 "Bottom": address pill + a glass capsule with back / forward / share / bookmarks / tabs under it
#define LG_BOTTOM_BAR 0

static const NSInteger kLGTag = 0x4C471A55;
static const void *kLGPillKey = &kLGPillKey;
static const void *kLGFXKey = &kLGFXKey;
static const void *kLGScrubKey = &kLGScrubKey;
static const void *kLGBounceKey = &kLGBounceKey;

static UIView *LGGlassIn(UIView *host);

// =====================  SPRING (same feel as liquidass press)  =====================
// plain UIView spring: nothing is kept alive on the view, so a pill that Safari recycles mid-animation is harmless

static void LGSpringScale(UIView *v, CGFloat scale, BOOL down) {
    if (!v) return;
    __weak UIView *wv = v;
    [UIView animateWithDuration:(down ? 0.32 : 0.55)
                          delay:0
         usingSpringWithDamping:(down ? 0.72 : 0.50)
          initialSpringVelocity:(down ? 0.5 : 1.0)
                        options:(UIViewAnimationOptionBeginFromCurrentState |
                                 UIViewAnimationOptionAllowUserInteraction)
                     animations:^{
        UIView *sv = wv;
        if (sv) sv.transform = down ? CGAffineTransformMakeScale(scale, scale) : CGAffineTransformIdentity;
    } completion:nil];
}

// =====================  THIN BACKDROP BLUR (same private layer liquidass uses)  =====================

@interface LGBackdrop : UIView
+ (BOOL)available;
@end
@implementation LGBackdrop {
    BOOL _applied;
}
+ (Class)layerClass { return NSClassFromString(@"CABackdropLayer") ?: CALayer.class; }
+ (BOOL)available {
    Class b = NSClassFromString(@"CABackdropLayer"), f = NSClassFromString(@"CAFilter");
    return b && f && [f respondsToSelector:NSSelectorFromString(@"filterWithType:")];
}
- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        self.userInteractionEnabled = NO;
        self.backgroundColor = UIColor.clearColor;
        self.opaque = NO;
        [self lg_apply];
    }
    return self;
}
- (void)didMoveToWindow { [super didMoveToWindow]; [self lg_apply]; }
- (void)layoutSubviews { [super layoutSubviews]; [self lg_apply]; }
static id LGMakeFilter(NSString *type, NSString *key, double value) {
    Class fc = NSClassFromString(@"CAFilter");
    if (!fc) return nil;
    id f = ((id (*)(Class, SEL, NSString *))objc_msgSend)(fc, NSSelectorFromString(@"filterWithType:"), type);
    if (!f) return nil;
    @try { [f setValue:@(value) forKey:key]; } @catch (__unused NSException *e) { return nil; }
    return f;
}
- (void)lg_apply {
    if (_applied) return;
    CALayer *layer = self.layer;
    Class bc = NSClassFromString(@"CABackdropLayer");
    if (!bc || ![layer isKindOfClass:bc]) return;
    @try { [layer setValue:@NO forKey:@"layerUsesCoreImageFilters"]; } @catch (__unused NSException *e) {}
    @try { [layer setValue:@YES forKey:@"windowServerAware"]; } @catch (__unused NSException *e) {}
    @try { [layer setValue:@(LG_BLUR_SCALE) forKey:@"scale"]; } @catch (__unused NSException *e) {}
    id blur = LGMakeFilter(@"gaussianBlur", @"inputRadius", LG_BLUR_RADIUS);
    id sat = LGMakeFilter(@"colorSaturate", @"inputAmount", LG_SATURATION);
    if (!blur) return;
    @try { [blur setValue:@YES forKey:@"inputNormalizeEdges"]; } @catch (__unused NSException *e) {}
    layer.filters = sat ? @[blur, sat] : @[blur];
    _applied = YES;
}
@end

// =====================  THE GLASS VIEW  =====================

@interface LGGlass : UIView
@property (nonatomic, assign) CGFloat radius;
@property (nonatomic, assign) BOOL clearStyle;
- (void)setPressed:(BOOL)pressed at:(CGPoint)p;
- (void)moveFingerTo:(CGPoint)p;
@end

@implementation LGGlass {
    UIView *_body;                 // rounded clip: blur + tint + sheen + inner glow
    UIView *_back;                 // thin backdrop (or stock material as fallback)
    UIView *_tint;
    CAGradientLayer *_sheen;
    CALayer *_innerHost;
    CAShapeLayer *_inner;
    CAShapeLayer *_innerMask;
    CAGradientLayer *_spec;
    CAShapeLayer *_specMask;
    CAShapeLayer *_edge;
    CALayer *_glowHost;
    CAGradientLayer *_glow;
    CGFloat _angle;
}
- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        self.userInteractionEnabled = NO;
        self.layer.shadowColor = UIColor.blackColor.CGColor;
        self.layer.shadowOpacity = 0.18;
        self.layer.shadowRadius = 14;
        self.layer.shadowOffset = CGSizeMake(0, 6);
        _angle = -M_PI_4;

        _body = [UIView new];
        _body.clipsToBounds = YES;
        _body.layer.cornerCurve = kCACornerCurveContinuous;
        [self addSubview:_body];

#if LG_LOW_BLUR
        if ([LGBackdrop available]) _back = [[LGBackdrop alloc] initWithFrame:CGRectZero];
#endif
        if (!_back) {
            _back = [[UIVisualEffectView alloc] initWithEffect:
                     [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial]];
        }
        [_body addSubview:_back];

        _tint = [UIView new];
        [_body addSubview:_tint];

        _sheen = [CAGradientLayer layer];
        _sheen.startPoint = CGPointMake(0.5, 0);
        _sheen.endPoint = CGPointMake(0.5, 0.85);
        [_body.layer addSublayer:_sheen];

        _innerHost = [CALayer layer];
        _innerMask = [CAShapeLayer layer];
        _innerHost.mask = _innerMask;
        _inner = [CAShapeLayer layer];
        _inner.fillColor = UIColor.blackColor.CGColor;
        _inner.fillRule = kCAFillRuleEvenOdd;
        _inner.shadowColor = UIColor.whiteColor.CGColor;
        [_innerHost addSublayer:_inner];
        [_body.layer addSublayer:_innerHost];

        _glowHost = [CALayer layer];
        _glowHost.masksToBounds = YES;
        _glowHost.cornerCurve = kCACornerCurveContinuous;
        _glow = [CAGradientLayer layer];
        _glow.type = kCAGradientLayerRadial;
        _glow.startPoint = CGPointMake(0.5, 0.5);
        _glow.endPoint = CGPointMake(1.0, 1.0);
        _glow.colors = @[(id)[UIColor colorWithWhite:1 alpha:0.60].CGColor,
                         (id)[UIColor colorWithWhite:1 alpha:0.28].CGColor,
                         (id)UIColor.clearColor.CGColor];
        _glow.locations = @[@0.0, @0.45, @1.0];
        _glow.opacity = 0;
        [_glowHost addSublayer:_glow];
        [self.layer addSublayer:_glowHost];

        _spec = [CAGradientLayer layer];
        _spec.locations = @[@0.0, @0.12, @0.34, @0.66, @0.88, @1.0];
        _specMask = [CAShapeLayer layer];
        _specMask.fillColor = nil;
        _specMask.strokeColor = UIColor.blackColor.CGColor;
        _spec.mask = _specMask;
        [self.layer addSublayer:_spec];

        _edge = [CAShapeLayer layer];
        _edge.fillColor = nil;
        [self.layer addSublayer:_edge];

        [self setClearStyle:YES];
    }
    return self;
}
- (void)setClearStyle:(BOOL)c {
    _clearStyle = c;
    // dark mode: a light dark veil keeps white text readable over bright pages; light mode: a faint white veil
    UIColor *(^veil)(CGFloat, CGFloat) = ^UIColor *(CGFloat light, CGFloat dark) {
        return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
            return t.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor colorWithWhite:0 alpha:dark]
                : [UIColor colorWithWhite:1 alpha:light];
        }];
    };
    _tint.backgroundColor = c ? veil(0.12, 0.16) : veil(0.26, 0.30);
_sheen.colors = @[(id)[UIColor colorWithWhite:1 alpha:0.0].CGColor,
                      (id)[UIColor colorWithWhite:1 alpha:0.0].CGColor];
    _inner.shadowOpacity = 0.0;
    _inner.shadowRadius = 0;
    _inner.shadowOffset = CGSizeMake(0, 0);
    self.layer.shadowOpacity = c ? 0.16 : 0.18;
    CGFloat m = c ? 0.30 : 0.30;
    id clear = (id)UIColor.clearColor.CGColor;
    _spec.colors = @[(id)[UIColor colorWithWhite:1 alpha:m].CGColor,
                     (id)[UIColor colorWithWhite:1 alpha:m * 0.50].CGColor,
                     clear, clear,
                     (id)[UIColor colorWithWhite:1 alpha:m * 0.40].CGColor,
                     (id)[UIColor colorWithWhite:1 alpha:m * 0.95].CGColor];
    _specMask.lineWidth = c ? 0.9 : 1.4;
    [self applyAngle];
    [self setNeedsLayout];
}
- (void)applyAngle {
    CGFloat dx = cos(_angle) * 0.5, dy = sin(_angle) * 0.5;
    _spec.startPoint = CGPointMake(0.5 + dx, 0.5 + dy);
    _spec.endPoint = CGPointMake(0.5 - dx, 0.5 - dy);
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.bounds;
    CGFloat r = MIN(self.radius, MIN(b.size.width, b.size.height) / 2);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _body.frame = b;
    _body.layer.cornerRadius = r;
    _back.frame = _body.bounds;
    _tint.frame = _body.bounds;
    _sheen.frame = _body.bounds;
    UIBezierPath *rr = [UIBezierPath bezierPathWithRoundedRect:b cornerRadius:r];
    _innerHost.frame = b;
    _innerMask.frame = _innerHost.bounds;
    _innerMask.path = rr.CGPath;
    _inner.frame = _innerHost.bounds;
    UIBezierPath *ring = [UIBezierPath bezierPathWithRect:CGRectInset(b, -40, -40)];
    [ring appendPath:rr];
    ring.usesEvenOddFillRule = YES;
    _inner.path = ring.CGPath;
    _glowHost.frame = b;
    _glowHost.cornerRadius = r;
    _spec.frame = b;
    _specMask.frame = _spec.bounds;
    _specMask.path = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(b, 0.5, 0.5) cornerRadius:r].CGPath;
    _edge.frame = b;
    _edge.path = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(b, 0.25, 0.25) cornerRadius:r].CGPath;
    _edge.lineWidth = 0.7;
    _edge.strokeColor = [UIColor.separatorColor colorWithAlphaComponent:0.30].CGColor;
    self.layer.shadowPath = rr.CGPath;
    [CATransaction commit];
}
- (void)traitCollectionDidChange:(UITraitCollection *)prev {
    [super traitCollectionDidChange:prev];
    _edge.strokeColor = [UIColor.separatorColor colorWithAlphaComponent:0.30].CGColor;
}
- (void)moveFingerTo:(CGPoint)p {
    CGRect b = self.bounds;
    CGFloat d = MAX(b.size.width, b.size.height) * 1.15;
    d = MIN(MAX(d, 90), 320);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _glow.frame = CGRectMake(p.x - d / 2, p.y - d / 2, d, d);
    CGFloat dx = p.x - CGRectGetMidX(b), dy = p.y - CGRectGetMidY(b);
    if (fabs(dx) + fabs(dy) > 1.0) {
        CGFloat target = atan2(dy, dx) + M_PI;
        CGFloat delta = atan2(sin(target - _angle), cos(target - _angle));
        _angle += delta * 0.35;
        [self applyAngle];
    }
    [CATransaction commit];
}
- (void)setPressed:(BOOL)pressed at:(CGPoint)p {
    if (pressed) [self moveFingerTo:p];
    CABasicAnimation *f = [CABasicAnimation animationWithKeyPath:@"opacity"];
    f.fromValue = @(((CALayer *)_glow.presentationLayer ?: _glow).opacity);
    f.toValue = @(pressed ? 1.0 : 0.0);
    f.duration = pressed ? 0.16 : 0.34;
    f.timingFunction = [CAMediaTimingFunction functionWithName:
        pressed ? kCAMediaTimingFunctionEaseOut : kCAMediaTimingFunctionEaseInEaseOut];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _glow.opacity = pressed ? 1.0 : 0.0;
    _spec.opacity = pressed ? 1.0 : 0.95;
    [CATransaction commit];
    [_glow addAnimation:f forKey:@"lgGlow"];
}
@end

static UIView *LGGlassIn(UIView *host) {
    for (UIView *s in host.subviews) if (s.tag == kLGTag && [s isKindOfClass:LGGlass.class]) return s;
    return nil;
}

// =====================  TOUCH EFFECT  =====================

@interface LGTouchFX : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, weak) UIView *host;
@property (nonatomic, assign) CGFloat scale;
@property (nonatomic, assign) BOOL scalesHost;
+ (void)attachTo:(UIView *)host scale:(CGFloat)scale scalesHost:(BOOL)sh;
@end

@implementation LGTouchFX
+ (void)attachTo:(UIView *)host scale:(CGFloat)scale scalesHost:(BOOL)sh {
    if (!host || objc_getAssociatedObject(host, kLGFXKey)) return;
    LGTouchFX *fx = [LGTouchFX new];
    fx.host = host;
    fx.scale = scale;
    fx.scalesHost = sh;
    UILongPressGestureRecognizer *g = [[UILongPressGestureRecognizer alloc] initWithTarget:fx action:@selector(handle:)];
    g.minimumPressDuration = 0;
    g.allowableMovement = CGFLOAT_MAX;
    g.cancelsTouchesInView = NO;
    g.delaysTouchesBegan = NO;
    g.delaysTouchesEnded = NO;
    g.delegate = fx;
    [host addGestureRecognizer:g];
    objc_setAssociatedObject(host, kLGFXKey, fx, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)b { return YES; }
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldRequireFailureOfGestureRecognizer:(UIGestureRecognizer *)b { return NO; }
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)b { return NO; }
- (void)handle:(UILongPressGestureRecognizer *)g {
    UIView *h = self.host;
    LGGlass *glass = (LGGlass *)LGGlassIn(h);
    if (!h || ![glass isKindOfClass:LGGlass.class]) return;
    CGPoint p = [g locationInView:glass];
    switch (g.state) {
        case UIGestureRecognizerStateBegan:
            [glass setPressed:YES at:p];
            LGSpringScale(self.scalesHost ? h : glass, self.scale, YES);
            break;
        case UIGestureRecognizerStateChanged:
            [glass moveFingerTo:p];
            break;
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed:
            [glass setPressed:NO at:p];
            LGSpringScale(self.scalesHost ? h : glass, self.scale, NO);
            break;
        default: break;
    }
}
@end

// =====================  EXTRA BOUNCE (new, does not touch the glass effects)  =====================
// iOS 26 style "jelly" press: dips on touch, overshoots and settles when released.

static void LGBounce(UIView *v, CGFloat scale, BOOL down) {
    if (!v) return;
    __weak UIView *wv = v;
    [UIView animateWithDuration:(down ? 0.26 : 0.62)
                          delay:0
         usingSpringWithDamping:(down ? 0.62 : 0.34)
          initialSpringVelocity:(down ? 0.8 : 1.4)
                        options:(UIViewAnimationOptionBeginFromCurrentState |
                                 UIViewAnimationOptionAllowUserInteraction)
                     animations:^{
        UIView *sv = wv;
        if (sv) sv.transform = down ? CGAffineTransformMakeScale(scale, scale) : CGAffineTransformIdentity;
    } completion:nil];
}

@interface LGBounceFX : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, weak) UIView *target;
@property (nonatomic, assign) CGFloat scale;
+ (void)attachTo:(UIView *)host target:(UIView *)target scale:(CGFloat)scale;
@end
@implementation LGBounceFX
+ (void)attachTo:(UIView *)host target:(UIView *)target scale:(CGFloat)scale {
    if (!host || !target || objc_getAssociatedObject(host, kLGBounceKey)) return;
    LGBounceFX *fx = [LGBounceFX new];
    fx.target = target;
    fx.scale = scale;
    UILongPressGestureRecognizer *g = [[UILongPressGestureRecognizer alloc] initWithTarget:fx action:@selector(handle:)];
    g.minimumPressDuration = 0;
    g.allowableMovement = CGFLOAT_MAX;
    g.cancelsTouchesInView = NO;
    g.delaysTouchesBegan = NO;
    g.delaysTouchesEnded = NO;
    g.delegate = fx;
    [host addGestureRecognizer:g];
    objc_setAssociatedObject(host, kLGBounceKey, fx, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)b { return YES; }
- (void)handle:(UILongPressGestureRecognizer *)g {
    switch (g.state) {
        case UIGestureRecognizerStateBegan: LGBounce(self.target, self.scale, YES); break;
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed: LGBounce(self.target, 1.0, NO); break;
        default: break;
    }
}
@end

// =====================  JELLY TOUCH  (smooth sensitivity - ADDED)  =====================
// iOS 26 glass leans toward your finger while you press and drag, then springs back with a small overshoot.
// Purely additive: it only touches layer.sublayerTransform of the pill / circle itself.
// LGTouchFX and LGBounceFX use view.transform and the glass is untouched, so nothing above is changed.

#define LG_JELLY 1            // 1 = on, 0 = off
#define LG_JELLY_HAPTIC 1     // soft tap when you touch down, 0 = silent
#define LG_JELLY_SMOOTH 0.30  // how smoothly the glass follows the finger: lower = lazier, higher = snappier

static const void *kLGJellyKey = &kLGJellyKey;

@interface LGJelly : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, weak) UIView *host;
+ (void)attachTo:(UIView *)host;
@end

@implementation LGJelly {
    CGFloat _tx, _ty, _sx, _sy;          // smoothed lean (translate) and stretch (scale)
    UIImpactFeedbackGenerator *_haptic;
}
- (instancetype)init {
    if ((self = [super init])) { _sx = 1; _sy = 1; }
    return self;
}
+ (void)attachTo:(UIView *)host {
#if LG_JELLY
    if (!host || objc_getAssociatedObject(host, kLGJellyKey)) return;
    LGJelly *j = [LGJelly new];
    j.host = host;
    UILongPressGestureRecognizer *g = [[UILongPressGestureRecognizer alloc] initWithTarget:j action:@selector(handle:)];
    g.minimumPressDuration = 0;
    g.allowableMovement = CGFLOAT_MAX;
    g.cancelsTouchesInView = NO;
    g.delaysTouchesBegan = NO;
    g.delaysTouchesEnded = NO;
    g.delegate = j;
    [host addGestureRecognizer:g];
    objc_setAssociatedObject(host, kLGJellyKey, j, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
#endif
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)b { return YES; }

// lean toward the finger and stretch a little (volume stays the same)
- (void)follow:(CGPoint)p {
    UIView *h = self.host;
    if (!h) return;
    CGSize s = h.bounds.size;
    if (s.width < 1 || s.height < 1) return;
    CGFloat nx = MAX(-1.5, MIN(1.5, (p.x - s.width / 2) / (s.width / 2)));
    CGFloat ny = MAX(-1.5, MIN(1.5, (p.y - s.height / 2) / (s.height / 2)));
    CGFloat maxX = MIN(s.width * 0.05, 6.0), maxY = MIN(s.height * 0.10, 4.0);
    CGFloat stretch = 1.0 + fabs(nx) * 0.05;
    CGFloat tx = nx * maxX, ty = ny * maxY, sx = stretch, sy = 1.0 / stretch;
    _tx += (tx - _tx) * LG_JELLY_SMOOTH;
    _ty += (ty - _ty) * LG_JELLY_SMOOTH;
    _sx += (sx - _sx) * LG_JELLY_SMOOTH;
    _sy += (sy - _sy) * LG_JELLY_SMOOTH;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    h.layer.sublayerTransform = CATransform3DScale(CATransform3DMakeTranslation(_tx, _ty, 0), _sx, _sy, 1);
    [CATransaction commit];
}

// let go: spring back to rest with a little overshoot
- (void)lg_letGo {
    UIView *h = self.host;
    if (!h) return;
    CALayer *L = h.layer;
    CATransform3D from = L.sublayerTransform;
    L.sublayerTransform = CATransform3DIdentity;
    CASpringAnimation *sp = [CASpringAnimation animationWithKeyPath:@"sublayerTransform"];
    sp.fromValue = [NSValue valueWithCATransform3D:from];
    sp.toValue = [NSValue valueWithCATransform3D:CATransform3DIdentity];
    sp.mass = 1.0;
    sp.stiffness = 260.0;
    sp.damping = 10.0;
    sp.initialVelocity = 0;
    sp.duration = sp.settlingDuration;
    [L addAnimation:sp forKey:@"lgJelly"];
    _tx = _ty = 0;
    _sx = _sy = 1;
}

- (void)handle:(UILongPressGestureRecognizer *)g {
    UIView *h = self.host;
    if (!h) return;
    switch (g.state) {
        case UIGestureRecognizerStateBegan: {
            // pick up from wherever a running spring-back currently is
            CALayer *L = h.layer;
            if ([L animationForKey:@"lgJelly"]) {
                CALayer *pl = (CALayer *)L.presentationLayer;
                if (pl) {
                    CATransform3D t = pl.sublayerTransform;
                    L.sublayerTransform = t;
                    _tx = t.m41; _ty = t.m42; _sx = t.m11; _sy = t.m22;
                }
                [L removeAnimationForKey:@"lgJelly"];
            }
#if LG_JELLY_HAPTIC
            if (!_haptic) _haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
            [_haptic impactOccurredWithIntensity:0.55];
#endif
            [self follow:[g locationInView:h]];
            break;
        }
        case UIGestureRecognizerStateChanged:
            [self follow:[g locationInView:h]];
            break;
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed:
            [self lg_letGo];
            break;
        default: break;
    }
}
@end

// =====================  STATE  =====================

static __weak UIView *gToolbarView;
static __weak UIView *gColl;
static BOOL gKeyboardVisible = NO;
static BOOL gCompactOn = (LG_BOTTOM_BAR ? NO : YES);
static CGFloat gTargetWidth = 0;
static CGFloat gRestH = 0;
static CGFloat gShiftY = 0;
static CFTimeInterval gLastRoles = 0;
static NSArray *gRoles;
static NSMutableSet<NSString *> *gHookedClasses;
static NSMutableSet<NSString *> *gMatched;

typedef NS_ENUM(NSInteger, LGRole) {
    LGRoleBack = 0, LGRoleForward, LGRoleShare, LGRoleBookmarks, LGRoleTabs, LGRoleCount
};

static NSString *LGT(NSString *en, NSString *es) {
    NSString *l = NSLocale.preferredLanguages.firstObject ?: @"en";
    return [l hasPrefix:@"es"] ? es : en;
}

// =====================  SCRUBBING SAFARI'S OWN BACKGROUNDS  =====================
// Hides only the stock fills / blurs / shadows. Anything that carries content (text, icons, buttons)
// is kept visible, so the address text and the tab-overview buttons survive.

static BOOL LGHasContent(UIView *v, int depth) {
    if ([v isKindOfClass:UILabel.class] || [v isKindOfClass:UITextField.class] ||
        [v isKindOfClass:UITextView.class] || [v isKindOfClass:UIControl.class]) return YES;
    if ([v isKindOfClass:UIImageView.class] && ((UIImageView *)v).image) return YES;
    NSString *n = NSStringFromClass(v.class);
    if ([n containsString:@"Label"] || [n containsString:@"Text"] || [n containsString:@"Button"] ||
        [n containsString:@"Icon"] || [n containsString:@"Glyph"] || [n containsString:@"Field"]) return YES;
    if (depth >= 5) return NO;
    for (UIView *s in v.subviews) {
        if (s.tag == kLGTag) continue;
        if (LGHasContent(s, depth + 1)) return YES;
    }
    return NO;
}

static void LGRootScrub(UIView *v) {
    if (!v) return;
    for (UIView *s in v.subviews) {
        if (s.tag == kLGTag) continue;
        NSString *n = NSStringFromClass(s.class);
        if ([n hasPrefix:@"WK"] || [n hasPrefix:@"LG"]) continue;
        if ([n containsString:@"Progress"]) continue;                       // keep the loading bar
        CGFloat h = s.bounds.size.height;
        if (h > 0 && h <= 4) continue;                                       // thin lines (progress)
        BOOL content = LGHasContent(s, 0);
        if ([s isKindOfClass:UIVisualEffectView.class]) {
            UIVisualEffectView *ev = (UIVisualEffectView *)s;
            if (![NSStringFromClass(ev.effect.class) containsString:@"Vibrancy"]) {
                if (ev.effect) ev.effect = nil;
                if (!content) { ev.hidden = YES; ev.alpha = 0; }
            }
        }
        if (!content &&
            ([n containsString:@"Background"] || [n containsString:@"Backdrop"] ||
             [n containsString:@"Platter"] || [n containsString:@"Bar"] ||
             [n containsString:@"ContainerView"] || [n containsString:@"FillView"] ||
             [n containsString:@"Shadow"])) {
            s.hidden = YES;
            s.alpha = 0;
        }
        s.backgroundColor = UIColor.clearColor;
        s.layer.backgroundColor = nil;
        LGRootScrub(s);
    }
}

// the layout hooks fire a lot while scrolling: do the full walk at most every `gap` seconds per root
static void LGScrubThrottled(UIView *v, CFTimeInterval gap) {
    if (!v) return;
    NSNumber *t = objc_getAssociatedObject(v, kLGScrubKey);
    CFTimeInterval now = CACurrentMediaTime();
    if (t && now - t.doubleValue < gap) return;
    objc_setAssociatedObject(v, kLGScrubKey, @(now), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    LGRootScrub(v);
}

static LGGlass *LGInstallEx(UIView *bar, UIEdgeInsets inset, CGFloat radius, BOOL clear) {
    LGGlass *g = (LGGlass *)LGGlassIn(bar);
    if (!g) {
        g = [[LGGlass alloc] initWithFrame:bar.bounds];
        g.tag = kLGTag;
        [bar insertSubview:g atIndex:0];
    }
    if (g.clearStyle != clear) g.clearStyle = clear;
    g.radius = radius;
    CGRect r = UIEdgeInsetsInsetRect(bar.bounds, inset);
    if (!CGSizeEqualToSize(g.bounds.size, r.size)) g.bounds = CGRectMake(0, 0, r.size.width, r.size.height);
    CGPoint c = CGPointMake(CGRectGetMidX(r), CGRectGetMidY(r));
    if (!CGPointEqualToPoint(g.center, c)) g.center = c;
    if (bar.subviews.firstObject != g) [bar sendSubviewToBack:g];
    bar.backgroundColor = UIColor.clearColor;
    bar.layer.backgroundColor = nil;
    bar.clipsToBounds = NO;
    LGScrubThrottled(bar, 0.05);
    return g;
}

static void LGContainer(UIView *v, UIEdgeInsets inset, CGFloat radius) {
    v.backgroundColor = UIColor.clearColor;
    v.layer.backgroundColor = nil;
    LGScrubThrottled(v, 0.05);
}

// =====================  TOOLBAR BUTTONS (RESOLVED BY ROLE)  =====================

static void LGCollectControls(UIView *root, NSMutableArray<UIControl *> *out, int depth) {
    if (depth > 6) return;
    for (UIView *s in root.subviews) {
        if (s.tag == kLGTag) continue;
        if ([s isKindOfClass:UIControl.class]) {
            CGSize z = s.bounds.size;
            if (z.width >= 20 && z.width <= 110 && z.height >= 28 && z.height <= 80) {
                [out addObject:(UIControl *)s];
                continue;
            }
        }
        LGCollectControls(s, out, depth + 1);
    }
}

static NSInteger LGRoleFromLabel(UIControl *c) {
    NSString *s = [[NSString stringWithFormat:@"%@ %@", c.accessibilityIdentifier ?: @"",
                    c.accessibilityLabel ?: @""] lowercaseString];
    if (s.length < 2) return -1;
    if ([s containsString:@"back"] || [s containsString:@"atrás"] || [s containsString:@"atras"]) return LGRoleBack;
    if ([s containsString:@"forward"] || [s containsString:@"adelante"]) return LGRoleForward;
    if ([s containsString:@"share"] || [s containsString:@"compartir"]) return LGRoleShare;
    if ([s containsString:@"bookmark"] || [s containsString:@"marcador"]) return LGRoleBookmarks;
    if ([s containsString:@"tab"] || [s containsString:@"pesta"]) return LGRoleTabs;
    return -1;
}

static NSArray *LGRoleControls(UIView *tb) {
    UIWindow *w = tb.window;
    if (!w) return nil;
    NSMutableArray<UIControl *> *cs = [NSMutableArray array];
    LGCollectControls(tb, cs, 0);
    [cs sortUsingComparator:^NSComparisonResult(UIControl *a, UIControl *b) {
        CGFloat ax = [a convertRect:a.bounds toView:w].origin.x;
        CGFloat bx = [b convertRect:b.bounds toView:w].origin.x;
        return ax < bx ? NSOrderedAscending : (ax > bx ? NSOrderedDescending : NSOrderedSame);
    }];
    NSUInteger n = cs.count;
    if (n < 4 || n > 5) return nil;
    NSInteger order5[5] = {LGRoleBack, LGRoleForward, LGRoleShare, LGRoleBookmarks, LGRoleTabs};
    NSInteger order4[4] = {LGRoleBack, LGRoleShare, LGRoleBookmarks, LGRoleTabs};
    NSMutableArray *res = [NSMutableArray array];
    for (int i = 0; i < LGRoleCount; i++) [res addObject:NSNull.null];
    for (NSUInteger i = 0; i < n; i++) res[(n == 5 ? order5[i] : order4[i])] = cs[i];
    for (UIControl *c in cs) {
        NSInteger r = LGRoleFromLabel(c);
        if (r >= 0 && res[r] != c) {
            for (int i = 0; i < LGRoleCount; i++) if (res[i] == c) res[i] = NSNull.null;
            res[r] = c;
        }
    }
    return res;
}

static UIControl *LGControlFor(LGRole role) {
    if (!gRoles || gRoles.count != LGRoleCount) return nil;
    id c = gRoles[role];
    if (!c || c == NSNull.null) return nil;
    if (![c isKindOfClass:UIControl.class]) return nil;
    UIControl *ctrl = (UIControl *)c;
    if (!ctrl.window || !ctrl.superview) return nil;
    return ctrl;
}

static BOOL LGPressControl(UIControl *c) {
    if (!c || !c.window) return NO;
    [c sendActionsForControlEvents:UIControlEventTouchUpInside];
    [c sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
    return YES;
}

static UIView *LGFindWebView(UIView *root, Class wk, int depth) {
    if (depth > 8) return nil;
    for (UIView *s in root.subviews) {
        if (s.hidden || s.alpha < 0.05) continue;
        if ([s isKindOfClass:wk] && s.bounds.size.height > 200) return s;
        UIView *r = LGFindWebView(s, wk, depth + 1);
        if (r) return r;
    }
    return nil;
}

static void LGWebNav(BOOL back) {
    Class wk = NSClassFromString(@"WKWebView");
    UIWindow *w = gColl.window ?: gToolbarView.window;
    if (!wk || !w) return;
    UIView *wv = LGFindWebView(w, wk, 0);
    if (!wv) return;
    SEL can = back ? NSSelectorFromString(@"canGoBack") : NSSelectorFromString(@"canGoForward");
    SEL go = back ? NSSelectorFromString(@"goBack") : NSSelectorFromString(@"goForward");
    if (![wv respondsToSelector:can] || ![wv respondsToSelector:go]) return;
    if (((BOOL (*)(id, SEL))objc_msgSend)(wv, can)) ((id (*)(id, SEL))objc_msgSend)(wv, go);
}

static void LGFire(LGRole role) {
    UIView *tb = gToolbarView;
    NSArray *fresh = tb.window ? LGRoleControls(tb) : nil;
    if (fresh) gRoles = fresh;
    UIControl *c = LGControlFor(role);
    if (c) {
        if (LGPressControl(c)) return;
    }
    if (role == LGRoleBack) LGWebNav(YES);
    else if (role == LGRoleForward) LGWebNav(NO);
}

// =====================  THE TWO CIRCLE BUTTONS (Fixed Arrow & Visibility)  =====================

@interface LGCircle : UIButton
@property (nonatomic, copy) void (^onTap)(void);
@property (nonatomic, strong) UIImageView *iconView;
+ (instancetype)circleWithSymbol:(NSString *)symbol label:(NSString *)label;
@end
@implementation LGCircle
+ (instancetype)circleWithSymbol:(NSString *)symbol label:(NSString *)label {
    LGCircle *b = [LGCircle buttonWithType:UIButtonTypeCustom];
    b.frame = CGRectMake(0, 0, 44, 44);
    b.accessibilityLabel = label;
    LGGlass *g = [[LGGlass alloc] initWithFrame:b.bounds];
    g.tag = kLGTag;
    g.clearStyle = YES;
    g.radius = 22;
    g.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [b addSubview:g];

    // the icon is our own image view ABOVE the glass (UIButton's imageView sits underneath it and was hidden)
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration
        configurationWithPointSize:19 weight:UIImageSymbolWeightSemibold scale:UIImageSymbolScaleMedium];
    UIImage *img = [[UIImage systemImageNamed:symbol withConfiguration:cfg]
                    imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    UIImageView *iv = [[UIImageView alloc] initWithImage:img];
    iv.frame = b.bounds;
    iv.contentMode = UIViewContentModeCenter;
    iv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    iv.userInteractionEnabled = NO;
    iv.tintColor = UIColor.labelColor;
    iv.layer.zPosition = 10;
    [b addSubview:iv];
    b.iconView = iv;

    [b addTarget:b action:@selector(lg_tapped) forControlEvents:UIControlEventTouchUpInside];
    [LGTouchFX attachTo:b scale:1.16 scalesHost:YES];
    [LGBounceFX attachTo:b target:iv scale:0.82];   // icon jelly-bounce
    [LGJelly attachTo:b];                            // lean toward the finger + spring back
    return b;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.iconView.superview == self) {
        self.iconView.frame = self.bounds;
        [self bringSubviewToFront:self.iconView];
    }
}
- (void)lg_tapped { if (self.onTap) self.onTap(); }
- (BOOL)pointInside:(CGPoint)p withEvent:(UIEvent *)e {
    return CGRectContainsPoint(CGRectInset(self.bounds, -6, -6), p);
}
@end

@interface LGOverlay : UIView @end
@implementation LGOverlay
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    UIView *h = [super hitTest:p withEvent:e];
    return (h == self) ? nil : h;
}
@end

static LGOverlay *gOverlay;
static UIView *gBackSlot, *gMoreSlot;
static LGCircle *gBackBtn, *gMoreBtn;
static NSString *gMenuSig;

static NSArray<UIMenuElement *> *LGMenuActions(void) {
    struct { LGRole role; const char *en; const char *es; const char *sym; } d[] = {
        {LGRoleForward,   "Forward",   "Adelante",  "chevron.right"},
        {LGRoleShare,     "Share",     "Compartir", "square.and.arrow.up"},
        {LGRoleBookmarks, "Bookmarks", "Marcadores","book"},
        {LGRoleTabs,      "Tabs",      "Pestañas",  "square.on.square"},
    };
    NSMutableArray<UIMenuElement *> *acts = [NSMutableArray array];
    for (int i = 0; i < 4; i++) {
        LGRole role = d[i].role;
        UIAction *a = [UIAction actionWithTitle:LGT(@(d[i].en), @(d[i].es))
                                          image:[UIImage systemImageNamed:@(d[i].sym)]
                                     identifier:nil
                                        handler:^(__kindof UIAction *x) { LGFire(role); }];
        [acts addObject:a];
    }
    return acts;
}

static void LGEnsureOverlay(UIWindow *w) {
    if (!gOverlay) {
        gOverlay = [[LGOverlay alloc] initWithFrame:w.bounds];
        gOverlay.backgroundColor = UIColor.clearColor;
        gOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        gBackBtn = [LGCircle circleWithSymbol:@"chevron.left" label:LGT(@"Back", @"Atrás")];
        gBackBtn.onTap = ^{ LGFire(LGRoleBack); };
        gMoreBtn = [LGCircle circleWithSymbol:@"ellipsis" label:LGT(@"More", @"Más")];
        gMoreBtn.showsMenuAsPrimaryAction = YES;
        gBackSlot = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 44, 44)];
        gMoreSlot = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 44, 44)];
        [gBackSlot addSubview:gBackBtn];
        [gMoreSlot addSubview:gMoreBtn];
        [gOverlay addSubview:gBackSlot];
        [gOverlay addSubview:gMoreSlot];
    }
    if (gOverlay.superview != w) { gOverlay.frame = w.bounds; [w addSubview:gOverlay]; }
    if (w.subviews.lastObject != gOverlay) [w bringSubviewToFront:gOverlay];
}

static void LGHideOverlay(void) {
    if (!gBackSlot || !gMoreSlot) return;
    gBackSlot.alpha = 0; gMoreSlot.alpha = 0;
    gBackSlot.userInteractionEnabled = NO; gMoreSlot.userInteractionEnabled = NO;
}

// =====================  TYPING MODE  (ADDED: X bubble, no back arrow, loupe lens)  =====================
// Like real iOS 26 Safari. While you type in the address bar:
//   - the back arrow goes away,
//   - the "..." bubble turns into a round X (cancel) bubble,
//   - a glass lens (loupe) pops up above your finger when you press and hold the field to move the cursor.
// Purely additive: it only reads the existing state (gKeyboardVisible, gBackSlot, gMoreBtn) and adds new things.
// Typing in a text box INSIDE a web page does not trigger any of this.

#define LG_TYPING_UI 1    // 1 = hide the back arrow + show the X bubble while typing in the address bar
#define LG_LENS 1         // 1 = glass loupe lens while you press and hold the address field

static BOOL gTyping = NO;          // keyboard is up AND it is the address bar
static BOOL gTypingUI = NO;        // the "..." bubble is currently showing as X
static CGFloat gBackFade = 1;
static __weak id gFR;
static __weak UIControl *gCancelCtl;
static const void *kLGLensKey = &kLGLensKey;

// ask UIKit who the first responder is (public trick: send an action to nil)
@interface UIResponder (LG26)
- (void)lg26_grabFR:(id)sender;
@end
@implementation UIResponder (LG26)
- (void)lg26_grabFR:(id)sender { gFR = self; }
@end

static BOOL LGIsWebInput(id fr) {
    if (![fr isKindOfClass:UIView.class]) return NO;
    for (UIView *v = (UIView *)fr; v; v = v.superview) {
        if ([NSStringFromClass(v.class) hasPrefix:@"WK"]) return YES;
    }
    return NO;
}

static BOOL LGIsCancelText(NSString *t) {
    if (t.length == 0 || t.length > 12) return NO;
    NSString *s = [t.lowercaseString stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return [s isEqualToString:@"cancel"] || [s isEqualToString:@"cancelar"];
}

static NSString *LGControlText(UIView *v, int depth) {
    if (depth > 3) return nil;
    if ([v isKindOfClass:UIButton.class]) {
        UIButton *b = (UIButton *)v;
        NSString *t = [b titleForState:UIControlStateNormal] ?: b.titleLabel.text;
        if (t.length == 0) {
            if (@available(iOS 15.0, *)) t = b.configuration.title;
        }
        if (t.length) return t;
    }
    if ([v isKindOfClass:UILabel.class]) return ((UILabel *)v).text;
    for (UIView *s in v.subviews) {
        NSString *t = LGControlText(s, depth + 1);
        if (t.length) return t;
    }
    return nil;
}

// Safari's own "Cancel" button (top right while typing)
static UIControl *LGFindCancelControl(UIView *root, UIWindow *w, int depth) {
    if (depth > 12) return nil;
    for (UIView *s in root.subviews) {
        if (s.tag == kLGTag) continue;
        NSString *n = NSStringFromClass(s.class);
        if ([n hasPrefix:@"WK"] || [n hasPrefix:@"LG"]) continue;
        if ([s isKindOfClass:UIControl.class] && LGIsCancelText(LGControlText(s, 0))) {
            CGRect r = [s convertRect:s.bounds toView:w];
            if (CGRectGetMidY(r) < w.bounds.size.height * 0.5) return (UIControl *)s;
        }
        UIControl *r = LGFindCancelControl(s, w, depth + 1);
        if (r) return r;
    }
    return nil;
}

static const void *kLGClearModeKey = &kLGClearModeKey;
static const void *kLGClearMaskKey = &kLGClearMaskKey;
static BOOL gClearHidden = NO;

// the small round x INSIDE the address field (not our X bubble): hide it while typing, put it back afterwards
static void LGHideClear(UIView *root, BOOL hide, int depth) {
    if (depth > 10) return;
    for (UIView *s in root.subviews) {
        if (s.tag == kLGTag) continue;
        NSString *n = NSStringFromClass(s.class);
        if ([n hasPrefix:@"WK"] || [n hasPrefix:@"LG"]) continue;
        if ([s isKindOfClass:UITextField.class]) {
            UITextField *tf = (UITextField *)s;
            if (hide) {
                if (tf.clearButtonMode != UITextFieldViewModeNever) {
                    objc_setAssociatedObject(tf, kLGClearModeKey, @(tf.clearButtonMode), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    tf.clearButtonMode = UITextFieldViewModeNever;
                }
            } else {
                NSNumber *m = objc_getAssociatedObject(tf, kLGClearModeKey);
                if (m) {
                    tf.clearButtonMode = (UITextFieldViewMode)m.integerValue;
                    objc_setAssociatedObject(tf, kLGClearModeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
            }
        }
        if ([n containsString:@"ClearButton"]) {
            if (hide) {
                if (!s.layer.mask) {
                    s.layer.mask = [CALayer layer];                       // empty mask = invisible
                    objc_setAssociatedObject(s, kLGClearMaskKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
            } else if (objc_getAssociatedObject(s, kLGClearMaskKey)) {
                s.layer.mask = nil;
                objc_setAssociatedObject(s, kLGClearMaskKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
        LGHideClear(s, hide, depth + 1);
    }
}

// called every frame from LGSync, but only does work 10x per second
static void LGTypingUpdate(UIWindow *w) {
    static CFTimeInterval last = 0;
    CFTimeInterval now = CACurrentMediaTime();
    if (now - last < 0.1) return;
    last = now;
    BOOL t = NO;
    if (gKeyboardVisible) {
        gFR = nil;
        [UIApplication.sharedApplication sendAction:@selector(lg26_grabFR:) to:nil from:nil forEvent:nil];
        t = !LGIsWebInput(gFR);      // if the responder can't be identified it counts as the address bar
    }
    gTyping = t;
#if LG_TYPING_UI
    // hide Safari's own "Cancel" while our X bubble is showing (a layer mask doesn't fight Safari's alpha/hidden)
    if (t && (!gCancelCtl || !gCancelCtl.window)) gCancelCtl = LGFindCancelControl(w, w, 0);
    UIControl *c = gCancelCtl;
    if (c) {
        if (t) { if (!c.layer.mask) c.layer.mask = [CALayer layer]; }
        else if (c.layer.mask) c.layer.mask = nil;
    }
    // small x inside the field
    if (t) { LGHideClear(w, YES, 0); gClearHidden = YES; }
    else if (gClearHidden) { LGHideClear(w, NO, 0); gClearHidden = NO; }
#endif
}

// the X bubble: press Safari's own Cancel, and if the keyboard is still up a moment later just close it
static void LGDismissTyping(void) {
    UIWindow *w = gColl.window;
    if (!w) return;
    UIControl *c = gCancelCtl ?: LGFindCancelControl(w, w, 0);
    if (c) [c sendActionsForControlEvents:UIControlEventTouchUpInside];
    __weak UIWindow *ww = w;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (gKeyboardVisible) [ww endEditing:YES];
    });
}

static UIImage *LGSymbolImage(NSString *name) {
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration
        configurationWithPointSize:19 weight:UIImageSymbolWeightSemibold scale:UIImageSymbolScaleMedium];
    return [[UIImage systemImageNamed:name withConfiguration:cfg]
            imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

// back arrow fades out while typing, "..." becomes the X bubble (and goes back afterwards)
static __weak UIView *gShiftedPill;
static CGFloat gTypeShift = 0;

// while typing the field grows to the left (the back arrow is gone) and keeps a gap before the X bubble
static void LGTypingShift(UIView *active, CGFloat ww) {
#if LG_TYPING_UI
    CGFloat goal = (gTyping && gCompactOn && active) ? ((12 + gTargetWidth / 2) - ww / 2) : 0;
    gTypeShift += (goal - gTypeShift) * 0.25;
    if (fabs(gTypeShift - goal) < 0.3) gTypeShift = goal;
    UIView *prev = gShiftedPill;
    if (prev && prev != active) { prev.transform = CGAffineTransformIdentity; gShiftedPill = nil; prev = nil; }
    if (active && fabs(gTypeShift) > 0.01) {
        if (CGAffineTransformIsIdentity(active.transform) || active == prev) {
            active.transform = CGAffineTransformMakeTranslation(gTypeShift, 0);
            gShiftedPill = active;
        }
    } else if (prev) {
        prev.transform = CGAffineTransformIdentity;
        gShiftedPill = nil;
    }
#endif
}

static void LGApplyTypingUI(void) {
#if LG_TYPING_UI
    BOOL typing = gTyping;
    CGFloat goal = typing ? 0 : 1;
    gBackFade += (goal - gBackFade) * 0.28;
    if (fabs(gBackFade - goal) < 0.02) gBackFade = goal;
    gBackSlot.alpha *= gBackFade;
    if (gBackFade < 0.5) gBackSlot.userInteractionEnabled = NO;

    if (typing != gTypingUI && gMoreBtn) {
        gTypingUI = typing;
        LGCircle *m = gMoreBtn;
        [UIView transitionWithView:m.iconView duration:0.18
                           options:UIViewAnimationOptionTransitionCrossDissolve
                        animations:^{ m.iconView.image = LGSymbolImage(typing ? @"xmark" : @"ellipsis"); }
                        completion:nil];
        if (typing) {
            m.menu = nil;
            m.showsMenuAsPrimaryAction = NO;
            m.onTap = ^{ LGDismissTyping(); };
        } else {
            m.onTap = nil;
            m.showsMenuAsPrimaryAction = YES;
            m.menu = [UIMenu menuWithChildren:LGMenuActions()];
        }
    }
#endif
}

// ---------- the loupe lens ----------
// A round liquid-glass bubble, like the iOS 26 loupe: it magnifies and BENDS whatever is behind it
// (bump distortion, centre stretched, edge compressed), has a caret in the middle, a darker curved edge,
// a bright specular rim and a thin red/blue fringe. It also stretches a little in the direction you drag.

static UIView *gLens, *gLensClip;
static CALayer *gLensImg;
static BOOL gLensShown = NO;
static CGPoint gLensLast;
static CGFloat gLensStretch = 1;
static CIContext *gLensCI;
static const CGFloat kLensD = 100;     // diameter
static const CGFloat kLensMag = 1.9;   // magnification

static void LGLensBuild(void) {
    if (gLens) return;
    gLens = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kLensD, kLensD)];
    gLens.userInteractionEnabled = NO;

    gLensClip = [[UIView alloc] initWithFrame:gLens.bounds];
    gLensClip.layer.cornerRadius = kLensD / 2;
    gLensClip.clipsToBounds = YES;
    gLensClip.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1];
    [gLens addSubview:gLensClip];

    // the magnified, bent picture of what is behind the lens
    gLensImg = [CALayer layer];
    gLensImg.frame = gLensClip.bounds;
    gLensImg.contentsGravity = kCAGravityResizeAspectFill;
    [gLensClip.layer addSublayer:gLensImg];

    // darker, curved edge: makes it feel like thick glass
    CAGradientLayer *vig = [CAGradientLayer layer];
    vig.type = kCAGradientLayerRadial;
    vig.frame = gLensClip.bounds;
    vig.colors = @[(id)[UIColor colorWithWhite:0 alpha:0].CGColor,
                   (id)[UIColor colorWithWhite:0 alpha:0.38].CGColor];
    vig.locations = @[@0.62, @1.0];
    vig.startPoint = CGPointMake(0.5, 0.5);
    vig.endPoint = CGPointMake(1.0, 0.5);
    [gLensClip.layer addSublayer:vig];

    // caret in the middle
    CALayer *caret = [CALayer layer];
    caret.frame = CGRectMake(kLensD / 2 - 1, kLensD / 2 - 19, 2, 38);
    caret.cornerRadius = 1;
    caret.backgroundColor = [UIColor colorWithRed:0.2 green:0.65 blue:1.0 alpha:1].CGColor;
    [gLensClip.layer addSublayer:caret];

    // glass rim + glow
    LGGlass *g = [[LGGlass alloc] initWithFrame:gLens.bounds];
    g.tag = kLGTag;
    g.clearStyle = YES;
    g.radius = kLensD / 2;
    [gLens addSubview:g];

    // chromatic fringe: a red and a blue rim, nudged apart a little
    NSArray *cols = @[[UIColor colorWithRed:1.0 green:0.25 blue:0.35 alpha:0.55],
                      [UIColor colorWithRed:0.25 green:0.55 blue:1.0 alpha:0.55]];
    CGFloat dx[2] = { -1.8, 1.8 };
    for (int i = 0; i < 2; i++) {
        CAShapeLayer *sl = [CAShapeLayer layer];
        sl.frame = gLens.bounds;
        sl.path = [UIBezierPath bezierPathWithOvalInRect:CGRectInset(gLens.bounds, 2.5, 2.5)].CGPath;
        sl.fillColor = nil;
        sl.strokeColor = ((UIColor *)cols[i]).CGColor;
        sl.lineWidth = 3;
        sl.transform = CATransform3DMakeTranslation(dx[i], 0, 0);
        [gLens.layer addSublayer:sl];
    }
    gLens.alpha = 0;
}

// draw what is behind the lens into a small image, bend it, put it in the lens
static void LGLensRender(UIWindow *w) {
    static CFTimeInterval last = 0;
    CFTimeInterval now = CACurrentMediaTime();
    if (now - last < 0.033) return;           // 30 fps is plenty
    last = now;
    CGFloat sr = kLensD / kLensMag;
    CGPoint c = gLens.center;
    CGRect src = CGRectMake(c.x - sr / 2, c.y - sr / 2, sr, sr);

    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat preferredFormat];
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:src.size format:fmt];
    BOOL wasHidden = gLens.hidden;
    gLens.hidden = YES;                        // never photograph ourselves
    UIImage *img = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [w drawViewHierarchyInRect:CGRectMake(-src.origin.x, -src.origin.y, w.bounds.size.width, w.bounds.size.height)
                afterScreenUpdates:NO];
    }];
    gLens.hidden = wasHidden;
    if (!img.CGImage) return;

    id result = (__bridge id)img.CGImage;
    @try {
        if (!gLensCI) gLensCI = [CIContext contextWithOptions:nil];
        CIImage *ci = [CIImage imageWithCGImage:img.CGImage];
        CGRect ext = ci.extent;
        CIFilter *f = [CIFilter filterWithName:@"CIBumpDistortion"];
        [f setValue:ci forKey:kCIInputImageKey];
        [f setValue:[CIVector vectorWithX:CGRectGetMidX(ext) Y:CGRectGetMidY(ext)] forKey:kCIInputCenterKey];
        [f setValue:@(ext.size.width * 0.58) forKey:kCIInputRadiusKey];
        [f setValue:@(0.55) forKey:kCIInputScaleKey];
        CIImage *out = f.outputImage;
        if (out) {
            CGImageRef bent = [gLensCI createCGImage:out fromRect:ext];
            if (bent) {
                result = (__bridge_transfer id)bent;     // ARC releases it
            }
        }
    } @catch (NSException *e) { }

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    gLensImg.contents = result;
    [CATransaction commit];
}

// the lens floats above the finger; it leans into the direction you drag
static void LGLensMove(UIWindow *w, CGPoint p) {
    CGFloat ww = w.bounds.size.width;
    CGFloat top = w.safeAreaInsets.top + kLensD / 2 + 6;
    gLens.center = CGPointMake(MAX(kLensD / 2 + 8, MIN(ww - kLensD / 2 - 8, p.x)), MAX(top, p.y - 98));

    CGFloat dx = fabs(p.x - gLensLast.x);
    gLensLast = p;
    CGFloat goal = 1.0 + MIN(dx / 36.0, 1.0) * 0.12;
    gLensStretch += (goal - gLensStretch) * 0.35;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    gLens.layer.sublayerTransform = CATransform3DMakeScale(gLensStretch, 1.0 / gLensStretch, 1);
    [CATransaction commit];

    LGLensRender(w);
}

static void LGLensShow(UIWindow *w) {
    LGLensBuild();
    if (gLens.superview != w) [w addSubview:gLens];
    [w bringSubviewToFront:gLens];
    if (gLensShown) return;
    gLensShown = YES;
    gLensLast = CGPointZero;
    gLensStretch = 1;
    gLens.layer.sublayerTransform = CATransform3DIdentity;
    gLens.transform = CGAffineTransformMakeScale(0.35, 0.35);
    gLens.alpha = 0;
    [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.62 initialSpringVelocity:0.9
                        options:(UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState)
                     animations:^{ gLens.transform = CGAffineTransformIdentity; gLens.alpha = 1; }
                     completion:nil];
}

static void LGLensHide(void) {
    if (!gLensShown) return;
    gLensShown = NO;
    [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ gLens.transform = CGAffineTransformMakeScale(0.4, 0.4); gLens.alpha = 0; }
                     completion:nil];
}

@interface LGLens : NSObject <UIGestureRecognizerDelegate>
+ (void)attachTo:(UIView *)host;
@end
@implementation LGLens {
    BOOL _active;
}
+ (void)attachTo:(UIView *)host {
#if LG_LENS
    if (!host || objc_getAssociatedObject(host, kLGLensKey)) return;
    LGLens *l = [LGLens new];
    UILongPressGestureRecognizer *g = [[UILongPressGestureRecognizer alloc] initWithTarget:l action:@selector(handle:)];
    g.minimumPressDuration = 0.28;
    g.allowableMovement = CGFLOAT_MAX;
    g.cancelsTouchesInView = NO;
    g.delaysTouchesBegan = NO;
    g.delaysTouchesEnded = NO;
    g.delegate = l;
    [host addGestureRecognizer:g];
    objc_setAssociatedObject(host, kLGLensKey, l, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
#endif
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)b { return YES; }
- (void)handle:(UILongPressGestureRecognizer *)g {
    UIWindow *w = g.view.window;
    if (!w) { _active = NO; LGLensHide(); return; }
    switch (g.state) {
        case UIGestureRecognizerStateBegan:
            _active = gTyping;                  // only while typing in the address bar
            if (!_active) return;
            LGLensShow(w);
            gLensLast = [g locationInView:w];
            LGLensMove(w, gLensLast);
            break;
        case UIGestureRecognizerStateChanged:
            if (_active) LGLensMove(w, [g locationInView:w]);
            break;
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed:
            if (_active) { _active = NO; LGLensHide(); }
            break;
        default: break;
    }
}
@end

// =====================  PILLS & SBR / HOOKS  =====================

static BOOL LGIsPillObj(id o) { return objc_getAssociatedObject(o, kLGPillKey) != nil; }

static CGRect LGNarrowBounds(CGRect b) {
    if (gCompactOn && gTargetWidth > 0 && b.size.width > gTargetWidth + 20) b.size.width = gTargetWidth;
    return b;
}
static CGRect LGNarrowFrame(CGRect f) {
    if (gCompactOn && gTargetWidth > 0 && f.size.width > gTargetWidth + 20) {
        f.origin.x += (f.size.width - gTargetWidth) / 2;
        f.size.width = gTargetWidth;
    }
    return f;
}

typedef void (*LGRectSetter)(id, SEL, CGRect);

static void LGHookPillClass(Class c) {
    NSString *name = NSStringFromClass(c);
    if (!gHookedClasses) gHookedClasses = [NSMutableSet set];
    if ([gHookedClasses containsObject:name]) return;
    if ([name hasPrefix:@"UI"] || [name hasPrefix:@"_UI"] || [name hasPrefix:@"LG"] || [name hasPrefix:@"WK"]) return;
    [gHookedClasses addObject:name];

    SEL sb = @selector(setBounds:), sf = @selector(setFrame:);
    Method mb = class_getInstanceMethod(c, sb);
    Method mf = class_getInstanceMethod(c, sf);
    if (mb) {
        LGRectSetter ob = (LGRectSetter)method_getImplementation(mb);
        IMP nb = imp_implementationWithBlock(^(UIView *s, CGRect r) {
            ob(s, sb, LGIsPillObj(s) ? LGNarrowBounds(r) : r);
        });
        if (!class_addMethod(c, sb, nb, method_getTypeEncoding(mb))) method_setImplementation(mb, nb);
    }
    if (mf) {
        LGRectSetter of = (LGRectSetter)method_getImplementation(mf);
        IMP nf = imp_implementationWithBlock(^(UIView *s, CGRect r) {
            of(s, sf, LGIsPillObj(s) ? LGNarrowFrame(r) : r);
        });
        if (!class_addMethod(c, sf, nf, method_getTypeEncoding(mf))) method_setImplementation(mf, nf);
    }
}

static void LGTrackPill(UIView *p) {
    if (!LGIsPillObj(p)) {
        objc_setAssociatedObject(p, kLGPillKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        LGHookPillClass(p.class);
        [LGTouchFX attachTo:p scale:1.04 scalesHost:NO];
        [LGJelly attachTo:p];
        [LGLens attachTo:p];
        if (!gMatched) gMatched = [NSMutableSet set];
        [gMatched addObject:NSStringFromClass(p.class)];
    }
    LGInstallEx(p, UIEdgeInsetsZero, 25, YES);
}

static void LGCollectPills(UIView *root, NSMutableArray<UIView *> *out, int depth) {
    if (depth > 3) return;
    for (UIView *s in root.subviews) {
        if (s.tag == kLGTag || s.hidden) continue;
        if (s == gToolbarView || s == gOverlay) continue;
        if ([NSStringFromClass(s.class) containsString:@"Toolbar"]) continue;
        CGSize z = s.bounds.size;
        if (LGIsPillObj(s) || (z.height >= 36 && z.height <= 64 && z.width >= 100)) [out addObject:s];
        else LGCollectPills(s, out, depth + 1);
    }
}

static UIView *LGFindToolbar(UIView *root, int depth) {
    static Class cB, cS;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cB = NSClassFromString(@"BrowserToolbar");
        cS = NSClassFromString(@"_SFToolbar");
    });
    if (depth > 10) return nil;
    for (UIView *s in root.subviews) {
        if (s.tag == kLGTag) continue;
        NSString *tn = NSStringFromClass(s.class);
        BOOL byName = NO;
        if ([tn containsString:@"Toolbar"] && ![tn hasPrefix:@"LG"] && s.window && s.bounds.size.width > 200)
            byName = CGRectGetMidY([s convertRect:s.bounds toView:s.window]) > s.window.bounds.size.height * 0.6;
        if ((cB && [s isKindOfClass:cB]) || (cS && [s isKindOfClass:cS]) || byName) return s;
        UIView *r = LGFindToolbar(s, depth + 1);
        if (r) return r;
    }
    return nil;
}

// iOS 26 "Bottom" style: keep Safari's toolbar, wrap its 5 buttons in a glass capsule
static __unused void LGStyleBottom(UIView *tb) {
    UIWindow *w = tb.window;
    if (!w) return;
    if (tb.layer.mask) tb.layer.mask = nil;
    tb.userInteractionEnabled = YES;
    NSMutableArray<UIControl *> *cs = [NSMutableArray array];
    LGCollectControls(tb, cs, 0);
    if (cs.count < 4) { LGScrubThrottled(tb, 0.06); return; }
    CGFloat minY = CGFLOAT_MAX, maxY = 0;
    for (UIControl *c in cs) {
        CGRect r = [c convertRect:c.bounds toView:tb];
        minY = MIN(minY, CGRectGetMinY(r));
        maxY = MAX(maxY, CGRectGetMaxY(r));
        c.tintColor = UIColor.labelColor;
        [LGBounceFX attachTo:c target:c scale:1.18];
    }
    CGFloat h = 52, mid = (minY + maxY) / 2;
    UIEdgeInsets inset = UIEdgeInsetsMake(MAX(0, mid - h / 2), 14,
                                          MAX(0, tb.bounds.size.height - (mid + h / 2)), 14);
    LGInstallEx(tb, inset, h / 2, YES);
}

static void LGToolbarLayout(UIView *v) {
    UIWindow *w = v.window;
    if (!w) return;
    CGRect r = [v convertRect:v.bounds toView:w];
    // gesture iPhones: the toolbar's frame can stop above the home indicator, so test its position, not its bottom edge
    if (CGRectGetMidY(r) < w.bounds.size.height * 0.6) return;
    if (gToolbarView != v) {
        gToolbarView = v;
        gRoles = nil;
    }
#if LG_BOTTOM_BAR
    LGStyleBottom(v);
#else
    if (!v.layer.mask) v.layer.mask = [CALayer layer];
    v.userInteractionEnabled = NO;
    [[v viewWithTag:kLGTag] removeFromSuperview];
#endif
}

// =====================  TAB OVERVIEW / EDIT MODE DETECTION  =====================
// In the tab overview (and while editing the address) Safari shows "+", "Página principal" and an OK/Done button
// in the bottom bar. There we step aside: full-width bar, no circles.

static BOOL LGIsDoneText(NSString *t) {
    if (t.length == 0 || t.length > 12) return NO;
    static NSSet *set;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        set = [NSSet setWithArray:@[@"ok", @"done", @"hecho", @"listo", @"terminado", @"fin", @"cancel", @"cancelar"]];
    });
    return [set containsObject:[t.lowercaseString stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]];
}

static BOOL LGFindDone(UIView *root, UIWindow *w, int depth) {
    if (depth > 12) return NO;
    for (UIView *s in root.subviews) {
        if (s.tag == kLGTag || s == gOverlay || s.hidden || s.alpha < 0.1) continue;
        NSString *n = NSStringFromClass(s.class);
        if ([n hasPrefix:@"WK"] || [n hasPrefix:@"LG"]) continue;
        NSString *t = nil;
        if ([s isKindOfClass:UIButton.class]) {
            UIButton *b = (UIButton *)s;
            t = [b titleForState:UIControlStateNormal] ?: b.titleLabel.text;
        } else if ([s isKindOfClass:UILabel.class]) {
            t = ((UILabel *)s).text;
        }
        if (LGIsDoneText(t)) {
            CGRect r = [s convertRect:s.bounds toView:w];
            if (CGRectGetMidY(r) > w.bounds.size.height * 0.62) return YES;
        }
        if (LGFindDone(s, w, depth + 1)) return YES;
    }
    return NO;
}

static void LGUpdateMode(UIWindow *w, UIView *coll) {
    static CFTimeInterval last = 0;
    CFTimeInterval now = CACurrentMediaTime();
    if (now - last < 0.12) return;
    last = now;
    BOOL compact = !LG_BOTTOM_BAR && !LGFindDone(w, w, 0);
    if (compact != gCompactOn) {
        gCompactOn = compact;
        [coll setNeedsLayout];
        NSMutableArray<UIView *> *ps = [NSMutableArray array];
        LGCollectPills(coll, ps, 0);
        for (UIView *p in ps) [p setNeedsLayout];
    }
}

// =====================  THE SYNC (Stable & Smooth)  =====================

static CGRect LGWindowRect(UIView *v, UIWindow *w) {
    CALayer *pl = v.layer.presentationLayer ?: v.layer;
    CALayer *wl = w.layer.presentationLayer ?: w.layer;
    return [pl convertRect:pl.bounds toLayer:wl];
}

static void LGSync(void) {
    UIView *coll = gColl;
    UIWindow *w = coll.window;
    if (!coll || !w) { LGHideOverlay(); return; }
    LGTypingUpdate(w);
    CGFloat ww = w.bounds.size.width;
    static __weak UIView *lastColl;
    if (coll != lastColl) { lastColl = coll; gShiftY = 0; }
    static CGFloat lastW = 0;
    if (fabs(ww - lastW) > 0.5) { lastW = ww; gRestH = 0; }
    gTargetWidth = ww - ((LG_TYPING_UI && gTyping) ? 80 : 128);   // typing: field is wider (no back arrow)

    if (!gToolbarView || !gToolbarView.window) {
        UIView *f = LGFindToolbar(w, 0);
        if (f) LGToolbarLayout(f);
    }
    UIView *tb = gToolbarView;
    if (tb.window && CACurrentMediaTime() - gLastRoles > 0.2) {
        gLastRoles = CACurrentMediaTime();
        NSArray *r = LGRoleControls(tb);
        if (r) gRoles = r;
    }

    if (tb.window) {
        // re-assert every 0.25s: Safari can re-show / re-lay-out the toolbar (page changes, rotation, keyboard)
        static CFTimeInterval lastTb = 0;
        CFTimeInterval nowT = CACurrentMediaTime();
        if (nowT - lastTb > 0.25) { lastTb = nowT; LGToolbarLayout(tb); }
    }

    LGUpdateMode(w, coll);

    NSMutableArray<UIView *> *pills = [NSMutableArray array];
    LGCollectPills(coll, pills, 0);
    UIView *active = nil;
    CGRect aR = CGRectZero;
    CGFloat best = CGFLOAT_MAX;
    for (UIView *p in pills) {
        LGTrackPill(p);
        if (gCompactOn && p.bounds.size.width > gTargetWidth + 20) {
            CGRect b = p.bounds;
            b.size.width = gTargetWidth;
            p.bounds = b;
        } else if (LG_TYPING_UI && gTyping && gCompactOn &&
                   p.bounds.size.width > 100 && p.bounds.size.width < gTargetWidth - 2) {
            CGRect b = p.bounds;                    // typing: grow the field into the back arrow's space
            b.size.width = gTargetWidth;
            p.bounds = b;
        }
        if (p.hidden || p.alpha < 0.05) continue;
        CGRect r = LGWindowRect(p, w);
        if (r.size.width < 60 || r.size.height < 20) continue;
        CGFloat off = fabs(CGRectGetMidX(r) - ww / 2);
        if (off < best) { best = off; active = p; aR = r; }
    }

    LGTypingShift(active, ww);
    LGScrubThrottled(coll, 0.06);
    if (tb && tb.window) LGScrubThrottled(tb, 0.06);

    if (!gCompactOn) {
        // tab overview / editing: stock layout, no circles
        if (gShiftY != 0) {
            gShiftY = 0;
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            coll.layer.sublayerTransform = CATransform3DIdentity;
            [CATransaction commit];
        }
        LGHideOverlay();
        return;
    }

    if (!active) {
        LGHideOverlay();
        return;
    }

    if (best < 30 && aR.size.height <= 64 && aR.size.height > gRestH) gRestH = aR.size.height;

    CGFloat limit = w.bounds.size.height - w.safeAreaInsets.bottom - 6;
    CGFloat excess = (CGRectGetMaxY(aR) - gShiftY) - limit;
    CGFloat want = (excess > 0.5 && excess <= 60) ? -excess : 0;
    if (fabs(want - gShiftY) > 0.25) {
        CGFloat old = gShiftY;
        gShiftY = want;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        coll.layer.sublayerTransform = CATransform3DMakeTranslation(0, gShiftY, 0);
        [CATransaction commit];
        aR.origin.y += (want - old);
    }

    CGFloat s = gRestH > 0 ? MIN(1.0, aR.size.height / gRestH) : 1.0;
    CGFloat fade = s >= 0.96 ? 1.0 : MAX(0.0, (s - 0.78) / 0.18);
    UIViewController *pv = w.rootViewController.presentedViewController;
    while (pv.presentedViewController) pv = pv.presentedViewController;
    if (pv && pv.view.window && !pv.isBeingDismissed &&
        CGRectIntersectsRect([pv.view convertRect:pv.view.bounds toView:w], aR)) fade = 0;
    
    LGEnsureOverlay(w);
    CGFloat sc = MAX(0.6, s);
    CGFloat cy = CGRectGetMidY(aR);
    gBackSlot.center = CGPointMake(36, cy);
    gMoreSlot.center = CGPointMake(ww - 36, cy);
    CGAffineTransform t = CGAffineTransformMakeScale(sc, sc);
    gBackSlot.transform = t;
    gMoreSlot.transform = t;
    gBackSlot.alpha = fade;
    gMoreSlot.alpha = fade;
    gBackSlot.userInteractionEnabled = gMoreSlot.userInteractionEnabled = fade > 0.5;
    LGApplyTypingUI();       // typing: back arrow hidden, "..." becomes the X bubble

    // Forzamos el botón de retroceso siempre habilitado y totalmente visible
    gBackBtn.enabled = YES;
    gBackBtn.alpha = 1.0;

    NSMutableString *sig = [NSMutableString string];
    for (int r = LGRoleForward; r < LGRoleCount; r++) {
        UIControl *c = LGControlFor((LGRole)r);
        [sig appendString:c ? (c.enabled ? @"1" : @"0") : @"x"];
    }
    if (![sig isEqualToString:gMenuSig]) {
        gMenuSig = sig;
        if (!gTypingUI) gMoreBtn.menu = [UIMenu menuWithChildren:LGMenuActions()];
    }
}

@interface LGTicker : NSObject
+ (void)start;
@end
@implementation LGTicker {
    CADisplayLink *_link;
}
+ (void)start {
    static LGTicker *t;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        t = [LGTicker new];
        t->_link = [CADisplayLink displayLinkWithTarget:t selector:@selector(tick:)];
        t->_link.preferredFramesPerSecond = 60;
        [t->_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
        NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
        [nc addObserver:t selector:@selector(pause) name:UIApplicationDidEnterBackgroundNotification object:nil];
        [nc addObserver:t selector:@selector(resume) name:UIApplicationDidBecomeActiveNotification object:nil];
    });
}
- (void)tick:(CADisplayLink *)l { LGSync(); }
- (void)pause { _link.paused = YES; }
- (void)resume { _link.paused = NO; }
@end

// =====================  CLASS NAMES  =====================

@interface SFUnifiedTabBarItemView : UIView @end
@interface SFCapsuleView : UIView @end
@interface SFCapsuleCollectionView : UIView @end
@interface CapsuleNavigationBarViewController : UIViewController @end
@interface SFUnifiedTabBar : UIView @end
@interface SFCapsuleNavigationBar : UIView @end
@interface _SFCapsuleNavigationBar : UIView @end
@interface CapsuleNavigationBar : UIView @end
@interface SFNavigationBar : UIView @end
@interface _SFNavigationBar : UIView @end
@interface _SFBrowserNavigationBar : UIView @end
@interface _SFCapsuleContainerView : UIView @end
@interface NavigationBar : UIView @end
@interface BrowserToolbar : UIView @end
@interface _SFToolbar : UIView @end
@interface SFNavigationBarBackgroundView : UIView @end

// =====================  HOOKS  =====================

%group Pills

%hook SFUnifiedTabBarItemView
- (void)layoutSubviews {
    %orig;
    LGTrackPill((UIView *)self);
}
%end

%hook SFCapsuleView
- (void)layoutSubviews {
    %orig;
    LGTrackPill((UIView *)self);
}
%end

%end // Pills

%group Containers

%hook SFCapsuleCollectionView
- (void)layoutSubviews {
    %orig;
    UIView *v = (UIView *)self;
    gColl = v;
    LGContainer(v, UIEdgeInsetsZero, 0);
    LGSync();
}
%end

%hook _SFCapsuleContainerView
- (void)layoutSubviews {
    %orig;
    LGContainer((UIView *)self, UIEdgeInsetsMake(0, 4, 0, 4), 25);
}
%end

%hook SFUnifiedTabBar
- (void)layoutSubviews {
    %orig;
    LGContainer((UIView *)self, UIEdgeInsetsMake(0, 4, 0, 4), 25);
}
%end
%hook SFCapsuleNavigationBar
- (void)layoutSubviews {
    %orig;
    LGContainer((UIView *)self, UIEdgeInsetsMake(0, 4, 0, 4), 25);
}
%end
%hook _SFCapsuleNavigationBar
- (void)layoutSubviews {
    %orig;
    LGContainer((UIView *)self, UIEdgeInsetsMake(0, 4, 0, 4), 25);
}
%end
%hook CapsuleNavigationBar
- (void)layoutSubviews {
    %orig;
    LGContainer((UIView *)self, UIEdgeInsetsMake(0, 4, 0, 4), 25);
}
%end
%hook SFNavigationBar
- (void)layoutSubviews {
    %orig;
    LGContainer((UIView *)self, UIEdgeInsetsMake(0, 4, 0, 4), 25);
}
%end
%hook _SFNavigationBar
- (void)layoutSubviews {
    %orig;
    LGContainer((UIView *)self, UIEdgeInsetsMake(0, 4, 0, 4), 25);
}
%end
%hook _SFBrowserNavigationBar
- (void)layoutSubviews {
    %orig;
    LGContainer((UIView *)self, UIEdgeInsetsMake(0, 4, 0, 4), 25);
}
%end
%hook NavigationBar
- (void)layoutSubviews {
    %orig;
    LGContainer((UIView *)self, UIEdgeInsetsMake(0, 4, 0, 4), 25);
}
%end

%end // Containers

%group Toolbars

%hook BrowserToolbar
- (void)layoutSubviews {
    %orig;
    LGToolbarLayout((UIView *)self);
}
%end

%hook _SFToolbar
- (void)layoutSubviews {
    %orig;
    LGToolbarLayout((UIView *)self);
}
%end

%end // Toolbars

%group Backgrounds

%hook SFNavigationBarBackgroundView
- (void)layoutSubviews {
    %orig;
    UIView *v = (UIView *)self;
    v.alpha = 0;
    v.hidden = YES;
    v.backgroundColor = UIColor.clearColor;
    v.layer.backgroundColor = nil;
}
%end

%end // Backgrounds

%group Loupe

// the stock text loupe is replaced by our glass lens while typing in the address bar
%hook UIView
- (void)didMoveToWindow {
    %orig;
    UIView *v = (UIView *)self;
    if (!LG_LENS || !gTyping || !v.window) return;
    NSString *n = NSStringFromClass(v.class);
    if ([n containsString:@"Loupe"] || [n containsString:@"Magnifier"] || [n containsString:@"Magnifying"]) {
        if (!v.layer.mask) v.layer.mask = [CALayer layer];     // empty mask = invisible, UIKit's alpha animations can't undo it
    }
}
%end

%end // Loupe

// =====================  START  =====================

%ctor {
    NSLog(@"[26Safari] loaded in %@", NSBundle.mainBundle.bundleIdentifier);

    NSOperationQueue *mq = NSOperationQueue.mainQueue;
    [[NSNotificationCenter defaultCenter] addObserverForName:UIKeyboardWillShowNotification
                                                      object:nil queue:mq usingBlock:^(NSNotification *n) {
        gKeyboardVisible = YES;
        LGSync();
    }];
    [[NSNotificationCenter defaultCenter] addObserverForName:UIKeyboardDidHideNotification
                                                      object:nil queue:mq usingBlock:^(NSNotification *n) {
        gKeyboardVisible = NO;
        gRoles = nil;
        if (gColl) [gColl setNeedsLayout];
    }];

    // hook as early as Safari's classes exist (the old fixed 1s delay let the stock bar flash at launch)
    static dispatch_once_t bootOnce;
    void (^boot)(void) = ^{
        dispatch_once(&bootOnce, ^{
            %init(Pills);
            %init(Containers);
            %init(Toolbars);
            %init(Backgrounds);
            %init(Loupe);
            [LGTicker start];
        });
    };
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                      object:nil queue:mq usingBlock:^(NSNotification *n) { boot(); }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ boot(); });
}