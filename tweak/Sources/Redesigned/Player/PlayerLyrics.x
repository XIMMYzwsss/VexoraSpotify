// Player redesign: the lyrics come to the player itself, the way the Music app shows them. The player
// is one screen and does not scroll (PlayerScroll.x), so the footer's lyrics glyph is the only way to
// them: it shrinks the cover into a thumbnail at the top of the artwork band, lifts the track's title
// up beside it, and fades the Apple Music style lines (Redesigned/Lyrics/SGRKaraokeView.h) into the
// room that frees between the title and the progress bar. Tapping it again puts the cover back.
//
// Nothing of Spotify's is taken apart for it. The cover is the Kit's now playing artwork drawn again
// in a view of the redesign's own, flown from where Spotify's cover is drawn to where the thumbnail
// belongs, while Spotify's list of covers goes to alpha 0 underneath: one view to move instead of a
// paging list of them, and the two pictures are the same one, so the swap is not seen. The title row
// is Spotify's own unit translated, the way PlayerFooter.x moves the footer's controls -- a transform
// survives the stack view laying its arranged views out again -- with a mask over it where the controls
// it moved toward begin, so a long title fades out before them instead of running under them. The row
// of chips over it (Switch to video) goes while the lines are up, since they take the room it sits in.
//
// Tree (trees/clean/player/01.txt): SPTNowPlayingView (:26) holds the content layers, the header row
// (:91), and id=npv.bottomStackView {0, 576.67, 402, 236} (:127) whose arranged views are the
// information unit {0, 0, 402, 64} (:160, the title, the artist and the add button), the duration unit
// {0, 64, 402, 40} (:209), the controls (:240) and the footer (:295). The title is
// id=now-playing-title-label and the artist id=now-playing-subtitle-label (:174, :185), both inside one
// arranged element view {12, 2.33, 304, 43.33} of the unit's row. Every measurement here is taken from
// the views themselves, since a player with a volume row or another mode's units has other numbers.
//
// The geometry is re-applied on every layout pass of the units, since a new track rebuilds the
// elements inside them, and it is undone before the player closes: the bar morphs back into a full
// size cover, which a thumbnail would not match.
#import <UIKit/UIGestureRecognizerSubclass.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Lyrics/SGRKaraokeView.h"
#import "Redesigned/Lyrics/LyricsLook.h"
#import "Redesigned/Lyrics/SGRSingControl.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Sing/SGSingController.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/LocalFiles/LocalFiles.h"
#import "Player.h"

static const CGFloat kThumbSide = 72;          // the cover once the lyrics are up
static const CGFloat kThumbGap = 16;           // between the thumbnail and the title beside it
static const CGFloat kTitleGap = 12;           // between the title and the controls at the trailing edge
static const CGFloat kTitleFade = 20;          // over how much of its end a title too long to fit fades out
static const CGFloat kThumbTop = 8;            // below the top of the artwork band
static const CGFloat kLyricsTop = 20;          // between the title row and the first line
static const CGFloat kLyricsBottom = 8;        // above the progress bar
// The lines are a surface arriving, not something moving: they come up from just under full size as the
// room for them opens, and go at once when it closes. An exit the eye waits through reads as a stall.
// A track that changes while the lines are up has this long to bring its own before they are put away. A
// look for them still running then is waited out, since a local file's sources are asked one after another,
// up to 6 s each, with a Musixmatch token fetched first the first time.
static const NSTimeInterval kLyricsGrace = 3;
// Below this the player has not laid out yet and nothing can be measured from it.
static const CGFloat kLivingHeight = 200;
// The lines on their own: the controls under them fade after this long without a touch.
static const NSTimeInterval kRest = 4;

static char kOverlayKey, kPlateKey, kTitleKey, kStackKey;
static BOOL sg_open;
static BOOL sg_moving;                      // the transition is in flight, so no layout pass may re-place it
static __weak UIView *sg_host;              // SPTNowPlayingView
static __weak UIViewController *sg_info, *sg_duration, *sg_floating;
static __weak UIView *sg_titleElement;      // the arranged element view holding the title and the artist
static __weak UIViewController *sg_player;  // NowPlayingViewController, whose units the controls are
static BOOL sg_alone;                       // the lines have the player to themselves
static BOOL sg_touching;                    // a finger is on the player, which holds the clock (SGRPlayerTouchWatcher)
static BOOL sg_singHolding;                 // Sing's open capsule or explanation holds the controls up
static NSTimer *sg_rest;
static __weak UIGestureRecognizer *sg_wake; // on the player, on while alone: the tap that brings the controls back
@class SGRPlayerLyricsOverlay;
static void syncSingControl(SGRPlayerLyricsOverlay *overlay);
static void restartRest(void);

#pragma mark - the overlay

// The thumbnail and the lines, side by side under one view so the lines' own view has no sibling of
// ours to hide: SGRKaraokeView takes the whole of whatever it is put in and dims what is next to it.
@interface SGRPlayerLyricsOverlay : UIView
@property (nonatomic, readonly) UIView *thumb;       // the cover, at full size, moved by its transform
@property (nonatomic, readonly) UIImageView *cover;
@property (nonatomic, readonly) UIView *stage;       // holds the lines' view alone
@property (nonatomic, readonly) SGRKaraokeView *lyrics;
@end

@implementation SGRPlayerLyricsOverlay {
    UIView *_thumb, *_stage;
    UIImageView *_cover;
    SGRKaraokeView *_lyrics;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _thumb = [[UIView alloc] initWithFrame:CGRectZero];
    // A tap on the cover beside the lines brings the full player back.
    [_thumb addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(sgr_thumbTapped)]];
    _thumb.isAccessibilityElement = YES;
    _thumb.accessibilityLabel = @"Show the player";
    _thumb.accessibilityTraits = UIAccessibilityTraitButton;
    _cover = [[UIImageView alloc] initWithFrame:CGRectZero];
    _cover.contentMode = UIViewContentModeScaleAspectFill;
    _cover.clipsToBounds = YES;
    _cover.layer.cornerCurve = kCACornerCurveContinuous;
    _cover.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_thumb addSubview:_cover];
    _stage = [[UIView alloc] initWithFrame:CGRectZero];
    [self addSubview:_stage];
    [self addSubview:_thumb];
    return self;
}

