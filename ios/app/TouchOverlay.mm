#import <UIKit/UIKit.h>
#import <UIKit/UIGestureRecognizerSubclass.h>

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
    if (UIAccessibilityIsReduceTransparencyEnabled()) {
        return [UIColor colorWithWhite:pressed ? 0.24 : 0.04 alpha:1.0];
    }
    if (UIAccessibilityDarkerSystemColorsEnabled()) {
        return [UIColor colorWithWhite:pressed ? 0.20 : 0.03 alpha:0.9];
    }
    return [UIColor colorWithWhite:0.04 alpha:pressed ? 0.62 : 0.33];
}

UIColor *border_color() {
    BOOL strongerContrast =
        UIAccessibilityIsReduceTransparencyEnabled() ||
        UIAccessibilityDarkerSystemColorsEnabled();
    return [UIColor colorWithWhite:1.0 alpha:strongerContrast ? 1.0 : 0.72];
}

UIColor *thumb_color() {
    if (UIAccessibilityIsReduceTransparencyEnabled()) {
        return [UIColor colorWithWhite:0.22 alpha:1.0];
    }
    return [UIColor colorWithWhite:0.16
                             alpha:UIAccessibilityDarkerSystemColorsEnabled() ? 0.9 : 0.58];
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

static void push_menu_toggle();

@interface BanjoPadTouchButton : UIView

@property(nonatomic, readonly) uint16_t buttonMask;
@property(nonatomic, strong) UILabel *label;
@property(nonatomic, assign) UITouch *activeTouch;
@property(nonatomic, assign) BOOL pressed;
@property(nonatomic, assign) NSUInteger accessibilityGeneration;

- (instancetype)initWithLabel:(NSString *)label
           accessibilityLabel:(NSString *)accessibilityLabel
                         mask:(uint16_t)mask
                         pill:(BOOL)pill
                        color:(UIColor *)color;
- (void)cancelInput;
- (void)updateAccessibilityAppearance;

@end

@implementation BanjoPadTouchButton {
    BOOL _pill;
    UIColor *_accentColor;
}

- (instancetype)initWithLabel:(NSString *)label
           accessibilityLabel:(NSString *)accessibilityLabel
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
        self.layer.shadowColor = UIColor.blackColor.CGColor;
        self.layer.shadowOpacity = 0.72;
        self.layer.shadowRadius = 3.0;
        self.layer.shadowOffset = CGSizeZero;
        self.backgroundColor = fill_color(NO);
        self.isAccessibilityElement = YES;
        self.accessibilityLabel = accessibilityLabel;
        self.accessibilityTraits = UIAccessibilityTraitButton;

        _label = [[UILabel alloc] initWithFrame:self.bounds];
        _label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _label.text = label;
        _label.textAlignment = NSTextAlignmentCenter;
        _label.textColor = color ?: UIColor.whiteColor;
        _label.shadowColor = [UIColor colorWithWhite:0.0 alpha:0.9];
        _label.shadowOffset = CGSizeMake(0.0, 1.0);
        UIFont *baseFont = [UIFont systemFontOfSize:15.0 weight:UIFontWeightBold];
        _label.font =
            [UIFontMetrics.defaultMetrics scaledFontForFont:baseFont maximumPointSize:22.0];
        _label.adjustsFontForContentSizeCategory = YES;
        _label.adjustsFontSizeToFitWidth = YES;
        _label.minimumScaleFactor = 0.75;
        _label.userInteractionEnabled = NO;
        [self addSubview:_label];

        [NSNotificationCenter.defaultCenter
            addObserver:self
               selector:@selector(accessibilityAppearanceChanged:)
                   name:UIAccessibilityDarkerSystemColorsStatusDidChangeNotification
                 object:nil];
        [NSNotificationCenter.defaultCenter
            addObserver:self
               selector:@selector(accessibilityAppearanceChanged:)
                   name:UIAccessibilityReduceTransparencyStatusDidChangeNotification
                 object:nil];
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)accessibilityAppearanceChanged:(NSNotification *)notification {
    [self updateAccessibilityAppearance];
}

