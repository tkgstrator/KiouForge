#import "Internal.h"

// ===========================================================================
// Hook_KifuObserve.m — wire kiou_kifuObserveMatchEnd into the five
// IMatchMode.OnMatchEndAsync sites.
//
// Binpatch path:
//   The recipe (recipes/kiouforge.py) emits an observer cave per site that
//   saves caller registers, materializes the mode index into X2 via
//   `MOVZ X2, #imm`, BLRs g_kiou_hook_slot[KIOU_SLOT_KIFU_OBSERVE], restores
//   registers, executes the displaced prologue, and branches to orig+4. The
//   slot points at kiou_kifuObserveMatchEnd; one slot serves all 5 sites.
//
// Jailed / JB-rootless path:
//   MSHookFunction (or DobbyHook under JAILED=1) installs a thin per-mode
//   thunk on each OnMatchEnd entry. The thunk forwards to
//   kiou_kifuObserveMatchEnd with its hard-coded mode index, then chains
//   back to orig(self, ct) so the original async state machine continues.
//
// Both paths converge on the same kiou_kifuObserveMatchEnd, which honors
// the master KIOU_FEATURE_KIFU_AUTOSAVE flag and the per-mode flags before
// invoking the writer.
//
// RVAs are pinned to KIOU 1.0.1 build 11; see _KIFU_OBSERVE_SITES in
// recipes/kiouforge.py for the matching prologue bytes.
// ===========================================================================

// UnityFramework base captured at install/publish time. Helpers.m reads
// this to resolve static il2cpp method pointers by RVA.
uintptr_t g_kfUnityBase = 0;

#define RVA_AI_END             0x59E5958
#define RVA_CPUSTREAM_END      0x59EC818
#define RVA_LOCAL_END          0x59FF8F8
#define RVA_ONLINE_END         0x5A0139C
#define RVA_RECORDREPLAY_END   0x5A2B564

// 16-byte UniTask return (see KFUniTaskRet in Internal.h).
typedef KFUniTaskRet (*OnMatchEndAsync_t)(void *self, void *ct);

static OnMatchEndAsync_t orig_AI_End            = NULL;
static OnMatchEndAsync_t orig_CPUStream_End     = NULL;
static OnMatchEndAsync_t orig_Local_End         = NULL;
static OnMatchEndAsync_t orig_Online_End        = NULL;
static OnMatchEndAsync_t orig_RecordReplay_End  = NULL;

// Per-mode thunks. Each thunk passes its hard-coded mode index to the
// shared kiou_kifuObserveMatchEnd, then chains to orig so the original
// async state machine continues. KKE used a `static` thunk family with a
// macro; we expand it inline here to keep the file scannable.

static KFUniTaskRet thunk_AI_End(void *self, void *ct) {
    kiou_kifuObserveMatchEnd(self, ct, KIOU_MMODE_AI_MATCH);
    if (orig_AI_End) return orig_AI_End(self, ct);
    return (KFUniTaskRet){ NULL, NULL };
}
static KFUniTaskRet thunk_CPUStream_End(void *self, void *ct) {
    kiou_kifuObserveMatchEnd(self, ct, KIOU_MMODE_CPU_STREAM);
    if (orig_CPUStream_End) return orig_CPUStream_End(self, ct);
    return (KFUniTaskRet){ NULL, NULL };
}
static KFUniTaskRet thunk_Local_End(void *self, void *ct) {
    kiou_kifuObserveMatchEnd(self, ct, KIOU_MMODE_LOCAL_PVP);
    if (orig_Local_End) return orig_Local_End(self, ct);
    return (KFUniTaskRet){ NULL, NULL };
}
static KFUniTaskRet thunk_Online_End(void *self, void *ct) {
    kiou_kifuObserveMatchEnd(self, ct, KIOU_MMODE_ONLINE_PVP);
    if (orig_Online_End) return orig_Online_End(self, ct);
    return (KFUniTaskRet){ NULL, NULL };
}
static KFUniTaskRet thunk_RecordReplay_End(void *self, void *ct) {
    kiou_kifuObserveMatchEnd(self, ct, KIOU_MMODE_RECORD_REPLAY);
    if (orig_RecordReplay_End) return orig_RecordReplay_End(self, ct);
    return (KFUniTaskRet){ NULL, NULL };
}

#ifndef IPA_BINPATCH
void install_KifuObserve_hook(uintptr_t unityBase) {
    g_kfUnityBase = unityBase;
    // Make sure the output directory is ready before the first match ends.
    NSString *outDir = kiou_kifEnsureOutputDir();
    file_log([NSString stringWithFormat:@"[KIFU] output dir = %@",
              outDir ?: @"(failed)"]);

    struct { const char *tag; uintptr_t rva;
             void *thunk; void **origSlot; } entries[] = {
        { "AIMatchMode",      RVA_AI_END,
          (void *)thunk_AI_End,           (void **)&orig_AI_End },
        { "CPUStreamMode",    RVA_CPUSTREAM_END,
          (void *)thunk_CPUStream_End,    (void **)&orig_CPUStream_End },
        { "LocalPvPMode",     RVA_LOCAL_END,
          (void *)thunk_Local_End,        (void **)&orig_Local_End },
        { "OnlinePvPMode",    RVA_ONLINE_END,
          (void *)thunk_Online_End,       (void **)&orig_Online_End },
        { "RecordReplayMode", RVA_RECORDREPLAY_END,
          (void *)thunk_RecordReplay_End, (void **)&orig_RecordReplay_End },
    };
    for (size_t i = 0; i < sizeof(entries)/sizeof(entries[0]); i++) {
        uintptr_t addr = unityBase + entries[i].rva;
        MSHookFunction((void *)addr, entries[i].thunk, entries[i].origSlot);
        file_log([NSString stringWithFormat:
                  @"[KIFU] %s.OnMatchEndAsync hooked @0x%lx (base+0x%lx)",
                  entries[i].tag, (unsigned long)addr,
                  (unsigned long)entries[i].rva]);
    }
}
#else
void publish_KifuObserve_slots(uintptr_t unityBase) {
    g_kfUnityBase = unityBase;
    NSString *outDir = kiou_kifEnsureOutputDir();
    file_log([NSString stringWithFormat:@"[KIFU] output dir = %@",
              outDir ?: @"(failed)"]);

    // One slot for all 5 sites — the cave passes mode_index in X2.
    g_kiou_hook_slot[KIOU_SLOT_KIFU_OBSERVE] = (void *)kiou_kifuObserveMatchEnd;
    file_log([NSString stringWithFormat:
              @"[BINPATCH] KifuObserve: slot[%d]=%p (handles all 5 IMatchMode sites)",
              KIOU_SLOT_KIFU_OBSERVE,
              g_kiou_hook_slot[KIOU_SLOT_KIFU_OBSERVE]]);
}
#endif