- (void)sgr_thumbTapped {
    if (SGRPlayerLyricsOpen() && !sg_moving) SGRPlayerToggleLyrics();
}

- (UIView *)thumb { return _thumb; }
- (UIImageView *)cover { return _cover; }
- (UIView *)stage { return _stage; }

// The lines seek when they are tapped and the thumbnail brings the player back, so everywhere else the
// overlay would only swallow touches: a view that takes them does, even with nothing on it.
//
// What it hands them to instead is the title row. Translated to the top of the player it is drawn well
// outside the stack view it is arranged in, and UIKit stops looking at a view whose bounds the touch is
// not in, so the add button and the menu that rode up with it are past Spotify's own reach. Asked here
// directly, the row answers for where it is drawn.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit != self) return hit;
    UIView *row = SGRPlayerLyricsOpen() ? sg_info.viewIfLoaded : nil;
    UIView *inRow = row ? [row hitTest:[row convertPoint:point fromView:self] withEvent:event] : nil;
    return inRow == row ? nil : inRow;
}

// Made on the first tap and kept afterward: it measures the song for its width before it can place a
// line, so a view built again on every tap would show nothing for the first frames. Out of the window
// it costs nothing -- its display link only runs while it is in one.
- (SGRKaraokeView *)lyrics {
    if (!_lyrics) {
        _lyrics = [[SGRKaraokeView alloc] initWithFrame:_stage.bounds];
        _lyrics.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        // Sing's mic stays while the lines are on their own, moving down with them (setAlone).
        _lyrics.keepsSing = YES;
    }
    if (_lyrics.superview != _stage) [_stage addSubview:_lyrics];
    _lyrics.frame = _stage.bounds;
    return _lyrics;
}

@end

#pragma mark - the measurements

typedef struct {
    BOOL ok;
    CGRect cover;     // where Spotify draws the cover now, in the player
    CGRect thumb;     // where it goes
    CGRect stage;     // where the lines go
    CGFloat lift;     // how far the title row rises
    CGFloat shift;    // how far the title slides right to clear the thumbnail, 0 when it sits under it
} SGRLyricsLayout;

// What a view's frame would be with the translation this file put on it left out.
static CGRect untransformed(UIView *view, UIView *host) {
    CGRect frame = SGFrameIn(view, host);
    CGAffineTransform t = view.transform;
    return CGRectOffset(frame, -t.tx, -t.ty);
}

static SGRLyricsLayout layoutIn(UIView *host) {
    SGRLyricsLayout l = {0};
    UIView *info = sg_info.viewIfLoaded, *duration = sg_duration.viewIfLoaded, *title = sg_titleElement;
    if (!host || host.bounds.size.height < kLivingHeight || !info || !duration) return l;
    CGRect area = SGRPlayerArtworkAreaIn(host), cover = SGRPlayerCoverFrameIn(host);
    if (CGRectIsNull(area) || CGRectIsNull(cover)) return l;
    CGRect row = untransformed(info, host), bar = untransformed(duration, host);
    // The thumbnail takes the title's own leading edge, so the two line up down the page.
    CGFloat leading = title ? CGRectGetMinX(untransformed(title, host)) : CGRectGetMinX(area) + SGRSideMargin;
    l.cover = cover;
    l.thumb = CGRectMake(leading, CGRectGetMinY(area) + kThumbTop, kThumbSide, kThumbSide);
    // Beside the thumbnail when the title can be moved clear of it, under it when it cannot be found.
    CGFloat top = title ? CGRectGetMidY(l.thumb) - row.size.height / 2 : CGRectGetMaxY(l.thumb) + SGRGrid;
    l.lift = top - CGRectGetMinY(row);
    l.shift = title ? kThumbSide + kThumbGap : 0;
    CGFloat lines = MAX(CGRectGetMaxY(l.thumb), top + row.size.height) + kLyricsTop;
    l.stage = CGRectMake(CGRectGetMinX(area), lines, area.size.width, CGRectGetMinY(bar) - kLyricsBottom - lines);
    l.ok = l.stage.size.height > kLivingHeight / 2 && l.lift < 0;
    return l;
}

#pragma mark - the title row

// Where the row's trailing controls start, in the unit's coordinates: the nearest arranged view on the
// trailing side of the title that is still there to be seen. The title may not reach it.
static CGFloat trailingEdgeIn(UIView *info) {
    UIView *title = sg_titleElement, *row = title.superview;
    if (!title || !row) return CGFLOAT_MAX;
    CGFloat titleLeft = CGRectGetMinX(untransformed(title, info));
    CGFloat limit = CGRectGetMaxX(SGFrameIn(row, info));
    for (UIView *view in row.subviews) {
        if (view == title || view.hidden || view.alpha < 0.01 || view.bounds.size.width < 1) continue;
        CGFloat x = CGRectGetMinX(SGFrameIn(view, info));
        if (x > titleLeft && x < limit) limit = x;
    }
    return limit;
}

