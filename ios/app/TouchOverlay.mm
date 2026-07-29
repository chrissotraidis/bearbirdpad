#import <UIKit/UIKit.h>

#include <algorithm>
#include <atomic>

#include <SDL.h>

#include "TouchInputShim.hpp"
#include "TouchOverlay.h"

namespace {

constexpr uint16_t ButtonA = 0x8000;
constexpr uint16_t ButtonB = 0x4000;
constexpr uint16_t ButtonZ = 0x2000;
constexpr uint16_t ButtonStart = 0x1000;
constexpr uint16_t ButtonDpadUp = 0x0800;
constexpr uint16_t ButtonDpadDown = 0x0400;
constexpr uint16_t ButtonDpadLeft = 0x0200;
constexpr uint16_t ButtonDpadRight = 0x0100;
constexpr uint16_t ButtonL = 0x0020;
constexpr uint16_t ButtonR = 0x0010;
constexpr uint16_t ButtonCUp = 0x0008;
constexpr uint16_t ButtonCDown = 0x0004;
constexpr uint16_t ButtonCLeft = 0x0002;
constexpr uint16_t ButtonCRight = 0x0001;

UIColor *fill_color(BOOL pressed) {
    return [UIColor colorWithWhite:0.04 alpha:pressed ? 0.62 : 0.33];
}

UIColor *border_color() {
    return [UIColor colorWithWhite:1.0 alpha:0.72];
}

UIWindow *active_window() {
    UIWindow *fallbackWindow = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateUnattached &&
            [scene isKindOfClass:UIWindowScene.class]) {
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (window.isKeyWindow) {
                    return window;
                }
                if (fallbackWindow == nil) {
                    fallbackWindow = window;
                }
            }
        }
    }
    return fallbackWindow;
}

NSString *settings_path() {
    NSString *documents =
        NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [[documents stringByAppendingPathComponent:@"BanjoRecompiled"]
        stringByAppendingPathComponent:@"ios-controls.json"];
}

} // namespace

@interface BanjoPadTouchButton : UIView

@property(nonatomic, readonly) uint16_t buttonMask;
@property(nonatomic, strong) UILabel *label;
@property(nonatomic, assign) UITouch *activeTouch;
@property(nonatomic, assign) BOOL pressed;

- (instancetype)initWithLabel:(NSString *)label
                         mask:(uint16_t)mask
                         pill:(BOOL)pill
                        color:(UIColor *)color;
- (void)cancelInput;

@end

@implementation BanjoPadTouchButton {
    BOOL _pill;
    UIColor *_accentColor;
}

- (instancetype)initWithLabel:(NSString *)label
                         mask:(uint16_t)mask
                         pill:(BOOL)pill
                        color:(UIColor *)color {
    self = [super initWithFrame:CGRectZero];
    if (self != nil) {
        _buttonMask = mask;
        _pill = pill;
        _accentColor = color ?: UIColor.whiteColor;
        self.multipleTouchEnabled = NO;
        self.exclusiveTouch = NO;
        self.layer.borderWidth = 2.0;
        self.layer.borderColor = border_color().CGColor;
        self.backgroundColor = fill_color(NO);

        _label = [[UILabel alloc] initWithFrame:self.bounds];
        _label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _label.text = label;
        _label.textAlignment = NSTextAlignmentCenter;
        _label.textColor = color ?: UIColor.whiteColor;
        _label.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightBold];
        _label.userInteractionEnabled = NO;
        [self addSubview:_label];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.layer.cornerRadius = MIN(self.bounds.size.width, self.bounds.size.height) * 0.5;
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    return CGRectContainsPoint(CGRectInset(self.bounds, -6.0, -6.0), point);
}

- (void)setPressed:(BOOL)pressed {
    if (_pressed == pressed) {
        return;
    }
    _pressed = pressed;
    self.backgroundColor = fill_color(pressed);
    self.layer.borderColor = (pressed ? _accentColor : border_color()).CGColor;
    BanjoPadTouch_SetButton(self.buttonMask, pressed ? 1 : 0);
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (self.activeTouch == nil) {
        self.activeTouch = touches.anyObject;
        self.pressed = YES;
    }
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (self.activeTouch != nil && [touches containsObject:self.activeTouch]) {
        CGPoint point = [self.activeTouch locationInView:self];
        if (!CGRectContainsPoint(CGRectInset(self.bounds, -20.0, -20.0), point)) {
            [self cancelInput];
        }
    }
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (self.activeTouch != nil && [touches containsObject:self.activeTouch]) {
        [self cancelInput];
    }
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (self.activeTouch != nil && [touches containsObject:self.activeTouch]) {
        [self cancelInput];
    }
}

