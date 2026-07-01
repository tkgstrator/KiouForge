#pragma once

#import "KIOUHook.h"
#import "il2cpp.h"
#import "logging.h"

// ===========================================================================
// Internal.h — KiouForge tweak-local declarations.
//
// The KIOU binary catalog (RVAs, hook-id enum, dispatcher externs, shared
// installer protos, KIOUUniTaskRet, KIOUNavigateToTitleScene) lives in
// vendor/KIOU-Hook/KIOUHook.h and is brought in by the import above.
// ===========================================================================

#ifndef KIOU_FORGE_COMMIT
#define KIOU_FORGE_COMMIT "unknown"
#endif

#ifndef KIOU_FORGE_VERSION
#define KIOU_FORGE_VERSION "dev"
#endif

// ---------------------------------------------------------------------------
// IL2CPP write helpers.
// ---------------------------------------------------------------------------

static inline void writeU8(void *base, uintptr_t off, uint8_t val) {
    if (!ptrLooksValid(base)) return;
    *(volatile uint8_t *)((uint8_t *)base + off) = val;
}

static inline void writeI32(void *base, uintptr_t off, int32_t val) {
    if (!ptrLooksValid(base)) return;
    *(volatile int32_t *)((uint8_t *)base + off) = val;
}

// ---------------------------------------------------------------------------
// Tweak-local hook installers (KiouForge feature hooks).
// Shared installer protos (KIOUInstallAccountObserveHook /
// KIOUInstallGrpcLoggingHook) come from KIOUHook.h.
// ---------------------------------------------------------------------------

void KIOUInstallFrameRateHook(uintptr_t unityBase);
void KIOUInstallAnalysisTuneHook(uintptr_t unityBase);
void KIOUInstallKifuObserveHook(uintptr_t unityBase);

// ---------------------------------------------------------------------------
// SyncSearchResult — mirrors Project.RshogiEngine.SyncSearchResult (struct).
// Defined here so Hook/AnalysisTune.m can declare the SearchFull hook with
// the correct sret return type, letting the C compiler manage x8 correctly.
//
//   Bestmove string* : +0x00
//   Score    int32   : +0x08
//   PV       string* : +0x10
//   Depth    int32   : +0x18
// ---------------------------------------------------------------------------
typedef struct {
    void    *Bestmove;  // il2cpp String*
    int32_t  Score;
    void    *PV;        // il2cpp String*
    int32_t  Depth;
} KIOUSyncSearchResult;

// ---------------------------------------------------------------------------
// KIF autosave — ported from KiouKifExporter.
//
// IMatchMode lifecycle observation. The observer cave passes the mode index
// in X2 so we can pick the right `_gameAdapter` field offset on `self` and
// recover the live GameController without guessing.
//
// Reference (dump.cs):
//   AIMatchMode      _gameAdapter @ 0x48
//   CPUStreamMode    _gameAdapter @ 0x50
//   LocalPvPMode     _gameAdapter @ 0x18
//   OnlinePvPMode    _gameAdapter @ 0x30
//   RecordReplayMode _gameAdapter @ 0x18
//
// The order MUST match _SITES observer rows in recipes/ — the recipe bakes
// each mode index as `MOVZ X2,#imm` in the cave.
// ---------------------------------------------------------------------------

// ShogiGameAdapter -> Project.ShogiCore.GameController field offset.
#define KIOU_ADAPTER_OFF_GAMECTRL 0x10

// Entry point invoked by the OnMatchEndAsync cave for every IMatchMode.
//   x0 = self (the IMatchMode instance)
//   x1 = ct   (CancellationToken)
//   x2 = mode_index (KiouMatchMode, injected by cave's MOVZ X2,#imm)
KIOUUniTaskRet KIOUKifuObserveMatchEnd(void *self, void *ct, uint32_t mode_index);

// Kif_Writer pipeline.
NSString *KIOUKifWriterEmit(void *gameCtrl,
                             void *matchConfig,
                             void *stateStore,
                             const char *matchModeTag);

// Helpers.
NSString *KIOUKifTimestamp(void);
NSString *KIOUKifSanitizeSegment(NSString *s, NSUInteger maxChars);
NSString *KIOUKifEnsureOutputDir(void);
NSString *KIOUKifDescribeStartpos(void *gameCtrl);
NSString *KIOUKifDescribeOpponents(void *matchConfig, void *stateStore);
NSString *KIOUKifTextFromGameController(void *gameCtrl,
                                         void *matchConfig,
                                         void *stateStore,
                                         const char *matchModeTag);

// KIFWriteOptions field offsets (KIOU 1.0.1 build 11).
#define KIFOPTS_OFF_BLACK_PLAYER_NAME 0x10
#define KIFOPTS_OFF_WHITE_PLAYER_NAME 0x18
#define KIFOPTS_OFF_START_DATETIME    0x20
#define KIFOPTS_OFF_MATCH_TITLE       0x30
#define KIFOPTS_OFF_TIME_RULE_LABEL   0x38
#define KIFOPTS_OFF_ENDING_LABEL      0x48

