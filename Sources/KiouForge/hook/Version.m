#import "Internal.h"

// ===========================================================================
// Hook_Version.m — title-screen version stamp removed.
//
// The version/commit is shown in the About section footer of the settings
// sheet (Hook_SettingsUI.m) instead. No hooks are installed from this file.
// ===========================================================================

#ifndef IPA_CHINLAN
void KFInstallVersionHook(__unused uintptr_t unityBase) { }
#else
void KFPublishVersionSlots(__unused uintptr_t unityBase) { }
#endif