- (void)cancelInput {
    self.activeTouch = nil;
    self.pressed = NO;
}

@end

@interface BanjoPadTouchStick : UIView

@property(nonatomic, strong) UIView *thumb;
@property(nonatomic, assign) UITouch *activeTouch;

- (void)cancelInput;

@end

@implementation BanjoPadTouchStick

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self != nil) {
        self.multipleTouchEnabled = NO;
        self.layer.borderWidth = 2.0;
        self.layer.borderColor = border_color().CGColor;
        self.backgroundColor = fill_color(NO);

        _thumb = [[UIView alloc] initWithFrame:CGRectZero];
        _thumb.userInteractionEnabled = NO;
        _thumb.layer.borderWidth = 2.0;
        _thumb.layer.borderColor = border_color().CGColor;
        _thumb.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.58];
        [self addSubview:_thumb];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.layer.cornerRadius = MIN(self.bounds.size.width, self.bounds.size.height) * 0.5;
    CGFloat thumbSize = self.bounds.size.width * 0.4;
    self.thumb.bounds = CGRectMake(0.0, 0.0, thumbSize, thumbSize);
    if (self.activeTouch == nil) {
        self.thumb.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    }
    self.thumb.layer.cornerRadius = thumbSize * 0.5;
}

- (void)updateForTouch:(UITouch *)touch {
    CGPoint center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    CGPoint point = [touch locationInView:self];
    CGFloat dx = point.x - center.x;
    CGFloat dy = point.y - center.y;
    CGFloat travel = self.bounds.size.width * 0.3;
    CGFloat length = hypot(dx, dy);
    if (length > travel) {
        dx *= travel / length;
        dy *= travel / length;
    }
    self.thumb.center = CGPointMake(center.x + dx, center.y + dy);
    BanjoPadTouch_SetStick(dx / travel, -dy / travel);
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (self.activeTouch == nil) {
        self.activeTouch = touches.anyObject;
        [self updateForTouch:self.activeTouch];
    }
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (self.activeTouch != nil && [touches containsObject:self.activeTouch]) {
        [self updateForTouch:self.activeTouch];
    }
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (self.activeTouch != nil && [touches containsObject:self.activeTouch]) {
        [self cancelInput];
    }
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (self.activeTouch != nil && [touches containsObject:self.activeTouch]) {
        [self cancelInput];
    }
}

- (void)cancelInput {
    self.activeTouch = nil;
    self.thumb.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    BanjoPadTouch_SetStick(0.0f, 0.0f);
}

@end

@interface BanjoPadTouchOverlay : UIView

@property(nonatomic, strong) BanjoPadTouchStick *stick;
@property(nonatomic, strong) NSArray<BanjoPadTouchButton *> *buttons;
@property(nonatomic, strong) BanjoPadTouchButton *buttonA;
@property(nonatomic, strong) BanjoPadTouchButton *buttonB;
@property(nonatomic, strong) BanjoPadTouchButton *buttonZLeft;
@property(nonatomic, strong) BanjoPadTouchButton *buttonZRight;
@property(nonatomic, strong) BanjoPadTouchButton *buttonL;
@property(nonatomic, strong) BanjoPadTouchButton *buttonR;
@property(nonatomic, strong) BanjoPadTouchButton *buttonStart;
@property(nonatomic, strong) BanjoPadTouchButton *cUp;
@property(nonatomic, strong) BanjoPadTouchButton *cDown;
@property(nonatomic, strong) BanjoPadTouchButton *cLeft;
@property(nonatomic, strong) BanjoPadTouchButton *cRight;
@property(nonatomic, strong) BanjoPadTouchButton *dUp;
@property(nonatomic, strong) BanjoPadTouchButton *dDown;
@property(nonatomic, strong) BanjoPadTouchButton *dLeft;
@property(nonatomic, strong) BanjoPadTouchButton *dRight;

- (void)cancelAllInputs;

@end

