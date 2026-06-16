#import "Internal.h"
#import <dlfcn.h>

// ===========================================================================
// Hook_FrameRate.m — FPS override via Application.set_targetFrameRate.
//
//   Application.set_targetFrameRate(int value)   RVA 0x6B6B758
//   [FreeFunction("SetTargetFrameRate")], dump.cs:872089
//
// Strategy:
//   - Hook set_targetFrameRate; when KIOU_FEATURE_FPS_OVERRIDE is on,
//     replace `value` with kiou_targetFps() before forwarding to orig.
//     This intercepts the game's own 30/60 set and rewrites it.
//   - When the settings slider changes, KFApplyFPS() calls set_targetFrameRate
//     directly via the resolved function pointer so the change takes effect
//     immediately without waiting for the game's next settings apply.
//
// Notes:
//   - >60 fps on ProMotion devices requires the IPA Info.plist key
//     CADisableMinimumFrameDurationOnPhone = true (added by the recipe).
//     Without it iOS caps at 60 even with higher values.
//   - QualitySettings.vSyncCount > 0 overrides targetFrameRate; retail KIOU
//     should have vSyncCount = 0 but verify on first bring-up if higher
//     presets do not take effect.
// ===========================================================================

#define RVA_SET_TARGET_FRAMERATE  0x6B6B758

// IL2CPP ABI for a static method: (value, MethodInfo *mi)
typedef void (*SetTargetFrameRate_t)(int32_t value, void *mi);

static SetTargetFrameRate_t orig_set_targetFrameRate = NULL;

// Unity base address cached at hook-install time for the direct-call helper.
static uintptr_t g_unityBaseForFPS = 0;

static void hook_set_targetFrameRate(int32_t value, void *mi) {
    int32_t v = kiou_featureEnabled(KIOU_FEATURE_FPS_OVERRIDE)
              ? kiou_targetFps() : value;
    if (v != value) {
        file_log([NSString stringWithFormat:
                  @"[FPS] set_targetFrameRate %d -> %d (override)", value, v]);
    }
    if (orig_set_targetFrameRate) orig_set_targetFrameRate(v, mi);
}

// Call set_targetFrameRate directly from the settings slider callback so the
// new value takes effect immediately (same direct-ABI pattern as
// Hook_AssistTune's SetHashSize call).
void KFApplyFPS(int32_t fps) {
    if (g_unityBaseForFPS == 0) return;
    SetTargetFrameRate_t fn =
        (SetTargetFrameRate_t)(g_unityBaseForFPS + RVA_SET_TARGET_FRAMERATE);
    fn(fps, NULL);
    file_log([NSString stringWithFormat:@"[FPS] applied %d fps (direct)", fps]);
}

#ifndef IPA_BINPATCH
void install_FrameRate_hook(uintptr_t unityBase) {
    g_unityBaseForFPS = unityBase;
    uintptr_t addr = unityBase + RVA_SET_TARGET_FRAMERATE;
    MSHookFunction((void *)addr,
                   (void *)hook_set_targetFrameRate,
                   (void **)&orig_set_targetFrameRate);
    file_log([NSString stringWithFormat:
              @"Application.set_targetFrameRate hooked @0x%lx (base+0x%x) fps=%d",
              (unsigned long)addr, RVA_SET_TARGET_FRAMERATE, (int)kiou_targetFps()]);
}
#else
void publish_FrameRate_slots(uintptr_t unityBase) {
    g_unityBaseForFPS = unityBase;
    g_kiou_hook_slot[KIOU_SLOT_SET_TARGET_FRAMERATE] =
        (void *)hook_set_targetFrameRate;
    orig_set_targetFrameRate = (SetTargetFrameRate_t)
        kiou_resolve_orig_trampoline(unityBase, RVA_SET_TARGET_FRAMERATE);
    file_log([NSString stringWithFormat:
              @"[BINPATCH] set_targetFrameRate: slot[%d]=%p orig=%p fps=%d",
              KIOU_SLOT_SET_TARGET_FRAMERATE,
              g_kiou_hook_slot[KIOU_SLOT_SET_TARGET_FRAMERATE],
              (void *)orig_set_targetFrameRate,
              (int)kiou_targetFps()]);
}
#endif
