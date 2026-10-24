// The app stays upright. Spotify's iPhone build is portrait only.
#import "Player.h"

void SGRPlayerShowLandscape(BOOL show) {
    (void)show;
}

void SGRPlayerLyricsOrientationChanged(void) {}

void SGRPlayerForceLandscapeLyrics(void) {}

void SGRPlayerShowPortraitLyrics(BOOL show) {
    (void)show;
}

void SGRPlayerPortraitLyricsObscured(BOOL obscured) {
    (void)obscured;
}
