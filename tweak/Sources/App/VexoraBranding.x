// Vexora Spotify branding: plan badge text, relabel "Spotify Free", "Vexora user" on profile only.
#import "Core/SGCore.h"

static char kProfileBadgeKey;

static UIColor *vexoraPlanPurple(void) {
    return [UIColor colorWithRed:0.52 green:0.28 blue:0.92 alpha:1];
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

static BOOL isUserProfileViewController(UIViewController *vc) {
    if (!vc.isViewLoaded) return NO;
    NSString *cls = NSStringFromClass(vc.class);
    if ([cls containsString:@"SideDrawer"] || [cls containsString:@"Search"] || [cls containsString:@"Funkis"]
        || [cls containsString:@"Settings"] || [cls containsString:@"Premium"])
        return NO;
    __block BOOL hasFollowers = NO;
    SGForEachView(vc.view, ^(UIView *v) {
        if (![v isKindOfClass:UILabel.class]) return;
        NSString *t = ((UILabel *)v).text ?: @"";
        if ([t rangeOfString:@"follower" options:NSCaseInsensitiveSearch].location != NSNotFound)
            hasFollowers = YES;
    });
    return hasFollowers;
}

static void ensureProfileUserBadge(UIViewController *vc) {
    if (!isUserProfileViewController(vc)) return;
    UIView *root = vc.view;
    __block UILabel *stats = nil, *name = nil;
    SGForEachView(root, ^(UIView *v) {
        if (![v isKindOfClass:UILabel.class]) return;
        UILabel *l = (UILabel *)v;
        if ([l.text rangeOfString:@"follower" options:NSCaseInsensitiveSearch].location != NSNotFound) stats = l;
        else if (l.text.length && l.font.pointSize >= 20 && ![l.text containsString:@"Playlist"]
                 && ![l.text containsString:@"follower"] && ![l.text isEqualToString:@"Edit"]
                 && ![l.text isEqualToString:@"Search"] && ![l.text isEqualToString:@"Home"])
            if (!name || l.font.pointSize > name.font.pointSize) name = l;
    });
    if (!stats || !name) return;
    UIView *host = name.superview;
    if (!host) return;

    UILabel *userBadge = objc_getAssociatedObject(host, &kProfileBadgeKey);
    if (!userBadge) {
        userBadge = [UILabel new];
        userBadge.text = @"Vexora user";
        userBadge.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
        userBadge.textColor = UIColor.whiteColor;
        userBadge.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1];
        userBadge.textAlignment = NSTextAlignmentCenter;
        userBadge.layer.cornerRadius = 4;
        userBadge.clipsToBounds = YES;
        userBadge.accessibilityElementsHidden = YES;
        [host addSubview:userBadge];
        objc_setAssociatedObject(host, &kProfileBadgeKey, userBadge, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [userBadge sizeToFit];
    CGRect nameFrame = [name convertRect:name.bounds toView:host];
    userBadge.frame = CGRectMake(nameFrame.origin.x, CGRectGetMaxY(nameFrame) + 6,
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
}
%end

%hook UIViewController
- (void)viewDidLayoutSubviews {
    %orig;
    ensureProfileUserBadge(self);
}
%end

%ctor {
    %init;
}
