#import <UIKit/UIKit.h>
#import "Headers/SPTPlayer.h"

// A URI Spotify types as id (NSURL or NSString) as a string; nil for anything else.
NSString *SGURIString(id uri);

@protocol SGPlayerStateObserver <NSObject>
// Called when the track, the context, paused, playing, loading or shuffle changed, not for position.
- (void)playerStateDidChange:(SPTPlayerState *)state;
@end
// Observers are held weakly and need no removal.
void SGAddPlayerStateObserver(id<SGPlayerStateObserver> observer);
// The last state reported, nil before the player has reported one.
SPTPlayerState *SGPlayerState(void);
// Whether music is actually going, including Connect on another device. This phone can sit on isPaused
// while the other device plays; the system now-playing rate is what tells then.
BOOL SGPlayerIsPlaying(void);
