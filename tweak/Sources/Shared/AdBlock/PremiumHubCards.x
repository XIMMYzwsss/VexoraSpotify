// Premium hub auto-fill was removed: it matched generic empty containers on unrelated pages and
// painted "Listen ad-free…" mid-screen. Strip any labels the old build may have injected (tag 88001).
#import "Core/SGCore.h"

static void removeStrayPremiumFillers(UIView *root) {
    SGForEachView(root, ^(UIView *v) {
        if (v.tag == 88001) [v removeFromSuperview];
    });
}

%hook UIWindow
- (void)layoutSubviews {
    %orig;
    removeStrayPremiumFillers(self);
}
%end

%ctor {
    %init;
}