// The title moved right by the thumbnail would run into the add button beside it, and it cannot simply
// be narrowed: Spotify lays its marquee labels out with constraints, which put the width back the next
// time anything in the row lays out -- and a long title, being a marquee, lays out often. A mask on the
// element takes no part in that, so it holds between passes, and it fades the title out where Spotify's
// own fade would have been rather than cutting it.
static void clipTitle(UIView *element, CGFloat width) {
    CGRect bounds = element.bounds;
    if (width >= bounds.size.width - 0.5 || bounds.size.height < 1) {
        element.layer.mask = nil;
        return;
    }
    CAGradientLayer *mask = [element.layer.mask isKindOfClass:CAGradientLayer.class] ? (CAGradientLayer *)element.layer.mask : nil;
    if (!mask) {
        mask = [CAGradientLayer layer];
        mask.colors = @[(id)UIColor.whiteColor.CGColor, (id)UIColor.whiteColor.CGColor, (id)UIColor.clearColor.CGColor];
        mask.startPoint = CGPointMake(0, 0.5);
        mask.endPoint = CGPointMake(1, 0.5);
        element.layer.mask = mask;
    }
    CGFloat fade = MIN(kTitleFade, width);
    CGRect frame = CGRectMake(0, 0, MAX(0, width), bounds.size.height);
    if (CGRectEqualToRect(frame, mask.frame)) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    mask.frame = frame;
    mask.locations = @[@0, @(width > 0 ? (width - fade) / width : 0), @1];
    [CATransaction commit];
}

// The unit's row lays its arranged views out after the unit's own pass, so the transforms go on after it.
static void placeTitleRow(SGRLyricsLayout l) {
    UIView *info = sg_info.viewIfLoaded;
    if (!info) return;
    [SGRowIn(info) layoutIfNeeded];
    CGFloat lift = sg_open ? l.lift : 0, shift = sg_open ? l.shift : 0;
    CGAffineTransform rise = CGAffineTransformMakeTranslation(0, round(lift));
    if (!CGAffineTransformEqualToTransform(info.transform, rise)) info.transform = rise;
    UIView *title = sg_titleElement;
    if (!title) return;
    CGAffineTransform slide = CGAffineTransformMakeTranslation(round(shift), 0);
    if (!CGAffineTransformEqualToTransform(title.transform, slide)) title.transform = slide;
    // Closed it reaches as far as Spotify meant it to; moved, only as far as the controls it moved toward.
    CGFloat room = CGFLOAT_MAX;
    if (sg_open) room = trailingEdgeIn(info) - kTitleGap - (CGRectGetMinX(untransformed(title, info)) + shift);
    clipTitle(title, room);
}

#pragma mark - opening and closing

BOOL SGRPlayerLyricsAvailable(void) {
    NSString *track = SGKaraokePlayingTrack();
    return track != nil && SGKaraokeLinesForTrack(track) != nil;
}

BOOL SGRPlayerLyricsOpen(void) {
    return sg_open;
}

// Puts the overlay's own views where the measurements say, without animating. The thumbnail is laid out
// at the size and place Spotify draws its cover at and moved by its transform alone, so a pass that
// runs while it is up leaves it exactly where the eye has it: the two are worked out from one
// measurement. Bounds and a center, not a frame, since both views can be under a transform.
static void place(SGRPlayerLyricsOverlay *overlay, UIView *host, SGRLyricsLayout l) {
    overlay.frame = CGRectUnion(l.cover, CGRectUnion(l.thumb, l.stage));
    CGRect cover = [overlay convertRect:l.cover fromView:host], stage = [overlay convertRect:l.stage fromView:host];
    overlay.thumb.bounds = (CGRect){CGPointZero, cover.size};
    overlay.thumb.center = CGPointMake(CGRectGetMidX(cover), CGRectGetMidY(cover));
    overlay.cover.frame = overlay.thumb.bounds;
    SGRShadowPlate *plate = SGRShadowPlateIn(overlay.thumb, &kPlateKey);
    plate.bounds = overlay.thumb.bounds;
    plate.center = CGPointMake(CGRectGetMidX(overlay.thumb.bounds), CGRectGetMidY(overlay.thumb.bounds));
    overlay.stage.bounds = (CGRect){CGPointZero, stage.size};
    overlay.stage.center = CGPointMake(CGRectGetMidX(stage), CGRectGetMidY(stage));
    overlay.lyrics.frame = overlay.stage.bounds;
    overlay.lyrics.extrasEnabled = SGEnabled(SGRKeyPlayerTranslateButton);
    syncSingControl(overlay);
}

// Where the thumbnail's view has to go to land on `l.thumb`, as a transform about its own center: the
// shadow and the corners travel with it that way, instead of a shadow redrawn on every frame.
static CGAffineTransform thumbTransform(SGRLyricsLayout l) {
    CGFloat scale = l.cover.size.width > 0 ? l.thumb.size.width / l.cover.size.width : 1;
    CGAffineTransform move = CGAffineTransformMakeTranslation(round(CGRectGetMidX(l.thumb) - CGRectGetMidX(l.cover)),
                                                             round(CGRectGetMidY(l.thumb) - CGRectGetMidY(l.cover)));
    return CGAffineTransformConcat(CGAffineTransformMakeScale(scale, scale), move);
}

#pragma mark - the lines on their own

// After kRest without a touch while the song plays, the controls under the lines fade and the lines grow
// down into their room, the way the Music app leaves its lyrics alone. The header row, the thumbnail and
// the title row stay, so the song playing is still named, and stay Spotify's and the thumbnail's to touch.
// The lines scroll as they always do and leave the controls hidden; a tap brings them back and is not a
// seek. A pause brings them back and keeps them; VoiceOver, a sheet over the player and the app in the
// background keep them up. A scroll through the lines hides them at once. Sing's mic stays with the lines,
// and a touch on it is the mic's: it does not bring the controls back.
//
// The tap is a recognizer on the player that recognizes with any other, so the thumbnail's tap closes the
// lyrics the same time it brings the controls back, and a button takes its own tap: UIKit gives a control
// its tap over a tap recognizer above it. A drag or a second finger fails it. The lines' own tap, the one
// that seeks, is off while they are alone, which holds whichever of the two would have finished first.

// The controls under the lines: every view of Spotify's bottom stack but the title row and the chips (gone
// while the lines are up), which is the progress bar, the buttons, the footer and a volume row where the
// phone has one. Each fades by its alpha and the stack is left alone, since the title row is in it too.
// Without the stack, the units of the first three. Only views on screen are taken, and only the ones
// faded (sg_faded) come back, so nothing Spotify keeps hidden is shown.
static NSHashTable<UIView *> *sg_faded;

