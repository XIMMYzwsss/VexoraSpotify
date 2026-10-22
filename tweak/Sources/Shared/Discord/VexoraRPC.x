// Discord status for this Spotify app, the same presence Vexora sends (Listening to Vexora).
#import "VexoraRPC.h"
#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/Player/PlayerState.h"
#import <Security/Security.h>

static NSString *const kDiscordClientId = @"1558323193859543080";
static NSString *const kKeychainService = @"app.vexora.ios.discord";

static NSString *clip(NSString *text, NSUInteger maxLen) {
    if (![text isKindOfClass:NSString.class]) return @"";
    NSString *s = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return s.length <= maxLen ? s : [s substringToIndex:maxLen];
}

static NSString *keychainToken(void) {
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kKeychainService,
        (__bridge id)kSecAttrAccount: @"token",
        (__bridge id)kSecReturnData: @YES,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne
    };
    CFTypeRef result = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)query, &result) != errSecSuccess || !result) return @"";
    NSData *data = CFBridgingRelease(result);
    return clip([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding], 400);
}

static NSString *savedToken(void) {
    NSString *stored = [NSUserDefaults.standardUserDefaults stringForKey:SGRKeyDiscordToken];
    if (stored.length) return clip(stored, 400);
    return keychainToken();
}

@interface SGVexoraDiscord : NSObject <NSURLSessionWebSocketDelegate, SGPlayerStateObserver>
@end

@implementation SGVexoraDiscord {
    NSURLSession *_session;
    NSURLSessionWebSocketTask *_task;
    NSTimer *_heartbeat, *_tick;
    NSString *_token, *_signature, *_track, *_cover;
    NSInteger _seq;
    BOOL _open, _identified, _dirty, _force;
    NSTimeInterval _lastSend;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _seq = -1;
    _session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.defaultSessionConfiguration delegate:self delegateQueue:NSOperationQueue.mainQueue];
    return self;
}

- (void)start {
    _token = savedToken();
    SGAddPlayerStateObserver(self);
    _tick = [NSTimer timerWithTimeInterval:3 target:self selector:@selector(refresh) userInfo:nil repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:_tick forMode:NSRunLoopCommonModes];
    if (_token.length) [self connect];
    [self refresh];
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    (void)state;
    _force = YES;
    [self refresh];
}

- (NSString *)lyricNow {
    NSString *track = SGKaraokePlayingTrack();
    NSArray<SGKaraokeLine *> *lines = SGKaraokeLinesForTrack(track);
    NSInteger ms = SGKaraokePositionMs();
    if (!lines.count || ms < 0) return @"";
    NSInteger index = SGKaraokeLeadLine(lines, ms);
    if (index < 0 || (NSUInteger)index >= lines.count) return @"";
    return clip(SGKaraokeLineText(lines[(NSUInteger)index]), 120);
}

- (NSString *)artworkURL {
    NSDictionary *metadata = SGPlayerState().track.metadata;
    if (![metadata isKindOfClass:NSDictionary.class]) return @"";
    for (NSString *field in @[@"image_xlarge_url", @"image_large_url", @"image_url"]) {
        NSString *value = metadata[field];
        if (![value isKindOfClass:NSString.class] || !value.length) continue;
        if ([value hasPrefix:@"https://"]) return value;
        if ([value hasPrefix:@"spotify:image:"]) return [@"https://i.scdn.co/image/" stringByAppendingString:[value substringFromIndex:14]];
    }
    return @"";
}

- (NSString *)discordImage:(NSString *)https {
    if (![https hasPrefix:@"https://"]) return @"";
    return [@"mp:external/https/" stringByAppendingString:[https substringFromIndex:8]];
}

