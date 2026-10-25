#import "SGMarquee.h"

// Points a second the text moves at, the rest at each end, and the fade over the edge it runs past.
static const CGFloat kSpeed = 30, kFade = 16;
static const CFTimeInterval kRest = 2;
static NSString *const kScroll = @"sg.marquee";

@implementation SGMarqueeLabel {
    UIView *_run;
    UILabel *_label, *_outer, *_edge;
    CAGradientLayer *_fade;
    NSString *_text;
    UIColor *_textColor, *_outlineColor;
    CGFloat _scrolled;   // how far the running animation travels, 0 while still
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.clipsToBounds = YES;
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitStaticText;
    _run = [UIView new];
    _run.userInteractionEnabled = NO;
    [self addSubview:_run];
    _label = [UILabel new];
    [_run addSubview:_label];
    _fade = [CAGradientLayer layer];
    _fade.startPoint = CGPointMake(0, 0.5);
    _fade.endPoint = CGPointMake(1, 0.5);
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(setNeedsLayout)
                                               name:UIAccessibilityReduceMotionStatusDidChangeNotification object:nil];
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (NSString *)text { return _text; }
- (UIFont *)font { return _label.font; }
- (UIColor *)textColor { return _textColor; }
- (UIColor *)outlineColor { return _outlineColor; }

static NSAttributedString *strokeLine(NSString *text, UIFont *font, UIColor *stroke, CGFloat width) {
    if (!text) text = @"";
    if (!font) font = [UIFont systemFontOfSize:17];
    if (!stroke) stroke = UIColor.blackColor;
    return [[NSAttributedString alloc] initWithString:text attributes:@{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: UIColor.clearColor,
        NSStrokeColorAttributeName: stroke,
        NSStrokeWidthAttributeName: @(width),
    }];
}

static BOOL lightColor(UIColor *color) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) return YES;
    return 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.62;
}

// The stroke sits under the fill, so the letters keep their own weight. A white stroke on white
// letters gets a thin dark edge between them, or the white ring would just look bolder.
- (void)applyLabel {
    UIFont *font = _label.font ?: [UIFont systemFontOfSize:17];
    UIColor *fill = _textColor ?: UIColor.labelColor;
    _label.attributedText = nil;
    _label.text = _text;
    _label.textColor = fill;
    _label.font = font;
    if (!_outlineColor || !_text.length) {
        _outer.hidden = _edge.hidden = YES;
        return;
    }
    if (!_outer) {
        _outer = [UILabel new];
        _edge = [UILabel new];
        _outer.clipsToBounds = _edge.clipsToBounds = NO;
        [_run insertSubview:_outer belowSubview:_label];
        [_run insertSubview:_edge aboveSubview:_outer];
    }
    _outer.hidden = NO;
    _outer.font = font;
    BOOL separate = lightColor(_outlineColor) && lightColor(fill);
    _outer.attributedText = strokeLine(_text, font, _outlineColor, separate ? 6 : 3.5);
    _edge.hidden = !separate;
    if (separate) {
        _edge.font = font;
        _edge.attributedText = strokeLine(_text, font, UIColor.blackColor, 3.2);
    }
}

- (void)setText:(NSString *)text {
    if (text == _text || [text isEqualToString:_text]) return;
    _text = [text copy];
    [self applyLabel];
    self.accessibilityLabel = text;
    _scrolled = -1;   // starts over from its start
    [self setNeedsLayout];
}

- (void)setFont:(UIFont *)font {
    _label.font = font;
    [self applyLabel];
    _scrolled = -1;
    [self setNeedsLayout];
}

- (void)setTextColor:(UIColor *)textColor {
    _textColor = textColor;
    [self applyLabel];
}

- (void)setOutlineColor:(UIColor *)outlineColor {
    if (outlineColor == _outlineColor || [outlineColor isEqual:_outlineColor]) return;
    _outlineColor = outlineColor;
    [self applyLabel];
    _scrolled = -1;
    [self setNeedsLayout];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    // A view out of its window loses its animations; back in one, it scrolls again.
    _scrolled = -1;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    CGFloat textWidth = ceil([_label sizeThatFits:CGSizeMake(CGFLOAT_MAX, size.height)].width);
    CGFloat overflow = textWidth - size.width;
    BOOL scrolls = overflow > 0.5 && !UIAccessibilityIsReduceMotionEnabled() && self.window;
    NSLineBreakMode wrap = scrolls ? NSLineBreakByClipping : NSLineBreakByTruncatingTail;
    _label.lineBreakMode = _outer.lineBreakMode = _edge.lineBreakMode = wrap;
    CGRect frame = CGRectMake(0, 0, scrolls ? textWidth : size.width, size.height);
    if (!CGRectEqualToRect(_run.frame, frame)) _run.frame = frame;
    _label.frame = _outer.frame = _edge.frame = _run.bounds;

    self.layer.mask = scrolls ? _fade : nil;
    if (scrolls) {
        _fade.frame = self.bounds;
        CGFloat edge = MIN(kFade / size.width, 0.2);
        // The trailing edge fades, where the text runs on; its start stays crisp at rest.
        _fade.colors = @[(id)UIColor.blackColor.CGColor, (id)UIColor.blackColor.CGColor, (id)UIColor.clearColor.CGColor];
        _fade.locations = @[@0, @(1 - edge), @1];
    }

    CGFloat travel = scrolls ? overflow + kFade : 0;
    if (travel == _scrolled && [_run.layer animationForKey:kScroll]) return;
    _scrolled = travel;
    [_run.layer removeAnimationForKey:kScroll];
    if (!scrolls) return;
    CFTimeInterval glide = travel / kSpeed, total = 2 * (kRest + glide);
    CAKeyframeAnimation *scroll = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
    scroll.values = @[@0, @0, @(-travel), @(-travel), @0];
    scroll.keyTimes = @[@0, @(kRest / total), @((kRest + glide) / total), @((2 * kRest + glide) / total), @1];
    scroll.timingFunctions = @[
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear],
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut],
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear],
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut],
    ];
    scroll.duration = total;
    scroll.repeatCount = HUGE_VALF;
    // A text's glide needs no more than the display's base rate.
    if (@available(iOS 15.0, *)) scroll.preferredFrameRateRange = CAFrameRateRangeMake(30, 60, 60);
    [_run.layer addAnimation:scroll forKey:kScroll];
}

@end