static NSArray<UIView *> *controlViews(void) {
    UIView *info = sg_info.viewIfLoaded, *floating = sg_floating.viewIfLoaded;
    NSMutableArray<UIView *> *views = [NSMutableArray array];
    UIView *stack = SGRFindByIdentifier(sg_host, @"npv.bottomStackView", &kStackKey);
    if (stack) {
        for (UIView *view in stack.subviews) {
            if ([info isDescendantOfView:view] || [floating isDescendantOfView:view]) continue;
            if (!view.hidden && view.alpha > 0.01) [views addObject:view];
        }
        return views;
    }
    static NSArray<NSString *> *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = @[@"DurationElementUnit", @"PlaybackControlsElementsUnit", @"FooterElementsUnit"];
    });
    // A unit's view answers to its controller as its next responder, wherever the unit sits in the tree.
    SGForEachView(sg_host, ^(UIView *view) {
        UIResponder *owner = view.nextResponder;
        if (![owner isKindOfClass:UIViewController.class] || ((UIViewController *)owner).viewIfLoaded != view) return;
        NSString *name = NSStringFromClass(owner.class);
        for (NSString *unit in names) {
            if ([name hasSuffix:unit] && !view.hidden && view.alpha > 0.01) [views addObject:view];
        }
    });
    return views;
}

static void fadeControls(BOOL faded) {
    if (!sg_faded) sg_faded = [NSHashTable weakObjectsHashTable];
    if (faded) {
        for (UIView *view in controlViews()) {
            view.alpha = 0;
            [sg_faded addObject:view];
        }
    } else {
        for (UIView *view in sg_faded) view.alpha = 1;
        [sg_faded removeAllObjects];
    }
}

// Where the lines go on their own: from where they start under the title row down to the bottom of the
// safe area, over the controls that faded.
static CGRect aloneStage(UIView *host, SGRLyricsLayout l) {
    CGRect safe = UIEdgeInsetsInsetRect(host.bounds, host.safeAreaInsets);
    return CGRectMake(CGRectGetMinX(l.stage), CGRectGetMinY(l.stage), l.stage.size.width,
                      CGRectGetMaxY(safe) - kLyricsBottom - CGRectGetMinY(l.stage));
}

// The lines' tap seeks, so it is off while they are alone. Back on a turn of the run loop later: the tap
// that brought the controls back is still being handed round, and must not reach it.
static void letLinesSeek(SGRPlayerLyricsOverlay *overlay, BOOL seek) {
    void (^apply)(void) = ^{
        if (seek == sg_alone) return;   // alone again since
        for (UIGestureRecognizer *recognizer in overlay.lyrics.gestureRecognizers) {
            if ([recognizer isKindOfClass:UITapGestureRecognizer.class]) recognizer.enabled = seek;
        }
    };
    if (seek) dispatch_async(dispatch_get_main_queue(), apply);
    else apply();
}

static void setAlone(BOOL alone, BOOL animated);

// A sheet, a menu or an alert over the player: the top controller on screen is not one the player is drawn
// in. The queue, devices and ⋯ sheets can be presented from the player's topmost parent rather than the
// player, which the player's own presentedViewController would miss, and Sing's explanation is an alert on
// the top controller (SGRSingControl.m).
static BOOL coveredBySheet(void) {
    UIViewController *top = SGTopController();
    UIView *host = sg_host;
    if (!top.viewIfLoaded || !host || [host isDescendantOfView:top.viewIfLoaded]) return NO;
    static NSUInteger logged;
    if (logged++ < 3) SGLog(@"redesign player: %@ over the player keeps the controls up", NSStringFromClass(top.class));
    return YES;
}

// Whether the clock runs: the lines up with the controls, the song playing with the app in front, no finger
// on the player and VoiceOver off (which keeps the controls up, and starts the clock again when it goes).
static BOOL mayCount(void) {
    SPTPlayerState *state = SGPlayerState();
    UIView *host = sg_host;
    return SGEnabled(SGRKeyLyricsAutoHide) && sg_open && !sg_alone && !sg_touching && !sg_singHolding && host.window && state && !state.isPaused
        && !UIAccessibilityIsVoiceOverRunning()
        && UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
}

// Whether the controls may fade as it runs out: not under a sheet, nor while Sing gets ready.
static BOOL mayRest(void) {
    return mayCount() && !coveredBySheet() && SGSingCurrentState() != SGSingPreparing;
}

// The clock starts again at every touch. Run out while something keeps the controls up (a sheet, Sing getting
// ready, lines still being measured), it starts over, so they fade once that has gone.
static void restartRest(void) {
    [sg_rest invalidate];
    sg_rest = nil;
    if (!mayCount()) return;
    sg_rest = [NSTimer scheduledTimerWithTimeInterval:kRest repeats:NO block:^(NSTimer *timer) {
        sg_rest = nil;
        if (mayRest()) setAlone(YES, YES);
        if (!sg_alone) restartRest();
    }];
}

static void singHolding(BOOL holding) {
    if (holding == sg_singHolding) return;
    sg_singHolding = holding;
    if (holding) {
        [sg_rest invalidate];
        sg_rest = nil;
    } else if (!sg_alone) {
        restartRest();
    }
}

static void syncSingControl(SGRPlayerLyricsOverlay *overlay) {
    if (!overlay) return;
    if (!SGEnabled(SGRKeyPlayerKaraokeButton)) {
        SGRSingControlRemoveForPage(overlay.stage);
        return;
    }
    __weak SGRPlayerLyricsOverlay *weakOverlay = overlay;
    SGRSingControlForPage(overlay.stage, overlay.lyrics.frame, sg_alone, ^(BOOL holding) {
        if (weakOverlay) singHolding(holding);
    });
}

@interface SGRPlayerTouchWatcher : UIGestureRecognizer <UIGestureRecognizerDelegate>
@end

