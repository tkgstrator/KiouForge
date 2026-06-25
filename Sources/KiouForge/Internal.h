#pragma once

#import <Foundation/Foundation.h>
#import <stdint.h>

// ---------------------------------------------------------------------------
// Hook engine selection.
// ---------------------------------------------------------------------------
#if IPA_CHINLAN
#import "chinlan.h"
#else
#import "hookengine.h"
#endif

// ---------------------------------------------------------------------------
// Chinlan slot table — keep in sync with recipes/v1_0_2.py.
// ---------------------------------------------------------------------------

// Single observer-dispatcher slot. Every CAVE_OBSERVER cave loads this
// pointer, BLRs it with W6 = hook_id, and routes through dispatch_one.
#define KIOU_KF_HOOK_SLOT_RVA            0x8F90C80

// Entry-cave slot table. Slot N at +N*8 holds the function pointer the
// CAVE_ENTRY cave BLRs directly (no dispatcher).
#define KIOU_KF_ENTRY_SLOT_BASE_RVA      0x091E91B8

// Cave geometry — mirrors recipes/common.py.
#define KIOU_KF_CAVE_REGION_START        0x826F5E8
#define KIOU_KF_CAVE_SIZE                84
#define KIOU_KF_CAVE_BYPASS_OFFSET       (KIOU_KF_CAVE_SIZE - 8)

// Hook id enum — one row per cave site. CAVE_OBSERVER caves embed this id
// in the cave's MOVZ W6,#imm so dispatch_one can switch on it. CAVE_ENTRY
// caves don't dispatch by id, but they still get an enum entry so the
// bypass index (cave allocation order) matches the enum value.
enum kiou_kf_hook_id {
    // Entry caves (route through entry slot table)
    KIOU_KF_HOOK_SET_TARGET_FRAMERATE = 0,
    KIOU_KF_HOOK_NSS_SETHASHSIZE,
    KIOU_KF_HOOK_NSS_SETSKILLEVEL,
    KIOU_KF_HOOK_NSS_SEARCHFULL,
    KIOU_KF_HOOK_ACCOUNT_EXISTS,
    KIOU_KF_HOOK_LOGIN_ARGS_CREATE,
    KIOU_KF_HOOK_REGISTER_USER_ARGS_CREATE,
    KIOU_KF_HOOK_RUN_LOGIN_SEQ_MOVENEXT,
    KIOU_KF_HOOK_GET_SELF_PROFILE_MOVENEXT,
    KIOU_KF_HOOK_HTTPMSGINVOKER_SEND_ASYNC,
    // Observer caves (routed by dispatch_one's switch)
    KIOU_KF_HOOK_KIFU_AI_END,
    KIOU_KF_HOOK_KIFU_CPUSTREAM_END,
    KIOU_KF_HOOK_KIFU_LOCAL_END,
    KIOU_KF_HOOK_KIFU_ONLINE_END,
    KIOU_KF_HOOK_KIFU_REPLAY_END,

    KIOU_KF_HOOK__COUNT,
};

// Entry-slot enum — one per CAVE_ENTRY row. Slot N's function pointer
// lives at unityBase + KIOU_KF_ENTRY_SLOT_BASE_RVA + N*8.
enum kiou_kf_entry_slot_id {
    KIOU_KF_ENTRY_SLOT_SET_TARGET_FRAMERATE = 0,
    KIOU_KF_ENTRY_SLOT_NSS_SETHASHSIZE,
    KIOU_KF_ENTRY_SLOT_NSS_SETSKILLEVEL,
    KIOU_KF_ENTRY_SLOT_NSS_SEARCHFULL,
    KIOU_KF_ENTRY_SLOT_ACCOUNT_EXISTS,
    KIOU_KF_ENTRY_SLOT_LOGIN_ARGS_CREATE,
    KIOU_KF_ENTRY_SLOT_REGISTER_USER_ARGS_CREATE,
    KIOU_KF_ENTRY_SLOT_RUN_LOGIN_SEQ_MOVENEXT,
    KIOU_KF_ENTRY_SLOT_GET_SELF_PROFILE_MOVENEXT,
    KIOU_KF_ENTRY_SLOT_HTTPMSGINVOKER_SEND_ASYNC,

    KIOU_KF_ENTRY_SLOT__COUNT,
};

// Site RVAs — used by JB-flavour MSHookFunction installers.
#define KIOU_KF_SITE_RVA_SET_TARGET_FRAMERATE       0x6B718A4
#define KIOU_KF_SITE_RVA_GAME_ORCHESTRATOR_IS_AFK   0x594A034
#define KIOU_KF_SITE_RVA_NSS_SETHASHSIZE            0x5D379DC
#define KIOU_KF_SITE_RVA_NSS_SETSKILLEVEL           0x5D37968
#define KIOU_KF_SITE_RVA_NSS_SEARCHFULL             0x5D37A74
#define KIOU_KF_SITE_RVA_AI_END                     0x59EA720
#define KIOU_KF_SITE_RVA_CPUSTREAM_END              0x59F15D4
#define KIOU_KF_SITE_RVA_LOCAL_END                  0x5A046B4
#define KIOU_KF_SITE_RVA_ONLINE_END                 0x5A06158
#define KIOU_KF_SITE_RVA_REPLAY_END                 0x5A30320
#define KIOU_KF_SITE_RVA_ACCOUNT_EXISTS             0x5922CD0
#define KIOU_KF_SITE_RVA_LOGIN_ARGS_CREATE          0x5B9DC04
#define KIOU_KF_SITE_RVA_REGISTER_USER_ARGS_CREATE  0x5B9DC94
#define KIOU_KF_SITE_RVA_RUN_LOGIN_SEQ_MOVENEXT     0x58152BC
#define KIOU_KF_SITE_RVA_GET_SELF_PROFILE_MOVENEXT  0x5BB99DC
#define KIOU_KF_SITE_RVA_HTTPMSGINVOKER_SEND_ASYNC  0x6082AC0
#define KIOU_KF_SITE_RVA_BACK_TO_TITLE_RUN_ASYNC    0x5CFC394

// Chinlan dispatcher publishes per-site cave-bypass addresses here so hook
// bodies can call orig without re-entering the cave.
#if IPA_CHINLAN
extern void * volatile g_inject_entry[KIOU_KF_HOOK__COUNT];
#endif

void KFChinlanPublish(uintptr_t unityBase);

// UnityFramework base captured at install time.
extern uintptr_t g_unityBase;

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

void KFInstallFrameRateHook(uintptr_t unityBase);
void KFInstallAnalysisTuneHook(uintptr_t unityBase);
void KFInstallKifuObserveHook(uintptr_t unityBase);
void KFInstallAccountObserveHook(uintptr_t unityBase);
void KFInstallGrpcLoggingHook(uintptr_t unityBase);

// Drive BackToTitleSequence.RunAsync — used by Settings UI on account switch.
void KFNavigateToTitleScene(void);


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
