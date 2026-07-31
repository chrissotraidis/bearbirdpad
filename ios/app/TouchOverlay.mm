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

@interface BearBirdPadTouchButton : UIView

@property(nonatomic, readonly) uint16_t buttonMask;
@property(nonatomic, strong) UILabel *label;
@property(nonatomic, assign) UITouch *activeTouch;
@property(nonatomic, assign) BOOL pressed;
@property(nonatomic, assign) BOOL latched;
@property(nonatomic, assign) BOOL supportsLongPressLatch;
@property(nonatomic, assign) BOOL layoutEditing;
@property(nonatomic, assign) NSUInteger accessibilityGeneration;
@property(nonatomic, assign) NSUInteger latchGeneration;
@property(nonatomic, copy) void (^layoutSelectionHandler)(UIView *);
@property(nonatomic, copy) BOOL (^releaseLatchHandler)(void);
@property(nonatomic, copy) void (^engageLatchHandler)(void);

- (instancetype)initWithLabel:(NSString *)label
           accessibilityLabel:(NSString *)accessibilityLabel
                         mask:(uint16_t)mask
                         pill:(BOOL)pill
                        color:(UIColor *)color;
- (void)cancelInput;
- (void)updateAccessibilityAppearance;

@end

@implementation BearBirdPadTouchButton {
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
    if (self.latched) {
        BOOL strongerContrast =
            UIAccessibilityIsReduceTransparencyEnabled() ||
            UIAccessibilityDarkerSystemColorsEnabled();
        self.backgroundColor = [UIColor colorWithRed:0.78
                                               green:0.46
                                                blue:0.04
                                               alpha:strongerContrast ? 1.0 : 0.88];
        self.layer.borderColor =
            [UIColor colorWithRed:1.0 green:0.84 blue:0.25 alpha:1.0].CGColor;
        return;
    }
    self.backgroundColor = fill_color(self.pressed);
    self.layer.borderColor = (self.pressed ? _accentColor : border_color()).CGColor;
}

- (void)setLatched:(BOOL)latched {
    if (_latched == latched) {
        return;
    }
    _latched = latched;
    self.accessibilityValue = latched ? @"Held" : nil;
    self.accessibilityTraits = UIAccessibilityTraitButton |
        (latched ? UIAccessibilityTraitSelected : 0);
    [self updateAccessibilityAppearance];
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
    BearBirdPadTouch_SetButton(self.buttonMask, pressed ? 1 : 0);
}

- (BOOL)accessibilityActivate {
    if (self.layoutEditing) {
        if (self.layoutSelectionHandler != nil) {
            self.layoutSelectionHandler(self);
        }
        return YES;
    }
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
    if (self.layoutEditing) {
        return;
    }
    if (self.activeTouch == nil) {
        BOOL releasedLatch = self.supportsLongPressLatch &&
            self.releaseLatchHandler != nil && self.releaseLatchHandler();
        self.activeTouch = touches.anyObject;
        self.pressed = YES;
        NSUInteger generation = ++self.latchGeneration;
        if (self.supportsLongPressLatch && !releasedLatch) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                           dispatch_get_main_queue(), ^{
                if (generation == self.latchGeneration && self.activeTouch != nil &&
                    self.engageLatchHandler != nil) {
                    self.engageLatchHandler();
                }
            });
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
    ++self.latchGeneration;
    self.activeTouch = nil;
    self.pressed = NO;
}

@end

@interface BearBirdPadTouchStick : UIView

@property(nonatomic, strong) UIView *thumb;
@property(nonatomic, assign) UITouch *activeTouch;
@property(nonatomic, assign) BOOL layoutEditing;
@property(nonatomic, assign) NSUInteger accessibilityGeneration;
@property(nonatomic, copy) void (^layoutSelectionHandler)(UIView *);

- (void)cancelInput;
- (BOOL)accessibilityMoveUp;
- (BOOL)accessibilityMoveDown;
- (BOOL)accessibilityMoveLeft;
- (BOOL)accessibilityMoveRight;
- (BOOL)accessibilityCenter;
- (void)updateAccessibilityAppearance;

@end

@implementation BearBirdPadTouchStick

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
    BearBirdPadTouch_SetStick(dx / travel, -dy / travel);
}

- (void)pulseAccessibilityX:(float)x y:(float)y direction:(NSString *)direction {
    NSUInteger generation = ++self.accessibilityGeneration;
    CGPoint center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    CGFloat travel = self.bounds.size.width * 0.3;
    self.thumb.center = CGPointMake(center.x + x * travel, center.y - y * travel);
    self.accessibilityValue = direction;
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, direction);
    BearBirdPadTouch_SetStick(x, y);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 160 * NSEC_PER_MSEC),
                   dispatch_get_main_queue(), ^{
        if (generation == self.accessibilityGeneration && self.activeTouch == nil) {
            BearBirdPadTouch_SetStick(0.0f, 0.0f);
            self.accessibilityValue = @"Centered";
            self.thumb.center =
                CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
        }
    });
}

- (void)accessibilityIncrement {
    if (self.layoutEditing) {
        return;
    }
    [self pulseAccessibilityX:0.0f y:1.0f direction:@"Up"];
}

