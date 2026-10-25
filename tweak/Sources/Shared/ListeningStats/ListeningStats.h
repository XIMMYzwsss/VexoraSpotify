// Listening stats (Mod Settings > Listening stats), under either look: plays counted on the phone as they
// happen, Spotify's own data export merged in, and the top tracks, artists, albums and playlists of a
// week, a month, a year and all time. The Vexora settings page shows the top artist and playlist.
//
//     SGPlayLog.m            the log, the export's parsers and the adding up; the Mac harness runs it
//     ListeningStats.x       the player watched, a play written down once it counts
//     ListeningStatsPage.m   the page, and the export picked and imported
//
// Nothing leaves the phone: the log is a file in Application Support, out of the settings backup.
// Threading: main thread only.
#import <UIKit/UIKit.h>

@class SGPlayLog;

// Plays are written down unless this is switched off; it applies at once.
#define SGKeyListeningStats @"spotifyglass.stats.record"
#define SGKeyPlaylistNames @"spotifyglass.stats.playlistNames"

SGPlayLog *SGListeningLog(void);
UIViewController *SGListeningStatsPage(void);
// "Name · 12 plays", or "None yet" when nothing has counted. All time.
NSString *SGListeningTopTrackLine(void);
NSString *SGListeningTopArtistLine(void);
NSString *SGListeningTopPlaylistLine(void);
// The player's "Playing from" line, kept against the playlist that is on now.
void SGListeningRememberContext(NSString *text);