- (void)lookupCover {
    SPTPlayerState *state = SGPlayerState();
    NSString *title = clip(state.track.trackTitle, 120);
    NSString *artist = clip(state.track.artistName, 120);
    if (!title.length) return;
    NSString *query = [NSString stringWithFormat:@"artist:\"%@\" track:\"%@\"", artist, title];
    NSString *escaped = [query stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
    NSURL *url = [NSURL URLWithString:[@"https://api.deezer.com/search?limit=1&q=" stringByAppendingString:escaped ?: @""]];
    NSString *key = [_track copy];
    __weak SGVexoraDiscord *weak = self;
    [[NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        (void)response; (void)error;
        dispatch_async(dispatch_get_main_queue(), ^{
            SGVexoraDiscord *self_ = weak;
            if (!self_ || ![self_->_track isEqualToString:key] || !data.length) return;
            NSDictionary *obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSArray *rows = [obj isKindOfClass:NSDictionary.class] ? obj[@"data"] : nil;
            NSDictionary *row = [rows isKindOfClass:NSArray.class] ? rows.firstObject : nil;
            NSString *cover = [row[@"album"] isKindOfClass:NSDictionary.class] ? row[@"album"][@"cover_xl"] : nil;
            if (![cover isKindOfClass:NSString.class] || ![cover hasPrefix:@"https://"]) return;
            self_->_cover = cover;
            self_->_force = YES;
            [self_ pushPresence];
        });
    }] resume];
}

- (NSDictionary *)presenceBody {
    SPTPlayerState *state = SGPlayerState();
    BOOL hasTrack = state.track.trackTitle.length > 0;
    BOOL playing = hasTrack && !state.isPaused;
    NSMutableDictionary *activity = [@{@"name": @"Vexora", @"type": @2, @"application_id": kDiscordClientId} mutableCopy];
    activity[@"details"] = hasTrack ? clip(state.track.trackTitle, 120) : @"Idle";
    NSString *artist = clip(state.track.artistName, 120);
    NSString *lyric = hasTrack ? [self lyricNow] : @"";
    NSString *album = [state.track.metadata[@"album_title"] isKindOfClass:NSString.class] ? state.track.metadata[@"album_title"] : @"";
    if (hasTrack && lyric.length) activity[@"state"] = clip([NSString stringWithFormat:@"%@ · %@", artist, lyric], 120);
    else if (hasTrack && artist.length) activity[@"state"] = artist;
    if (hasTrack) {
        NSInteger posMs = MAX(0, SGKaraokePositionMs());
        long long nowMs = (long long)([NSDate date].timeIntervalSince1970 * 1000);
        long long durMs = (long long)llround(MAX(0, state.duration) * 1000);
        if (durMs > posMs) activity[@"timestamps"] = @{@"start": @(nowMs - posMs), @"end": @(nowMs - posMs + durMs)};
        else activity[@"timestamps"] = @{@"start": @(nowMs - posMs)};
        NSString *image = _cover.length ? _cover : [self artworkURL];
        NSString *external = [self discordImage:image];
        if (external.length) {
            NSMutableDictionary *assets = [@{@"large_image": external} mutableCopy];
            if (album.length) assets[@"large_text"] = clip(album, 120);
            else if (lyric.length) assets[@"large_text"] = lyric;
            activity[@"assets"] = assets;
        }
    }
    (void)playing;
    return @{@"since": NSNull.null, @"activities": @[activity], @"status": @"online", @"afk": @NO};
}

- (void)connect {
    if (!_token.length || _task) return;
    _task = [_session webSocketTaskWithURL:[NSURL URLWithString:@"wss://gateway.discord.gg/?v=10&encoding=json"]];
    [_task resume];
    [self receive];
}

- (void)closeSocket {
    _open = NO;
    _identified = NO;
    [_heartbeat invalidate];
    _heartbeat = nil;
    [_task cancelWithCloseCode:NSURLSessionWebSocketCloseCodeNormalClosure reason:nil];
    _task = nil;
}

- (void)receive {
    NSURLSessionWebSocketTask *task = _task;
    if (!task) return;
    __weak SGVexoraDiscord *weak = self;
    [task receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage *message, NSError *error) {
        SGVexoraDiscord *self_ = weak;
        if (!self_ || task != self_->_task) return;
        if (error) {
            [self_ closeSocket];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self_ connect]; });
            return;
        }
        NSString *text = message.string;
        if (!text.length && message.data) text = [[NSString alloc] initWithData:message.data encoding:NSUTF8StringEncoding];
        [self_ handle:text];
        [self_ receive];
    }];
}

