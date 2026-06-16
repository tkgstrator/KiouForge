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
//   C) NativeSyncSession.SearchFull(string sfen, int depth)  RVA 0x5D32178 —
//      hook the depth argument. The analysis presenter calls
//      SearchFull(sfen, 15) inside RunAnalysisAsync; we override the depth
//      to kiou_analysisDepth().
//
//      ABI note: SearchFull returns SyncSearchResult (a struct, see
//      dump.cs:1602517), which on arm64 uses the indirect-return convention
//      where the caller sets X8 to the sret buffer before BL. Our cave
//      entry trampoline does NOT preserve X8 across the BLR to the slot —
//      it preserves only LR. The trick: declare the C hook with the
//      KFSyncSearchResult return type. The compiler then itself uses X8
//      for the orig() return (matching the caller's expectation), and the
//      RET at cave-tail propagates X0 (= sret pointer the caller set) back
//      unchanged. So no asm shim is needed — just be sure to declare the
//      hook function with the correct struct return type.
//
//      SearchFull may also be called by other code paths (NOT just the
//      analysis presenter); BSE in particular may call NativeSyncSession
//      methods. Forge gates the override on KIOU_FEATURE_ANALYSIS_TUNE only;
//      operators concerned about the depth applying outside the analysis
//      flow should turn the toggle off during live play.
// ===========================================================================

#define RVA_NSS_SETHASHSIZE    0x5D320E0
#define RVA_NSS_SETSKILLEVEL   0x5D3206C
#define RVA_NSS_SEARCHFULL     0x5D32178

// IL2CPP instance-method ABI:
//   void (NativeSyncSession *self, int32_t arg, MethodInfo *mi)
typedef void (*NSSSetHashSize_t)(void *self, int32_t mb, void *mi);
typedef void (*NSSSetSkillLevel_t)(void *self, int32_t level, void *mi);
// SearchFull: returns SyncSearchResult by value (arm64 sret via X8).
typedef KFSyncSearchResult (*NSSSearchFull_t)(void *self, void *sfen,
                                              int32_t depth, void *mi);

static NSSSetHashSize_t   orig_NSS_SetHashSize   = NULL;
static NSSSetSkillLevel_t orig_NSS_SetSkillLevel = NULL;
static NSSSearchFull_t    orig_NSS_SearchFull    = NULL;

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

static KFSyncSearchResult hook_NSS_SearchFull(void *self, void *sfen,
                                              int32_t depth, void *mi) {
    int32_t target = kiou_featureEnabled(KIOU_FEATURE_ANALYSIS_TUNE)
                   ? kiou_analysisDepth() : depth;
    if (target != depth) {
        file_log([NSString stringWithFormat:
                  @"[ANALYSIS] SearchFull depth %d -> %d (override)",
                  depth, target]);
    }
    if (orig_NSS_SearchFull) {
        return orig_NSS_SearchFull(self, sfen, target, mi);
    }
    KFSyncSearchResult empty = {0};
    return empty;
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
    {
        uintptr_t addr = unityBase + RVA_NSS_SEARCHFULL;
        MSHookFunction((void *)addr,
                       (void *)hook_NSS_SearchFull,
                       (void **)&orig_NSS_SearchFull);
        file_log([NSString stringWithFormat:
                  @"NativeSyncSession.SearchFull hooked @0x%lx depth=%d",
                  (unsigned long)addr, (int)kiou_analysisDepth()]);
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

    g_kiou_hook_slot[KIOU_SLOT_NSS_SEARCHFULL] = (void *)hook_NSS_SearchFull;
    orig_NSS_SearchFull = (NSSSearchFull_t)
        kiou_resolve_orig_trampoline(unityBase, RVA_NSS_SEARCHFULL);

    file_log([NSString stringWithFormat:
              @"[BINPATCH] AnalysisTune: SetHashSize slot[%d]=%p orig=%p, "
              @"SetSkillLevel slot[%d]=%p orig=%p, "
              @"SearchFull slot[%d]=%p orig=%p "
              @"(depth=%d hash=%d MB skill=%d)",
              KIOU_SLOT_NSS_SETHASHSIZE,
              g_kiou_hook_slot[KIOU_SLOT_NSS_SETHASHSIZE],
              (void *)orig_NSS_SetHashSize,
              KIOU_SLOT_NSS_SETSKILLEVEL,
              g_kiou_hook_slot[KIOU_SLOT_NSS_SETSKILLEVEL],
              (void *)orig_NSS_SetSkillLevel,
              KIOU_SLOT_NSS_SEARCHFULL,
              g_kiou_hook_slot[KIOU_SLOT_NSS_SEARCHFULL],
              (void *)orig_NSS_SearchFull,
              (int)kiou_analysisDepth(),
              (int)kiou_analysisHashMB(),
              (int)kiou_analysisSkillLevel()]);
}
#endif