@implementation BanjoPadTouchOverlay

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self != nil) {
        self.backgroundColor = UIColor.clearColor;
        self.multipleTouchEnabled = YES;

        UIColor *blue = [UIColor colorWithRed:0.36 green:0.72 blue:1.0 alpha:1.0];
        UIColor *green = [UIColor colorWithRed:0.43 green:0.92 blue:0.54 alpha:1.0];
        UIColor *amber = [UIColor colorWithRed:1.0 green:0.78 blue:0.22 alpha:1.0];
        UIColor *red = [UIColor colorWithRed:1.0 green:0.45 blue:0.42 alpha:1.0];

        _stick = [[BanjoPadTouchStick alloc] initWithFrame:CGRectZero];
        _buttonA = [[BanjoPadTouchButton alloc] initWithLabel:@"A" mask:ButtonA pill:NO color:blue];
        _buttonB = [[BanjoPadTouchButton alloc] initWithLabel:@"B" mask:ButtonB pill:NO color:green];
        _buttonZLeft = [[BanjoPadTouchButton alloc] initWithLabel:@"Z" mask:ButtonZ pill:YES color:nil];
        _buttonZRight = [[BanjoPadTouchButton alloc] initWithLabel:@"Z" mask:ButtonZ pill:NO color:nil];
        _buttonL = [[BanjoPadTouchButton alloc] initWithLabel:@"L" mask:ButtonL pill:YES color:nil];
        _buttonR = [[BanjoPadTouchButton alloc] initWithLabel:@"R" mask:ButtonR pill:YES color:nil];
        _buttonStart =
            [[BanjoPadTouchButton alloc] initWithLabel:@"START" mask:ButtonStart pill:YES color:red];
        _cUp = [[BanjoPadTouchButton alloc] initWithLabel:@"▲" mask:ButtonCUp pill:NO color:amber];
        _cDown = [[BanjoPadTouchButton alloc] initWithLabel:@"▼" mask:ButtonCDown pill:NO color:amber];
        _cLeft = [[BanjoPadTouchButton alloc] initWithLabel:@"◀" mask:ButtonCLeft pill:NO color:amber];
        _cRight = [[BanjoPadTouchButton alloc] initWithLabel:@"▶" mask:ButtonCRight pill:NO color:amber];
        _dUp = [[BanjoPadTouchButton alloc] initWithLabel:@"▲" mask:ButtonDpadUp pill:NO color:nil];
        _dDown = [[BanjoPadTouchButton alloc] initWithLabel:@"▼" mask:ButtonDpadDown pill:NO color:nil];
        _dLeft = [[BanjoPadTouchButton alloc] initWithLabel:@"◀" mask:ButtonDpadLeft pill:NO color:nil];
        _dRight = [[BanjoPadTouchButton alloc] initWithLabel:@"▶" mask:ButtonDpadRight pill:NO color:nil];

        _buttons = @[
            _buttonA, _buttonB, _buttonZLeft, _buttonZRight, _buttonL, _buttonR, _buttonStart,
            _cUp, _cDown, _cLeft, _cRight, _dUp, _dDown, _dLeft, _dRight
        ];
        [self addSubview:_stick];
        for (BanjoPadTouchButton *button in _buttons) {
            [self addSubview:button];
        }
        _buttonL.hidden = YES;
        _dUp.hidden = YES;
        _dDown.hidden = YES;
        _dLeft.hidden = YES;
        _dRight.hidden = YES;
    }
    return self;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self ? nil : hit;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    UIEdgeInsets safe = self.safeAreaInsets;
    CGFloat scale = self.bounds.size.height < 560.0 ? 0.85 : 1.0;
    CGFloat left = safe.left;
    CGFloat right = self.bounds.size.width - safe.right;
    CGFloat bottom = self.bounds.size.height - safe.bottom;

    void (^place)(UIView *, CGFloat, CGFloat, CGFloat, CGFloat) =
        ^(UIView *view, CGFloat x, CGFloat y, CGFloat width, CGFloat height) {
            view.bounds = CGRectMake(0.0, 0.0, width * scale, height * scale);
            view.center = CGPointMake(x, y);
        };

    place(self.stick, left + 120.0 * scale, bottom - 120.0 * scale, 150.0, 150.0);
    place(self.buttonZLeft, left + 96.0 * scale, bottom - 232.0 * scale, 84.0, 44.0);
    place(self.buttonL, left + 96.0 * scale, bottom - 288.0 * scale, 84.0, 44.0);
    place(self.buttonA, right - 78.0 * scale, bottom - 188.0 * scale, 66.0, 66.0);
    place(self.buttonB, right - 156.0 * scale, bottom - 210.0 * scale, 66.0, 66.0);
    place(self.buttonR, right - 110.0 * scale, bottom - 280.0 * scale, 84.0, 44.0);

    CGFloat cx = right - 120.0 * scale;
    CGFloat cy = bottom - 84.0 * scale;
    place(self.cUp, cx, cy - 52.0 * scale, 46.0, 46.0);
    place(self.cDown, cx, cy + 52.0 * scale, 46.0, 46.0);
    place(self.cLeft, cx - 52.0 * scale, cy, 46.0, 46.0);
    place(self.cRight, cx + 52.0 * scale, cy, 46.0, 46.0);
    place(self.buttonZRight, right - 232.0 * scale, bottom - 120.0 * scale, 46.0, 46.0);
    place(self.buttonStart, right - 320.0 * scale, bottom - 40.0 * scale, 96.0, 40.0);

    CGFloat dx = left + 120.0 * scale;
    CGFloat dy = bottom - 320.0 * scale;
    place(self.dUp, dx, dy - 48.0 * scale, 46.0, 46.0);
    place(self.dDown, dx, dy + 48.0 * scale, 46.0, 46.0);
    place(self.dLeft, dx - 48.0 * scale, dy, 46.0, 46.0);
    place(self.dRight, dx + 48.0 * scale, dy, 46.0, 46.0);
}