- (void)updateAccessibilityAppearance {
    self.backgroundColor = fill_color(self.pressed);
    self.layer.borderColor = (self.pressed ? _accentColor : border_color()).CGColor;
}

- (CGRect)interactionBounds {
    static const CGFloat minimumTargetSize = 44.0;
    CGFloat horizontalInset = MAX(6.0, (minimumTargetSize - self.bounds.size.width) * 0.5);
    CGFloat verticalInset = MAX(6.0, (minimumTargetSize - self.bounds.size.height) * 0.5);
    return CGRectInset(self.bounds, -horizontalInset, -verticalInset);
}

- (UIBezierPath *)hitPathForBounds:(CGRect)bounds {
    CGFloat cornerRadius = _pill
        ? CGRectGetHeight(bounds) * 0.5
        : MIN(CGRectGetWidth(bounds), CGRectGetHeight(bounds)) * 0.5;
    return [UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:cornerRadius];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat cornerRadius = MIN(self.bounds.size.width, self.bounds.size.height) * 0.5;
    self.layer.cornerRadius = cornerRadius;
    self.layer.shadowPath =
        [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:cornerRadius].CGPath;
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    return [[self hitPathForBounds:[self interactionBounds]] containsPoint:point];
}

- (CGRect)accessibilityFrame {
    return UIAccessibilityConvertFrameToScreenCoordinates([self interactionBounds], self);
}

- (void)setPressed:(BOOL)pressed {
    if (_pressed == pressed) {
        return;
    }
    _pressed = pressed;
    [self updateAccessibilityAppearance];
    BanjoPadTouch_SetButton(self.buttonMask, pressed ? 1 : 0);
}

- (BOOL)accessibilityActivate {
    if (self.buttonMask == 0) {
        push_menu_toggle();
        return YES;
    }

    NSUInteger generation = ++self.accessibilityGeneration;
    self.pressed = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_MSEC),
                   dispatch_get_main_queue(), ^{
        if (generation == self.accessibilityGeneration && self.activeTouch == nil) {
            self.pressed = NO;
        }
    });
    return YES;
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
        CGRect releaseBounds = CGRectInset(self.bounds, -20.0, -20.0);
        if (![[self hitPathForBounds:releaseBounds] containsPoint:point]) {
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
    ++self.accessibilityGeneration;
    self.activeTouch = nil;
    self.pressed = NO;
}

@end

@interface BanjoPadTouchStick : UIView

@property(nonatomic, strong) UIView *thumb;
@property(nonatomic, assign) UITouch *activeTouch;
@property(nonatomic, assign) NSUInteger accessibilityGeneration;

- (void)cancelInput;
- (BOOL)accessibilityMoveUp;
- (BOOL)accessibilityMoveDown;
- (BOOL)accessibilityMoveLeft;
- (BOOL)accessibilityMoveRight;
- (BOOL)accessibilityCenter;
- (void)updateAccessibilityAppearance;

@end

