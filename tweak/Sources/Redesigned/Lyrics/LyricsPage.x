#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRRepaint.h"
#import "Redesigned/Kit/SGRBridges.h"
#import "LyricsLook.h"

static char kPageGlassKey, kBlackBgKey, kCoverKey, kBlurKey, kDimKey, kObsKey;
static const NSInteger kLyricsSolidBackgroundTag = 88002;

static UIView *clearAncestors(UIView *view) {
    UIView *top = view;
    for (UIView *v = view; v && ![v isKindOfClass:UIWindow.class]
            && ![NSStringFromClass(v.class) hasPrefix:@"UITransition"]; v = v.superview) {
        v.layer.backgroundColor = NULL;
        top = v;
    }
    return top;
}

static void tuneSpotifyEffects(UIView *root, UIView *black, UIView *cover, UIView *blur, UIView *dim) {
    NSSet<UIView *> *ours = [NSSet setWithObjects:black, cover, blur, dim, nil];
    NSMutableArray<UIView *> *stack = [root.subviews mutableCopy];
    while (stack.count) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        if ([ours containsObject:v]) continue;
        if ([v isKindOfClass:UIVisualEffectView.class]) v.hidden = YES;
        [stack addObjectsFromArray:v.subviews];
    }
}

static void refreshCoverGlow(UIView *page) {
    UIImageView *cover = objc_getAssociatedObject(page, &kCoverKey);
    if (!cover || cover.hidden) return;
    UIImage *art = SGRNowPlayingArtwork(NULL, NULL);
    if (art) cover.image = art;
}

static void layoutLyricsBackground(UIView *page) {
    BOOL coverMode = SGRLyricsFullscreenBackgroundNow() == SGRLyricsFullscreenBackgroundCover;
    UIView *black = objc_getAssociatedObject(page, &kBlackBgKey);
    UIImageView *cover = objc_getAssociatedObject(page, &kCoverKey);
    UIVisualEffectView *blur = objc_getAssociatedObject(page, &kBlurKey);
    UIView *dim = objc_getAssociatedObject(page, &kDimKey);

    if (!black) {
        black = [UIView new];
        black.tag = kLyricsSolidBackgroundTag;
        black.backgroundColor = UIColor.blackColor;
        black.opaque = YES;
        black.userInteractionEnabled = NO;
        black.accessibilityElementsHidden = YES;
        objc_setAssociatedObject(page, &kBlackBgKey, black, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [page insertSubview:black atIndex:0];
    }
    if (!cover) {
        cover = [UIImageView new];
        cover.contentMode = UIViewContentModeScaleAspectFill;
        cover.clipsToBounds = YES;
        cover.userInteractionEnabled = NO;
        cover.accessibilityElementsHidden = YES;
        objc_setAssociatedObject(page, &kCoverKey, cover, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [page insertSubview:cover aboveSubview:black];
    }
    if (!blur) {
        blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
        blur.userInteractionEnabled = NO;
        blur.accessibilityElementsHidden = YES;
        objc_setAssociatedObject(page, &kBlurKey, blur, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [page insertSubview:blur aboveSubview:cover];
    }
    if (!dim) {
        dim = [UIView new];
        dim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];
        dim.userInteractionEnabled = NO;
        dim.accessibilityElementsHidden = YES;
        objc_setAssociatedObject(page, &kDimKey, dim, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [page insertSubview:dim aboveSubview:blur];
    }

    black.frame = page.bounds;
    black.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    cover.frame = CGRectInset(page.bounds, -page.bounds.size.width * 0.15, -page.bounds.size.height * 0.15);
    cover.center = CGPointMake(CGRectGetMidX(page.bounds), CGRectGetMidY(page.bounds));
    cover.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    blur.frame = page.bounds;
    blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    dim.frame = page.bounds;
    dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    black.hidden = coverMode;
    cover.hidden = blur.hidden = dim.hidden = !coverMode;
    if (coverMode) refreshCoverGlow(page);

    page.opaque = !coverMode;
    page.backgroundColor = coverMode ? UIColor.clearColor : UIColor.blackColor;
    tuneSpotifyEffects(page, black, cover, blur, dim);

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

    page.layer.backgroundColor = NULL;
    sgr_lyricsPageRoot = clearAncestors(page);
    layoutLyricsBackground(page);

    if (!objc_getAssociatedObject(page, &kObsKey)) {
        id token = [NSNotificationCenter.defaultCenter addObserverForName:SGRLyricsLookDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            [page setNeedsLayout];
        }];
        id token2 = [NSNotificationCenter.defaultCenter addObserverForName:SGRNowPlayingArtworkDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            refreshCoverGlow(page);
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
