#import "Internal.h"
#import "Settings.h"

#import <UIKit/UIKit.h>

// ===========================================================================
// Settings.m — right-edge swipe trigger that presents the existing
// KFditorSettingsViewController (Hook_SettingsUI.m).
//
// Design:
//   * The settings table itself is owned by Hook_SettingsUI.m via
//     `KFPresentSettings()`. We don't duplicate any of that
//     UI here — we only own the gesture that opens it.
//   * The recognizer is attached to the key window's gesture-recognizer
//     list. Touches inside game UI are unaffected: only screen-edge
//     pans crossing the right bezel trigger.
//   * The handler object is retained statically so its lifetime is
//     independent of any view controller (the recognizer holds the
//     target with weak semantics).
//
// Naming mirrors the sibling tweak KiouKifExporter so the two sources
// stay easy to diff side-by-side.
// ===========================================================================

// KFPresentSettings() is implemented in Hook_SettingsUI.m. Same
// extern-in-callsite pattern Hook_FriendUnhide.m uses; do not lift this
// into Internal.h.
extern void KFPresentSettings(void);

// ---------------------------------------------------------------------------
// KFKeyWindow — iOS 13+ safe replacement for the deprecated
// [UIApplication sharedApplication].keyWindow. Walks connected
// UIWindowScenes and returns the first key window in a foreground-active
// scene. Falls back to the first visible window if none is marked key.
// Returns nil when called before the app has set up its window hierarchy.
//
// Duplicated locally (Hook_SettingsUI.m has an equivalent `activeWindow()`
// at file scope). Keeping a copy here costs nothing and means this file is
// self-contained — Hook_SettingsUI.m doesn't need to expose its helper.
// ---------------------------------------------------------------------------
static UIWindow *KFKeyWindow(void) {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *ws = (UIWindowScene *)scene;
        if (ws.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *w in ws.windows) {
            if (w.isKeyWindow) return w;
        }
        if (ws.windows.count > 0) return ws.windows.firstObject;
    }
    return nil;
}

// ===========================================================================
// KFGestureHandler — target for the UIScreenEdgePanGestureRecognizer.
// Kept as a separate NSObject so its lifetime is independent of any VC.
// ===========================================================================
@interface KFGestureHandler : NSObject
- (void)handleEdgePan:(UIScreenEdgePanGestureRecognizer *)gr;
@end

@implementation KFGestureHandler

- (void)handleEdgePan:(UIScreenEdgePanGestureRecognizer *)gr {
    // Fire on Began only — we don't need to track the drag.
    if (gr.state != UIGestureRecognizerStateBegan) return;
    file_log(@"[KF] right-edge swipe began -> presenting settings");
    KFPresentSettings();
}

@end

// ---------------------------------------------------------------------------
// KFGestureInstall — public entry point called from Tweak.m.
//
// Attaches a UIScreenEdgePanGestureRecognizer (right edge) to the key
// window. The handler object is retained statically so it lives for the
// app's lifetime without needing an owner. Retries every second until
// the window is up; once attached, becomes a no-op.
// ---------------------------------------------------------------------------
void KFGestureInstall(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *win = KFKeyWindow();
        if (!win) {
            dispatch_after(
                dispatch_time(DISPATCH_TIME_NOW,
                              (int64_t)(1.0 * NSEC_PER_SEC)),
                dispatch_get_main_queue(), ^{
                    KFGestureInstall();
                });
            return;
        }

        // Guard: don't install twice (e.g. if KFGestureInstall is somehow
        // called a second time after a window recreation).
        for (UIGestureRecognizer *gr in win.gestureRecognizers) {
            if ([gr isKindOfClass:[UIScreenEdgePanGestureRecognizer class]]) {
                UIScreenEdgePanGestureRecognizer *ep =
                    (UIScreenEdgePanGestureRecognizer *)gr;
                if (ep.edges & UIRectEdgeRight) {
                    file_log(@"[KF] right-edge gesture already installed, skipping");
                    return;
                }
            }
        }

        static KFGestureHandler *sHandler = nil;
        static dispatch_once_t once;
        dispatch_once(&once, ^{ sHandler = [[KFGestureHandler alloc] init]; });

        UIScreenEdgePanGestureRecognizer *gr =
            [[UIScreenEdgePanGestureRecognizer alloc]
                initWithTarget:sHandler
                        action:@selector(handleEdgePan:)];
        gr.edges = UIRectEdgeRight;
        [win addGestureRecognizer:gr];

        file_log(@"[KF] right-edge swipe gesture installed on key window");
    });
}
