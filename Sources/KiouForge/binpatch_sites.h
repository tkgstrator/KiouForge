#pragma once

#include <stdint.h>

// ===========================================================================
// binpatch_sites.h — KiouForge binpatch slot table.
//
// Single source of truth shared between:
//   * Sources/KiouForge/BinpatchEntries.m
//   * recipes/kiouforge.py
//
// All RVAs are pinned to KIOU 1.0.1 build 11's UnityFramework. See
// docs/porting.md (or KiouEditor's docs/porting.md as a reference) when
// KIOU updates.
//
// CO-EXISTENCE
// ---------------------------------
// KiouForge reserves 5 slots (40 B) in UnityFramework __DATA,__bss at
// [KIOU_HOOK_SLOT_BASE_RVA, KIOU_HOOK_SLOT_BASE_RVA + KIOU_SLOT_COUNT*8).
// The patcher's assert_slot_in_bss() validates the range at patch time.
// KiouForge is designed to be installed standalone; it does not co-exist
// with KiouEditor in the same IPA.
// ===========================================================================

// ---------------------------------------------------------------------------
// Slot indices.
// ---------------------------------------------------------------------------
enum {
    KIOU_SLOT_SET_TARGET_FRAMERATE      = 0,   // Application.set_targetFrameRate
    KIOU_SLOT_GAME_ORCHESTRATOR_IS_AFK  = 1,   // GameOrchestrator.IsAfkEnabled
    KIOU_SLOT_NSS_SETHASHSIZE           = 2,   // NativeSyncSession.SetHashSize
    KIOU_SLOT_NSS_SETSKILLEVEL          = 3,   // NativeSyncSession.SetSkillLevel
    KIOU_SLOT_TITLE_SCENE_MOVENEXT      = 4,   // TitleScene version stamp
    KIOU_SLOT_NSS_SEARCHFULL            = 5,   // NativeSyncSession.SearchFull (depth)
    KIOU_SLOT_COUNT                     = 6,
};

// ---------------------------------------------------------------------------
// __bss slot table base.
// 6 slots * 8 B = 48 B below KiouKifExporter's slot at 0x8F90CD0.
// ---------------------------------------------------------------------------
#define KIOU_HOOK_SLOT_BASE_RVA  0x8F90CA0   // 0x8F90CD0 - 6*8
extern void **g_kiou_hook_slot;

// ---------------------------------------------------------------------------
// Cave payload size — must match recipes/kiouforge.py::CAVE_PAYLOAD_SIZE.
// ---------------------------------------------------------------------------
#define KIOU_BINPATCH_CAVE_PAYLOAD_SIZE  84

// ---------------------------------------------------------------------------
// Orig-trampoline resolver (thin wrapper over ipa_binpatch_resolve_orig).
// ---------------------------------------------------------------------------
uintptr_t kiou_resolve_orig_trampoline(uintptr_t unityBase, uintptr_t siteRVA);

// ---------------------------------------------------------------------------
// Site RVAs (KIOU 1.0.1 build 11 UnityFramework).
// ---------------------------------------------------------------------------
#define KIOU_SITE_RVA_SET_TARGET_FRAMERATE      0x6B6B758
#define KIOU_SITE_RVA_GAME_ORCHESTRATOR_IS_AFK  0x59455D4
#define KIOU_SITE_RVA_NSS_SETHASHSIZE           0x5D320E0
#define KIOU_SITE_RVA_NSS_SETSKILLEVEL          0x5D3206C
#define KIOU_SITE_RVA_TITLE_SCENE_MOVENEXT      0x5DCC728
#define KIOU_SITE_RVA_NSS_SEARCHFULL            0x5D32178
