#if IPA_CHINLAN

#import "Internal.h"

// ===========================================================================
// ChinlanDispatcher — chinlan flavour only.
//
// Ported from KiouEngineBridge/ChinlanDispatcher.m.
//
// CAVE_OBSERVER caves all load a single slot at unityBase +
// KIOU_KF_HOOK_SLOT_RVA and BLR it with W6 = hook_id. The slot points
// at dispatch_one, which switches on hook_id and forwards to the matching
// Hook_*.m observer body.
//
// CAVE_ENTRY caves each load their own slot at unityBase +
// KIOU_KF_ENTRY_SLOT_BASE_RVA + slot_index*8 and BLR it. KFChinlanPublish()
// writes the live hook function pointers into those slots.
//
// g_inject_entry[i] holds the per-site cave-bypass entry pointer so a
// hook can call orig without re-entering the dispatcher cave (the cave
// at unityBase+RVA is now `B <cave_va>` and would otherwise loop).
// ===========================================================================

void * volatile g_inject_entry[KIOU_KF_HOOK__COUNT] = {0};

// ---------------------------------------------------------------------------
// Observer hook bodies — declared in their respective Hook_*.m files.
// Each takes the original arg registers and runs the pre-orig observation
// work; the cave resumes the displaced prologue + B orig+4 afterwards.
// ---------------------------------------------------------------------------
extern void HookAiEnd(void *self, void *ct);
extern void HookCpuStreamEnd(void *self, void *ct);
extern void HookLocalEnd(void *self, void *ct);
extern void HookOnlineEnd(void *self, void *ct);
extern void HookReplayEnd(void *self, void *ct);

// ---------------------------------------------------------------------------
// Entry hook bodies — declared in their respective Hook_*.m files (the
// KIOU-Hook ones live under vendor/KIOU-Hook/Hook/). CAVE_ENTRY hooks
// replace orig; the body calls the cave bypass (resolved by KIOUHookOrig)
// to invoke the original method when needed.
// ---------------------------------------------------------------------------
extern void  KFHookSetTargetFrameRateEntry(int32_t value, void *mi);
extern void  KFHookNSSSetHashSizeEntry(void *self, int32_t mb, void *mi);
extern void  KFHookNSSSetSkillLevelEntry(void *self, int32_t level, void *mi);
extern void *KFHookNSSSearchFullEntry(void *self, void *sfen, int32_t depth, void *mi);
extern bool  KFHookAccountExists(void *data);
extern void *KFHookLoginArgsCreate(void *deviceId, void *distinctId);
extern void *KFHookRegisterUserArgsCreate(void *userName, void *distinctId);
extern void  KFHookRunLoginSeqMoveNext(void *self);
extern void  KFHookGetSelfProfileMoveNext(void *self);
extern void *KFHookHttpMsgInvokerSendAsync(void *self, void *request, void *ct);

// ---------------------------------------------------------------------------
// dispatch_one — single shared observer slot, switches on W6=hook_id.
//
// Receives the original X0..X5/X7 arguments verbatim, plus the per-site
// hook id in W6. Each case forwards to the matching observer body. Unused
// parameter slots are silently dropped per AAPCS64 — the hook bodies only
// read what they need.
// ---------------------------------------------------------------------------
static void dispatch_one(void *x0, void *x1, void *x2, void *x3, void *x4,
                         void *x5, uint32_t hook_id, void *x7) {
    (void)x2; (void)x3; (void)x4; (void)x5; (void)x7;
    switch (hook_id) {
    // OnMatchEndAsync(self, ct)
    case KIOU_KF_HOOK_KIFU_AI_END:        HookAiEnd(x0, x1); break;
    case KIOU_KF_HOOK_KIFU_CPUSTREAM_END: HookCpuStreamEnd(x0, x1); break;
    case KIOU_KF_HOOK_KIFU_LOCAL_END:     HookLocalEnd(x0, x1); break;
    case KIOU_KF_HOOK_KIFU_ONLINE_END:    HookOnlineEnd(x0, x1); break;
    case KIOU_KF_HOOK_KIFU_REPLAY_END:    HookReplayEnd(x0, x1); break;
    default:
        IPALog([NSString stringWithFormat:
                  @"[CHINLAN] unknown hook_id=%u self=%p",
                  (unsigned)hook_id, x0]);
        break;
    }
}