// Sees every touch on the player and takes none. It never recognizes: it holds the clock while a finger is
// down, so a hold on Sing's slider that runs past the rest fades nothing under it, and starts the clock once
// the last finger lifts. Nothing can end its watch early, or a scroll or a hold that recognized would start
// the clock under the finger.
@implementation SGRPlayerTouchWatcher
- (instancetype)init {
    if (!(self = [super initWithTarget:nil action:nil])) return nil;
    self.delegate = self;
    self.cancelsTouchesInView = NO;
    self.delaysTouchesBegan = NO;
    self.delaysTouchesEnded = NO;
    return self;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}
- (BOOL)canBePreventedByGestureRecognizer:(UIGestureRecognizer *)other {
    return NO;
}
- (BOOL)canPreventGestureRecognizer:(UIGestureRecognizer *)other {
    return NO;
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    sg_touching = YES;
    [sg_rest invalidate];
    sg_rest = nil;
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self lifted:event];
}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self lifted:event];
}
- (void)lifted:(UIEvent *)event {
    for (UITouch *touch in [event touchesForGestureRecognizer:self]) {
        if (touch.phase != UITouchPhaseEnded && touch.phase != UITouchPhaseCancelled) return;
    }
    self.state = UIGestureRecognizerStateFailed;
}
// After the last finger, or the watch ended any other way.
- (void)reset {
    [super reset];
    if (!sg_touching) return;
    sg_touching = NO;
    if (!sg_alone) restartRest();
}
@end

@interface SGRPlayerWake : UITapGestureRecognizer <UIGestureRecognizerDelegate>
@end

// Takes no touch from anything under it, and lets every other recognizer have the same tap.
@implementation SGRPlayerWake
- (instancetype)init {
    if (!(self = [super initWithTarget:nil action:nil])) return nil;
    [self addTarget:self action:@selector(sgr_woke)];
    self.delegate = self;
    self.cancelsTouchesInView = NO;
    self.delaysTouchesEnded = NO;
    self.enabled = NO;
    return self;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}
// Sing's mic and its slider stay while the lines are alone, and a touch on them is theirs alone.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
    for (UIView *v = touch.view; v; v = v.superview) {
        if ([v isKindOfClass:NSClassFromString(@"SGRSingControl")]) return NO;
    }
    return YES;
}
- (void)sgr_woke {
    setAlone(NO, YES);
    restartRest();
}
@end

static void setAlone(BOOL alone, BOOL animated) {
    if (sg_open) return;
    UIView *host = sg_host;
    if (alone == sg_alone || !host || (alone && !sg_open)) return;
    SGRLyricsLayout l = layoutIn(host);
    // Going alone needs somewhere to put the lines. Coming back never waits for it: the controls and the
    // lines' tap are given back even when the player can no longer be measured.
    if (alone && !l.ok) return;
    sg_alone = alone;
    if (alone) {
        [sg_rest invalidate];
        sg_rest = nil;
        l.stage = aloneStage(host, l);
    }
    SGRPlayerLyricsOverlay *overlay = objc_getAssociatedObject(host, &kOverlayKey);
    // Layout and opacity have their own timing; Reduce Motion dissolves the layout in place.
    void (^move)(void) = ^{
        if (!overlay.superview || !l.ok) return;
        place(overlay, host, l);
        overlay.thumb.transform = thumbTransform(l);
        // The lines take the new height in this same spring, so the sung line rides with the stage rather than
        // springing to the new anchor at the next line (SGRKaraokeView's layoutSubviews).
        [overlay.lyrics layoutIfNeeded];
    };
    void (^fade)(void) = ^{
        if (overlay.superview) overlay.lyrics.extrasHidden = alone;
        fadeControls(alone);
    };
    sg_wake.enabled = alone;
    if (overlay) letLinesSeek(overlay, !alone);
    if (animated) {
        SGRAnimateLayout(host, move, nil);
        // Going, the controls take their time, since nobody waits on them; coming back at a touch, they answer at
        // once, from wherever the fade out has got to.
        SGRAnimate(alone ? SGRMotionFade : SGRMotionRespond, fade, nil);
    } else {
        move();
        fade();
    }
    SGLog(@"redesign player: the lines %@", alone ? @"on their own" : @"with the controls");
}

static void setOpen(BOOL open, BOOL animated) {
    (void)animated;
    if (open == sg_open) return;
    if (open && !SGRPlayerLyricsAvailable()) return;
    sg_open = open;
    SGRPlayerLyricsChanged();
    SGRPlayerShowPortraitLyrics(open);
    if (open) SGRPlayerLyricsOrientationChanged();
    if (!open) {
        setAlone(NO, NO);
        SGRPlayerShowLandscape(NO);
        sg_floating.viewIfLoaded.alpha = 1;
        SGRPlayerCoverList().alpha = 1;
        if (sg_titleElement) {
            sg_titleElement.transform = CGAffineTransformIdentity;
            sg_titleElement.layer.mask = nil;
        }
        if (sg_info.viewIfLoaded) sg_info.viewIfLoaded.transform = CGAffineTransformIdentity;
    }
    SGRPlayerMotionCoverLaidOut();
    SGLog(@"redesign player: lyrics %@", open ? @"on their own page" : @"back on the player");
}

void SGRPlayerToggleLyrics(void) {
    if (!sg_open && !SGRPlayerLyricsAvailable()) return;
    setOpen(!sg_open, YES);
}

// A layout pass, a new track or a turn of the phone: the state is put back where it belongs without
// animating, since the frames it is measured from have just changed.
static void replace(void) {
    if (sg_open) return;
    UIView *host = sg_host;
    if (!host || sg_moving) return;   // a pass in the middle of the transition would cut it short
    placeTitleRow(layoutIn(host));
    sg_floating.viewIfLoaded.alpha = 1;
}

#pragma mark - the units