@implementation BanjoPadTouchStick

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self != nil) {
        self.multipleTouchEnabled = NO;
        self.layer.borderWidth = 2.0;
        self.layer.borderColor = border_color().CGColor;
        self.layer.shadowColor = UIColor.blackColor.CGColor;
        self.layer.shadowOpacity = 0.72;
        self.layer.shadowRadius = 3.0;
        self.layer.shadowOffset = CGSizeZero;
        self.backgroundColor = fill_color(NO);
        self.isAccessibilityElement = YES;
        self.accessibilityLabel = @"Control stick";
        self.accessibilityHint =
            @"Swipe up or down for vertical movement. Use Actions for every direction.";
        self.accessibilityTraits = UIAccessibilityTraitAdjustable;
        self.accessibilityValue = @"Centered";
        self.accessibilityCustomActions = @[
            [[UIAccessibilityCustomAction alloc] initWithName:@"Move up"
                                                       target:self
                                                     selector:@selector(accessibilityMoveUp)],
            [[UIAccessibilityCustomAction alloc] initWithName:@"Move down"
                                                       target:self
                                                     selector:@selector(accessibilityMoveDown)],
            [[UIAccessibilityCustomAction alloc] initWithName:@"Move left"
                                                       target:self
                                                     selector:@selector(accessibilityMoveLeft)],
            [[UIAccessibilityCustomAction alloc] initWithName:@"Move right"
                                                       target:self
                                                     selector:@selector(accessibilityMoveRight)],
            [[UIAccessibilityCustomAction alloc] initWithName:@"Center"
                                                       target:self
                                                     selector:@selector(accessibilityCenter)],
        ];

        _thumb = [[UIView alloc] initWithFrame:CGRectZero];
        _thumb.userInteractionEnabled = NO;
        _thumb.layer.borderWidth = 2.0;
        [self addSubview:_thumb];
        [self updateAccessibilityAppearance];

        [NSNotificationCenter.defaultCenter
            addObserver:self
               selector:@selector(accessibilityAppearanceChanged:)
                   name:UIAccessibilityDarkerSystemColorsStatusDidChangeNotification
                 object:nil];
        [NSNotificationCenter.defaultCenter
            addObserver:self
               selector:@selector(accessibilityAppearanceChanged:)
                   name:UIAccessibilityReduceTransparencyStatusDidChangeNotification
                 object:nil];
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)accessibilityAppearanceChanged:(NSNotification *)notification {
    [self updateAccessibilityAppearance];
}

- (void)updateAccessibilityAppearance {
    self.backgroundColor = fill_color(NO);
    self.layer.borderColor = border_color().CGColor;
    self.thumb.backgroundColor = thumb_color();
    self.thumb.layer.borderColor = border_color().CGColor;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat cornerRadius = MIN(self.bounds.size.width, self.bounds.size.height) * 0.5;
    self.layer.cornerRadius = cornerRadius;
    self.layer.shadowPath =
        [UIBezierPath bezierPathWithOvalInRect:self.bounds].CGPath;
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

- (void)pulseAccessibilityX:(float)x y:(float)y direction:(NSString *)direction {
    NSUInteger generation = ++self.accessibilityGeneration;
    CGPoint center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    CGFloat travel = self.bounds.size.width * 0.3;
    self.thumb.center = CGPointMake(center.x + x * travel, center.y - y * travel);
    self.accessibilityValue = direction;
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, direction);
    BanjoPadTouch_SetStick(x, y);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 160 * NSEC_PER_MSEC),
                   dispatch_get_main_queue(), ^{
        if (generation == self.accessibilityGeneration && self.activeTouch == nil) {
            BanjoPadTouch_SetStick(0.0f, 0.0f);
            self.accessibilityValue = @"Centered";
            self.thumb.center =
                CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
        }
    });
}

- (void)accessibilityIncrement {
    [self pulseAccessibilityX:0.0f y:1.0f direction:@"Up"];
}

- (void)accessibilityDecrement {
    [self pulseAccessibilityX:0.0f y:-1.0f direction:@"Down"];
}

- (BOOL)accessibilityMoveUp {
    [self pulseAccessibilityX:0.0f y:1.0f direction:@"Up"];
    return YES;
}

- (BOOL)accessibilityMoveDown {
    [self pulseAccessibilityX:0.0f y:-1.0f direction:@"Down"];
    return YES;
}

- (BOOL)accessibilityMoveLeft {
    [self pulseAccessibilityX:-1.0f y:0.0f direction:@"Left"];
    return YES;
}

- (BOOL)accessibilityMoveRight {
    [self pulseAccessibilityX:1.0f y:0.0f direction:@"Right"];
    return YES;
}

