// ListeningStats.h says what Listening stats is. This is the recording: PlayerState's observer is told
// when the track or playing changes, never the position, so a play's length is the wall-clock time it
// spent playing, and it is written down when the next track takes over.
//
// ponytail: a track on repeat one never changes the state's track, so its replays are not counted, and a
// play cut off by Spotify being killed is lost; position polling would catch both.
#import "Core/SGCore.h"
#import "Shared/Player/PlayerState.h"
#import "ListeningStats.h"
#import "SGPlayLog.h"

SGPlayLog *SGListeningLog(void) {
    static SGPlayLog *log;
    if (!log) {
        NSString *support = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
        log = [[SGPlayLog alloc] initWithPath:[support stringByAppendingPathComponent:@"spoti.pw/Listening.tsv"]];
    }
    return log;
}

static NSString *stringIn(id value) {
    return [value isKindOfClass:NSString.class] ? value : nil;
}

static BOOL isPlaylistURI(NSString *uri) {
    return [uri containsString:@":playlist:"];
}

static NSString *savedPlaylistName(NSString *uri) {
    id names = [NSUserDefaults.standardUserDefaults dictionaryForKey:SGKeyPlaylistNames];
    id name = [names isKindOfClass:NSDictionary.class] ? names[uri] : nil;
    return [name isKindOfClass:NSString.class] && [name length] ? name : nil;
}

static NSString *playlistTitle(NSString *text) {
    NSString *name = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *lower = name.lowercaseString;
    for (NSString *prefix in @[@"playing from ", @"playing "]) {
        if ([lower hasPrefix:prefix] && name.length > prefix.length) {
            name = [[name substringFromIndex:prefix.length] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            lower = name.lowercaseString;
            break;
        }
    }
    for (NSString *sep in @[@" • ", @" · "]) {
        NSRange range = [name rangeOfString:sep];
        if (range.location == NSNotFound || range.location > 24) continue;
        NSString *head = [name substringToIndex:range.location].lowercaseString;
        if ([head containsString:@"playlist"]) name = [name substringFromIndex:NSMaxRange(range)];
    }
    name = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return name.length && ![name hasPrefix:@"spotify:"] ? name : nil;
}

static NSString *nameInMetadata(NSDictionary *metadata) {
    for (NSString *key in @[@"context_name", @"context_title", @"playlist_name", @"entity_name", @"context_description"]) {
        NSString *name = playlistTitle(stringIn(metadata[key]));
        if (name) return name;
    }
    return nil;
}

@interface SGPlayRecorder : NSObject <SGPlayerStateObserver>
- (void)rememberContext:(NSString *)text;
@end

static SGPlayRecorder *sg_recorder;

void SGListeningRememberContext(NSString *text) {
    [sg_recorder rememberContext:text];
}

@implementation SGPlayRecorder {
    SGPlay *_play;
    double _duration, _listened;
    CFAbsoluteTime _since;   // when it started playing, 0 while it is not
}

// Songs and local files; not ads, episodes or the silence between.
static BOOL isMusic(NSString *uri) {
    return [uri hasPrefix:@"spotify:track:"] || [uri hasPrefix:@"spotify:local:"];
}

// The metadata can come after the track does, so what is missing is filled in on every report.
- (void)fill:(SPTPlayerState *)state {
    SPTPlayerTrack *track = state.track;
    NSDictionary *metadata = [track respondsToSelector:@selector(metadata)] ? track.metadata : nil;
    if (!_play.title.length) _play.title = stringIn(track.trackTitle) ?: stringIn(metadata[@"title"]) ?: @"";
    if (!_play.artist.length) _play.artist = stringIn(metadata[@"artist_name"]) ?: stringIn(track.artistName) ?: @"";
    if (!_play.album.length) _play.album = stringIn(metadata[@"album_title"]) ?: @"";
    NSString *context = SGURIString(state.contextURI);
    if (isPlaylistURI(context)) {
        _play.playlistURI = context;
        if (!_play.playlist.length) _play.playlist = nameInMetadata(metadata) ?: savedPlaylistName(context) ?: @"";
    }
    if (_duration <= 0) _duration = state.duration;
}

- (void)rememberContext:(NSString *)text {
    SPTPlayerState *state = SGPlayerState();
    NSString *uri = SGURIString(state.contextURI);
    NSString *name = playlistTitle(text);
    if (!isPlaylistURI(uri) || !name.length) return;
    if ([name isEqualToString:state.track.trackTitle] || [name isEqualToString:state.track.artistName]) return;
    static NSString *seenURI, *seenName;
    if ([uri isEqualToString:seenURI] && [name isEqualToString:seenName]) {
        if ([_play.playlistURI isEqualToString:uri] && !_play.playlist.length) _play.playlist = name;
        return;
    }
    seenURI = uri;
    seenName = name;
    NSMutableDictionary *names = [[NSUserDefaults.standardUserDefaults dictionaryForKey:SGKeyPlaylistNames] mutableCopy] ?: [NSMutableDictionary dictionary];
    if ([names[uri] isEqualToString:name]) {
        if ([_play.playlistURI isEqualToString:uri] && !_play.playlist.length) _play.playlist = name;
        return;
    }
    if (names.count >= 300 && !names[uri]) return;
    names[uri] = name;
    [NSUserDefaults.standardUserDefaults setObject:names forKey:SGKeyPlaylistNames];
    if ([_play.playlistURI isEqualToString:uri]) _play.playlist = name;
}

- (void)finish {
    if (_play && _play.title.length && _play.artist.length && SGPlayCounts(_listened, _duration) && SGEnabled(SGKeyListeningStats)) {
        _play.end = (int64_t)time(NULL);
        _play.ms = (int64_t)(_listened * 1000);
        [SGListeningLog() record:_play];
    }
    _play = nil;
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (_since) _listened += now - _since;
    _since = 0;
    NSString *uri = SGURIString(state.track.URI);
    if (![uri isEqualToString:_play.uri]) {
        [self finish];
        if (isMusic(uri)) {
            _play = [SGPlay new];
            _play.uri = uri;
            _play.playlistURI = @"";
            _play.playlist = @"";
            _duration = _listened = 0;
        }
    }
    if (!_play) return;
    [self fill:state];
    BOOL loading = [state respondsToSelector:@selector(isLoading)] && state.isLoading;
    if (state.isPlaying && !state.isPaused && !loading) _since = now;
}

- (void)terminate {
    if (_since) _listened += CFAbsoluteTimeGetCurrent() - _since;
    _since = 0;
    [self finish];
}

@end

%ctor {
    sg_recorder = [SGPlayRecorder new];
    SGAddPlayerStateObserver(sg_recorder);
    [NSNotificationCenter.defaultCenter addObserver:sg_recorder selector:@selector(terminate) name:UIApplicationWillTerminateNotification object:nil];
}