%hook _TtC19NowPlaying_ViewImpl24NowPlayingViewController
- (void)viewDidLayoutSubviews {
    %orig;
    UIView *host = ((UIViewController *)self).viewIfLoaded;
    if (!host || host.bounds.size.height < kLivingHeight) return;
    sg_player = (UIViewController *)self;
    if (sg_host != host) {
        sg_host = host;
        [host addGestureRecognizer:[SGRPlayerTouchWatcher new]];
        SGRPlayerWake *wake = [SGRPlayerWake new];
        [host addGestureRecognizer:wake];
        sg_wake = wake;
        SGLog(@"redesign player: the lyrics have the player's view %.0fx%.0f", host.bounds.size.width, host.bounds.size.height);
    }
    replace();
}

// The bar morphs back out of a full size cover as the player closes, so the thumbnail is put away first.
- (void)viewWillDisappear:(BOOL)animated {
    if (sg_open) setOpen(NO, NO);
    %orig;
}
%end

%hook _TtC20NowPlaying_ModesImpl23InformationElementsUnit
- (void)viewDidLayoutSubviews {
    %orig;
    UIViewController *unit = (UIViewController *)self;
    sg_info = unit;
    UIView *host = unit.viewIfLoaded;
    // The title and the artist are two labels of one arranged element view, which is what moves.
    UIView *label = SGRFindByIdentifier(host, @"now-playing-title-label", &kTitleKey);
    UIView *element = nil;
    for (UIView *v = label; v && v != host; v = v.superview) {
        if ([v.superview isKindOfClass:UIStackView.class]) { element = v; break; }
    }
    if (element && sg_titleElement != element) {
        sg_titleElement = element;
        static dispatch_once_t once;
        dispatch_once(&once, ^{ SGLog(@"redesign player: the title rides on %@ %@", NSStringFromClass(element.class), NSStringFromCGRect(element.frame)); });
    }
    replace();
}
%end

%hook _TtC20NowPlaying_ModesImpl19DurationElementUnit
- (void)viewDidLayoutSubviews {
    %orig;
    sg_duration = (UIViewController *)self;
    replace();
}
%end

// The chips over the title (Switch to video and whatever else a track brings) sit in the middle of the
// room the lines take, so they go while the lines are up. The row keeps its height: the rest of the
// bottom stack stays where it was, which is the whole point of lifting only the title out of it.
%hook _TtC20NowPlaying_ModesImpl20FloatingElementsUnit
- (void)viewDidLayoutSubviews {
    %orig;
    sg_floating = (UIViewController *)self;
    replace();
}
%end

#pragma mark - the track changing under them

@interface SGRPlayerLyricsWatcher : NSObject <SGPlayerStateObserver>
@end

@implementation SGRPlayerLyricsWatcher {
    NSString *_track;
    BOOL _graceOver;   // the track playing has had its kLyricsGrace
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    // An edit of a local file's names gives it a new lyrics key, and the sources search again under it.
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(editsChanged:) name:SGLocalFileEditsDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(linesKept:) name:SGKaraokeLinesDidChangeNotification object:nil];
    return self;
}

// A rename is looked up like a new track, so lines that stay up with none for the new names go once the
// look for them ends, as a new track's do after the grace.
- (void)editsChanged:(NSNotification *)note {
    if (![note.object isKindOfClass:NSString.class] || ![note.object isEqualToString:_track]) return;
    SGRPlayerLyricsChanged();
}

// Lines kept for the track playing, or the look for them over with none. The glyph is told only when they
// are here, since SGRPlayerLyricsChanged sets the animated artwork's blur each time.
- (void)linesKept:(NSNotification *)note {
    if (![note.object isEqual:SGKaraokePlayingTrack()]) return;
    if (SGRPlayerLyricsAvailable()) SGRPlayerLyricsChanged();
    else [self closeIfNone];
}

// The lines go once the grace is over and nothing is looking for the track's own any more.
- (void)closeIfNone {
    if (!_graceOver || !sg_open || SGRPlayerLyricsAvailable() || SGKaraokeLooking(SGKaraokePlayingTrack())) return;
    SGLog(@"redesign player: no lyrics for the track that came on, the cover is back");
    setOpen(NO, YES);
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    // A pause brings the controls back and keeps them; playing again starts the clock.
    if (state.isPaused) {
        setAlone(NO, YES);
        [sg_rest invalidate];
        sg_rest = nil;
    } else if (!sg_rest && !sg_alone) {
        restartRest();
    }
    NSString *track = SGURIString(state.track.URI);
    if (!track || [track isEqualToString:_track]) return;
    _track = track;
    _graceOver = NO;
    SGRPlayerLyricsChanged();
    // The lines already up wait out a grace for the new track's before they go, a track after it its own.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kLyricsGrace * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (![self->_track isEqualToString:track]) return;
        self->_graceOver = YES;
        [self closeIfNone];
    });
}

@end

#pragma mark - lyrics page

static const CGFloat kPageCover = 72, kPagePad = 20, kPageGap = 12;

@interface SGRPortraitLyricsController : UIViewController <SGPlayerStateObserver>
@end

static SGRPortraitLyricsController *sg_page;

@implementation SGRPortraitLyricsController {
    SGRArtworkField *_field;
    UIImageView *_cover;
    SGMarqueeLabel *_title, *_artist;
    UIButton *_close, *_play;
    UIStackView *_controls;
    UIView *_stage;
    SGRKaraokeView *_lyrics;
    NSTimer *_rest;
    UIView *_shield;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskPortrait;
}