- (void)cancelAllInputs {
    [self.stick cancelInput];
    for (BanjoPadTouchButton *button in self.buttons) {
        [button cancelInput];
    }
    BanjoPadTouch_ReleaseAll();
}

@end

@interface BanjoPadCameraGestureDelegate : NSObject <UIGestureRecognizerDelegate>
@end

static BanjoPadTouchOverlay *sOverlay;
static BanjoPadTouchButton *sMenuButton;
static UIPanGestureRecognizer *sCameraGesture;
static BanjoPadCameraGestureDelegate *sCameraDelegate;
static std::atomic_bool sEnabled(true);
static std::atomic_bool sMenuVisible(true);
static std::atomic_bool sControllerConnected(false);
static NSUInteger sCameraGeneration;

@implementation BanjoPadCameraGestureDelegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
       shouldReceiveTouch:(UITouch *)touch {
    if (sOverlay == nil || sMenuVisible.load()) {
        return NO;
    }
    UIView *view = touch.view;
    while (view != nil) {
        if ([view isKindOfClass:BanjoPadTouchButton.class] ||
            [view isKindOfClass:BanjoPadTouchStick.class]) {
            return NO;
        }
        view = view.superview;
    }
    CGPoint point = [touch locationInView:gestureRecognizer.view];
    return point.x >= gestureRecognizer.view.bounds.size.width * 0.5;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
        shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}

@end

static void save_enabled_setting() {
    NSString *path = settings_path();
    NSString *directory = path.stringByDeletingLastPathComponent;
    [NSFileManager.defaultManager createDirectoryAtPath:directory
                           withIntermediateDirectories:YES
                                            attributes:nil
                                                 error:nil];
    NSDictionary *json = @{@"touch_controls": @(sEnabled.load())};
    NSData *data = [NSJSONSerialization dataWithJSONObject:json options:NSJSONWritingPrettyPrinted error:nil];
    [data writeToFile:path options:NSDataWritingAtomic error:nil];
}

static void load_enabled_setting() {
    NSData *data = [NSData dataWithContentsOfFile:settings_path()];
    if (data == nil) {
        return;
    }
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSNumber *enabled = [json isKindOfClass:NSDictionary.class] ? json[@"touch_controls"] : nil;
    if ([enabled isKindOfClass:NSNumber.class]) {
        sEnabled.store(enabled.boolValue);
    }
}

static void push_menu_toggle() {
    SDL_Event event{};
    event.type = SDL_KEYDOWN;
    event.key.state = SDL_PRESSED;
    event.key.keysym.scancode = SDL_SCANCODE_ESCAPE;
    event.key.keysym.sym = SDLK_ESCAPE;
    SDL_PushEvent(&event);
    event.type = SDL_KEYUP;
    event.key.state = SDL_RELEASED;
    SDL_PushEvent(&event);
}

static void handle_camera_pan(UIPanGestureRecognizer *gesture) {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [gesture setTranslation:CGPointZero inView:gesture.view];
    }
    if (gesture.state == UIGestureRecognizerStateChanged) {
        CGPoint translation = [gesture translationInView:gesture.view];
        [gesture setTranslation:CGPointZero inView:gesture.view];
        float x = std::clamp(static_cast<float>(translation.x / 60.0), -1.0f, 1.0f);
        float y = std::clamp(static_cast<float>(-translation.y / 60.0), -1.0f, 1.0f);
        BanjoPadTouch_SetCamera(x, y);
        NSUInteger generation = ++sCameraGeneration;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 40 * NSEC_PER_MSEC),
                       dispatch_get_main_queue(), ^{
            if (generation == sCameraGeneration) {
                BanjoPadTouch_SetCamera(0.0f, 0.0f);
            }
        });
    }
    if (gesture.state == UIGestureRecognizerStateEnded ||
        gesture.state == UIGestureRecognizerStateCancelled ||
        gesture.state == UIGestureRecognizerStateFailed) {
        ++sCameraGeneration;
        BanjoPadTouch_SetCamera(0.0f, 0.0f);
    }
}