void *KIOUIl2cppStringNew(const char *utf8);
void  KIOUKifFillWriteOptions(void *opts,
                               void *matchConfig,
                               void *stateStore,
                               void *gameCtrl,
                               const char *matchModeTag);

// ---------------------------------------------------------------------------
// Runtime feature toggles.
// ---------------------------------------------------------------------------
typedef NS_ENUM(NSInteger, KiouFeature) {
    KIOU_FEATURE_FPS_OVERRIDE    = 0,  // Hook_FrameRate FPS override
    KIOU_FEATURE_DISABLE_AFK     = 1,  // Hook_AfkDisable suppress warning
    KIOU_FEATURE_ANALYSIS_TUNE   = 2,  // Hook_AnalysisTune post-game engine
    KIOU_FEATURE_KIFU_AUTOSAVE   = 3,  // Hook_KifuObserve auto-save KIF
    KIOU_FEATURE_COUNT,
};

bool KIOUFeatureEnabled(KiouFeature f);
void KIOUSetFeatureEnabled(KiouFeature f, bool enabled);
NSString *KIOUFeatureLabel(KiouFeature f);

bool KIOUFeatureHasNavigation(KiouFeature f);

// ---------------------------------------------------------------------------
// Per-match-mode toggles for kifu autosave.
// ---------------------------------------------------------------------------
typedef NS_ENUM(NSInteger, KiouMatchMode) {
    KIOU_MMODE_AI_MATCH      = 0,
    KIOU_MMODE_CPU_STREAM    = 1,
    KIOU_MMODE_LOCAL_PVP     = 2,
    KIOU_MMODE_ONLINE_PVP    = 3,
    KIOU_MMODE_RECORD_REPLAY = 4,
    KIOU_MMODE_COUNT,
};

bool      KIOUKifuModeEnabled(KiouMatchMode m);
void      KIOUSetKifuModeEnabled(KiouMatchMode m, bool enabled);
NSString *KIOUKifuModeLabel(KiouMatchMode m);

// IMatchMode self -> _gameAdapter field offsets. The enum order MUST match
// the observer rows of _SITES in recipes/ — the recipe bakes each index as
// `MOVZ X2,#imm` in the cave.
static const uintptr_t kKiouMatchModeAdapterOffsets[KIOU_MMODE_COUNT] = {
    [KIOU_MMODE_AI_MATCH]      = 0x48,
    [KIOU_MMODE_CPU_STREAM]    = 0x50,
    [KIOU_MMODE_LOCAL_PVP]     = 0x18,
    [KIOU_MMODE_ONLINE_PVP]    = 0x30,
    [KIOU_MMODE_RECORD_REPLAY] = 0x18,
};

// IMatchMode self -> _stateStore field offsets. All five IMatchMode
// implementations carry a GameStateStore reference sitting one pointer
// slot before _gameAdapter — reading it lets the kif writer pull
// player names via the same ReactiveProperty<PlayerInfo> path online
// matches use.
static const uintptr_t kKiouMatchModeStateStoreOffsets[KIOU_MMODE_COUNT] = {
    [KIOU_MMODE_AI_MATCH]      = 0x40,
    [KIOU_MMODE_CPU_STREAM]    = 0x48,
    [KIOU_MMODE_LOCAL_PVP]     = 0x10,
    [KIOU_MMODE_ONLINE_PVP]    = 0x28,
    [KIOU_MMODE_RECORD_REPLAY] = 0x10,
};

static const char *const kKiouMatchModeTags[KIOU_MMODE_COUNT] = {
    [KIOU_MMODE_AI_MATCH]      = "AIMatchMode",
    [KIOU_MMODE_CPU_STREAM]    = "CPUStreamMode",
    [KIOU_MMODE_LOCAL_PVP]     = "LocalPvPMode",
    [KIOU_MMODE_ONLINE_PVP]    = "OnlinePvPMode",
    [KIOU_MMODE_RECORD_REPLAY] = "RecordReplayMode",
};

// ---------------------------------------------------------------------------
// FPS preset table and accessor.
// ---------------------------------------------------------------------------
#define KIOU_FPS_PRESET_COUNT  7
// Presets (preset[i] is the FPS value): {15,24,30,45,60,90,120}

int32_t KIOUTargetFPS(void);
int32_t KIOUFPSIndex(void);
void    KIOUSetFPSIndex(int32_t idx);

// ---------------------------------------------------------------------------
// Analysis engine tuning (NativeSyncSession post-game path only).
// ---------------------------------------------------------------------------
int32_t KIOUAnalysisDepth(void);
void    KIOUSetAnalysisDepth(int32_t v);

#define KIOU_ANALYSIS_HASH_PRESET_COUNT  6
// Presets: {16, 64, 128, 256, 512, 1024}

int32_t KIOUAnalysisHashIndex(void);
void    KIOUSetAnalysisHashIndex(int32_t idx);
int32_t KIOUAnalysisHashMB(void);
int32_t KIOUAnalysisSkillLevel(void);
void    KIOUSetAnalysisSkillLevel(int32_t v);