- (BOOL)accessibilityCenter {
    ++self.accessibilityGeneration;
    self.thumb.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    self.accessibilityValue = @"Centered";
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, self.accessibilityValue);
    BanjoPadTouch_SetStick(0.0f, 0.0f);
    return YES;
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
    ++self.accessibilityGeneration;
    self.activeTouch = nil;
    self.thumb.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    self.accessibilityValue = @"Centered";
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
@property(nonatomic, assign) BOOL controllerConnected;

- (void)cancelAllInputs;
- (void)setOptionalControlsShowL:(BOOL)showL showDpad:(BOOL)showDpad;
- (void)updateControllerAppearance;

@end

@implementation BanjoPadTouchOverlay

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self != nil) {
        self.backgroundColor = UIColor.clearColor;
        self.multipleTouchEnabled = YES;
        [NSNotificationCenter.defaultCenter
            addObserver:self
               selector:@selector(accessibilityAppearanceChanged:)
                   name:UIAccessibilityReduceTransparencyStatusDidChangeNotification
                 object:nil];
        [NSNotificationCenter.defaultCenter
            addObserver:self
               selector:@selector(accessibilityAppearanceChanged:)
                   name:UIAccessibilityDarkerSystemColorsStatusDidChangeNotification
                 object:nil];

        UIColor *blue = [UIColor colorWithRed:0.36 green:0.72 blue:1.0 alpha:1.0];
        UIColor *green = [UIColor colorWithRed:0.43 green:0.92 blue:0.54 alpha:1.0];
        UIColor *amber = [UIColor colorWithRed:1.0 green:0.78 blue:0.22 alpha:1.0];
        UIColor *red = [UIColor colorWithRed:1.0 green:0.45 blue:0.42 alpha:1.0];

        _stick = [[BanjoPadTouchStick alloc] initWithFrame:CGRectZero];
        _buttonA = [[BanjoPadTouchButton alloc] initWithLabel:@"A"
                                         accessibilityLabel:@"A button"
                                                       mask:ButtonA
                                                       pill:NO
                                                      color:blue];
        _buttonB = [[BanjoPadTouchButton alloc] initWithLabel:@"B"
                                         accessibilityLabel:@"B button"
                                                       mask:ButtonB
                                                       pill:NO
                                                      color:green];
        _buttonZLeft = [[BanjoPadTouchButton alloc] initWithLabel:@"Z"
                                             accessibilityLabel:@"Left Z trigger"
                                                           mask:ButtonZ
                                                           pill:YES
                                                          color:nil];
        _buttonZRight = [[BanjoPadTouchButton alloc] initWithLabel:@"Z"
                                              accessibilityLabel:@"Right Z trigger"
                                                            mask:ButtonZ
                                                            pill:NO
                                                           color:nil];
        _buttonL = [[BanjoPadTouchButton alloc] initWithLabel:@"L"
                                         accessibilityLabel:@"L shoulder button"
                                                       mask:ButtonL
                                                       pill:YES
                                                      color:nil];
        _buttonR = [[BanjoPadTouchButton alloc] initWithLabel:@"R"
                                         accessibilityLabel:@"R shoulder button"
                                                       mask:ButtonR
                                                       pill:YES
                                                      color:nil];
        _buttonStart =
            [[BanjoPadTouchButton alloc] initWithLabel:@"START"
                                  accessibilityLabel:@"Start button"
                                                mask:ButtonStart
                                                pill:YES
                                               color:red];
        _cUp = [[BanjoPadTouchButton alloc] initWithLabel:@"▲"
                                      accessibilityLabel:@"C Up button"
                                                    mask:ButtonCUp
                                                    pill:NO
                                                   color:amber];
        _cDown = [[BanjoPadTouchButton alloc] initWithLabel:@"▼"
                                        accessibilityLabel:@"C Down button"
                                                      mask:ButtonCDown
                                                      pill:NO
                                                     color:amber];
        _cLeft = [[BanjoPadTouchButton alloc] initWithLabel:@"◀"
                                        accessibilityLabel:@"C Left button"
                                                      mask:ButtonCLeft
                                                      pill:NO
                                                     color:amber];
        _cRight = [[BanjoPadTouchButton alloc] initWithLabel:@"▶"
                                         accessibilityLabel:@"C Right button"
                                                       mask:ButtonCRight
                                                       pill:NO
                                                      color:amber];
        _dUp = [[BanjoPadTouchButton alloc] initWithLabel:@"▲"
                                      accessibilityLabel:@"D-pad Up"
                                                    mask:ButtonDpadUp
                                                    pill:NO
                                                   color:nil];
        _dDown = [[BanjoPadTouchButton alloc] initWithLabel:@"▼"
                                        accessibilityLabel:@"D-pad Down"
                                                      mask:ButtonDpadDown
                                                      pill:NO
                                                     color:nil];
        _dLeft = [[BanjoPadTouchButton alloc] initWithLabel:@"◀"
                                        accessibilityLabel:@"D-pad Left"
                                                      mask:ButtonDpadLeft
                                                      pill:NO
                                                     color:nil];
        _dRight = [[BanjoPadTouchButton alloc] initWithLabel:@"▶"
                                         accessibilityLabel:@"D-pad Right"
                                                       mask:ButtonDpadRight
                                                       pill:NO
                                                      color:nil];

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

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)accessibilityAppearanceChanged:(NSNotification *)notification {
    [self updateControllerAppearance];
}