- (BOOL)accessibilityActivate {
    if (self.layoutEditing && self.layoutSelectionHandler != nil) {
        self.layoutSelectionHandler(self);
        return YES;
    }
    return NO;
}

- (void)accessibilityDecrement {
    if (self.layoutEditing) {
        return;
    }
    [self pulseAccessibilityX:0.0f y:-1.0f direction:@"Down"];
}

- (BOOL)accessibilityMoveUp {
    if (self.layoutEditing) {
        return YES;
    }
    [self pulseAccessibilityX:0.0f y:1.0f direction:@"Up"];
    return YES;
}

- (BOOL)accessibilityMoveDown {
    if (self.layoutEditing) {
        return YES;
    }
    [self pulseAccessibilityX:0.0f y:-1.0f direction:@"Down"];
    return YES;
}

- (BOOL)accessibilityMoveLeft {
    if (self.layoutEditing) {
        return YES;
    }
    [self pulseAccessibilityX:-1.0f y:0.0f direction:@"Left"];
    return YES;
}

- (BOOL)accessibilityMoveRight {
    if (self.layoutEditing) {
        return YES;
    }
    [self pulseAccessibilityX:1.0f y:0.0f direction:@"Right"];
    return YES;
}

- (BOOL)accessibilityCenter {
    if (self.layoutEditing) {
        return YES;
    }
    ++self.accessibilityGeneration;
    self.thumb.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    self.accessibilityValue = @"Centered";
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, self.accessibilityValue);
    BearBirdPadTouch_SetStick(0.0f, 0.0f);
    return YES;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (self.layoutEditing) {
        return;
    }
    if (self.activeTouch == nil) {
        self.activeTouch = touches.anyObject;
        [self updateForTouch:self.activeTouch];
    }
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (self.layoutEditing) {
        return;
    }
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
    BearBirdPadTouch_SetStick(0.0f, 0.0f);
}

@end

static BearBirdPadTouchButton *sMenuButton;
static std::atomic_bool sLayoutEditorActive(false);
static BOOL sLayoutEditorRequested;

@interface BearBirdPadTouchOverlay : UIView

@property(nonatomic, strong) BearBirdPadTouchStick *stick;
@property(nonatomic, strong) NSArray<BearBirdPadTouchButton *> *buttons;
@property(nonatomic, strong) BearBirdPadTouchButton *buttonA;
@property(nonatomic, strong) BearBirdPadTouchButton *buttonB;
@property(nonatomic, strong) BearBirdPadTouchButton *buttonZLeft;
@property(nonatomic, strong) BearBirdPadTouchButton *buttonZRight;
@property(nonatomic, strong) BearBirdPadTouchButton *buttonL;
@property(nonatomic, strong) BearBirdPadTouchButton *buttonR;
@property(nonatomic, strong) BearBirdPadTouchButton *buttonStart;
@property(nonatomic, strong) BearBirdPadTouchButton *cUp;
@property(nonatomic, strong) BearBirdPadTouchButton *cDown;
@property(nonatomic, strong) BearBirdPadTouchButton *cLeft;
@property(nonatomic, strong) BearBirdPadTouchButton *cRight;
@property(nonatomic, strong) BearBirdPadTouchButton *dUp;
@property(nonatomic, strong) BearBirdPadTouchButton *dDown;
@property(nonatomic, strong) BearBirdPadTouchButton *dLeft;
@property(nonatomic, strong) BearBirdPadTouchButton *dRight;
@property(nonatomic, assign) BOOL controllerConnected;
@property(nonatomic, assign) BOOL showL;
@property(nonatomic, assign) BOOL showDpad;
@property(nonatomic, assign) BOOL zLatched;
@property(nonatomic, assign) BOOL layoutEditing;
@property(nonatomic, strong) NSArray<UIView *> *editableControls;
@property(nonatomic, strong) NSMutableArray<UIGestureRecognizer *> *editGestures;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSArray<NSNumber *> *> *layoutCenters;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *layoutScales;
@property(nonatomic, strong) NSMutableSet<NSString *> *hiddenControls;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSValue *> *defaultSizes;
@property(nonatomic, copy) NSString *layoutProfile;
@property(nonatomic, strong) UIView *selectedControl;
@property(nonatomic, strong) UIView *editorPanel;
@property(nonatomic, strong) UILabel *editorLabel;
@property(nonatomic, strong) UISlider *sizeSlider;
@property(nonatomic, strong) UIButton *visibilityButton;
@property(nonatomic, strong) UIButton *resetButton;
@property(nonatomic, strong) UIButton *doneButton;

- (void)cancelAllInputs;
- (void)beginLayoutEditing;
- (void)endLayoutEditing;
- (void)setOptionalControlsShowL:(BOOL)showL showDpad:(BOOL)showDpad;
- (void)updateControllerAppearance;
- (BOOL)releaseLatchedZ;
- (void)engageLatchedZ;

@end

