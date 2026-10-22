#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRRepaint.h"

static char kPageGlassKey, kBlackBgKey;
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

    UIView *black = objc_getAssociatedObject(page, &kBlackBgKey);
    if (!black) {
        black = [UIView new];
        black.tag = kLyricsSolidBackgroundTag;
        black.backgroundColor = UIColor.blackColor;
        black.userInteractionEnabled = NO;
        black.accessibilityElementsHidden = YES;
        objc_setAssociatedObject(page, &kBlackBgKey, black, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [page insertSubview:black atIndex:0];
    }
    black.frame = page.bounds;
    black.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    UIVisualEffectView *glass = SGGlassFor(page, &kPageGlassKey);
    glass.hidden = YES;
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"_TtC32Lyrics_FullscreenElementPageImpl14FullscreenView"]);
}
