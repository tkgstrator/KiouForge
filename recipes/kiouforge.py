"""Recipe for KiouForge — binpatch distribution.

KiouForge is a local quality-of-life tool for KIOU: FPS preset extension,
AFK false-positive suppression, and post-game analysis engine tuning. It does
not unlock entitlements, modify server-stored data, or touch any in-match
assist feature.

Patch chain is identical to KiouEditor (see that tweak for the full
explanation). Differences:
  - 6 hook slots (down from 24).
  - Slot base: 0x8F90CA0 = 0x8F90CD0 - 6*8 (below KiouKifExporter's slot;
    KiouForge replaces autosave so both should not be installed together).
  - PLIST_KEYS adds CADisableMinimumFrameDurationOnPhone = True so >60 fps
    values reach the display on ProMotion devices.

CAVE_REGION and cave payload shape are identical to KiouEditor so the two
recipes can share __TEXT zero-fill without collision (they target different
IPAs, but the layout is validated independently by assert_slot_in_bss).
"""

from __future__ import annotations

from tools.encode import (
    adrp,
    b_imm,
    blr_x,
    ldp_post_x,
    ldr_x_imm,
    movz_w_imm,
    ret_insn,
    stp_pre_x,
)

_NOP = b"\x1f\x20\x03\xd5"

# ---------------------------------------------------------------------------
# Target identification
# ---------------------------------------------------------------------------

TARGET_BASENAME = "UnityFramework"
DYLIB_PATH = "@executable_path/Frameworks/KiouForge.dylib"

# ---------------------------------------------------------------------------
# Code-cave region (shared layout with KiouEditor; same __TEXT zero-fill).
# ---------------------------------------------------------------------------

CAVE_REGION = (0x8268024, 0x826C000)

# ---------------------------------------------------------------------------
# Hook slot base.
#
# 5 slots * 8 B = 40 B below KiouKifExporter's slot at 0x8F90CD0.
#   0x8F90CD0 - 5*8 = 0x8F90CA8
#
# Must match KIOU_HOOK_SLOT_BASE_RVA in binpatch_sites.h.
# ---------------------------------------------------------------------------

KIOU_SLOT_COUNT = 6
HOOK_SLOT_BASE_RVA = 0x8F90CD0 - KIOU_SLOT_COUNT * 8  # 0x8F90CA0

CAVE_PAYLOAD_SIZE = 84  # 21 instructions — identical to KiouEditor

_ENTRY_INSNS = 8
_TAIL_BYTES  = 8
_PAD_INSNS   = (CAVE_PAYLOAD_SIZE - _ENTRY_INSNS * 4 - _TAIL_BYTES) // 4  # 11


def _build_entry_cave_payload(orig_va, slot_va, displaced_insn, slot_index):
    """Return a build_payload(cave_va) -> bytes closure for one site."""
    if len(displaced_insn) != 4:
        raise ValueError(f"displaced_insn must be 4 bytes; got {len(displaced_insn)}")
    if not (0 <= slot_index < KIOU_SLOT_COUNT):
        raise ValueError(f"slot_index out of range: {slot_index}")

    def build(cave_va):
        out = bytearray()
        cur = cave_va

        def emit(insn):
            nonlocal cur
            out.extend(insn)
            cur += 4

        emit(stp_pre_x(29, 30, 31, -0x10))
        emit(adrp(16, cur, slot_va))
        emit(ldr_x_imm(16, 16, slot_va & 0xFFF))
        emit(movz_w_imm(9, slot_index))
        emit(blr_x(16))
        emit(ldp_post_x(29, 30, 31, 0x10))
        emit(ret_insn())
        emit(_NOP)

        for _ in range(_PAD_INSNS):
            emit(_NOP)

        emit(displaced_insn)
        emit(b_imm(cur, orig_va + 4))

        if len(out) != CAVE_PAYLOAD_SIZE:
            raise AssertionError(
                f"cave payload wrong size: got {len(out)}, expected {CAVE_PAYLOAD_SIZE}"
            )
        return bytes(out)

    return build


# ---------------------------------------------------------------------------
# Slot-index constants (must match binpatch_sites.h enum order).
# ---------------------------------------------------------------------------

