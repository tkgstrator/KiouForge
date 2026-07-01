#import "Internal.h"

// ===========================================================================
// hook/AnalysisTune.m — post-game kifu analysis engine strengthening.
//
// Three NativeSyncSession hooks (SetHashSize / SetSkillLevel / SearchFull)
// gated on KIOU_FEATURE_ANALYSIS_TUNE. Affects post-game analysis only.
// ===========================================================================

#define RVA_NSS_SETHASHSIZE    KIOU_HOOK_RVA_NSS_SETHASHSIZE
#define RVA_NSS_SETSKILLEVEL   KIOU_HOOK_RVA_NSS_SETSKILLEVEL
#define RVA_NSS_SEARCHFULL     KIOU_HOOK_RVA_NSS_SEARCHFULL

typedef void (*NSSSetHashSize_t)(void *self, int32_t mb, void *mi);
typedef void (*NSSSetSkillLevel_t)(void *self, int32_t level, void *mi);
typedef KIOUSyncSearchResult (*NSSSearchFull_t)(void *self, void *sfen,
                                              int32_t depth, void *mi);

#if !IPA_CHINLAN
static NSSSetHashSize_t   orig_NSS_SetHashSize   = NULL;
static NSSSetSkillLevel_t orig_NSS_SetSkillLevel = NULL;
static NSSSearchFull_t    orig_NSS_SearchFull    = NULL;
#endif

static int32_t pickHashMB(int32_t mb) {
    int32_t target = KIOUFeatureEnabled(KIOU_FEATURE_ANALYSIS_TUNE)
                   ? KIOUAnalysisHashMB() : mb;
    if (target != mb) {
        IPALog([NSString stringWithFormat:
                  @"[ANALYSIS] SetHashSize %d -> %d MB (override)", mb, target]);
    }
    return target;
}

static int32_t pickSkillLevel(int32_t level) {
    int32_t target = KIOUFeatureEnabled(KIOU_FEATURE_ANALYSIS_TUNE)
                   ? KIOUAnalysisSkillLevel() : level;
    if (target != level) {
        IPALog([NSString stringWithFormat:
                  @"[ANALYSIS] SetSkillLevel %d -> %d (override)", level, target]);
    }
    return target;
}

static int32_t pickDepth(int32_t depth) {
    int32_t target = KIOUFeatureEnabled(KIOU_FEATURE_ANALYSIS_TUNE)
                   ? KIOUAnalysisDepth() : depth;
    if (target != depth) {
        IPALog([NSString stringWithFormat:
                  @"[ANALYSIS] SearchFull depth %d -> %d (override)",
                  depth, target]);
    }
    return target;
}

#if IPA_CHINLAN
void KIOUHookNSSSetHashSizeEntry(void *self, int32_t mb, void *mi) {
    int32_t v = pickHashMB(mb);
    NSSSetHashSize_t bypass =
        (NSSSetHashSize_t)g_inject_entry[KIOU_HOOK_ID_NSS_SETHASHSIZE];
    if (bypass) bypass(self, v, mi);
}

void KIOUHookNSSSetSkillLevelEntry(void *self, int32_t level, void *mi) {
    int32_t v = pickSkillLevel(level);
    NSSSetSkillLevel_t bypass =
        (NSSSetSkillLevel_t)g_inject_entry[KIOU_HOOK_ID_NSS_SETSKILLEVEL];
    if (bypass) bypass(self, v, mi);
}

KIOUSyncSearchResult KIOUHookNSSSearchFullEntry(void *self, void *sfen,
                                            int32_t depth, void *mi) {
    int32_t v = pickDepth(depth);
    NSSSearchFull_t bypass =
        (NSSSearchFull_t)g_inject_entry[KIOU_HOOK_ID_NSS_SEARCHFULL];
    if (bypass) return bypass(self, sfen, v, mi);
    KIOUSyncSearchResult empty = {0};
    return empty;
}

void KIOUInstallAnalysisTuneHook(uintptr_t unityBase) {
    (void)unityBase;
    IPALog([NSString stringWithFormat:
              @"[CHINLAN] AnalysisTune: entry hooks wired "
              @"(depth=%d hash=%d MB skill=%d)",
              (int)KIOUAnalysisDepth(),
              (int)KIOUAnalysisHashMB(),
              (int)KIOUAnalysisSkillLevel()]);
}
#else
static void HookNSSSetHashSize(void *self, int32_t mb, void *mi) {
    int32_t v = pickHashMB(mb);
    if (orig_NSS_SetHashSize) orig_NSS_SetHashSize(self, v, mi);
}

static void HookNSSSetSkillLevel(void *self, int32_t level, void *mi) {
    int32_t v = pickSkillLevel(level);
    if (orig_NSS_SetSkillLevel) orig_NSS_SetSkillLevel(self, v, mi);
}

static KIOUSyncSearchResult HookNSSSearchFull(void *self, void *sfen,
                                            int32_t depth, void *mi) {
    int32_t v = pickDepth(depth);
    if (orig_NSS_SearchFull) return orig_NSS_SearchFull(self, sfen, v, mi);
    KIOUSyncSearchResult empty = {0};
    return empty;
}

void KIOUInstallAnalysisTuneHook(uintptr_t unityBase) {
    {
        uintptr_t addr = unityBase + RVA_NSS_SETHASHSIZE;
        MSHookFunction((void *)addr,
                       (void *)HookNSSSetHashSize,
                       (void **)&orig_NSS_SetHashSize);
        IPALog([NSString stringWithFormat:
                  @"NativeSyncSession.SetHashSize hooked @0x%lx hash=%d MB",
                  (unsigned long)addr, (int)KIOUAnalysisHashMB()]);
    }
    {
        uintptr_t addr = unityBase + RVA_NSS_SETSKILLEVEL;
        MSHookFunction((void *)addr,
                       (void *)HookNSSSetSkillLevel,
                       (void **)&orig_NSS_SetSkillLevel);
        IPALog([NSString stringWithFormat:
                  @"NativeSyncSession.SetSkillLevel hooked @0x%lx skill=%d",
                  (unsigned long)addr, (int)KIOUAnalysisSkillLevel()]);
    }
    {
        uintptr_t addr = unityBase + RVA_NSS_SEARCHFULL;
        MSHookFunction((void *)addr,
                       (void *)HookNSSSearchFull,
                       (void **)&orig_NSS_SearchFull);
        IPALog([NSString stringWithFormat:
                  @"NativeSyncSession.SearchFull hooked @0x%lx depth=%d",
                  (unsigned long)addr, (int)KIOUAnalysisDepth()]);
    }
}
#endif