- (BOOL)shouldAutorotate {
    return NO;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    _field = [[SGRArtworkField alloc] initWithFrame:self.view.bounds];
    _field.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _field.showsBackdrop = YES;
    SGRPlayerApplyBackgroundToField(_field, SGRPlayerBackground());
    NSString *identity = nil;
    UIImage *art = SGRNowPlayingArtwork(NULL, &identity);
    if (art) [_field setArtwork:art identity:identity animated:NO];
    [self.view addSubview:_field];

    _cover = [UIImageView new];
    _cover.contentMode = UIViewContentModeScaleAspectFill;
    _cover.clipsToBounds = YES;
    _cover.layer.cornerRadius = 10;
    _cover.layer.cornerCurve = kCACornerCurveContinuous;
    _cover.image = art;
    [self.view addSubview:_cover];

    _title = [SGMarqueeLabel new];
    _title.font = SGRFont(UIFontTextStyleHeadline, UIFontWeightBold, UIContentSizeCategoryExtraExtraLarge);
    _title.textColor = UIColor.whiteColor;
    _artist = [SGMarqueeLabel new];
    _artist.font = SGRFont(UIFontTextStyleSubheadline, UIFontWeightRegular, UIContentSizeCategoryExtraExtraLarge);
    _artist.textColor = [UIColor colorWithWhite:1 alpha:0.62];
    [self.view addSubview:_title];
    [self.view addSubview:_artist];

    _close = [UIButton buttonWithType:UIButtonTypeSystem];
    SGRStyleLyricsChromeButton(_close, @"chevron.down", 18, UIImageSymbolWeightSemibold);
    _close.tintColor = UIColor.whiteColor;
    _close.accessibilityLabel = @"Close lyrics";
    [_close addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_close];

    _play = [UIButton buttonWithType:UIButtonTypeSystem];
    _play.tintColor = UIColor.whiteColor;
    [_play addTarget:self action:@selector(togglePlay) forControlEvents:UIControlEventTouchUpInside];
    UIButton *previous = [self transport:@"backward.fill" label:@"Previous track" action:@selector(previous)];
    UIButton *next = [self transport:@"forward.fill" label:@"Next track" action:@selector(next)];
    SGRStyleLyricsChromeButton(_play, @"pause.fill", 28, UIImageSymbolWeightBold);
    _controls = [[UIStackView alloc] initWithArrangedSubviews:@[previous, _play, next]];
    _controls.distribution = UIStackViewDistributionEqualSpacing;
    _controls.alignment = UIStackViewAlignmentCenter;
    [self.view addSubview:_controls];

    _stage = [UIView new];
    _stage.backgroundColor = UIColor.clearColor;
    _stage.opaque = NO;
    [self.view addSubview:_stage];
    _lyrics = [[SGRKaraokeView alloc] initWithFrame:CGRectZero];
    _lyrics.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _lyrics.extrasEnabled = SGEnabled(SGRKeyPlayerTranslateButton);
    _lyrics.paintsBackdrop = NO;
    [_stage addSubview:_lyrics];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(backdropChanged) name:SGRLyricsLookDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(backdropChanged) name:SGRLyricsCoverColorsDidChangeNotification object:nil];

    _shield = [UIView new];
    _shield.accessibilityElementsHidden = YES;
    [_shield addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(wake)]];
    UIPanGestureRecognizer *pull = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pulled:)];
    [self.view addGestureRecognizer:pull];

    SGAddPlayerStateObserver(self);
    [self playerStateDidChange:SGPlayerState()];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(artworkChanged) name:SGRNowPlayingArtworkDidChangeNotification object:nil];
    [self applyChrome];
}

- (UIButton *)transport:(NSString *)symbol label:(NSString *)label action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    SGRStyleLyricsChromeButton(button, symbol, 22, UIImageSymbolWeightBold);
    button.tintColor = UIColor.whiteColor;
    button.accessibilityLabel = label;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_rest invalidate];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect safe = UIEdgeInsetsInsetRect(self.view.bounds, self.view.safeAreaInsets);
    CGFloat top = CGRectGetMinY(safe) + 8;
    _cover.frame = CGRectMake(CGRectGetMinX(safe) + kPagePad, top, kPageCover, kPageCover);
    _close.frame = CGRectMake(CGRectGetMaxX(safe) - kPagePad - 44, top, 44, 44);
    CGFloat textX = CGRectGetMaxX(_cover.frame) + kPageGap;
    CGFloat textW = CGRectGetMinX(_close.frame) - textX - 8;
    CGFloat titleH = ceil(_title.font.lineHeight), artistH = ceil(_artist.font.lineHeight);
    CGFloat textY = top + (kPageCover - titleH - artistH) / 2;
    _title.frame = CGRectMake(textX, textY, textW, titleH);
    _artist.frame = CGRectMake(textX, CGRectGetMaxY(_title.frame), textW, artistH);
    CGFloat controlsH = 52;
    _controls.frame = CGRectMake(CGRectGetMinX(safe) + 36, CGRectGetMaxY(safe) - controlsH - 8, safe.size.width - 72, controlsH);
    CGFloat stageY = CGRectGetMaxY(_cover.frame) + 16;
    CGFloat stageH = CGRectGetMinY(_controls.frame) - 8 - stageY;
    if (stageH < 1) stageH = 1;
    _stage.frame = CGRectMake(0, stageY, MAX(self.view.bounds.size.width, 0), stageH);
    _lyrics.frame = _stage.bounds;
    _shield.frame = self.view.bounds;
    SGRLyricsFillScreen(self.view, _field);
}

- (void)applyChrome {
    UIColor *outline = SGRLyricsOutlineColor();
    _title.outlineColor = outline;
    _artist.outlineColor = outline;
    SGRRefreshLyricsChromeButton(_close);
    SGRRefreshLyricsChromeButton(_play);
    for (UIView *view in _controls.arrangedSubviews)
        if ([view isKindOfClass:UIButton.class]) SGRRefreshLyricsChromeButton((UIButton *)view);
}

- (void)backdropChanged {
    [self.view setNeedsLayout];
    [self applyChrome];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self restartRest];
}

- (id<SPTPlayer>)player {
    id player = SGKaraokePlayer();
    return [player respondsToSelector:@selector(pause:)] ? player : nil;
}

- (void)togglePlay {
    if (SGPlayerState().isPaused) [self.player resume:nil];
    else [self.player pause:nil];
    [self restartRest];
}

