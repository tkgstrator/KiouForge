"""Recipe for KiouForge — binpatch distribution.

KiouForge is a local quality-of-life tool for KIOU: FPS preset extension,
AFK false-positive suppression, and post-game analysis engine tuning. It does
not unlock entitlements, modify server-stored data, or touch any in-match
assist feature.

Patch chain is identical to KiouEditor (see that tweak for the full
explanation). Differences:
  - 6 hook slots (title-screen stamp removed; was 7).
  - Slot base: 0x8F90CA8 = 0x8F90CD8 - 6*8 (below KiouKifExporter's slot;
    KiouForge replaces autosave so both should not be installed together).
  - PLIST_KEYS adds CADisableMinimumFrameDurationOnPhone = True so >60 fps
    values reach the display on ProMotion devices.

CAVE_REGION and cave payload shape are identical to KiouEditor so the two
recipes can share __TEXT zero-fill without collision (they target different
IPAs, but the layout is validated independently by assert_slot_in_bss).
"""

from __future__ import annotations

from tools.encode import (
    add_x_imm,
    adrp,
    b_imm,
    blr_x,
    ldp_off_x,
    ldp_post_x,
    ldr_x_imm,
    movz_w_imm,
    ret_insn,
    stp_off_x,
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
HOOK_SLOT_BASE_RVA = 0x8F90CD8 - KIOU_SLOT_COUNT * 8  # 0x8F90CA8

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
KIOU_SLOT_NSS_SEARCHFULL           = 4
KIOU_SLOT_KIFU_OBSERVE             = 5

# Mode-index constants for the observer cave — MUST match KiouMatchMode enum
# in Sources/KiouForge/Internal.h.
# Cave kinds — the recipe supports two cave shapes today:
#
#   "entry"    : the hook REPLACES the original. The cave BLRs the slot
#                with orig's args, then runs the displaced prologue +
#                B orig+4 (so chain-back via KFResolveOrigTrampoline
#                works). Used for FPS / AFK / engine tuning / version stamp.
#
#   "observer" : the hook PEEKS BEFORE orig runs. The cave saves caller
#                regs, MOVZ X2 with `aux` (mode index), BLRs the slot,
#                restores regs, then continues into the displaced prologue.
#                The hook's return value is dead — orig writes the real
#                result a few insns later. Used for the 5
#                IMatchMode.OnMatchEndAsync sites (kifu autosave).
#
# Future cave kinds (sret-aware entry / post-orig observer / predicate /
# multi-hook / stack-arg / PC-relative prologue) can be added by:
#   1. writing a new `_build_<kind>_cave_payload(...)` function above,
#   2. mapping the kind to its builder in `_CAVE_BUILDERS` below,
#   3. adding row(s) to `_SITES` with the new kind. `aux` can be reused as
#      the kind's per-row payload — int, tuple, or dict if needed.
CAVE_ENTRY    = "entry"
CAVE_OBSERVER = "observer"

# Unified site table. One 6-tuple per cave site:
#
#   (slot_index, site_off, prologue_hex, cave_kind, aux, label)
#
# `aux` is per-kind payload baked into the cave:
#   * entry    → aux is None (unused)
#   * observer → aux is the mode_index for `MOVZ X2,#imm`
#
# All prologues captured from clean Kiou-1.0.1 build 11 UnityFramework via
#   xxd -s <site_off> -l 4 -p UnityFramework
#
#   f44fbea9 = STP X20,X19,[SP,#-0x20]!
#   f657bda9 = STP X22,X21,[SP,#-0x30]!
#   f85fbca9 = STP X24,X23,[SP,#-0x40]!
#   ff0301d1 = SUB SP,SP,#0x40
#   ff0303d1 = SUB SP,SP,#0xC0
#   ff8301d1 = SUB SP,SP,#0x60
#   ffc305d1 = SUB SP,SP,#0x170
# All PC-independent — each can be relocated verbatim into a cave.
_SITES: list[tuple[int, int, str, str, object, str]] = [
    # --- Entry caves ---
    (KIOU_SLOT_SET_TARGET_FRAMERATE,     0x6B6B758, "f44fbea9", CAVE_ENTRY,    None,
     "Application.set_targetFrameRate"),
    (KIOU_SLOT_GAME_ORCHESTRATOR_IS_AFK, 0x59455D4, "f44fbea9", CAVE_ENTRY,    None,
     "GameOrchestrator.IsAfkEnabled"),
    (KIOU_SLOT_NSS_SETHASHSIZE,          0x5D320E0, "ff0301d1", CAVE_ENTRY,    None,
     "NativeSyncSession.SetHashSize"),
    (KIOU_SLOT_NSS_SETSKILLEVEL,         0x5D3206C, "ff0301d1", CAVE_ENTRY,    None,
     "NativeSyncSession.SetSkillLevel"),
    (KIOU_SLOT_NSS_SEARCHFULL,           0x5D32178, "ffc305d1", CAVE_ENTRY,    None,
     "NativeSyncSession.SearchFull"),
    # --- Observer caves: all share KIOU_SLOT_KIFU_OBSERVE; aux is the
    # mode_index baked into the cave's MOVZ X2,#imm so the hook can
    # discriminate. Order = KiouMatchMode enum order. ---
    (KIOU_SLOT_KIFU_OBSERVE,             0x59E5958, "f657bda9", CAVE_OBSERVER, 0,
     "AIMatchMode.OnMatchEndAsync"),
    (KIOU_SLOT_KIFU_OBSERVE,             0x59EC818, "ff8301d1", CAVE_OBSERVER, 1,
     "CPUStreamMode.OnMatchEndAsync"),
    (KIOU_SLOT_KIFU_OBSERVE,             0x59FF8F8, "f44fbea9", CAVE_OBSERVER, 2,
     "LocalPvPMode.OnMatchEndAsync"),
    (KIOU_SLOT_KIFU_OBSERVE,             0x5A0139C, "ff8301d1", CAVE_OBSERVER, 3,
     "OnlinePvPMode.OnMatchEndAsync"),
    (KIOU_SLOT_KIFU_OBSERVE,             0x5A2B564, "f85fbca9", CAVE_OBSERVER, 4,
     "RecordReplayMode.OnMatchEndAsync"),
]


def _validate_sites() -> None:
    """Validate _SITES: row shape, prologue hex, slot coverage.

    Rules:
      * site offsets are unique (no two caves at the same site).
      * "entry" rows: one per slot (entry caves are 1:1).
      * "observer" rows: same slot may appear multiple times; aux must be
        a non-negative int (the mode index for MOVZ X2,#imm).
      * A slot cannot be used for both entry and observer caves.
      * Every slot in [0, KIOU_SLOT_COUNT) must be claimed by at least
        one row.
      * Prologues must be 8 lowercase hex chars decoding to 4 bytes.
    """
    offs_seen: set[int] = set()
    entry_slots_seen: set[int] = set()
    observer_slots_seen: set[int] = set()
    tbd: list[str] = []
    for slot, off, prologue_hex, kind, aux, label in _SITES:
        if not (0 <= slot < KIOU_SLOT_COUNT):
            raise AssertionError(
                f"slot index out of [0, {KIOU_SLOT_COUNT}) for {label}: {slot}"
            )
        if off in offs_seen:
            raise AssertionError(f"duplicate site offset 0x{off:X} ({label})")
        offs_seen.add(off)
        if kind == CAVE_ENTRY:
            if slot in entry_slots_seen:
                raise AssertionError(
                    f"duplicate entry slot {slot} ({label}); entry slots are 1:1"
                )
            if aux is not None:
                raise AssertionError(
                    f"entry rows must have aux=None; {label} has aux={aux!r}"
                )
            entry_slots_seen.add(slot)
        elif kind == CAVE_OBSERVER:
            if not isinstance(aux, int) or aux < 0:
                raise AssertionError(
                    f"observer rows must have aux=<non-negative mode_index>; "
                    f"{label} has aux={aux!r}"
                )
            observer_slots_seen.add(slot)
        else:
            raise AssertionError(
                f"unknown cave_kind={kind!r} for {label}; "
                f"add it to _CAVE_BUILDERS"
            )
        if prologue_hex == "":
            tbd.append(f"  slot[{slot:>2}] @ 0x{off:08X}  {label}")
            continue
        if len(prologue_hex) != 8:
            raise AssertionError(
                f"prologue hex for {label} must be 8 chars, got {len(prologue_hex)}"
            )
        bytes.fromhex(prologue_hex)
    conflict = entry_slots_seen & observer_slots_seen
    if conflict:
        raise AssertionError(
            f"slot(s) used for both entry and observer caves: {sorted(conflict)}"
        )
    covered = entry_slots_seen | observer_slots_seen
    missing = set(range(KIOU_SLOT_COUNT)) - covered
    if missing:
        raise AssertionError(
            f"slots {sorted(missing)} in [0,{KIOU_SLOT_COUNT}) have no caves"
        )
    if tbd:
        raise NotImplementedError(
            "recipes/kiouforge.py: prologue bytes not captured yet:\n"
            + "\n".join(tbd)
        )


_validate_sites()


# ---------------------------------------------------------------------------
# Observer cave for IMatchMode.OnMatchEndAsync sites.
#
# Same shape as KiouKifExporter's recipe (proven on iOS 18 CSM): save
# caller-saved regs + args, MOVZ X2 with the mode index, BLR through the
# slot, restore everything, run the displaced prologue, branch to orig+4.
# This is a BEFORE-orig observer — the hook's return is dead (the cave
# rewrites x0/x1 with whatever orig produces a few insns later).
#
# Distinct from _build_entry_cave_payload above, which REPLACES the original
# (the hook's return is propagated to the caller). The observer cave is the
# right shape for "let me peek as it happens, but the game keeps running".
# ---------------------------------------------------------------------------

KIFU_CAVE_PAYLOAD_SIZE = 84  # 21 instructions, same envelope as entry caves


def _build_observer_cave_payload(
    orig_va: int, slot_va: int, displaced_insn: bytes, mode_index: int
):
    """Observer cave: peek before orig runs."""
    if len(displaced_insn) != 4:
        raise ValueError(f"displaced_insn must be 4 bytes; got {len(displaced_insn)}")
    if not (0 <= mode_index <= 0xFFFF):
        raise ValueError(f"mode_index out of MOVZ 16-bit range: {mode_index}")

    def build(cave_va):
        out = bytearray()
        cur = cave_va

        def emit(insn):
            nonlocal cur
            out.extend(insn)
            cur += 4

        # --- prologue: save LR, callee-saved scratch, and arg registers ---
        emit(stp_pre_x(29, 30, 31, -0x90))
        emit(stp_off_x(19, 20, 31, 0x10))
        emit(stp_off_x(21, 22, 31, 0x20))
        emit(stp_off_x(0, 1, 31, 0x30))
        emit(stp_off_x(2, 3, 31, 0x40))
        emit(stp_off_x(4, 5, 31, 0x50))
        emit(stp_off_x(6, 7, 31, 0x60))
        # MOV X29, SP via ADD X29, SP, #0.
        emit(add_x_imm(29, 31, 0))

        # --- materialize SLOT address; load published hook pointer ---
        emit(adrp(16, cur, slot_va))
        emit(ldr_x_imm(16, 16, slot_va & 0xFFF))

        # --- pass the mode index to the hook via X2 ---
        emit(movz_w_imm(2, mode_index))

        emit(blr_x(16))

        # --- restore ---
        emit(ldp_off_x(6, 7, 31, 0x60))
        emit(ldp_off_x(4, 5, 31, 0x50))
        emit(ldp_off_x(2, 3, 31, 0x40))
        emit(ldp_off_x(0, 1, 31, 0x30))
        emit(ldp_off_x(21, 22, 31, 0x20))
        emit(ldp_off_x(19, 20, 31, 0x10))
        emit(ldp_post_x(29, 30, 31, 0x90))

        # --- execute the displaced prologue insn verbatim ---
        emit(displaced_insn)

        # --- branch to (orig + 4) ---
        emit(b_imm(cur, orig_va + 4))

        if len(out) != KIFU_CAVE_PAYLOAD_SIZE:
            raise AssertionError(
                f"observer cave wrong size: got {len(out)}, expected {KIFU_CAVE_PAYLOAD_SIZE}"
            )
        return bytes(out)

    return build


PATCHES: list = []


# ---------------------------------------------------------------------------
# Cave kind → payload builder dispatch.
#
# Each builder is a callable with the signature:
#   (orig_va, slot_va, displaced_insn, slot_index, aux) -> build(cave_va) -> bytes
#
# To add a new cave kind:
#   1. Implement `_build_<kind>_cave_payload(orig_va, slot_va, displaced_insn,
#      slot_index, aux)` returning the inner `build(cave_va) -> bytes` closure.
#   2. Add `"<kind>": _build_<kind>_cave_payload,` here.
#   3. Add row(s) to `_SITES` with the new kind. `_validate_sites` accepts
#      any kind present in this dict; extend its validation rules if the new
#      kind has constraints (e.g. multiplicity, aux type).
#
# The existing builders take slightly different keyword sets (entry uses
# `slot_index`, observer uses `mode_index`); the dispatch wraps each so the
# call site here is uniform.
# ---------------------------------------------------------------------------

def _wrap_entry(orig_va, slot_va, displaced_insn, slot_index, aux):
    del aux  # entry caves don't use aux
    return _build_entry_cave_payload(
        orig_va=orig_va,
        slot_va=slot_va,
        displaced_insn=displaced_insn,
        slot_index=slot_index,
    )


def _wrap_observer(orig_va, slot_va, displaced_insn, slot_index, aux):
    del slot_index  # observer caves don't bake the slot index into MOVZ
    return _build_observer_cave_payload(
        orig_va=orig_va,
        slot_va=slot_va,
        displaced_insn=displaced_insn,
        mode_index=aux,
    )


_CAVE_BUILDERS: dict = {
    CAVE_ENTRY:    _wrap_entry,
    CAVE_OBSERVER: _wrap_observer,
}


def _payload_for_row(slot_index, site_off, prologue_hex, kind, aux):
    builder = _CAVE_BUILDERS.get(kind)
    if builder is None:
        raise AssertionError(
            f"no cave builder registered for kind={kind!r}; "
            f"add it to _CAVE_BUILDERS"
        )
    return builder(
        orig_va=site_off,
        slot_va=HOOK_SLOT_BASE_RVA + slot_index * 8,
        displaced_insn=bytes.fromhex(prologue_hex),
        slot_index=slot_index,
        aux=aux,
    )


def _label_for_row(slot_index, kind, aux, label):
    if kind == CAVE_OBSERVER:
        return f"slot[{slot_index:>2}] observer mode={aux} {label}"
    return f"slot[{slot_index:>2}] {label}"


CAVE_PATCHES: list = [
    (
        site_off,
        bytes.fromhex(prologue_hex),
        _payload_for_row(slot_index, site_off, prologue_hex, kind, aux),
        _label_for_row(slot_index, kind, aux, label),
    )
    for slot_index, site_off, prologue_hex, kind, aux, label in _SITES
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