- (void)handle:(NSString *)text {
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *obj = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![obj isKindOfClass:NSDictionary.class]) return;
    NSInteger op = [obj[@"op"] integerValue];
    if ([obj[@"s"] isKindOfClass:NSNumber.class]) _seq = [obj[@"s"] integerValue];
    if (op == 10) {
        NSTimeInterval ms = [obj[@"d"][@"heartbeat_interval"] doubleValue];
        if (ms < 1000) ms = 41250;
        [_heartbeat invalidate];
        _heartbeat = [NSTimer timerWithTimeInterval:ms / 1000.0 target:self selector:@selector(beat) userInfo:nil repeats:YES];
        [NSRunLoop.mainRunLoop addTimer:_heartbeat forMode:NSRunLoopCommonModes];
        [self beat];
        _open = YES;
        [self sendJSON:@{@"op": @2, @"d": @{@"token": _token ?: @"", @"properties": @{@"os": @"iOS", @"browser": @"Discord iOS", @"device": @"iPhone"}, @"presence": [self presenceBody]}}];
    } else if (op == 7 || op == 9) {
        [self closeSocket];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self connect]; });
    } else if (op == 0 && !_identified) {
        _identified = YES;
        _force = YES;
        [self pushPresence];
    }
}

- (void)beat {
    [self sendJSON:@{@"op": @1, @"d": _seq >= 0 ? @(_seq) : NSNull.null}];
}

- (void)refresh {
    NSString *next = savedToken();
    if (![next isEqualToString:_token ?: @""]) {
        _token = next;
        [self closeSocket];
        if (_token.length) [self connect];
    }
    NSString *track = SGKaraokePlayingTrack() ?: @"";
    if (![track isEqualToString:_track ?: @""]) {
        _track = track;
        _cover = @"";
        _force = YES;
        [self lookupCover];
    }
    if (SGPlayerState().isPaused) _force = YES;
    _dirty = YES;
    [self pushPresence];
}

- (void)pushPresence {
    if (!_open || !_token.length) return;
    NSTimeInterval now = NSDate.timeIntervalSinceReferenceDate;
    if (!_force && now - _lastSend < 4) return;
    NSData *data = [NSJSONSerialization dataWithJSONObject:[self presenceBody] options:0 error:nil];
    NSString *sig = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
    if (!_force && [sig isEqualToString:_signature ?: @""]) return;
    _signature = sig;
    _force = NO;
    _lastSend = now;
    [self sendJSON:@{@"op": @3, @"d": [self presenceBody]}];
}

- (void)sendJSON:(id)obj {
    if (!_task || !obj) return;
    NSData *data = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
    if (!data) return;
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    [_task sendMessage:[[NSURLSessionWebSocketMessage alloc] initWithString:text] completionHandler:^(NSError *error) {
        if (error) SGLog(@"discord: %@", error.localizedDescription);
    }];
}

- (void)URLSession:(NSURLSession *)session webSocketTask:(NSURLSessionWebSocketTask *)task didCloseWithCode:(NSURLSessionWebSocketCloseCode)code reason:(NSData *)reason {
    (void)session; (void)reason;
    if (task != _task) return;
    _open = NO;
    _identified = NO;
    [_heartbeat invalidate];
    _heartbeat = nil;
    _task = nil;
    if (code == 4004) {
        SGLog(@"discord: token rejected");
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self connect]; });
}

@end

static SGVexoraDiscord *sg_discord;

void SGVexoraDiscordStart(void) {
    if (sg_discord) return;
    sg_discord = [SGVexoraDiscord new];
    [sg_discord start];
}

static void askToken(void) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Discord token" message:@"The same token Vexora uses. Status shows as Listening to Vexora, with the current lyric." preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Token";
        field.secureTextEntry = YES;
        field.text = savedToken();
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Clear" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [NSUserDefaults.standardUserDefaults removeObjectForKey:SGRKeyDiscordToken];
        [sg_discord refresh];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *token = clip(alert.textFields.firstObject.text, 400);
        if (token.length) [NSUserDefaults.standardUserDefaults setObject:token forKey:SGRKeyDiscordToken];
        else [NSUserDefaults.standardUserDefaults removeObjectForKey:SGRKeyDiscordToken];
        [sg_discord refresh];
    }]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

SGModRow *SGVexoraDiscordRow(void) {
    return SGStatActionRow(@"Discord status", @"Listening to Vexora, including the lyric line", ^NSString *{
        return savedToken().length ? @"On" : @"Off";
    }, ^{ askToken(); });
}

%ctor {
    SGVexoraDiscordStart();
}