- (void)setControllerConnected:(BOOL)controllerConnected {
    _controllerConnected = controllerConnected;
    [self updateControllerAppearance];
}

- (void)updateControllerAppearance {
    BOOL strongerContrast =
        UIAccessibilityIsReduceTransparencyEnabled() ||
        UIAccessibilityDarkerSystemColorsEnabled();
    self.alpha = self.controllerConnected && !strongerContrast ? 0.4 : 1.0;
}

- (void)setOptionalControlsShowL:(BOOL)showL showDpad:(BOOL)showDpad {
    if (!showL) {
        [self.buttonL cancelInput];
    }
    if (!showDpad) {
        [self.dUp cancelInput];
        [self.dDown cancelInput];
        [self.dLeft cancelInput];
        [self.dRight cancelInput];
    }
    self.buttonL.hidden = !showL;
    self.dUp.hidden = !showDpad;
    self.dDown.hidden = !showDpad;
    self.dLeft.hidden = !showDpad;
    self.dRight.hidden = !showDpad;
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

@interface BanjoPadCameraGesture : UIGestureRecognizer

- (CGPoint)consumeTranslation;

@end

@implementation BanjoPadCameraGesture {
    UITouch *_activeTouch;
    CGPoint _startPoint;
    CGPoint _lastPoint;
    CGPoint _pendingTranslation;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_activeTouch != nil) {
        return;
    }
    _activeTouch = touches.anyObject;
    _startPoint = [_activeTouch locationInView:self.view];
    _lastPoint = _startPoint;
    _pendingTranslation = CGPointZero;
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_activeTouch == nil || ![touches containsObject:_activeTouch]) {
        return;
    }

    CGPoint point = [_activeTouch locationInView:self.view];
    if (self.state == UIGestureRecognizerStatePossible) {
        static const CGFloat activationDistance = 8.0;
        CGFloat dx = point.x - _startPoint.x;
        CGFloat dy = point.y - _startPoint.y;
        if (hypot(dx, dy) < activationDistance) {
            return;
        }
        _pendingTranslation = CGPointMake(dx, dy);
        _lastPoint = point;
        self.state = UIGestureRecognizerStateBegan;
        return;
    }

    if (self.state == UIGestureRecognizerStateBegan ||
        self.state == UIGestureRecognizerStateChanged) {
        _pendingTranslation.x += point.x - _lastPoint.x;
        _pendingTranslation.y += point.y - _lastPoint.y;
        _lastPoint = point;
        self.state = UIGestureRecognizerStateChanged;
    }
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_activeTouch == nil || ![touches containsObject:_activeTouch]) {
        return;
    }
    _activeTouch = nil;
    self.state = self.state == UIGestureRecognizerStatePossible
        ? UIGestureRecognizerStateFailed
        : UIGestureRecognizerStateEnded;
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_activeTouch != nil && [touches containsObject:_activeTouch]) {
        _activeTouch = nil;
        self.state = self.state == UIGestureRecognizerStatePossible
            ? UIGestureRecognizerStateFailed
            : UIGestureRecognizerStateCancelled;
    }
}

