// PlayerState.h names the hooks and why they are the ones.
#import <MediaPlayer/MediaPlayer.h>
#import "Core/SGCore.h"
#import "PlayerState.h"

NSString *SGURIString(id uri) {
    if ([uri isKindOfClass:NSString.class]) return uri;
    if ([uri isKindOfClass:NSURL.class]) return ((NSURL *)uri).absoluteString;
    return nil;
}

static NSHashTable<id<SGPlayerStateObserver>> *sg_stateObservers;
static SPTPlayerState *sg_playerState;
static NSString *sg_stateKey;
// Set once the now playing platform has reported; the mod's own observer on the player stands down.
static BOOL sg_platformReported = NO;

void SGAddPlayerStateObserver(id<SGPlayerStateObserver> observer) {
    if (!observer) return;
    if (!sg_stateObservers) sg_stateObservers = [NSHashTable weakObjectsHashTable];
    [sg_stateObservers addObject:observer];
}

SPTPlayerState *SGPlayerState(void) {
    return sg_playerState;
}

BOOL SGPlayerIsPlaying(void) {
    NSDictionary *info = MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo;
    NSNumber *rate = info[MPNowPlayingInfoPropertyPlaybackRate];
    if ([rate isKindOfClass:NSNumber.class] && rate.doubleValue > 0.01) return YES;
    if (@available(iOS 13.0, *)) {
        if (MPNowPlayingInfoCenter.defaultCenter.playbackState == MPNowPlayingPlaybackStatePlaying) return YES;
    }
    SPTPlayerState *state = sg_playerState;
    if (!state) return NO;
    if ([state respondsToSelector:@selector(isPlaying)] && [state respondsToSelector:@selector(isPaused)]
        && state.isPlaying && !state.isPaused) return YES;
    if ([state respondsToSelector:@selector(isPaused)] && !state.isPaused && state.track) return YES;
    return NO;
}

// What an observer is told about; the state object itself is new with every position report.
static NSString *keyOf(SPTPlayerState *state) {
    SPTPlayerOptions *options = [state respondsToSelector:@selector(options)] ? state.options : nil;
    BOOL shuffling = [options respondsToSelector:@selector(shufflingContext)] && options.shufflingContext;
    return [NSString stringWithFormat:@"%@|%@|%d%d%d%d", SGURIString(state.track.URI), SGURIString(state.contextURI),
            state.isPaused, state.isPlaying, [state respondsToSelector:@selector(isLoading)] && state.isLoading, shuffling];
}

static void publish(SPTPlayerState *state) {
    sg_playerState = state;
    NSString *key = keyOf(state);
    if ([key isEqualToString:sg_stateKey]) return;
    sg_stateKey = key;
    for (id<SGPlayerStateObserver> observer in sg_stateObservers.allObjects) [observer playerStateDidChange:state];
}

static void report(id state, BOOL platform) {
    if (![state isKindOfClass:objc_getClass("SPTPlayerState")]) return;
    dispatch_block_t apply = ^{
        if (platform) sg_platformReported = YES;
        else if (sg_platformReported) return;
        publish(state);
    };
    if (NSThread.isMainThread) apply();
    else dispatch_async(dispatch_get_main_queue(), apply);
}

@interface SGPlayerObserver : NSObject
@end

@implementation SGPlayerObserver
- (void)player:(id)player stateDidChange:(id)state {
    report(state, NO);
}
@end

static SGPlayerObserver *sg_ownObserver;

%hook _TtC23NowPlaying_PlatformImpl28StatefulPlayerImplementation
- (void)player:(id)player stateDidChange:(id)state {
    %orig;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        SGLog(@"player state: from %@, a %@, on the main thread %d", [player class], [state class], NSThread.isMainThread);
    });
    report(state, YES);
}
%end

%hook SPTEsperantoPlayer
- (void)addPlayerObserver:(id)observer {
    %orig;
    id player = self;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            sg_ownObserver = [SGPlayerObserver new];
            [(id<SPTPlayer>)player addPlayerObserver:sg_ownObserver];
            id state = [player respondsToSelector:@selector(state)] ? [(id<SPTPlayer>)player state] : nil;
            if (state) report(state, NO);
        });
    });
}
%end

// Connect often leaves SPTPlayerState.isPaused set on this phone while the other device plays. The
// now-playing rate is what moves, so observers get a chance to run the field and the clip then.
%hook MPNowPlayingInfoCenter
- (void)setNowPlayingInfo:(NSDictionary *)info {
    %orig;
    static NSString *lastTitle;
    static double lastRate = NAN;
    NSString *title = [info[MPMediaItemPropertyTitle] isKindOfClass:NSString.class] ? info[MPMediaItemPropertyTitle] : @"";
    NSNumber *rate = info[MPNowPlayingInfoPropertyPlaybackRate];
    // Spotify's elapsed-only dictionaries leave the rate out. That is not a pause: treating it as 0
    // republished every observer and paused the clip, which froze Moving artwork on Home.
    double r = [rate isKindOfClass:NSNumber.class] ? rate.doubleValue : (!isnan(lastRate) ? lastRate : 0);
    BOOL changed = !lastTitle || ![title isEqualToString:lastTitle] || !(fabs(r - lastRate) < 0.01);
    lastTitle = title;
    lastRate = r;
    if (!changed) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!sg_playerState) return;
        sg_stateKey = nil;
        publish(sg_playerState);
    });
}
%end

%ctor {
    %init;
    SGRequireClasses(@[@"_TtC23NowPlaying_PlatformImpl28StatefulPlayerImplementation", @"SPTEsperantoPlayer", @"SPTPlayerState"]);
}
