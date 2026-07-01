#import "Internal.h"

// ===========================================================================
// hook/FrameRate.m — FPS override via Application.set_targetFrameRate.
// ===========================================================================

#define RVA_SET_TARGET_FRAMERATE  KIOU_HOOK_RVA_SET_TARGET_FRAMERATE

// IL2CPP ABI for a static method: (value, MethodInfo *mi)
typedef void (*SetTargetFrameRate_t)(int32_t value, void *mi);

#if !IPA_CHINLAN
static SetTargetFrameRate_t orig_set_targetFrameRate = NULL;
#endif

static int32_t pickFPS(int32_t value) {
    int32_t v = KIOUFeatureEnabled(KIOU_FEATURE_FPS_OVERRIDE)
              ? KIOUTargetFPS() : value;
    if (v != value) {
        IPALog([NSString stringWithFormat:
                  @"[FPS] set_targetFrameRate %d -> %d (override)", value, v]);
    }
    return v;
}

// Direct call from the settings slider callback so the new value takes
// effect immediately without waiting for KIOU's next settings apply.
void KIOUApplyFPS(int32_t fps) {
    if (g_unityBase == 0) return;
    SetTargetFrameRate_t fn =
        (SetTargetFrameRate_t)(g_unityBase + RVA_SET_TARGET_FRAMERATE);
    fn(fps, NULL);
    IPALog([NSString stringWithFormat:@"[FPS] applied %d fps (direct)", fps]);
}

#if IPA_CHINLAN
void KIOUHookSetTargetFrameRateEntry(int32_t value, void *mi) {
    int32_t v = pickFPS(value);
    SetTargetFrameRate_t bypass =
        (SetTargetFrameRate_t)g_inject_entry[KIOU_HOOK_ID_SET_TARGET_FRAMERATE];
    if (bypass) bypass(v, mi);
}

void KIOUInstallFrameRateHook(uintptr_t unityBase) {
    (void)unityBase;
    IPALog([NSString stringWithFormat:
              @"[CHINLAN] set_targetFrameRate: entry hook wired (fps=%d)",
              (int)KIOUTargetFPS()]);
}
#else
static void HookSetTargetFrameRate(int32_t value, void *mi) {
    int32_t v = pickFPS(value);
    if (orig_set_targetFrameRate) orig_set_targetFrameRate(v, mi);
}

void KIOUInstallFrameRateHook(uintptr_t unityBase) {
    uintptr_t addr = unityBase + RVA_SET_TARGET_FRAMERATE;
    MSHookFunction((void *)addr,
                   (void *)HookSetTargetFrameRate,
                   (void **)&orig_set_targetFrameRate);
    IPALog([NSString stringWithFormat:
              @"Application.set_targetFrameRate hooked @0x%lx (base+0x%x) fps=%d",
              (unsigned long)addr, RVA_SET_TARGET_FRAMERATE, (int)KIOUTargetFPS()]);
}
#endif