@interface BanjoPadMenuTapTarget : NSObject
- (void)tapped;
@end

@interface BanjoPadCameraTarget : NSObject
- (void)panned:(UIPanGestureRecognizer *)gesture;
@end

static BanjoPadMenuTapTarget *sMenuTapTarget;
static BanjoPadCameraTarget *sCameraTarget;

@implementation BanjoPadMenuTapTarget
- (void)tapped {
    push_menu_toggle();
}
@end

@implementation BanjoPadCameraTarget
- (void)panned:(UIPanGestureRecognizer *)gesture {
    handle_camera_pan(gesture);
}
@end

static void install_menu_button(UIWindow *window) {
    if (sMenuButton == nil) {
        sMenuTapTarget = [[BanjoPadMenuTapTarget alloc] init];
        sMenuButton =
            [[BanjoPadTouchButton alloc] initWithLabel:@"•••" mask:0 pill:NO color:nil];
        sMenuButton.accessibilityLabel = @"Open BanjoPad menu";
        [sMenuButton addGestureRecognizer:
            [[UITapGestureRecognizer alloc] initWithTarget:sMenuTapTarget action:@selector(tapped)]];
    }
    if (sMenuButton.superview != window) {
        [sMenuButton removeFromSuperview];
        [window addSubview:sMenuButton];
    }
    CGFloat size = 38.0;
    UIEdgeInsets safe = window.safeAreaInsets;
    sMenuButton.bounds = CGRectMake(0.0, 0.0, size, size);
    sMenuButton.center =
        CGPointMake(window.bounds.size.width - safe.right - 36.0, safe.top + 24.0);
}

static void apply_overlay_state();

static void install_when_ready() {
    UIWindow *window = active_window();
    if (window == nil) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC),
                       dispatch_get_main_queue(), ^{
            install_when_ready();
        });
        return;
    }

    install_menu_button(window);
    if (sCameraGesture == nil) {
        sCameraDelegate = [[BanjoPadCameraGestureDelegate alloc] init];
        sCameraTarget = [[BanjoPadCameraTarget alloc] init];
        sCameraGesture =
            [[UIPanGestureRecognizer alloc] initWithTarget:sCameraTarget action:@selector(panned:)];
        [window addGestureRecognizer:sCameraGesture];
        sCameraGesture.delegate = sCameraDelegate;
        sCameraGesture.cancelsTouchesInView = NO;
        sCameraGesture.maximumNumberOfTouches = 1;
    }
    apply_overlay_state();
}

static void apply_overlay_state() {
    UIWindow *window = active_window();
    if (window == nil) {
        return;
    }
    install_menu_button(window);

    if (!sEnabled.load() || sMenuVisible.load()) {
        [sOverlay cancelAllInputs];
        [sOverlay removeFromSuperview];
        sOverlay = nil;
        sCameraGesture.enabled = NO;
        [window bringSubviewToFront:sMenuButton];
        return;
    }

    if (sOverlay == nil) {
        sOverlay = [[BanjoPadTouchOverlay alloc] initWithFrame:window.bounds];
        sOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    }
    if (sOverlay.superview != window) {
        [sOverlay removeFromSuperview];
        sOverlay.frame = window.bounds;
        [window addSubview:sOverlay];
    }
    sOverlay.alpha = sControllerConnected.load() ? 0.4 : 1.0;
    sCameraGesture.enabled = YES;
    [window bringSubviewToFront:sOverlay];
    [window bringSubviewToFront:sMenuButton];
}

extern "C" int BanjoPadTouch_Available(void) {
    return 1;
}

extern "C" int BanjoPadTouch_Enabled(void) {
    return sEnabled.load() ? 1 : 0;
}

extern "C" void BanjoPadTouch_Install(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        load_enabled_setting();
        install_when_ready();
    });
}

extern "C" void BanjoPadTouch_SetEnabled(int enabled) {
    sEnabled.store(enabled != 0);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!sEnabled.load()) {
            BanjoPadTouch_ReleaseAll();
        }
        save_enabled_setting();
        apply_overlay_state();
    });
}

extern "C" void BanjoPadTouch_SetMenuVisible(int visible) {
    bool newValue = visible != 0;
    if (sMenuVisible.exchange(newValue) == newValue) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        apply_overlay_state();
    });
}

extern "C" void BanjoPadTouch_SetControllerConnected(int connected) {
    bool newValue = connected != 0;
    if (sControllerConnected.exchange(newValue) == newValue) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        apply_overlay_state();
    });
}