@implementation BearBirdPadTouchOverlay

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

        _stick = [[BearBirdPadTouchStick alloc] initWithFrame:CGRectZero];
        _buttonA = [[BearBirdPadTouchButton alloc] initWithLabel:@"A"
                                         accessibilityLabel:@"A button"
                                                       mask:ButtonA
                                                       pill:NO
                                                      color:blue];
        _buttonB = [[BearBirdPadTouchButton alloc] initWithLabel:@"B"
                                         accessibilityLabel:@"B button"
                                                       mask:ButtonB
                                                       pill:NO
                                                      color:green];
        _buttonZLeft = [[BearBirdPadTouchButton alloc] initWithLabel:@"Z"
                                             accessibilityLabel:@"Left Z trigger"
                                                           mask:ButtonZ
                                                           pill:YES
                                                          color:nil];
        _buttonZRight = [[BearBirdPadTouchButton alloc] initWithLabel:@"Z"
                                              accessibilityLabel:@"Right Z trigger"
                                                            mask:ButtonZ
                                                            pill:NO
                                                           color:nil];
        _buttonL = [[BearBirdPadTouchButton alloc] initWithLabel:@"L"
                                         accessibilityLabel:@"L shoulder button"
                                                       mask:ButtonL
                                                       pill:YES
                                                      color:nil];
        _buttonR = [[BearBirdPadTouchButton alloc] initWithLabel:@"R"
                                         accessibilityLabel:@"R shoulder button"
                                                       mask:ButtonR
                                                       pill:YES
                                                      color:nil];
        _buttonStart =
            [[BearBirdPadTouchButton alloc] initWithLabel:@"START"
                                  accessibilityLabel:@"Start button"
                                                mask:ButtonStart
                                                pill:YES
                                               color:red];
        _cUp = [[BearBirdPadTouchButton alloc] initWithLabel:@"▲"
                                      accessibilityLabel:@"C Up button"
                                                    mask:ButtonCUp
                                                    pill:NO
                                                   color:amber];
        _cDown = [[BearBirdPadTouchButton alloc] initWithLabel:@"▼"
                                        accessibilityLabel:@"C Down button"
                                                      mask:ButtonCDown
                                                      pill:NO
                                                     color:amber];
        _cLeft = [[BearBirdPadTouchButton alloc] initWithLabel:@"◀"
                                        accessibilityLabel:@"C Left button"
                                                      mask:ButtonCLeft
                                                      pill:NO
                                                     color:amber];
        _cRight = [[BearBirdPadTouchButton alloc] initWithLabel:@"▶"
                                         accessibilityLabel:@"C Right button"
                                                       mask:ButtonCRight
                                                       pill:NO
                                                      color:amber];
        _dUp = [[BearBirdPadTouchButton alloc] initWithLabel:@"▲"
                                      accessibilityLabel:@"D-pad Up"
                                                    mask:ButtonDpadUp
                                                    pill:NO
                                                   color:nil];
        _dDown = [[BearBirdPadTouchButton alloc] initWithLabel:@"▼"
                                        accessibilityLabel:@"D-pad Down"
                                                      mask:ButtonDpadDown
                                                      pill:NO
                                                     color:nil];
        _dLeft = [[BearBirdPadTouchButton alloc] initWithLabel:@"◀"
                                        accessibilityLabel:@"D-pad Left"
                                                      mask:ButtonDpadLeft
                                                      pill:NO
                                                     color:nil];
        _dRight = [[BearBirdPadTouchButton alloc] initWithLabel:@"▶"
                                         accessibilityLabel:@"D-pad Right"
                                                       mask:ButtonDpadRight
                                                       pill:NO
                                                      color:nil];

        _buttons = @[
            _buttonA, _buttonB, _buttonZLeft, _buttonZRight, _buttonL, _buttonR, _buttonStart,
            _cUp, _cDown, _cLeft, _cRight, _dUp, _dDown, _dLeft, _dRight
        ];
        _layoutCenters = [NSMutableDictionary dictionary];
        _layoutScales = [NSMutableDictionary dictionary];
        _hiddenControls = [NSMutableSet set];
        _defaultSizes = [NSMutableDictionary dictionary];
        _editGestures = [NSMutableArray array];

        _stick.accessibilityIdentifier = @"stick";
        _buttonA.accessibilityIdentifier = @"a";
        _buttonB.accessibilityIdentifier = @"b";
        _buttonZLeft.accessibilityIdentifier = @"z-left";
        _buttonZRight.accessibilityIdentifier = @"z-right";
        _buttonL.accessibilityIdentifier = @"l";
        _buttonR.accessibilityIdentifier = @"r";
        _buttonStart.accessibilityIdentifier = @"start";
        _cUp.accessibilityIdentifier = @"c-up";
        _cDown.accessibilityIdentifier = @"c-down";
        _cLeft.accessibilityIdentifier = @"c-left";
        _cRight.accessibilityIdentifier = @"c-right";
        _dUp.accessibilityIdentifier = @"d-up";
        _dDown.accessibilityIdentifier = @"d-down";
        _dLeft.accessibilityIdentifier = @"d-left";
        _dRight.accessibilityIdentifier = @"d-right";
        _editableControls = @[
            _stick, _buttonA, _buttonB, _buttonZLeft, _buttonZRight, _buttonL, _buttonR,
            _buttonStart, _cUp, _cDown, _cLeft, _cRight, _dUp, _dDown, _dLeft, _dRight
        ];
        __weak BearBirdPadTouchOverlay *weakSelf = self;
        void (^selectForAccessibility)(UIView *) = ^(UIView *control) {
            [weakSelf selectControl:control];
        };
        _stick.layoutSelectionHandler = selectForAccessibility;
        for (BearBirdPadTouchButton *button in _buttons) {
            button.layoutSelectionHandler = selectForAccessibility;
        }
        BOOL (^releaseLatchedZ)(void) = ^BOOL {
            return [weakSelf releaseLatchedZ];
        };
        void (^engageLatchedZ)(void) = ^{
            [weakSelf engageLatchedZ];
        };
        for (BearBirdPadTouchButton *button in @[ _buttonZLeft, _buttonZRight ]) {
            button.supportsLongPressLatch = YES;
            button.releaseLatchHandler = releaseLatchedZ;
            button.engageLatchHandler = engageLatchedZ;
            button.accessibilityHint =
                @"Hold for two seconds to keep Z held. Tap either Z to release.";
        }

        [self addSubview:_stick];
        for (BearBirdPadTouchButton *button in _buttons) {
            [self addSubview:button];
        }
        _buttonL.hidden = YES;
        _dUp.hidden = YES;
        _dDown.hidden = YES;
        _dLeft.hidden = YES;
        _dRight.hidden = YES;
        [self installLayoutEditor];
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

