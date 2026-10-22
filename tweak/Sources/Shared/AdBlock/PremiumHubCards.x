// Spoof Premium blocks some marketing APIs; subscription hub cards can render empty. Fill them with copy.
#import "Core/SGCore.h"

static char kPremiumFilledKey;

static BOOL premiumHubPage(UIViewController *vc) {
    NSString *title = vc.navigationItem.title ?: @"";
    if ([title containsString:@"Premium"] || [title containsString:@"premium"]) return YES;
    if ([title containsString:@"subscription"] || [title containsString:@"Subscription"]) return YES;
    return NO;
}

static BOOL cardLooksEmpty(UIView *card) {
    if (card.hidden || card.alpha < 0.05) return NO;
    CGFloat h = card.bounds.size.height, w = card.bounds.size.width;
    if (h < 72 || w < 180) return NO;
    __block BOOL hasArt = NO, hasBody = NO;
    SGForEachView(card, ^(UIView *v) {
        if ([v isKindOfClass:UIImageView.class] && ((UIImageView *)v).image.size.width > 16) hasArt = YES;
        if ([v isKindOfClass:UILabel.class]) {
            NSString *t = ((UILabel *)v).text;
            if (t.length > 28 && ![t isEqualToString:@"Subscription"] && ![t hasPrefix:@"Snapshot"]) hasBody = YES;
        }
    });
    return !hasArt && !hasBody;
}

static void fillPremiumCard(UIView *card, NSString *title) {
    if (objc_getAssociatedObject(card, &kPremiumFilledKey)) return;
    UILabel *body = [UILabel new];
    body.tag = 88001;
    body.numberOfLines = 0;
    body.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
    body.textColor = [UIColor colorWithWhite:1 alpha:0.78];
    if ([title containsString:@"Manage"]) {
        body.text = @"Vexora Spotify Premium is active on this device. Plan changes still happen on the web.";
    } else {
        body.text = @"Listen ad-free, download offline, and stream in high quality with Vexora Spotify Premium.";
    }
    CGFloat inset = 16;
    body.frame = CGRectInset(card.bounds, inset, inset);
    body.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [card addSubview:body];
    objc_setAssociatedObject(card, &kPremiumFilledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void fillPremiumHub(UIViewController *vc) {
    if (!premiumHubPage(vc)) return;
    NSString *title = vc.navigationItem.title ?: @"";
    SGForEachView(vc.view, ^(UIView *v) {
        if (!cardLooksEmpty(v)) return;
        fillPremiumCard(v, title);
    });
}

%hook UIViewController
- (void)viewDidLayoutSubviews {
    %orig;
    fillPremiumHub(self);
}
%end

%ctor {
    %init;
}