KIOU_SLOT_SET_TARGET_FRAMERATE     = 0
KIOU_SLOT_GAME_ORCHESTRATOR_IS_AFK = 1
KIOU_SLOT_NSS_SETHASHSIZE          = 2
KIOU_SLOT_NSS_SETSKILLEVEL         = 3
KIOU_SLOT_TITLE_SCENE_MOVENEXT     = 4
KIOU_SLOT_NSS_SEARCHFULL           = 5

# (slot_index, site_off, expected_prologue_hex, label)
#
# All prologues captured from clean Kiou-1.0.1 build 11 UnityFramework
# via: xxd -s <site_off> -l 4 -p UnityFramework
#
#   f44fbea9 = STP X20,X19,[SP,#-0x20]!  (PC-independent)
#   ff0301d1 = SUB SP,SP,#0x40           (PC-independent)
#   ff0303d1 = SUB SP,SP,#0xC0           (PC-independent)
#   ffc305d1 = SUB SP,SP,#0x170          (PC-independent)
_SITES: list[tuple[int, int, str, str]] = [
    (KIOU_SLOT_SET_TARGET_FRAMERATE,     0x6B6B758, "f44fbea9",
     "Application.set_targetFrameRate"),
    (KIOU_SLOT_GAME_ORCHESTRATOR_IS_AFK, 0x59455D4, "f44fbea9",
     "GameOrchestrator.IsAfkEnabled"),
    (KIOU_SLOT_NSS_SETHASHSIZE,          0x5D320E0, "ff0301d1",
     "NativeSyncSession.SetHashSize"),
    (KIOU_SLOT_NSS_SETSKILLEVEL,         0x5D3206C, "ff0301d1",
     "NativeSyncSession.SetSkillLevel"),
    (KIOU_SLOT_TITLE_SCENE_MOVENEXT,     0x5DCC728, "ff0303d1",
     "TitleScene+<OnActivateAsync>d__10.MoveNext"),
    (KIOU_SLOT_NSS_SEARCHFULL,           0x5D32178, "ffc305d1",
     "NativeSyncSession.SearchFull"),
]


def _validate_sites() -> None:
    if len(_SITES) != KIOU_SLOT_COUNT:
        raise AssertionError(
            f"_SITES must have {KIOU_SLOT_COUNT} rows; got {len(_SITES)}"
        )
    slots_seen: set[int] = set()
    offs_seen:  set[int] = set()
    tbd: list[str] = []
    for slot, off, prologue_hex, label in _SITES:
        if slot in slots_seen:
            raise AssertionError(f"duplicate slot index {slot} ({label})")
        if off in offs_seen:
            raise AssertionError(f"duplicate site offset 0x{off:X} ({label})")
        slots_seen.add(slot)
        offs_seen.add(off)
        if prologue_hex == "":
            tbd.append(f"  slot[{slot:>2}] @ 0x{off:08X}  {label}")
            continue
        if len(prologue_hex) != 8:
            raise AssertionError(
                f"prologue hex for {label} must be 8 chars, got {len(prologue_hex)}"
            )
        bytes.fromhex(prologue_hex)
    if tbd:
        raise NotImplementedError(
            "recipes/kiouforge.py: prologue bytes not captured yet for "
            f"{len(tbd)}/{KIOU_SLOT_COUNT} sites:\n" + "\n".join(tbd)
        )


_validate_sites()

PATCHES: list = []

CAVE_PATCHES: list = [
    (
        site_off,
        bytes.fromhex(prologue_hex),
        _build_entry_cave_payload(
            orig_va=site_off,
            slot_va=HOOK_SLOT_BASE_RVA + slot_index * 8,
            displaced_insn=bytes.fromhex(prologue_hex),
            slot_index=slot_index,
        ),
        f"slot[{slot_index:>2}] {label}",
    )
    for slot_index, site_off, prologue_hex, label in _SITES
]

# ---------------------------------------------------------------------------
# Info.plist additions.
#
# CADisableMinimumFrameDurationOnPhone = True:  unlocks >60 fps on ProMotion
#   devices (iPhone 13 Pro+, iPad Pro M1+). Without this iOS caps the
#   display link at 60 Hz regardless of targetFrameRate.
# UIFileSharingEnabled + LSSupportsOpeningDocumentsInPlace:  exposes
#   Documents/ through Files.app so operators can retrieve kiouforge.log.
# ---------------------------------------------------------------------------

PLIST_KEYS: dict = {
    "CADisableMinimumFrameDurationOnPhone": True,
    "UIFileSharingEnabled": True,
    "LSSupportsOpeningDocumentsInPlace": True,
}