- (void)engageLatchedZ {
    if (self.zLatched) {
        return;
    }
    self.zLatched = YES;
    self.buttonZLeft.latched = YES;
    self.buttonZRight.latched = YES;
    BearBirdPadTouch_SetButton(ButtonZ, 1);
    UIAccessibilityPostNotification(
        UIAccessibilityAnnouncementNotification, @"Z held");
}

- (BOOL)releaseLatchedZ {
    if (!self.zLatched) {
        return NO;
    }
    self.zLatched = NO;
    self.buttonZLeft.latched = NO;
    self.buttonZRight.latched = NO;
    BearBirdPadTouch_SetButton(ButtonZ, 0);
    UIAccessibilityPostNotification(
        UIAccessibilityAnnouncementNotification, @"Z released");
    return YES;
}

- (void)setOptionalControlsShowL:(BOOL)showL showDpad:(BOOL)showDpad {
    self.showL = showL;
    self.showDpad = showDpad;
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
    [self setNeedsLayout];
}

- (UIButton *)editorButtonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
    button.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.14];
    button.layer.cornerRadius = 10.0;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)installLayoutEditor {
    self.editorPanel = [[UIView alloc] initWithFrame:CGRectZero];
    self.editorPanel.accessibilityIdentifier = @"touch-layout-editor";
    self.editorPanel.backgroundColor = [UIColor colorWithWhite:0.04 alpha:0.9];
    self.editorPanel.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.24].CGColor;
    self.editorPanel.layer.borderWidth = 1.0;
    self.editorPanel.layer.cornerRadius = 16.0;
    self.editorPanel.hidden = YES;

    self.editorLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.editorLabel.textColor = UIColor.whiteColor;
    self.editorLabel.numberOfLines = 2;
    self.editorLabel.adjustsFontSizeToFitWidth = YES;
    self.editorLabel.minimumScaleFactor = 0.75;
    self.editorLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
    [self.editorPanel addSubview:self.editorLabel];

    self.sizeSlider = [[UISlider alloc] initWithFrame:CGRectZero];
    self.sizeSlider.accessibilityIdentifier = @"touch-layout-size";
    self.sizeSlider.accessibilityLabel = @"Selected control size";
    self.sizeSlider.minimumValue = 0.70f;
    self.sizeSlider.maximumValue = 1.50f;
    self.sizeSlider.value = 1.0f;
    self.sizeSlider.minimumTrackTintColor =
        [UIColor colorWithRed:0.36 green:0.72 blue:1.0 alpha:1.0];
    [self.sizeSlider addTarget:self
                        action:@selector(editorSizeChanged:)
              forControlEvents:UIControlEventValueChanged];
    [self.editorPanel addSubview:self.sizeSlider];

    self.visibilityButton =
        [self editorButtonWithTitle:@"Hide" action:@selector(toggleSelectedVisibility)];
    self.resetButton =
        [self editorButtonWithTitle:@"Reset" action:@selector(resetCurrentLayout)];
    self.doneButton =
        [self editorButtonWithTitle:@"Done" action:@selector(endLayoutEditing)];
    self.visibilityButton.accessibilityIdentifier = @"touch-layout-visibility";
    self.resetButton.accessibilityIdentifier = @"touch-layout-reset";
    self.doneButton.accessibilityIdentifier = @"touch-layout-done";
    self.doneButton.backgroundColor =
        [UIColor colorWithRed:0.10 green:0.48 blue:0.92 alpha:0.9];
    [self.editorPanel addSubview:self.visibilityButton];
    [self.editorPanel addSubview:self.resetButton];
    [self.editorPanel addSubview:self.doneButton];
    [self addSubview:self.editorPanel];

    for (UIView *control in self.editableControls) {
        UIPanGestureRecognizer *pan =
            [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(moveControl:)];
        UITapGestureRecognizer *tap =
            [[UITapGestureRecognizer alloc] initWithTarget:self
                                                    action:@selector(selectControlGesture:)];
        pan.enabled = NO;
        tap.enabled = NO;
        [control addGestureRecognizer:pan];
        [control addGestureRecognizer:tap];
        [self.editGestures addObject:pan];
        [self.editGestures addObject:tap];
    }
}

