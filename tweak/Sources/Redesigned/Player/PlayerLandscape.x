// The app stays upright. Spotify's iPhone build is portrait only. An older build overwrote that with
// landscape in the Info.plist and answered every window with both directions, and opening lyrics then
// made a second window key in a scene the page could not stand in.
#import "Player.h"
#import <objc/runtime.h>

static UIInterfaceOrientationMask portraitOnly(id self, SEL _cmd, UIApplication *application, UIWindow *window) {
    (void)self; (void)_cmd; (void)application; (void)window;
    return UIInterfaceOrientationMaskPortrait;
}

static void lockPortrait(void) {
    id delegate = UIApplication.sharedApplication.delegate;
    if (!delegate) return;
    SEL selector = @selector(application:supportedInterfaceOrientationsForWindow:);
    Method method = class_getInstanceMethod([delegate class], selector);
    if (method) method_setImplementation(method, (IMP)portraitOnly);
    else class_addMethod([delegate class], selector, (IMP)portraitOnly, "Q@:@@");
}

void SGRPlayerShowLandscape(BOOL show) {
    (void)show;
}

void SGRPlayerLyricsOrientationChanged(void) {
}

void SGRPlayerForceLandscapeLyrics(void) {
}

%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{ lockPortrait(); });
}