- (void)reset {
    [super reset];
    _activeTouch = nil;
    _startPoint = CGPointZero;
    _lastPoint = CGPointZero;
    _pendingTranslation = CGPointZero;
}

- (CGPoint)consumeTranslation {
    CGPoint translation = _pendingTranslation;
    _pendingTranslation = CGPointZero;
    return translation;
}

@end

@interface BanjoPadCameraGestureDelegate : NSObject <UIGestureRecognizerDelegate>
@end

static BanjoPadTouchOverlay *sOverlay;
static BanjoPadTouchButton *sMenuButton;
static BanjoPadCameraGesture *sCameraGesture;
static BanjoPadCameraGestureDelegate *sCameraDelegate;
static id sResignObserver;
static std::atomic_bool sEnabled(true);
static std::atomic_bool sHideWhenControllerConnected(false);
static std::atomic_bool sShowDpad(false);
static std::atomic_bool sShowL(false);
static std::atomic_bool sMenuVisible(true);
static std::atomic_bool sControllerConnected(false);
static NSUInteger sCameraGeneration;

static void cancel_all_inputs() {
    [sOverlay cancelAllInputs];
    [sMenuButton cancelInput];
    BanjoPadTouch_ReleaseAll();
}

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

static void save_control_settings() {
    NSString *path = settings_path();
    NSString *directory = path.stringByDeletingLastPathComponent;
    [NSFileManager.defaultManager createDirectoryAtPath:directory
                           withIntermediateDirectories:YES
                                            attributes:nil
                                                 error:nil];
    NSDictionary *json = @{
        @"hide_when_controller_connected": @(sHideWhenControllerConnected.load()),
        @"show_dpad": @(sShowDpad.load()),
        @"show_l_button": @(sShowL.load()),
        @"touch_controls": @(sEnabled.load()),
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:json options:NSJSONWritingPrettyPrinted error:nil];
    [data writeToFile:path options:NSDataWritingAtomic error:nil];
}