- (void)layoutEditorPanel {
    if (self.editorPanel.hidden) {
        return;
    }
    UIEdgeInsets safe = self.safeAreaInsets;
    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat panelWidth = MIN(620.0, width - safe.left - safe.right - 20.0);
    CGFloat panelHeight = CGRectGetHeight(self.bounds) < 560.0 ? 76.0 : 86.0;
    self.editorPanel.frame = CGRectMake(
        CGRectGetMidX(self.bounds) - panelWidth * 0.5,
        safe.top + 8.0,
        panelWidth,
        panelHeight);

    CGFloat inset = 12.0;
    CGFloat buttonWidth = 70.0;
    CGFloat gap = 8.0;
    CGFloat contentHeight = panelHeight - inset * 2.0;
    CGFloat trailingButtonsWidth = buttonWidth * 3.0 + gap * 2.0;
    CGFloat labelWidth = MIN(150.0, panelWidth * 0.23);
    CGFloat sliderX = inset + labelWidth + gap;
    CGFloat sliderWidth =
        panelWidth - inset * 2.0 - labelWidth - gap - trailingButtonsWidth - gap;
    self.editorLabel.frame = CGRectMake(inset, inset, labelWidth, contentHeight);
    self.sizeSlider.frame =
        CGRectMake(sliderX, inset, MAX(80.0, sliderWidth), contentHeight);

    CGFloat buttonX = panelWidth - inset - trailingButtonsWidth;
    for (UIButton *button in
         @[ self.visibilityButton, self.resetButton, self.doneButton ]) {
        button.frame = CGRectMake(buttonX, inset, buttonWidth, contentHeight);
        buttonX += buttonWidth + gap;
    }
}

- (NSString *)profileForCompact:(BOOL)compact {
    return compact ? @"phone-v1" : @"tablet-v1";
}

- (NSString *)storageKeyForProfile:(NSString *)profile {
    return [@"BearBirdPad.TouchLayout." stringByAppendingString:profile];
}

- (void)loadLayoutForProfile:(NSString *)profile {
    if ([self.layoutProfile isEqualToString:profile]) {
        return;
    }
    self.layoutProfile = profile;
    [self.layoutCenters removeAllObjects];
    [self.layoutScales removeAllObjects];
    [self.hiddenControls removeAllObjects];

    NSDictionary *stored =
        [NSUserDefaults.standardUserDefaults dictionaryForKey:[self storageKeyForProfile:profile]];
    NSDictionary *centers = stored[@"centers"];
    NSDictionary *scales = stored[@"scales"];
    NSArray *hidden = stored[@"hidden"];
    if ([centers isKindOfClass:NSDictionary.class]) {
        [self.layoutCenters addEntriesFromDictionary:centers];
    }
    if ([scales isKindOfClass:NSDictionary.class]) {
        [self.layoutScales addEntriesFromDictionary:scales];
    }
    if ([hidden isKindOfClass:NSArray.class]) {
        for (id key in hidden) {
            if ([key isKindOfClass:NSString.class]) {
                [self.hiddenControls addObject:key];
            }
        }
    }
}

- (void)saveCurrentLayout {
    if (self.layoutProfile.length == 0) {
        return;
    }
    NSString *storageKey = [self storageKeyForProfile:self.layoutProfile];
    if (self.layoutCenters.count == 0 &&
        self.layoutScales.count == 0 &&
        self.hiddenControls.count == 0) {
        [NSUserDefaults.standardUserDefaults removeObjectForKey:storageKey];
        return;
    }
    NSArray<NSString *> *hidden =
        [self.hiddenControls.allObjects sortedArrayUsingSelector:@selector(compare:)];
    NSDictionary *stored = @{
        @"centers": [self.layoutCenters copy],
        @"scales": [self.layoutScales copy],
        @"hidden": hidden,
    };
    [NSUserDefaults.standardUserDefaults
        setObject:stored
           forKey:storageKey];
}

- (BOOL)isOptionalControlDisabled:(UIView *)control {
    if (control == self.buttonL) {
        return !self.showL;
    }
    return !self.showDpad &&
        (control == self.dUp || control == self.dDown ||
         control == self.dLeft || control == self.dRight);
}

- (void)clampControlToSafeBounds:(UIView *)control {
    UIEdgeInsets safe = self.safeAreaInsets;
    CGFloat halfWidth = CGRectGetWidth(control.bounds) * 0.5;
    CGFloat halfHeight = CGRectGetHeight(control.bounds) * 0.5;
    CGFloat minX = safe.left + halfWidth + 4.0;
    CGFloat maxX = CGRectGetWidth(self.bounds) - safe.right - halfWidth - 4.0;
    CGFloat minY = safe.top + halfHeight + 4.0;
    CGFloat maxY = CGRectGetHeight(self.bounds) - safe.bottom - halfHeight - 4.0;
    control.center = CGPointMake(
        std::clamp(control.center.x, minX, MAX(minX, maxX)),
        std::clamp(control.center.y, minY, MAX(minY, maxY)));
}