// ---------------------------------------------------------------------------
// Per-site cave-bypass entry. Each cave starts at
//   unityBase + KIOU_KF_CAVE_REGION_START + slot_index*KIOU_KF_CAVE_SIZE
// and the bypass entry (displaced prologue + B orig+4) lives at
//   cave_va + KIOU_KF_CAVE_BYPASS_OFFSET.
// ---------------------------------------------------------------------------
static void *bypass_entry_for_hook(uintptr_t unityBase, uint32_t hook_id) {
    return (void *)(unityBase
                    + KIOU_KF_CAVE_REGION_START
                    + (uintptr_t)hook_id * KIOU_KF_CAVE_SIZE
                    + KIOU_KF_CAVE_BYPASS_OFFSET);
}

// ---------------------------------------------------------------------------
// KFChinlanPublish — install the observer dispatcher pointer + entry slot
// table the moment UnityFramework's base address is known.
// ---------------------------------------------------------------------------
void KFChinlanPublish(uintptr_t unityBase) {
    if (unityBase == 0) {
        IPALog(@"[CHINLAN] publish skipped: unityBase is zero");
        return;
    }

    // Observer dispatcher slot.
    void * volatile *slot =
        (void * volatile *)(unityBase + KIOU_KF_HOOK_SLOT_RVA);
    *slot = (void *)&dispatch_one;

    // Per-hook cave-bypass entries.
    for (uint32_t i = 0; i < KIOU_KF_HOOK__COUNT; i++) {
        g_inject_entry[i] = bypass_entry_for_hook(unityBase, i);
    }

    // Entry-slot table — one slot per CAVE_ENTRY hook.
    void * volatile *entrySlots =
        (void * volatile *)(unityBase + KIOU_KF_ENTRY_SLOT_BASE_RVA);
    entrySlots[KIOU_KF_ENTRY_SLOT_SET_TARGET_FRAMERATE]      = (void *)&KFHookSetTargetFrameRateEntry;
    entrySlots[KIOU_KF_ENTRY_SLOT_NSS_SETHASHSIZE]           = (void *)&KFHookNSSSetHashSizeEntry;
    entrySlots[KIOU_KF_ENTRY_SLOT_NSS_SETSKILLEVEL]          = (void *)&KFHookNSSSetSkillLevelEntry;
    entrySlots[KIOU_KF_ENTRY_SLOT_NSS_SEARCHFULL]            = (void *)&KFHookNSSSearchFullEntry;
    entrySlots[KIOU_KF_ENTRY_SLOT_ACCOUNT_EXISTS]            = (void *)&KFHookAccountExists;
    entrySlots[KIOU_KF_ENTRY_SLOT_LOGIN_ARGS_CREATE]         = (void *)&KFHookLoginArgsCreate;
    entrySlots[KIOU_KF_ENTRY_SLOT_REGISTER_USER_ARGS_CREATE] = (void *)&KFHookRegisterUserArgsCreate;
    entrySlots[KIOU_KF_ENTRY_SLOT_RUN_LOGIN_SEQ_MOVENEXT]    = (void *)&KFHookRunLoginSeqMoveNext;
    entrySlots[KIOU_KF_ENTRY_SLOT_GET_SELF_PROFILE_MOVENEXT] = (void *)&KFHookGetSelfProfileMoveNext;
    entrySlots[KIOU_KF_ENTRY_SLOT_HTTPMSGINVOKER_SEND_ASYNC] = (void *)&KFHookHttpMsgInvokerSendAsync;

    IPALog([NSString stringWithFormat:
              @"[CHINLAN] dispatcher=%p observer slot=%p (unityBase+0x%lx) "
              @"entry slots base=%p (unityBase+0x%x) inject_entry[ai_end]=%p "
              @"cave_start=0x%lx cave_size=%u bypass_off=0x%x count=%u",
              (void *)&dispatch_one, (void *)slot,
              (unsigned long)KIOU_KF_HOOK_SLOT_RVA,
              (void *)entrySlots,
              (unsigned)KIOU_KF_ENTRY_SLOT_BASE_RVA,
              (void *)g_inject_entry[KIOU_KF_HOOK_KIFU_AI_END],
              (unsigned long)KIOU_KF_CAVE_REGION_START,
              (unsigned)KIOU_KF_CAVE_SIZE,
              (unsigned)KIOU_KF_CAVE_BYPASS_OFFSET,
              (unsigned)KIOU_KF_HOOK__COUNT]);
}

#endif  // IPA_CHINLAN
