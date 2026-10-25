#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Shared/Player/SpeedPitch.h"
#import "Player.h"
#import "Shared/ListeningStats/ListeningStats.h"

static char kGlassKey, kCloseKey, kMoreKey, kPillKey, kPillViewKey, kContextIdKey;

static void glassInside(UIViewController *unit, NSArray<NSString *> *identifiers, const void **findKeys) {
    UIView *host = unit.viewIfLoaded;
    if (!host) return;
    NSUInteger found = 0;
    for (NSUInteger i = 0; i < identifiers.count; i++) {
        UIView *button = SGRFindByIdentifier(host, identifiers[i], findKeys[i]);
        if (!button) {
            static NSMutableSet<NSString *> *missing;
            if (!missing) missing = [NSMutableSet set];
            if (![missing containsObject:identifiers[i]]) {
                [missing addObject:identifiers[i]];
                SGLog(@"redesign player: %@ not found in %@, left as Spotify's", identifiers[i], NSStringFromClass(host.class));
            }
            continue;
        }
        SGRGlassInside(button, &kGlassKey, SGRGlassCircleSize);
        if ([identifiers[i] isEqualToString:@"Context menu"]) {
            SGPlayerMenuWatchMoreButton(button);
            SGRPlayerMenuWatchMoreButton(button);
        }
        found++;
    }

    static NSMutableSet<NSString *> *logged;
    if (!logged) logged = [NSMutableSet set];
    NSString *unitName = NSStringFromClass(unit.class);
    if (![logged containsObject:unitName]) {
        [logged addObject:unitName];
        SGLog(@"redesign player: glass inside %lu of %lu buttons in %@", (unsigned long)found, (unsigned long)identifiers.count, unitName);
    }
}


// The header's context line ("Playing from ...") on a glass pill of its own, so it reads over any cover, the
// sharp artwork of the fill background included. The pill lives on the header itself, centered between
// minimize and ⋯, sized to the text up to that gap, so Spotify's truncated label and a clipped parent
// cannot hide the glass or cut the name short.
static const CGFloat kPillPadX = 16, kPillMinHeight = 34, kPillMinWidth = 72;

