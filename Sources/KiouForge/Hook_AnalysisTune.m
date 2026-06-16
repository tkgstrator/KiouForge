#import "Internal.h"

// ===========================================================================
// Hook_AnalysisTune.m — post-game kifu analysis engine strengthening.
//
// The post-game analysis flow (KifuDetailPopupAnalysisPresenter) runs the
// on-device Rshogi NNUE engine (NativeSyncSession) to compute move scores
// for the finished game. This is SEPARATE from BeginnerSupportEvaluator
// (the in-match hint arrow, which KiouForge does not touch). Strengthening
// this engine only affects analysis of already-completed games — never live
// match play — so it carries no competitive advantage.
//
// Retail constants baked into KifuDetailPopupAnalysisPresenter (dump.cs:819966):
//   const SearchDepth    = 15
//   const OwnedHashSizeMb = 16
//
// Two hooks target the NativeSyncSession API (dump.cs:1602544):
//
//   A) NativeSyncSession.SetHashSize(int mb)   RVA 0x5D320E0 — hook the mb
//      argument. The analysis presenter calls SetHashSize(16) during
//      EnsureEngineReadyAsync; we bump it to kiou_analysisHashMB().
//      KiouEditor notes: "nothing in retail calls SetHashSize for BSE", so
//      retail-only callers of SetHashSize are analysis-presenter sessions.
//
//   B) NativeSyncSession.SetSkillLevel(int level)  RVA 0x5D3206C — hook
//      the level argument. Retail analysis uses the engine default
//      (level 20, already max), so this is belt-and-braces.
//
// NOTE — depth override:
//   NativeSyncSession.SearchFull(string sfen, int depth) is the analysis
//   entry point. It returns SyncSearchResult (a struct, dump.cs:1602517),
//   so hooking it requires careful handling of the x8 sret register the
//   C calling convention does not preserve. This hook is deferred until
//   a sret-aware cave variant or a different interception point is
//   available. Hash + skill already provide most of the benefit.
// ===========================================================================

#define RVA_NSS_SETHASHSIZE    0x5D320E0
#define RVA_NSS_SETSKILLEVEL   0x5D3206C

// IL2CPP instance-method ABI:
//   void (NativeSyncSession *self, int32_t arg, MethodInfo *mi)
typedef void (*NSSSetHashSize_t)(void *self, int32_t mb, void *mi);
typedef void (*NSSSetSkillLevel_t)(void *self, int32_t level, void *mi);

static NSSSetHashSize_t   orig_NSS_SetHashSize   = NULL;
static NSSSetSkillLevel_t orig_NSS_SetSkillLevel = NULL;

static void hook_NSS_SetHashSize(void *self, int32_t mb, void *mi) {
    int32_t target = kiou_featureEnabled(KIOU_FEATURE_ANALYSIS_TUNE)
                   ? kiou_analysisHashMB() : mb;
    if (target != mb) {
        file_log([NSString stringWithFormat:
                  @"[ANALYSIS] SetHashSize %d -> %d MB (override)", mb, target]);
    }
    if (orig_NSS_SetHashSize) orig_NSS_SetHashSize(self, target, mi);
}

static void hook_NSS_SetSkillLevel(void *self, int32_t level, void *mi) {
    int32_t target = kiou_featureEnabled(KIOU_FEATURE_ANALYSIS_TUNE)
                   ? kiou_analysisSkillLevel() : level;
    if (target != level) {
        file_log([NSString stringWithFormat:
                  @"[ANALYSIS] SetSkillLevel %d -> %d (override)", level, target]);
    }
    if (orig_NSS_SetSkillLevel) orig_NSS_SetSkillLevel(self, target, mi);
}

#ifndef IPA_BINPATCH
void install_AnalysisTune_hook(uintptr_t unityBase) {
    {
        uintptr_t addr = unityBase + RVA_NSS_SETHASHSIZE;
        MSHookFunction((void *)addr,
                       (void *)hook_NSS_SetHashSize,
                       (void **)&orig_NSS_SetHashSize);
        file_log([NSString stringWithFormat:
                  @"NativeSyncSession.SetHashSize hooked @0x%lx hash=%d MB",
                  (unsigned long)addr, (int)kiou_analysisHashMB()]);
    }
    {
        uintptr_t addr = unityBase + RVA_NSS_SETSKILLEVEL;
        MSHookFunction((void *)addr,
                       (void *)hook_NSS_SetSkillLevel,
                       (void **)&orig_NSS_SetSkillLevel);
        file_log([NSString stringWithFormat:
                  @"NativeSyncSession.SetSkillLevel hooked @0x%lx skill=%d",
                  (unsigned long)addr, (int)kiou_analysisSkillLevel()]);
    }
}
#else
void publish_AnalysisTune_slots(uintptr_t unityBase) {
    g_kiou_hook_slot[KIOU_SLOT_NSS_SETHASHSIZE] = (void *)hook_NSS_SetHashSize;
    orig_NSS_SetHashSize = (NSSSetHashSize_t)
        kiou_resolve_orig_trampoline(unityBase, RVA_NSS_SETHASHSIZE);

    g_kiou_hook_slot[KIOU_SLOT_NSS_SETSKILLEVEL] = (void *)hook_NSS_SetSkillLevel;
    orig_NSS_SetSkillLevel = (NSSSetSkillLevel_t)
        kiou_resolve_orig_trampoline(unityBase, RVA_NSS_SETSKILLEVEL);

    file_log([NSString stringWithFormat:
              @"[BINPATCH] AnalysisTune: SetHashSize slot[%d]=%p orig=%p, "
              @"SetSkillLevel slot[%d]=%p orig=%p (hash=%d MB skill=%d)",
              KIOU_SLOT_NSS_SETHASHSIZE,
              g_kiou_hook_slot[KIOU_SLOT_NSS_SETHASHSIZE],
              (void *)orig_NSS_SetHashSize,
              KIOU_SLOT_NSS_SETSKILLEVEL,
              g_kiou_hook_slot[KIOU_SLOT_NSS_SETSKILLEVEL],
              (void *)orig_NSS_SetSkillLevel,
              (int)kiou_analysisHashMB(), (int)kiou_analysisSkillLevel()]);
}
#endif