- (void)applySavedLayoutForCompact:(BOOL)compact {
    [self loadLayoutForProfile:[self profileForCompact:compact]];
    [self.defaultSizes removeAllObjects];
    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat height = CGRectGetHeight(self.bounds);
    for (UIView *control in self.editableControls) {
        NSString *key = control.accessibilityIdentifier;
        if (key.length == 0) {
            continue;
        }
        CGSize defaultSize = control.bounds.size;
        self.defaultSizes[key] = [NSValue valueWithCGSize:defaultSize];
        NSNumber *storedScale = self.layoutScales[key];
        CGFloat scale = [storedScale isKindOfClass:NSNumber.class]
            ? std::clamp(storedScale.doubleValue, 0.70, 1.50)
            : 1.0;
        control.bounds = CGRectMake(
            0.0, 0.0, defaultSize.width * scale, defaultSize.height * scale);

        NSArray<NSNumber *> *center = self.layoutCenters[key];
        if ([center isKindOfClass:NSArray.class] && center.count == 2 &&
            [center[0] isKindOfClass:NSNumber.class] &&
            [center[1] isKindOfClass:NSNumber.class]) {
            control.center =
                CGPointMake(center[0].doubleValue * width, center[1].doubleValue * height);
        }
        [self clampControlToSafeBounds:control];

        BOOL hidden =
            [self.hiddenControls containsObject:key] || [self isOptionalControlDisabled:control];
        control.hidden = self.layoutEditing ? NO : hidden;
        control.alpha = self.layoutEditing && hidden ? 0.28 : 1.0;
        BOOL selected = self.layoutEditing && control == self.selectedControl;
        control.layer.shadowColor =
            (selected
                ? [UIColor colorWithRed:1.0 green:0.78 blue:0.16 alpha:1.0]
                : UIColor.blackColor).CGColor;
        control.layer.shadowRadius = selected ? 8.0 : 3.0;
        control.layer.shadowOpacity = selected ? 1.0 : 0.72;
        control.layer.shadowOffset = CGSizeZero;
    }
    [self layoutEditorPanel];
    [self bringSubviewToFront:self.editorPanel];
}

- (void)selectControl:(UIView *)control {
    if (!self.layoutEditing || control == nil) {
        return;
    }
    self.selectedControl = control;
    NSString *label = control.accessibilityLabel;
    if (label.length == 0) {
        label = control.accessibilityIdentifier;
    }
    self.editorLabel.text =
        [NSString stringWithFormat:@"%@\nDrag to move • Size", label];
    NSString *key = control.accessibilityIdentifier;
    NSNumber *scale = self.layoutScales[key];
    self.sizeSlider.value =
        [scale isKindOfClass:NSNumber.class] ? scale.floatValue : 1.0f;

    BOOL optionalDisabled = [self isOptionalControlDisabled:control];
    BOOL hidden = [self.hiddenControls containsObject:key];
    NSString *visibilityTitle = optionalDisabled ? @"Settings" : (hidden ? @"Show" : @"Hide");
    [self.visibilityButton setTitle:visibilityTitle forState:UIControlStateNormal];
    self.visibilityButton.enabled =
        !optionalDisabled && ![key isEqualToString:@"stick"];
    self.visibilityButton.alpha = self.visibilityButton.enabled ? 1.0 : 0.4;
    [self setNeedsLayout];
}

- (void)selectControlGesture:(UITapGestureRecognizer *)gesture {
    [self selectControl:gesture.view];
}

- (void)moveControl:(UIPanGestureRecognizer *)gesture {
    UIView *control = gesture.view;
    if (!self.layoutEditing || control == nil) {
        return;
    }
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [self selectControl:control];
    }
    CGPoint translation = [gesture translationInView:self];
    control.center = CGPointMake(
        control.center.x + translation.x,
        control.center.y + translation.y);
    [gesture setTranslation:CGPointZero inView:self];
    [self clampControlToSafeBounds:control];
    self.layoutCenters[control.accessibilityIdentifier] = @[
        @(control.center.x / CGRectGetWidth(self.bounds)),
        @(control.center.y / CGRectGetHeight(self.bounds)),
    ];
}

- (void)editorSizeChanged:(UISlider *)slider {
    UIView *control = self.selectedControl;
    NSString *key = control.accessibilityIdentifier;
    NSValue *sizeValue = self.defaultSizes[key];
    if (control == nil || key.length == 0 || sizeValue == nil) {
        return;
    }
    CGFloat scale = std::clamp((CGFloat)slider.value, 0.70, 1.50);
    self.layoutScales[key] = @(scale);
    CGSize baseSize = sizeValue.CGSizeValue;
    control.bounds =
        CGRectMake(0.0, 0.0, baseSize.width * scale, baseSize.height * scale);
    [self clampControlToSafeBounds:control];
    self.layoutCenters[key] = @[
        @(control.center.x / CGRectGetWidth(self.bounds)),
        @(control.center.y / CGRectGetHeight(self.bounds)),
    ];
}

