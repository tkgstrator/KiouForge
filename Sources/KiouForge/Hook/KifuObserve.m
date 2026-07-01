#import "Internal.h"

// ===========================================================================
// hook/KifuObserve.m — IMatchMode.OnMatchEndAsync observer hooks.
//
// Five sites (AI / CPUStream / LocalPvP / OnlinePvP / RecordReplay) all
// route into mode-specific HookXxxEnd(self, ct) observer bodies that
// invoke KIOUKifuObserveMatchEnd with the right KiouMatchMode index.
//
// Chinlan path:
//   Each cave passes its hook_id in W6 to the shared observer slot at
//   KIOU_HOOK_OBSERVER_SLOT_RVA; dispatch_one in ChinlanDispatcher.m switches
//   on hook_id and calls HookXxxEnd directly.
//
// JB path:
//   MSHookFunction installs HookXxxEnd as a trampoline on each
//   OnMatchEnd site; the chain-to-orig path runs after the observer body.
// ===========================================================================

#define RVA_AI_END             KIOU_HOOK_RVA_AI_END
#define RVA_CPUSTREAM_END      KIOU_HOOK_RVA_CPUSTREAM_END
#define RVA_LOCAL_END          KIOU_HOOK_RVA_LOCAL_END
#define RVA_ONLINE_END         KIOU_HOOK_RVA_ONLINE_END
#define RVA_REPLAY_END         KIOU_HOOK_RVA_REPLAY_END

// 16-byte UniTask return (see KIOUUniTaskRet in Internal.h).
typedef KIOUUniTaskRet (*OnMatchEndAsync_t)(void *self, void *ct);

#if !IPA_CHINLAN
static OnMatchEndAsync_t orig_AI_End            = NULL;
static OnMatchEndAsync_t orig_CPUStream_End     = NULL;
static OnMatchEndAsync_t orig_Local_End         = NULL;
static OnMatchEndAsync_t orig_Online_End        = NULL;
static OnMatchEndAsync_t orig_RecordReplay_End  = NULL;
#endif

// ---------------------------------------------------------------------------
// Observer bodies — single source of truth, called by both chinlan
// dispatch_one and (via the JB trampolines below) MSHookFunction.
// ---------------------------------------------------------------------------
void HookAiEnd       (void *self, void *ct) { KIOUKifuObserveMatchEnd(self, ct, KIOU_MMODE_AI_MATCH); }
void HookCpuStreamEnd(void *self, void *ct) { KIOUKifuObserveMatchEnd(self, ct, KIOU_MMODE_CPU_STREAM); }
void HookLocalEnd    (void *self, void *ct) { KIOUKifuObserveMatchEnd(self, ct, KIOU_MMODE_LOCAL_PVP); }
void HookOnlineEnd   (void *self, void *ct) { KIOUKifuObserveMatchEnd(self, ct, KIOU_MMODE_ONLINE_PVP); }
void HookReplayEnd   (void *self, void *ct) { KIOUKifuObserveMatchEnd(self, ct, KIOU_MMODE_RECORD_REPLAY); }

#if !IPA_CHINLAN
// JB-flavour trampolines: observer body first, then chain to orig.
static KIOUUniTaskRet ThunkAIEnd(void *self, void *ct) {
    HookAiEnd(self, ct);
    if (orig_AI_End) return orig_AI_End(self, ct);
    return (KIOUUniTaskRet){ NULL, NULL };
}
static KIOUUniTaskRet ThunkCPUStreamEnd(void *self, void *ct) {
    HookCpuStreamEnd(self, ct);
    if (orig_CPUStream_End) return orig_CPUStream_End(self, ct);
    return (KIOUUniTaskRet){ NULL, NULL };
}
static KIOUUniTaskRet ThunkLocalEnd(void *self, void *ct) {
    HookLocalEnd(self, ct);
    if (orig_Local_End) return orig_Local_End(self, ct);
    return (KIOUUniTaskRet){ NULL, NULL };
}
static KIOUUniTaskRet ThunkOnlineEnd(void *self, void *ct) {
    HookOnlineEnd(self, ct);
    if (orig_Online_End) return orig_Online_End(self, ct);
    return (KIOUUniTaskRet){ NULL, NULL };
}
static KIOUUniTaskRet ThunkReplayEnd(void *self, void *ct) {
    HookReplayEnd(self, ct);
    if (orig_RecordReplay_End) return orig_RecordReplay_End(self, ct);
    return (KIOUUniTaskRet){ NULL, NULL };
}
#endif

void KIOUInstallKifuObserveHook(uintptr_t unityBase) {
    NSString *outDir = KIOUKifEnsureOutputDir();
    IPALog([NSString stringWithFormat:@"[KIFU] output dir = %@",
              outDir ?: @"(failed)"]);
#if IPA_CHINLAN
    // Nothing to do — KIOUChinlanPublish has already wired dispatch_one
    // into the observer slot; dispatch_one switches on W6=hook_id and
    // calls HookXxxEnd directly.
    (void)unityBase;
    IPALog(@"[CHINLAN] KifuObserve: dispatch_one routes all 5 IMatchMode sites");
#else
    struct { const char *tag; uintptr_t rva;
             void *thunk; void **origSlot; } entries[] = {
        { "AIMatchMode",      RVA_AI_END,
          (void *)ThunkAIEnd,           (void **)&orig_AI_End },
        { "CPUStreamMode",    RVA_CPUSTREAM_END,
          (void *)ThunkCPUStreamEnd,    (void **)&orig_CPUStream_End },
        { "LocalPvPMode",     RVA_LOCAL_END,
          (void *)ThunkLocalEnd,        (void **)&orig_Local_End },
        { "OnlinePvPMode",    RVA_ONLINE_END,
          (void *)ThunkOnlineEnd,       (void **)&orig_Online_End },
        { "RecordReplayMode", RVA_REPLAY_END,
          (void *)ThunkReplayEnd,       (void **)&orig_RecordReplay_End },
    };
    for (size_t i = 0; i < sizeof(entries)/sizeof(entries[0]); i++) {
        uintptr_t addr = unityBase + entries[i].rva;
        MSHookFunction((void *)addr, entries[i].thunk, entries[i].origSlot);
        IPALog([NSString stringWithFormat:
                  @"[KIFU] %s.OnMatchEndAsync hooked @0x%lx (base+0x%lx)",
                  entries[i].tag, (unsigned long)addr,
                  (unsigned long)entries[i].rva]);
    }
#endif
}
