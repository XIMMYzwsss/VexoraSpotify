#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRRepaint.h"
#import "Redesigned/Kit/SGRBridges.h"
#import "LyricsLook.h"

static char kPageGlassKey, kBackdropKey, kObsKey;
static const NSInteger kLyricsSolidBackgroundTag = 88002;
static const NSInteger kLyricsRadialGlowTagA = 88003;
static const NSInteger kLyricsRadialGlowTagB = 88004;

static UIView *lyricsShell(UIView *page) {
    return page;
}

static void hideSpotifyGlass(UIView *root, UIView *backdrop) {
    NSMutableArray<UIView *> *stack = [root.subviews mutableCopy];
    while (stack.count) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        if (v == backdrop) continue;
        if ([v isKindOfClass:UIVisualEffectView.class]) v.hidden = YES;
        [stack addObjectsFromArray:v.subviews];
    }
}

static UIColor *averageRGB(uint8_t *px, int count) {
    if (count <= 0) return UIColor.whiteColor;
    double r = 0, g = 0, b = 0;
    for (int i = 0; i < count; i++) {
        r += px[i * 4];
        g += px[i * 4 + 1];
        b += px[i * 4 + 2];
    }
    r /= count;
    g /= count;
    b /= count;
    return [UIColor colorWithRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:1];
}

static NSArray<UIColor *> *colorsFromArtwork(UIImage *image) {
    UIColor *fallback = [UIColor colorWithRed:30 / 255.0 green:215 / 255.0 blue:96 / 255.0 alpha:1];
    if (!image.CGImage) return @[fallback, fallback];
    const size_t w = 40, h = 40;
    uint8_t *data = calloc(w * h, 4);
    if (!data) return @[fallback, fallback];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(data, w, h, 8, w * 4, space,
        (CGBitmapInfo)(kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big));
    CGColorSpaceRelease(space);
    if (!ctx) {
        free(data);
        return @[fallback, fallback];
    }
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), image.CGImage);
    CGContextRelease(ctx);
    int quarter = (int)(w * h / 4);
    UIColor *top = averageRGB(data, quarter);
    UIColor *bottom = averageRGB(data + (w * h - quarter) * 4, quarter);
    free(data);
    return @[top, bottom];
}

static CAGradientLayer *radialLayer(UIColor *center, CGPoint origin) {
    CAGradientLayer *layer = [CAGradientLayer layer];
    layer.type = kCAGradientLayerRadial;
    UIColor *edge = [center colorWithAlphaComponent:0];
    layer.colors = @[(id)[center colorWithAlphaComponent:0.42].CGColor, (id)edge.CGColor];
    layer.locations = @[@0, @1];
    layer.startPoint = origin;
    layer.endPoint = CGPointMake(MIN(1, origin.x + 0.55), MIN(1, origin.y + 0.55));
    return layer;
}

static void refreshRadialColors(UIView *backdrop) {
    NSArray<UIColor *> *pair = colorsFromArtwork(SGRNowPlayingArtwork(NULL, NULL));
    for (NSNumber *tag in @[@(kLyricsRadialGlowTagA), @(kLyricsRadialGlowTagB)]) {
        UIView *host = [backdrop viewWithTag:tag.integerValue];
        if (!host) continue;
        for (CALayer *sub in [host.layer.sublayers copy]) [sub removeFromSuperlayer];
        CGPoint origin = tag.integerValue == kLyricsRadialGlowTagA ? CGPointMake(0.16, 0.08) : CGPointMake(0.92, 0.92);
        CAGradientLayer *rad = radialLayer(pair[tag.integerValue == kLyricsRadialGlowTagA ? 0 : 1], origin);
        rad.frame = host.bounds;
        [host.layer addSublayer:rad];
    }
}

static UIView *glowHost(NSInteger tag) {
    UIView *host = [UIView new];
    host.tag = tag;
    host.userInteractionEnabled = NO;
    host.accessibilityElementsHidden = YES;
    host.backgroundColor = UIColor.clearColor;
    return host;
}

static void layoutLyricsBackdrop(UIView *page) {
    UIView *shell = lyricsShell(page);
    sgr_lyricsPageRoot = shell;
    BOOL original = SGRLyricsFullscreenBackgroundNow() == SGRLyricsFullscreenBackgroundOriginal;
    BOOL coverMode = SGRLyricsFullscreenBackgroundNow() == SGRLyricsFullscreenBackgroundCover;

    UIView *backdrop = objc_getAssociatedObject(shell, &kBackdropKey);
    if (!backdrop) {
        backdrop = [UIView new];
        backdrop.tag = kLyricsSolidBackgroundTag;
        backdrop.backgroundColor = UIColor.blackColor;
        backdrop.opaque = YES;
        backdrop.userInteractionEnabled = NO;
        backdrop.accessibilityElementsHidden = YES;
        [backdrop addSubview:glowHost(kLyricsRadialGlowTagA)];
        [backdrop addSubview:glowHost(kLyricsRadialGlowTagB)];
        objc_setAssociatedObject(shell, &kBackdropKey, backdrop, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [shell insertSubview:backdrop atIndex:0];
    }

    backdrop.frame = shell.bounds;
    backdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [shell sendSubviewToBack:backdrop];

    for (NSNumber *tag in @[@(kLyricsRadialGlowTagA), @(kLyricsRadialGlowTagB)]) {
        UIView *host = [backdrop viewWithTag:tag.integerValue];
        host.frame = backdrop.bounds;
        host.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        host.hidden = !coverMode;
    }

    backdrop.hidden = original;
    if (original) {
        shell.backgroundColor = UIColor.clearColor;
        shell.opaque = NO;
        page.backgroundColor = UIColor.clearColor;
        page.opaque = NO;
        UIVisualEffectView *glass = SGGlassFor(page, &kPageGlassKey);
        glass.hidden = YES;
        return;
    }

    shell.opaque = YES;
    shell.backgroundColor = UIColor.blackColor;
    page.opaque = YES;
    page.backgroundColor = UIColor.blackColor;
    page.layer.backgroundColor = NULL;

    hideSpotifyGlass(shell, backdrop);
    if (coverMode) refreshRadialColors(backdrop);

    UIVisualEffectView *glass = SGGlassFor(page, &kPageGlassKey);
    glass.hidden = YES;
}

%hook _TtC32Lyrics_FullscreenElementPageImpl14FullscreenView
- (void)setBackgroundColor:(UIColor *)color {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ SGLog(@"lyrics page paints itself %@ through UIView", color); });
    %orig(nil);
}

- (void)layoutSubviews {
    %orig;
    UIView *page = (UIView *)self;
    if (page.bounds.size.height < 200) return;
    layoutLyricsBackdrop(page);

    if (!objc_getAssociatedObject(page, &kObsKey)) {
        id token = [NSNotificationCenter.defaultCenter addObserverForName:SGRLyricsLookDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            [page setNeedsLayout];
        }];
        id token2 = [NSNotificationCenter.defaultCenter addObserverForName:SGRNowPlayingArtworkDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            UIView *shell = lyricsShell(page);
            UIView *backdrop = objc_getAssociatedObject(shell, &kBackdropKey);
            if (backdrop && !backdrop.hidden && SGRLyricsFullscreenBackgroundNow() == SGRLyricsFullscreenBackgroundCover)
                refreshRadialColors(backdrop);
        }];
        objc_setAssociatedObject(page, &kObsKey, @[token, token2], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"_TtC32Lyrics_FullscreenElementPageImpl14FullscreenView"]);
}