- (void)previous {
    [self.player skipToPreviousTrackWithOptions:nil];
    [self restartRest];
}

- (void)next {
    [self.player skipToNextTrackWithOptions:nil];
    [self restartRest];
}

- (void)close {
    SGRPlayerToggleLyrics();
}

- (void)pulled:(UIPanGestureRecognizer *)pan {
    if (pan.state == UIGestureRecognizerStateEnded && [pan translationInView:self.view].y > 90) [self close];
}

- (void)artworkChanged {
    NSString *identity = nil;
    UIImage *art = SGRNowPlayingArtwork(NULL, &identity);
    if (!art) return;
    _cover.image = art;
    [_field setArtwork:art identity:identity animated:YES];
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    if (!state) return;
    _title.text = state.track.trackTitle;
    _artist.text = state.track.artistName;
    BOOL paused = state.isPaused;
    SGRStyleLyricsChromeButton(_play, paused ? @"play.fill" : @"pause.fill", 28, UIImageSymbolWeightBold);
    _play.accessibilityLabel = paused ? @"Play" : @"Pause";
    _field.motionHeld = paused;
    if (paused) [self setControlsShown:YES];
    else if (!_rest && !_shield.superview) [self restartRest];
}

- (void)setControlsShown:(BOOL)shown {
    [_rest invalidate];
    _rest = nil;
    if (shown) [_shield removeFromSuperview];
    else if (!_shield.superview) [self.view addSubview:_shield];
    SGRAnimate(shown ? SGRMotionRespond : SGRMotionFade, ^{
        self->_controls.alpha = shown ? 1 : 0;
        self->_close.alpha = shown ? 1 : 0;
        self->_lyrics.extrasHidden = !shown;
    }, nil);
    if (shown) [self restartRest];
}

- (void)wake {
    [self setControlsShown:YES];
}

- (void)restartRest {
    [_rest invalidate];
    _rest = nil;
}

@end

static UIWindowScene *phoneScene(void) {
    UIWindowScene *fallback = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        if (!fallback) fallback = (UIWindowScene *)scene;
        if (scene.activationState == UISceneActivationStateForegroundActive) return (UIWindowScene *)scene;
    }
    return fallback;
}

static UIWindow *hostWindow(UIWindowScene *scene) {
    for (UIWindow *window in scene.windows) if (window.isKeyWindow && !window.hidden) return window;
    for (UIWindow *window in scene.windows) if (!window.hidden && window.windowLevel <= UIWindowLevelNormal) return window;
    return nil;
}

void SGRPlayerPortraitLyricsObscured(BOOL obscured) {
    sg_page.view.hidden = obscured;
}

// A second window made key is what UIKit rejects once the app has been allowed to turn. The page is a
// child of the window already on screen, so opening it does not ask the scene to rotate.
void SGRPlayerShowPortraitLyrics(BOOL show) {
    if (!phoneScene()) return;
    if (show && !sg_page) {
        UIWindow *host = hostWindow(phoneScene());
        UIViewController *parent = host.rootViewController;
        if (!host || !parent) return;
        SGRPortraitLyricsController *page = [SGRPortraitLyricsController new];
        page.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        [parent addChildViewController:page];
        page.view.frame = host.bounds;
        page.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        page.view.alpha = 0;
        [host addSubview:page.view];
        [page didMoveToParentViewController:parent];
        sg_page = page;
        SGRAnimate(SGRMotionFade, ^{ page.view.alpha = 1; }, nil);
        SGLog(@"redesign player: lyrics page up");
    } else if (!show && sg_page) {
        SGRPortraitLyricsController *page = sg_page;
        sg_page = nil;
        page.view.userInteractionEnabled = NO;
        SGRAnimate(SGRMotionFade, ^{ page.view.alpha = 0; }, ^(BOOL finished) {
            (void)finished;
            [page willMoveToParentViewController:nil];
            [page.view removeFromSuperview];
            [page removeFromParentViewController];
        });
        SGLog(@"redesign player: lyrics page down");
    }
}

static SGRPlayerLyricsWatcher *sg_watcher;

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    sg_watcher = [SGRPlayerLyricsWatcher new];
    SGAddPlayerStateObserver(sg_watcher);
    // In the background the controls stay up; back in front the clock starts again.
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        setAlone(NO, NO);
        [sg_rest invalidate];
        sg_rest = nil;
    }];
    [NSNotificationCenter.defaultCenter addObserverForName:SGSingDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        if (!sg_open || !sg_host) return;
        syncSingControl(objc_getAssociatedObject(sg_host, &kOverlayKey));
    }];
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        restartRest();
        // The lyrics button asked again on the way back and twice after, as the lines can land in the meantime;
        // it stayed dimmed after an instrumental heard in the background.
        SGRPlayerLyricsChanged();
        for (NSNumber *wait in @[@1, @3]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(wait.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ SGRPlayerLyricsChanged(); });
        }
    }];
    // VoiceOver keeps the controls up: turned on, it brings them back.
    [NSNotificationCenter.defaultCenter addObserverForName:UIAccessibilityVoiceOverStatusDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        setAlone(NO, YES);
        restartRest();
    }];
    [NSNotificationCenter.defaultCenter addObserverForName:SGRNowPlayingArtworkDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        if (!sg_open) return;
        SGRPlayerLyricsOverlay *overlay = objc_getAssociatedObject(sg_host, &kOverlayKey);
        overlay.cover.image = SGRNowPlayingArtwork(NULL, NULL);
    }];
    SGRequireClasses(@[
        @"_TtC19NowPlaying_ViewImpl24NowPlayingViewController",
        @"_TtC20NowPlaying_ModesImpl23InformationElementsUnit",
        @"_TtC20NowPlaying_ModesImpl19DurationElementUnit",
        @"_TtC20NowPlaying_ModesImpl20FloatingElementsUnit",
    ]);
}
