// Player redesign: lyrics stay a presented page. The rest of Spotify stays portrait. When that page
// is up and Landscape lyrics is on, this file lets that page turn with the phone.
#import <objc/runtime.h>
#import <UIKit/UIKit.h>
#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "Player.h"

static UIInterfaceOrientationMask maskForDevice(UIDeviceOrientation orientation) {
    if (orientation == UIDeviceOrientationLandscapeLeft) return UIInterfaceOrientationMaskLandscapeRight;
    if (orientation == UIDeviceOrientationLandscapeRight) return UIInterfaceOrientationMaskLandscapeLeft;
    if (orientation == UIDeviceOrientationPortrait) return UIInterfaceOrientationMaskPortrait;
    return 0;
}

static BOOL lyricsMayTurn(void) {
    return SGRPlayerLyricsOpen() && SGEnabled(SGRKeyLandscapeLyrics);
}

static UIInterfaceOrientationMask orientationsFor(id self, SEL _cmd, UIApplication *application, UIWindow *window) {
    (void)self; (void)_cmd; (void)application; (void)window;
    return lyricsMayTurn() ? UIInterfaceOrientationMaskAllButUpsideDown : UIInterfaceOrientationMaskPortrait;
}

static void answerForOrientations(void) {
    static BOOL done;
    id delegate = UIApplication.sharedApplication.delegate;
    if (done || !delegate) return;
    done = YES;
    SEL selector = @selector(application:supportedInterfaceOrientationsForWindow:);
    Method method = class_getInstanceMethod([delegate class], selector);
    if (method) method_setImplementation(method, (IMP)orientationsFor);
    else class_addMethod([delegate class], selector, (IMP)orientationsFor, "Q@:@@");
}

static UIWindowScene *phoneScene(void) {
    UIWindowScene *fallback = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        if (!fallback) fallback = (UIWindowScene *)scene;
        if (scene.activationState == UISceneActivationStateForegroundActive) return (UIWindowScene *)scene;
    }
    return fallback;
}

static void requestOrientations(UIInterfaceOrientationMask mask) {
    UIWindowScene *scene = phoneScene();
    if (!scene) return;
    if (@available(iOS 16.0, *)) {
        UIWindowSceneGeometryPreferencesIOS *preferences = [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:mask];
        [scene requestGeometryUpdateWithPreferences:preferences errorHandler:^(NSError *error) {
            SGLog(@"redesign player: the scene did not turn: %@", error.localizedDescription);
        }];
        UIViewController *top = SGTopController();
        [top setNeedsUpdateOfSupportedInterfaceOrientations];
    }
}

void SGRPlayerLyricsOrientationChanged(void) {
    answerForOrientations();
    if (lyricsMayTurn()) {
        UIInterfaceOrientationMask side = maskForDevice(UIDevice.currentDevice.orientation);
        requestOrientations(side ? side : UIInterfaceOrientationMaskAllButUpsideDown);
    } else {
        requestOrientations(UIInterfaceOrientationMaskPortrait);
    }
}

void SGRPlayerShowLandscape(BOOL show) {
    (void)show;
    SGRPlayerLyricsOrientationChanged();
}

void SGRPlayerForceLandscapeLyrics(void) {
    SGRPlayerLyricsOrientationChanged();
}

%ctor {
    if (!SGRedesignedUI()) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        answerForOrientations();
        [UIDevice.currentDevice beginGeneratingDeviceOrientationNotifications];
        [NSNotificationCenter.defaultCenter addObserverForName:UIDeviceOrientationDidChangeNotification object:nil queue:nil
                                                    usingBlock:^(NSNotification *note) {
            if (SGRPlayerLyricsOpen()) SGRPlayerLyricsOrientationChanged();
        }];
    });
}
