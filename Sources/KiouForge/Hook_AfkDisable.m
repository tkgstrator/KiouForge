#import "Internal.h"

// ===========================================================================
// Hook_AfkDisable.m — Suppress false AFK warnings during long-think sessions.
//
//   GameOrchestrator.IsAfkEnabled()   RVA 0x59455D4
//   Project.Game.Presentation, dump.cs:1211711
//
// The orchestrator fires an AFK warning after ~60 s of no input, then
// force-surrenders ~15 s later. Returning false disables both without
// touching any other state machine.
//
// Typical use-case: device left on the board while thinking through a
// position or stepping away briefly. Not intended to enable true AFK
// abuse in competitive play — the tool's README explicitly states it
// targets client-side quality-of-life only.
// ===========================================================================

#define RVA_GAME_ORCHESTRATOR_IS_AFK_ENABLED  0x59455D4

typedef bool (*IsAfkEnabled_t)(void *self);

static IsAfkEnabled_t orig_GO_IsAfkEnabled = NULL;

static bool hook_GO_IsAfkEnabled(void *self) {
    if (KFFeatureEnabled(KIOU_FEATURE_DISABLE_AFK)) {
        return false;
    }
    return orig_GO_IsAfkEnabled ? orig_GO_IsAfkEnabled(self) : true;
}

#ifndef IPA_BINPATCH
void KFInstallAfkDisableHook(uintptr_t unityBase) {
    uintptr_t addr = unityBase + RVA_GAME_ORCHESTRATOR_IS_AFK_ENABLED;
    MSHookFunction((void *)addr,
                   (void *)hook_GO_IsAfkEnabled,
                   (void **)&orig_GO_IsAfkEnabled);
    file_log([NSString stringWithFormat:
              @"GameOrchestrator.IsAfkEnabled hooked @0x%lx (base+0x%x)",
              (unsigned long)addr, RVA_GAME_ORCHESTRATOR_IS_AFK_ENABLED]);
}
#else
void KFPublishAfkDisableSlots(uintptr_t unityBase) {
    g_kfHookSlot[KIOU_SLOT_GAME_ORCHESTRATOR_IS_AFK] =
        (void *)hook_GO_IsAfkEnabled;
    orig_GO_IsAfkEnabled = (IsAfkEnabled_t)
        KFResolveOrigTrampoline(unityBase,
                                     RVA_GAME_ORCHESTRATOR_IS_AFK_ENABLED);
    file_log([NSString stringWithFormat:
              @"[BINPATCH] GameOrchestrator.IsAfkEnabled: slot[%d]=%p orig=%p",
              KIOU_SLOT_GAME_ORCHESTRATOR_IS_AFK,
              g_kfHookSlot[KIOU_SLOT_GAME_ORCHESTRATOR_IS_AFK],
              (void *)orig_GO_IsAfkEnabled]);
}
#endif
