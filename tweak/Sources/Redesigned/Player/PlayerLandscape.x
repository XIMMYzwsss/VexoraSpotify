// The app stays upright. Spotify's iPhone build is portrait only, and nothing here asks it to turn.
#import "Player.h"

void SGRPlayerShowLandscape(BOOL show) {
    (void)show;
}

void SGRPlayerLyricsOrientationChanged(void) {
}

void SGRPlayerForceLandscapeLyrics(void) {
}
