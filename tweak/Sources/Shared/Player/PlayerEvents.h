#import <UIKit/UIKit.h>

extern NSString *const SGPlayerTransitionNotification;
extern NSString *const SGPlayerTransitionEndedNotification;
CFTimeInterval SGPlayerTransitionEnds(void);
// The full-screen player is on screen: viewWillAppear through viewDidDisappear of its background unit.
BOOL SGPlayerIsOpen(void);