static NSString *visibleText(UILabel *label) {
    NSString *text = label.text.length ? label.text : label.attributedText.string;
    return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static BOOL viewInside(UIView *view, UIView *ancestor) {
    if (!ancestor) return NO;
    for (UIView *walk = view; walk; walk = walk.superview) {
        if (walk == ancestor) return YES;
    }
    return NO;
}

static UILabel *labelIn(UIView *root) {
    __block UILabel *found = nil;
    SGForEachView(root, ^(UIView *view) {
        if (found || ![view isKindOfClass:UILabel.class]) return;
        if (visibleText((UILabel *)view).length) found = (UILabel *)view;
    });
    return found;
}

static UILabel *contextLabelIn(UIView *host) {
    UIView *minBtn = SGRFindByIdentifier(host, @"now-playing-minimize-button", &kCloseKey);
    UIView *moreBtn = SGRFindByIdentifier(host, @"Context menu", &kMoreKey);
    UIView *named = SGRFindByIdentifier(host, @"now-playing-context*", &kContextIdKey);
    if (named) {
        UILabel *inside = [named isKindOfClass:UILabel.class] ? (UILabel *)named : labelIn(named);
        if (inside) return inside;
    }
    __block UILabel *playingFrom = nil;
    __block UILabel *centered = nil;
    __block CGFloat bestDist = CGFLOAT_MAX;
    CGFloat mid = CGRectGetMidX(host.bounds);
    SGForEachView(host, ^(UIView *view) {
        if (![view isKindOfClass:UILabel.class]) return;
        UILabel *label = (UILabel *)view;
        if (label.hidden || label.alpha < 0.01) return;
        if (viewInside(label, minBtn) || viewInside(label, moreBtn)) return;
        NSString *text = visibleText(label);
        if (text.length < 2) return;
        if (label.font.pointSize > 0 && label.font.pointSize < 10) return;
        NSString *lower = text.lowercaseString;
        if ([lower hasPrefix:@"playing"]) {
            playingFrom = label;
            return;
        }
        CGRect frame = [label convertRect:label.bounds toView:host];
        if (frame.size.height < 10 || frame.size.height > 44) return;
        CGFloat dist = fabs(CGRectGetMidX(frame) - mid);
        if (dist < bestDist) {
            bestDist = dist;
            centered = label;
        }
    });
    return playingFrom ?: centered;
}

static UIView *headerAnchor(UIView *label, UIView *host) {
    UIView *anchor = label;
    while (anchor.superview && anchor.superview != host) anchor = anchor.superview;
    return anchor.superview == host ? anchor : nil;
}

static void pillBehindContext(UIViewController *unit) {
    UIView *host = unit.viewIfLoaded;
    if (!host) return;
    UILabel *label = contextLabelIn(host);
    NSString *text = visibleText(label);
    if (text.length) SGListeningRememberContext(text);
    UIView *box = objc_getAssociatedObject(host, &kPillViewKey);
    if (!label || !text.length) {
        box.hidden = YES;
        return;
    }
    if (!box) {
        box = [UIView new];
        box.userInteractionEnabled = NO;
        box.accessibilityElementsHidden = YES;
        box.clipsToBounds = NO;
        objc_setAssociatedObject(host, &kPillViewKey, box, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIView *anchor = headerAnchor(label, host);
    if (box.superview != host) {
        if (anchor) [host insertSubview:box belowSubview:anchor];
        else [host insertSubview:box atIndex:0];
    } else if (anchor) {
        NSUInteger boxIndex = [host.subviews indexOfObject:box];
        NSUInteger anchorIndex = [host.subviews indexOfObject:anchor];
        if (boxIndex > anchorIndex) [host insertSubview:box belowSubview:anchor];
    }

    UIView *minBtn = SGRFindByIdentifier(host, @"now-playing-minimize-button", &kCloseKey);
    UIView *moreBtn = SGRFindByIdentifier(host, @"Context menu", &kMoreKey);
    CGRect left = minBtn ? [minBtn convertRect:minBtn.bounds toView:host] : CGRectMake(8, 0, SGRGlassCircleSize, SGRGlassCircleSize);
    CGRect right = moreBtn ? [moreBtn convertRect:moreBtn.bounds toView:host]
                           : CGRectMake(MAX(0, host.bounds.size.width - 8 - SGRGlassCircleSize), 0, SGRGlassCircleSize, SGRGlassCircleSize);
    CGFloat maxWidth = CGRectGetMinX(right) - CGRectGetMaxX(left) - 10;
    if (maxWidth < kPillMinWidth) maxWidth = MAX(kPillMinWidth, host.bounds.size.width - 96);

    UIFont *font = label.font ?: [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    CGRect textBounds = [text boundingRectWithSize:CGSizeMake(MAX(40, maxWidth - 2 * kPillPadX), 28)
                                           options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                        attributes:@{NSFontAttributeName: font}
                                           context:nil];
    CGFloat width = MIN(MAX(ceil(textBounds.size.width) + 2 * kPillPadX, kPillMinWidth), maxWidth);
    CGFloat height = MAX(kPillMinHeight, ceil(MAX(textBounds.size.height, font.lineHeight)) + 12);

    CGRect labelInHost = [label convertRect:label.bounds toView:host];
    CGFloat midY = CGRectGetMidY(labelInHost);
    if (midY < 8 || midY > host.bounds.size.height) midY = CGRectGetMidY(left);
    CGFloat midX = (CGRectGetMaxX(left) + CGRectGetMinX(right)) / 2;
    if (midX < 20 || !isfinite(midX)) midX = CGRectGetMidX(host.bounds);
    box.bounds = CGRectMake(0, 0, width, height);
    box.center = CGPointMake(midX, midY);
    box.hidden = NO;
    box.alpha = 1;
    SGRGlassCapsuleInside(box, &kPillKey, box.bounds.size, YES);

    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.65;
    label.numberOfLines = 1;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.baselineAdjustment = UIBaselineAdjustmentAlignCenters;
    if (label.superview) {
        CGRect fitted = [host convertRect:CGRectInset(box.frame, kPillPadX - 2, 4) toView:label.superview];
        if (fitted.size.width >= 40 && fitted.size.height >= 12) {
            label.frame = fitted;
            label.preferredMaxLayoutWidth = fitted.size.width;
        }
    }
}

%hook _TtC20NowPlaying_ModesImpl18HeaderElementsUnit
- (void)viewDidLayoutSubviews {
    %orig;
    static const void *keys[] = {&kCloseKey, &kMoreKey};
    glassInside((UIViewController *)self, @[@"now-playing-minimize-button", @"Context menu"], keys);
    pillBehindContext((UIViewController *)self);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"_TtC20NowPlaying_ModesImpl18HeaderElementsUnit"]);
}
