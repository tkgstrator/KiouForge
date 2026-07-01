#pragma once

#import <Foundation/Foundation.h>

// ===========================================================================
// Settings.h — KiouForge right-edge swipe trigger for the settings sheet.
//
// Naming intentionally mirrors KiouForge/Sources/KiouForge/Settings.h
// (the sibling tweak shipped the same UI pattern first). The KiouForge
// settings table itself lives in Hook_SettingsUI.m and Persistence.m — this
// header only declares the gesture installer that opens it.
//
//   KIOUGestureInstall()  — attach a UIScreenEdgePanGestureRecognizer
//     (right edge) to the key window. Right-edge swipe → present the
//     existing KEditorSettingsViewController via
//     `KIOUPresentSettings()` (defined in Hook_SettingsUI.m).
//
//     Safe to call multiple times (no-op once a right-edge recognizer is
//     already attached) and safe to call from any thread — the
//     implementation hops to the main queue itself via dispatch_async
//     and retries until the UIWindow is up.
// ===========================================================================

void KIOUGestureInstall(void);
