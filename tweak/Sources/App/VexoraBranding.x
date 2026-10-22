// Vexora Spotify branding: plan badge text, profile header, relabel "Spotify Free".
#import "Core/SGCore.h"

static char kProfilePatchKey, kProfileBadgeKey;

static UIColor *vexoraPlanPurple(void) {
    return [UIColor colorWithRed:0.52 green:0.28 blue:0.92 alpha:1];
}

static UIColor *vexoraPatchRed(void) {
    return [UIColor colorWithRed:0.91 green:0.08 blue:0.16 alpha:1];
}

static BOOL isSpotifyFreePlanText(NSString *text) {
    if (!text.length) return NO;
    NSString *lower = text.lowercaseString;
    if ([lower containsString:@"spotify free"]) return YES;
    if ([text isEqualToString:@"Taurine"] || [text isEqualToString:@"Vexora Spotify"]) return YES;
    if ([text isEqualToString:@"Spotify Premium"]) return YES;
    return NO;
}

static NSString *vexoraPlanLabel(NSString *text) {
    return isSpotifyFreePlanText(text) ? @"Vexora Spotify" : text;
}

static void stylePlanBadge(UILabel *label) {
    label.text = @"Vexora Spotify";
    label.textColor = UIColor.whiteColor;
    UIView *badge = label.superview;
    badge.backgroundColor = vexoraPlanPurple();
    if (CGRectGetHeight(badge.bounds) > 4)
        badge.layer.cornerRadius = CGRectGetHeight(badge.bounds) / 2;
    badge.clipsToBounds = YES;
}

static void relabelPlanBadges(UIView *root) {
    SGForEachView(root, ^(UIView *view) {
        if (![view isKindOfClass:UILabel.class]) return;
        UILabel *label = (UILabel *)view;
        if (isSpotifyFreePlanText(label.text)) stylePlanBadge(label);
        else if ([label.attributedText.string containsString:@"Spotify Free"]) {
            NSMutableAttributedString *a = [label.attributedText mutableCopy];
            [a.mutableString replaceOccurrencesOfString:@"Spotify Free" withString:@"Vexora Spotify"
                                                options:0 range:NSMakeRange(0, a.length)];
            label.attributedText = a;
            stylePlanBadge(label);
        }
    });
}

static void ensureProfilePatch(UIView *root) {
    __block UILabel *stats = nil, *name = nil;
    SGForEachView(root, ^(UIView *v) {
        if (![v isKindOfClass:UILabel.class]) return;
        UILabel *l = (UILabel *)v;
        if ([l.text rangeOfString:@"followers" options:NSCaseInsensitiveSearch].location != NSNotFound) stats = l;
        else if (l.text.length && l.font.pointSize >= 20 && ![l.text containsString:@"Playlist"]
                 && ![l.text containsString:@"followers"] && ![l.text isEqualToString:@"Edit"])
            if (!name || l.font.pointSize > name.font.pointSize) name = l;
    });
    if (!stats || !name) return;
    UIView *host = name.superview;
    if (!host) return;
    UILabel *patch = objc_getAssociatedObject(host, &kProfilePatchKey);
    if (!patch) {
        patch = [UILabel new];
        patch.text = @"Patched by Vexora";
        patch.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
        patch.textColor = vexoraPatchRed();
        patch.accessibilityElementsHidden = YES;
        [host addSubview:patch];
        objc_setAssociatedObject(host, &kProfilePatchKey, patch, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        UILabel *user = [UILabel new];
        user.text = @"Vexora user";
        user.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
        user.textColor = UIColor.whiteColor;
        user.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1];
        user.textAlignment = NSTextAlignmentCenter;
        user.layer.cornerRadius = 4;
        user.clipsToBounds = YES;
        [host addSubview:user];
        objc_setAssociatedObject(host, &kProfileBadgeKey, user, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UILabel *userBadge = objc_getAssociatedObject(host, &kProfileBadgeKey);
    [patch sizeToFit];
    [userBadge sizeToFit];
    CGRect nameFrame = [name convertRect:name.bounds toView:host];
    patch.frame = CGRectMake(nameFrame.origin.x, CGRectGetMaxY(nameFrame) + 4, patch.bounds.size.width + 2, patch.bounds.size.height);
    userBadge.frame = CGRectMake(nameFrame.origin.x, CGRectGetMaxY(patch.frame) + 6,
                                 MAX(88, userBadge.bounds.size.width + 16), 20);
}

%hook UILabel
- (void)setText:(NSString *)text {
    %orig(vexoraPlanLabel(text));
}

- (void)setAttributedText:(NSAttributedString *)attributedText {
    if (!attributedText.length) {
        %orig;
        return;
    }
    if ([attributedText.string containsString:@"Spotify Free"]) {
        NSMutableAttributedString *a = [attributedText mutableCopy];
        [a.mutableString replaceOccurrencesOfString:@"Spotify Free" withString:@"Vexora Spotify"
                                            options:0 range:NSMakeRange(0, a.length)];
        %orig(a);
        return;
    }
    %orig;
}
%end

%hook UIWindow
- (void)layoutSubviews {
    %orig;
    relabelPlanBadges(self);
    ensureProfilePatch(self);
}
%end

%ctor {
    %init;
}