static void load_control_settings() {
    NSData *data = [NSData dataWithContentsOfFile:settings_path()];
    if (data == nil) {
        return;
    }
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSNumber *enabled = [json isKindOfClass:NSDictionary.class] ? json[@"touch_controls"] : nil;
    if ([enabled isKindOfClass:NSNumber.class]) {
        sEnabled.store(enabled.boolValue);
    }
    NSNumber *hideWhenControllerConnected =
        [json isKindOfClass:NSDictionary.class] ? json[@"hide_when_controller_connected"] : nil;
    if ([hideWhenControllerConnected isKindOfClass:NSNumber.class]) {
        sHideWhenControllerConnected.store(hideWhenControllerConnected.boolValue);
    }
    NSNumber *showDpad = [json isKindOfClass:NSDictionary.class] ? json[@"show_dpad"] : nil;
    if ([showDpad isKindOfClass:NSNumber.class]) {
        sShowDpad.store(showDpad.boolValue);
    }
    NSNumber *showL = [json isKindOfClass:NSDictionary.class] ? json[@"show_l_button"] : nil;
    if ([showL isKindOfClass:NSNumber.class]) {
        sShowL.store(showL.boolValue);
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

static void handle_camera_pan(BanjoPadCameraGesture *gesture) {
    if (gesture.state == UIGestureRecognizerStateBegan ||
        gesture.state == UIGestureRecognizerStateChanged) {
        CGPoint translation = [gesture consumeTranslation];
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
- (void)panned:(BanjoPadCameraGesture *)gesture;
@end

static BanjoPadMenuTapTarget *sMenuTapTarget;
static BanjoPadCameraTarget *sCameraTarget;

@implementation BanjoPadMenuTapTarget
- (void)tapped {
    push_menu_toggle();
}
@end

@implementation BanjoPadCameraTarget
- (void)panned:(BanjoPadCameraGesture *)gesture {
    handle_camera_pan(gesture);
}
@end

static void install_menu_button(UIWindow *window) {
    if (sMenuButton == nil) {
        sMenuTapTarget = [[BanjoPadMenuTapTarget alloc] init];
        sMenuButton =
            [[BanjoPadTouchButton alloc] initWithLabel:@"•••"
                                  accessibilityLabel:@"BanjoPad menu"
                                                mask:0
                                                pill:NO
                                               color:nil];
        sMenuButton.accessibilityHint = @"Opens or closes the BanjoPad menu.";
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
            [[BanjoPadCameraGesture alloc] initWithTarget:sCameraTarget action:@selector(panned:)];
        [window addGestureRecognizer:sCameraGesture];
        sCameraGesture.delegate = sCameraDelegate;
        sCameraGesture.cancelsTouchesInView = NO;
        sCameraGesture.delaysTouchesBegan = NO;
        sCameraGesture.delaysTouchesEnded = NO;
    }
    apply_overlay_state();
}

static void apply_overlay_state() {
    UIWindow *window = active_window();
    if (window == nil) {
        return;
    }
    install_menu_button(window);

    if (!sEnabled.load() || sMenuVisible.load() ||
        (sControllerConnected.load() && sHideWhenControllerConnected.load())) {
        cancel_all_inputs();
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
    [sOverlay setOptionalControlsShowL:sShowL.load() showDpad:sShowDpad.load()];
    if (sOverlay.superview != window) {
        [sOverlay removeFromSuperview];
        sOverlay.frame = window.bounds;
        [window addSubview:sOverlay];
    }
    sOverlay.controllerConnected = sControllerConnected.load();
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

extern "C" int BanjoPadTouch_HideWhenControllerConnected(void) {
    return sHideWhenControllerConnected.load() ? 1 : 0;
}

extern "C" int BanjoPadTouch_ShowDpad(void) {
    return sShowDpad.load() ? 1 : 0;
}

extern "C" int BanjoPadTouch_ShowL(void) {
    return sShowL.load() ? 1 : 0;
}

extern "C" void BanjoPadTouch_Install(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (sResignObserver == nil) {
            sResignObserver = [NSNotificationCenter.defaultCenter
                addObserverForName:UIApplicationWillResignActiveNotification
                            object:nil
                             queue:NSOperationQueue.mainQueue
                        usingBlock:^(NSNotification *) {
                            cancel_all_inputs();
                        }];
        }
        load_control_settings();
        install_when_ready();
    });
}

extern "C" void BanjoPadTouch_SetEnabled(int enabled) {
    sEnabled.store(enabled != 0);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!sEnabled.load()) {
            cancel_all_inputs();
        }
        save_control_settings();
        apply_overlay_state();
    });
}

extern "C" void BanjoPadTouch_SetHideWhenControllerConnected(int hidden) {
    sHideWhenControllerConnected.store(hidden != 0);
    dispatch_async(dispatch_get_main_queue(), ^{
        save_control_settings();
        apply_overlay_state();
    });
}

extern "C" void BanjoPadTouch_SetShowDpad(int visible) {
    sShowDpad.store(visible != 0);
    dispatch_async(dispatch_get_main_queue(), ^{
        save_control_settings();
        apply_overlay_state();
    });
}

extern "C" void BanjoPadTouch_SetShowL(int visible) {
    sShowL.store(visible != 0);
    dispatch_async(dispatch_get_main_queue(), ^{
        save_control_settings();
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