- (void)toggleSelectedVisibility {
    NSString *key = self.selectedControl.accessibilityIdentifier;
    if (key.length == 0 || [key isEqualToString:@"stick"] ||
        [self isOptionalControlDisabled:self.selectedControl]) {
        return;
    }
    if ([self.hiddenControls containsObject:key]) {
        [self.hiddenControls removeObject:key];
    } else {
        [self.hiddenControls addObject:key];
    }
    [self selectControl:self.selectedControl];
}

- (void)resetCurrentLayout {
    if (self.layoutProfile.length == 0) {
        return;
    }
    [self.layoutCenters removeAllObjects];
    [self.layoutScales removeAllObjects];
    [self.hiddenControls removeAllObjects];
    [NSUserDefaults.standardUserDefaults
        removeObjectForKey:[self storageKeyForProfile:self.layoutProfile]];
    [self setNeedsLayout];
    [self selectControl:self.buttonA];
}

- (void)beginLayoutEditing {
    if (self.layoutEditing) {
        return;
    }
    [self cancelAllInputs];
    self.layoutEditing = YES;
    self.stick.layoutEditing = YES;
    for (BearBirdPadTouchButton *button in self.buttons) {
        button.layoutEditing = YES;
    }
    for (UIGestureRecognizer *gesture in self.editGestures) {
        gesture.enabled = YES;
    }
    self.editorPanel.hidden = NO;
    sLayoutEditorActive.store(true);
    sMenuButton.hidden = YES;
    [self selectControl:self.buttonA];
    [self setNeedsLayout];
    SDL_Log("[BearBirdPad] touch layout editor opened");
}

- (void)endLayoutEditing {
    if (!self.layoutEditing) {
        return;
    }
    [self saveCurrentLayout];
    self.layoutEditing = NO;
    self.stick.layoutEditing = NO;
    for (BearBirdPadTouchButton *button in self.buttons) {
        button.layoutEditing = NO;
    }
    for (UIGestureRecognizer *gesture in self.editGestures) {
        gesture.enabled = NO;
    }
    self.editorPanel.hidden = YES;
    self.selectedControl = nil;
    sLayoutEditorActive.store(false);
    sMenuButton.hidden = NO;
    [self setNeedsLayout];
    SDL_Log("[BearBirdPad] touch layout saved");
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
    [self applySavedLayoutForCompact:self.bounds.size.height < 560.0];
}

- (void)cancelAllInputs {
    [self.stick cancelInput];
    for (BearBirdPadTouchButton *button in self.buttons) {
        [button cancelInput];
    }
    self.zLatched = NO;
    self.buttonZLeft.latched = NO;
    self.buttonZRight.latched = NO;
    BearBirdPadTouch_ReleaseAll();
}

@end

@interface BearBirdPadCameraGesture : UIGestureRecognizer

- (CGPoint)consumeTranslation;

@end

@implementation BearBirdPadCameraGesture {
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

@interface BearBirdPadCameraGestureDelegate : NSObject <UIGestureRecognizerDelegate>
@end

static BearBirdPadTouchOverlay *sOverlay;
static BearBirdPadCameraGesture *sCameraGesture;
static BearBirdPadCameraGestureDelegate *sCameraDelegate;
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
    BearBirdPadTouch_ReleaseAll();
}

@implementation BearBirdPadCameraGestureDelegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
       shouldReceiveTouch:(UITouch *)touch {
    if (sOverlay == nil || sMenuVisible.load() || sLayoutEditorActive.load()) {
        return NO;
    }
    UIView *view = touch.view;
    while (view != nil) {
        if ([view isKindOfClass:BearBirdPadTouchButton.class] ||
            [view isKindOfClass:BearBirdPadTouchStick.class]) {
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

static void handle_camera_pan(BearBirdPadCameraGesture *gesture) {
    if (gesture.state == UIGestureRecognizerStateBegan ||
        gesture.state == UIGestureRecognizerStateChanged) {
        CGPoint translation = [gesture consumeTranslation];
        float x = std::clamp(static_cast<float>(translation.x / 60.0), -1.0f, 1.0f);
        float y = std::clamp(static_cast<float>(-translation.y / 60.0), -1.0f, 1.0f);
        BearBirdPadTouch_SetCamera(x, y);
        NSUInteger generation = ++sCameraGeneration;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 40 * NSEC_PER_MSEC),
                       dispatch_get_main_queue(), ^{
            if (generation == sCameraGeneration) {
                BearBirdPadTouch_SetCamera(0.0f, 0.0f);
            }
        });
    }
    if (gesture.state == UIGestureRecognizerStateEnded ||
        gesture.state == UIGestureRecognizerStateCancelled ||
        gesture.state == UIGestureRecognizerStateFailed) {
        ++sCameraGeneration;
        BearBirdPadTouch_SetCamera(0.0f, 0.0f);
    }
}

@interface BearBirdPadMenuTapTarget : NSObject
- (void)tapped;
@end

@interface BearBirdPadCameraTarget : NSObject
- (void)panned:(BearBirdPadCameraGesture *)gesture;
@end

static BearBirdPadMenuTapTarget *sMenuTapTarget;
static BearBirdPadCameraTarget *sCameraTarget;

@implementation BearBirdPadMenuTapTarget
- (void)tapped {
    push_menu_toggle();
}
@end

@implementation BearBirdPadCameraTarget
- (void)panned:(BearBirdPadCameraGesture *)gesture {
    handle_camera_pan(gesture);
}
@end

static void install_menu_button(UIWindow *window) {
    if (sMenuButton == nil) {
        sMenuTapTarget = [[BearBirdPadMenuTapTarget alloc] init];
        sMenuButton =
            [[BearBirdPadTouchButton alloc] initWithLabel:@"•••"
                                  accessibilityLabel:@"BearBirdPad menu"
                                                mask:0
                                                pill:NO
                                               color:nil];
        sMenuButton.accessibilityHint = @"Opens or closes the BearBirdPad menu.";
        [sMenuButton addGestureRecognizer:
            [[UITapGestureRecognizer alloc] initWithTarget:sMenuTapTarget action:@selector(tapped)]];
    }
    if (sMenuButton.superview != window) {
        [sMenuButton removeFromSuperview];
        [window addSubview:sMenuButton];
    }
    CGFloat size = 38.0;
    CGFloat edgeInset = 20.0;
    CGFloat halfSize = size * 0.5;
    UIEdgeInsets safe = window.safeAreaInsets;
    sMenuButton.bounds = CGRectMake(0.0, 0.0, size, size);
    sMenuButton.center = CGPointMake(
        window.bounds.size.width - safe.right - edgeInset - halfSize,
        safe.top + edgeInset + halfSize);
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
        sCameraDelegate = [[BearBirdPadCameraGestureDelegate alloc] init];
        sCameraTarget = [[BearBirdPadCameraTarget alloc] init];
        sCameraGesture =
            [[BearBirdPadCameraGesture alloc] initWithTarget:sCameraTarget action:@selector(panned:)];
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

    BOOL unavailable = !sEnabled.load() ||
        (sControllerConnected.load() && sHideWhenControllerConnected.load());
    if (unavailable) {
        sLayoutEditorRequested = NO;
    }
    if (unavailable || sMenuVisible.load()) {
        [sOverlay endLayoutEditing];
        cancel_all_inputs();
        [sOverlay removeFromSuperview];
        sOverlay = nil;
        sCameraGesture.enabled = NO;
        [window bringSubviewToFront:sMenuButton];
        return;
    }

    if (sOverlay == nil) {
        sOverlay = [[BearBirdPadTouchOverlay alloc] initWithFrame:window.bounds];
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
    if (sLayoutEditorRequested) {
        sLayoutEditorRequested = NO;
        [sOverlay beginLayoutEditing];
    }
}

extern "C" int BearBirdPadTouch_Available(void) {
    return 1;
}

extern "C" int BearBirdPadTouch_Enabled(void) {
    return sEnabled.load() ? 1 : 0;
}

extern "C" int BearBirdPadTouch_HideWhenControllerConnected(void) {
    return sHideWhenControllerConnected.load() ? 1 : 0;
}

extern "C" int BearBirdPadTouch_ShowDpad(void) {
    return sShowDpad.load() ? 1 : 0;
}

extern "C" int BearBirdPadTouch_ShowL(void) {
    return sShowL.load() ? 1 : 0;
}

extern "C" void BearBirdPadTouch_BeginLayoutEditing(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!sEnabled.load()) {
            SDL_Log("[BearBirdPad] layout editor requires Touch Controls");
            return;
        }
        if (sControllerConnected.load() && sHideWhenControllerConnected.load()) {
            SDL_Log("[BearBirdPad] layout editor unavailable while touch controls are hidden");
            return;
        }
        sLayoutEditorRequested = YES;
        if (sMenuVisible.load()) {
            push_menu_toggle();
        } else {
            apply_overlay_state();
        }
    });
}

extern "C" void BearBirdPadTouch_Install(void) {
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

extern "C" void BearBirdPadTouch_SetEnabled(int enabled) {
    sEnabled.store(enabled != 0);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!sEnabled.load()) {
            sLayoutEditorRequested = NO;
            cancel_all_inputs();
        }
        save_control_settings();
        apply_overlay_state();
    });
}

extern "C" void BearBirdPadTouch_SetHideWhenControllerConnected(int hidden) {
    sHideWhenControllerConnected.store(hidden != 0);
    dispatch_async(dispatch_get_main_queue(), ^{
        save_control_settings();
        apply_overlay_state();
    });
}

extern "C" void BearBirdPadTouch_SetShowDpad(int visible) {
    sShowDpad.store(visible != 0);
    dispatch_async(dispatch_get_main_queue(), ^{
        save_control_settings();
        apply_overlay_state();
    });
}

extern "C" void BearBirdPadTouch_SetShowL(int visible) {
    sShowL.store(visible != 0);
    dispatch_async(dispatch_get_main_queue(), ^{
        save_control_settings();
        apply_overlay_state();
    });
}

extern "C" void BearBirdPadTouch_SetMenuVisible(int visible) {
    bool newValue = visible != 0;
    if (sMenuVisible.exchange(newValue) == newValue) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        apply_overlay_state();
    });
}

extern "C" void BearBirdPadTouch_SetControllerConnected(int connected) {
    bool newValue = connected != 0;
    if (sControllerConnected.exchange(newValue) == newValue) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        apply_overlay_state();
    });
}
