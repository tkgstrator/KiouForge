#pragma once

#import <Foundation/Foundation.h>
#import <stdint.h>

// ---------------------------------------------------------------------------
// Hook engine selection.
// ---------------------------------------------------------------------------
#if IPA_CHINLAN
#import "ChinlanSites.h"
#else
#import "hookengine.h"
#endif

#import "il2cpp.h"
#import "logging.h"

// ===========================================================================
// Internal.h — KiouForge shared declarations.
//
// Write helpers (writeU8 / writeI32) are included here so hook files can
// mutate IL2CPP fields where needed (e.g. AFK gate).
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
// Per-module hook installers.
// ---------------------------------------------------------------------------

#if IPA_CHINLAN
void KFPublishFrameRateSlots(uintptr_t unityBase);
void KFPublishAfkDisableSlots(uintptr_t unityBase);
void KFPublishAnalysisTuneSlots(uintptr_t unityBase);
void KFPublishKifuObserveSlots(uintptr_t unityBase);
void KFChinlanBootstrap(void);
BOOL KFChinlanPublished(void);
#else
void KFInstallFrameRateHook(uintptr_t unityBase);
void KFInstallAfkDisableHook(uintptr_t unityBase);
void KFInstallAnalysisTuneHook(uintptr_t unityBase);
void KFInstallKifuObserveHook(uintptr_t unityBase);
#endif

// UnityFramework base address captured at install/publish time. Read by the
// Kif_Writer pipeline to resolve static il2cpp methods by RVA.
extern uintptr_t g_kfUnityBase;

// ---------------------------------------------------------------------------
// SyncSearchResult — mirrors Project.RshogiEngine.SyncSearchResult (struct).
// Defined here so Hook_AnalysisTune.m can declare the SearchFull hook with
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
} KFSyncSearchResult;

// ---------------------------------------------------------------------------
// KIF autosave — ported from KiouKifExporter.
//
// IMatchMode lifecycle observation. The observer cave (recipes/kiouforge.py)
// passes the mode index in X2 so we can pick the right `_gameAdapter` field
// offset on `self` and recover the live GameController without guessing.
//
// Reference (dump.cs):
//   AIMatchMode      _gameAdapter @ 0x48
//   CPUStreamMode    _gameAdapter @ 0x50
//   LocalPvPMode     _gameAdapter @ 0x18
//   OnlinePvPMode    _gameAdapter @ 0x30
//   RecordReplayMode _gameAdapter @ 0x18
//
// The order MUST match _SITES observer rows in recipes/kiouforge.py — the
// recipe bakes each mode index as `MOVZ X2,#imm` in the cave.
// kKiouMatchModeAdapterOffsets / kKiouMatchModeTags are defined further
// down, after the KiouMatchMode enum is declared.
// ---------------------------------------------------------------------------

// ShogiGameAdapter -> Project.ShogiCore.GameController field offset.
#define KIOU_ADAPTER_OFF_GAMECTRL 0x10

// UniTask is a 16-byte struct (IUniTaskSource* + short token); on arm64 it
// returns in {x0, x1}. The observer cave throws away the hook's return
// value (it runs the displaced prologue + branches to orig+4 next), but we
// match the shape for ABI correctness.
typedef struct { void *r0; void *r1; } KFUniTaskRet;

// Entry point invoked by the OnMatchEndAsync cave for every IMatchMode.
//   x0 = self (the IMatchMode instance)
//   x1 = ct   (CancellationToken)
//   x2 = mode_index (KiouMatchMode, injected by cave's MOVZ X2,#imm)
KFUniTaskRet KFKifuObserveMatchEnd(void *self, void *ct, uint32_t mode_index);

// Kif_Writer pipeline.
NSString *KFKifWriterEmit(void *gameCtrl,
                             void *matchConfig,
                             void *stateStore,
                             const char *matchModeTag);

