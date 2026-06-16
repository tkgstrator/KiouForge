#pragma once

#import <Foundation/Foundation.h>
#import <stdint.h>

// ---------------------------------------------------------------------------
// Hook engine selection.
// ---------------------------------------------------------------------------
#if IPA_BINPATCH
#import "binpatch_sites.h"
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

#if IPA_BINPATCH
void publish_FrameRate_slots(uintptr_t unityBase);
void publish_AfkDisable_slots(uintptr_t unityBase);
void publish_AnalysisTune_slots(uintptr_t unityBase);
void publish_Version_slots(uintptr_t unityBase);
void kiou_binpatch_bootstrap(void);
BOOL kiou_binpatch_published(void);
#else
void install_FrameRate_hook(uintptr_t unityBase);
void install_AfkDisable_hook(uintptr_t unityBase);
void install_AnalysisTune_hook(uintptr_t unityBase);
void install_Version_hook(uintptr_t unityBase);
#endif

// ---------------------------------------------------------------------------
// Runtime feature toggles.
// ---------------------------------------------------------------------------
typedef NS_ENUM(NSInteger, KiouFeature) {
    KIOU_FEATURE_FPS_OVERRIDE    = 0,  // Hook_FrameRate FPS override
    KIOU_FEATURE_DISABLE_AFK     = 1,  // Hook_AfkDisable suppress warning
    KIOU_FEATURE_ANALYSIS_TUNE   = 2,  // Hook_AnalysisTune post-game engine
    KIOU_FEATURE_COUNT,
};

bool kiou_featureEnabled(KiouFeature f);
void kiou_setFeatureEnabled(KiouFeature f, bool enabled);
NSString *kiou_featureLabel(KiouFeature f);

// ---------------------------------------------------------------------------
// FPS preset table and accessor.
//
//   kiou_targetFps()  — resolved FPS value from the user's chosen preset
//   kiou_fpsIndex()   — preset index [0, KIOU_FPS_PRESET_COUNT)
//   kiou_setFpsIndex()
// ---------------------------------------------------------------------------
#define KIOU_FPS_PRESET_COUNT  7
// Presets (preset[i] is the FPS value): {15,24,30,45,60,90,120}

int32_t kiou_targetFps(void);
int32_t kiou_fpsIndex(void);
void    kiou_setFpsIndex(int32_t idx);

// ---------------------------------------------------------------------------
// Analysis engine tuning (NativeSyncSession post-game path only).
//
//   hash index maps to {16, 64, 128, 256, 512, 1024} MB
//   skill range 1..20, default 20
//
// NOTE: depth override is deferred — NativeSyncSession.SearchFull returns a
// struct (SyncSearchResult) making the hook ABI require extra care around the
// sret convention. Hash + skill already provide substantial strengthening.
// ---------------------------------------------------------------------------
#define KIOU_ANALYSIS_HASH_PRESET_COUNT  6
// Presets: {16, 64, 128, 256, 512, 1024}

int32_t kiou_analysisHashIndex(void);
void    kiou_setAnalysisHashIndex(int32_t idx);
int32_t kiou_analysisHashMB(void);
int32_t kiou_analysisSkillLevel(void);
void    kiou_setAnalysisSkillLevel(int32_t v);
