#import "SGGlassPolicy.h"
#import "SGRuntime.h"

BOOL SGPlayerScreenGlassEnabled(void) {
    return NO;
}

BOOL SGGlassTintsFromContentEnabled(void) {
    return NO;
}

BOOL SGViewIsOnPlayerScreen(UIView *view) {
    if (!view) return NO;
    for (UIView *walk = view; walk; walk = walk.superview) {
        NSString *name = NSStringFromClass(walk.class);
        if ([name containsString:@"NowPlaying"]
            || [name containsString:@"NPV"]
            || [name containsString:@"Lyrics_Card"]
            || [name containsString:@"Lyrics_NPV"]
            || [name containsString:@"SGRPlayerMenu"]
            || [name containsString:@"SGRSingControl"]
            || [name containsString:@"SGRLyricsSongPill"]) return YES;
    }
    return NO;
}