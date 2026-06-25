"""KiouForge patch constants for app version 1.0.1 (CFBundleVersion 11).

RVAs verified against assets/1.0.1/dump.cs.index.json on 2026-06-15.
Note: account switching / gRPC header swap are not supported on 1.0.1.
"""

from recipes.common import CAVE_ENTRY, CAVE_OBSERVER

BUILD = 11

CAVE_REGION         = (0x8268024, 0x826C000)
HOOK_SLOT_RVA       = 0x8F90C80
PROBED_HOOK_SLOT_RVA = HOOK_SLOT_RVA

INJECT_ENTRY_TABLE_RVA        = 0x8F90C00
PROBED_INJECT_ENTRY_TABLE_RVA = 0x8F90C00
ENTRY_SLOT_BASE_RVA           = 0x091E91B8
ZERO_REGION_END_RVA           = 0x091F5978

AFK_SITE   = 0x59455D4
AFK_ORIG_8 = "f44fbea9fd7b01a9"

# fmt: off
SITES = [
    # --- Entry caves (CAVE_ENTRY) ---
    (0x6B6B758, "f44fbea9", "KIOU_KF_HOOK_SET_TARGET_FRAMERATE",     CAVE_ENTRY, "Application.set_targetFrameRate"),
    (0x5D320E0, "ff0301d1", "KIOU_KF_HOOK_NSS_SETHASHSIZE",          CAVE_ENTRY, "NativeSyncSession.SetHashSize"),
    (0x5D3206C, "ff0301d1", "KIOU_KF_HOOK_NSS_SETSKILLEVEL",         CAVE_ENTRY, "NativeSyncSession.SetSkillLevel"),
    (0x5D32178, "ffc305d1", "KIOU_KF_HOOK_NSS_SEARCHFULL",           CAVE_ENTRY, "NativeSyncSession.SearchFull"),

    # --- Observer caves (CAVE_OBSERVER): IMatchMode.OnMatchEndAsync × 5 ---
    (0x59E5958, "f657bda9", "KIOU_KF_HOOK_KIFU_AI_END",        CAVE_OBSERVER, "AIMatchMode.OnMatchEndAsync"),
    (0x59EC818, "ff8301d1", "KIOU_KF_HOOK_KIFU_CPUSTREAM_END", CAVE_OBSERVER, "CPUStreamMode.OnMatchEndAsync"),
    (0x59FF8F8, "f44fbea9", "KIOU_KF_HOOK_KIFU_LOCAL_END",     CAVE_OBSERVER, "LocalPvPMode.OnMatchEndAsync"),
    (0x5A0139C, "ff8301d1", "KIOU_KF_HOOK_KIFU_ONLINE_END",    CAVE_OBSERVER, "OnlinePvPMode.OnMatchEndAsync"),
    (0x5A2B564, "f85fbca9", "KIOU_KF_HOOK_KIFU_REPLAY_END",    CAVE_OBSERVER, "RecordReplayMode.OnMatchEndAsync"),
]
# fmt: on