// Helpers.
NSString *KFKifTimestamp(void);
NSString *KFKifSanitizeSegment(NSString *s, NSUInteger maxChars);
NSString *KFKifEnsureOutputDir(void);
NSString *KFKifDescribeStartpos(void *gameCtrl);
NSString *KFKifDescribeOpponents(void *matchConfig, void *stateStore);
NSString *KFKifTextFromGameController(void *gameCtrl,
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

void *KFIl2cppStringNew(const char *utf8);
void  KFKifFillWriteOptions(void *opts,
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

bool KFFeatureEnabled(KiouFeature f);
void KFSetFeatureEnabled(KiouFeature f, bool enabled);
NSString *KFFeatureLabel(KiouFeature f);

// True when this feature row should push a sub-screen for fine-grained
// configuration (e.g. KIFU_AUTOSAVE has per-mode toggles). The settings UI
// uses this to choose between a row-with-UISwitch vs. a row-with-disclosure.
bool KFFeatureHasNavigation(KiouFeature f);

// ---------------------------------------------------------------------------
// Per-match-mode toggles for kifu autosave.
//
// Each mode's flag defaults to YES so a fresh install autosaves every match.
// The OnMatchEnd hook checks BOTH the master KIOU_FEATURE_KIFU_AUTOSAVE
// toggle AND the per-mode flag before emitting the KIF file. Modes the user
// explicitly turned off are skipped silently.
// ---------------------------------------------------------------------------
typedef NS_ENUM(NSInteger, KiouMatchMode) {
    KIOU_MMODE_AI_MATCH      = 0,
    KIOU_MMODE_CPU_STREAM    = 1,
    KIOU_MMODE_LOCAL_PVP     = 2,
    KIOU_MMODE_ONLINE_PVP    = 3,
    KIOU_MMODE_RECORD_REPLAY = 4,
    KIOU_MMODE_COUNT,
};

bool      KFKifuModeEnabled(KiouMatchMode m);
void      KFSetKifuModeEnabled(KiouMatchMode m, bool enabled);
NSString *KFKifuModeLabel(KiouMatchMode m);

// IMatchMode self -> _gameAdapter field offsets. The enum order MUST match
// the observer rows of _SITES in recipes/kiouforge.py — the recipe bakes
// each index as `MOVZ X2,#imm` in the cave.
static const uintptr_t kKiouMatchModeAdapterOffsets[KIOU_MMODE_COUNT] = {
    [KIOU_MMODE_AI_MATCH]      = 0x48,
    [KIOU_MMODE_CPU_STREAM]    = 0x50,
    [KIOU_MMODE_LOCAL_PVP]     = 0x18,
    [KIOU_MMODE_ONLINE_PVP]    = 0x30,
    [KIOU_MMODE_RECORD_REPLAY] = 0x18,
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
//
//   KFTargetFPS()  — resolved FPS value from the user's chosen preset
//   KFFPSIndex()   — preset index [0, KIOU_FPS_PRESET_COUNT)
//   KFSetFPSIndex()
// ---------------------------------------------------------------------------
#define KIOU_FPS_PRESET_COUNT  7
// Presets (preset[i] is the FPS value): {15,24,30,45,60,90,120}

int32_t KFTargetFPS(void);
int32_t KFFPSIndex(void);
void    KFSetFPSIndex(int32_t idx);

// ---------------------------------------------------------------------------
// Analysis engine tuning (NativeSyncSession post-game path only).
//
//   hash index maps to {16, 64, 128, 256, 512, 1024} MB
//   skill range 1..20, default 20
//
// ---------------------------------------------------------------------------
// Analysis depth.
//   range 1..36; default 15 (retail SearchDepth constant).
//   Stored as a plain int — no preset table.
// ---------------------------------------------------------------------------
int32_t KFAnalysisDepth(void);
void    KFSetAnalysisDepth(int32_t v);

#define KIOU_ANALYSIS_HASH_PRESET_COUNT  6
// Presets: {16, 64, 128, 256, 512, 1024}

int32_t KFAnalysisHashIndex(void);
void    KFSetAnalysisHashIndex(int32_t idx);
int32_t KFAnalysisHashMB(void);
int32_t KFAnalysisSkillLevel(void);
void    KFSetAnalysisSkillLevel(int32_t v);
