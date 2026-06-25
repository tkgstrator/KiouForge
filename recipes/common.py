"""Version-independent recipe constants and cave payload builders for KiouForge.

Shared by all per-version modules (v1_0_1.py, v1_0_2.py, …).
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

# ---------------------------------------------------------------------------
# Target identification
# ---------------------------------------------------------------------------

TARGET_BASENAME = "UnityFramework"
DYLIB_PATH = "@executable_path/Frameworks/KiouForge.dylib"

# ---------------------------------------------------------------------------
# Info.plist additions
# ---------------------------------------------------------------------------

PLIST_KEYS: dict = {
    "CADisableMinimumFrameDurationOnPhone": True,
    "UIFileSharingEnabled": True,
    "LSSupportsOpeningDocumentsInPlace": True,
}

# ---------------------------------------------------------------------------
# Cave kinds
# ---------------------------------------------------------------------------

CAVE_OBSERVER = "observer"
CAVE_ENTRY    = "entry"

CAVE_PAYLOAD_SIZE = 84   # 21 arm64 instructions

_NOP = b"\x1f\x20\x03\xd5"

# ---------------------------------------------------------------------------
# Hook ID enum — mirrors ``enum kiou_kf_hook_id`` in Internal.h.
# Every CAVE_* row in v_<ver>.py SITES carries one of these names.
# ---------------------------------------------------------------------------

HOOK_IDS: dict[str, int] = {
    # CAVE_ENTRY hooks first (caves route through their own entry slots)
    "KIOU_KF_HOOK_SET_TARGET_FRAMERATE":      0,
    "KIOU_KF_HOOK_NSS_SETHASHSIZE":           1,
    "KIOU_KF_HOOK_NSS_SETSKILLEVEL":          2,
    "KIOU_KF_HOOK_NSS_SEARCHFULL":            3,
    "KIOU_KF_HOOK_ACCOUNT_EXISTS":            4,
    "KIOU_KF_HOOK_LOGIN_ARGS_CREATE":         5,
    "KIOU_KF_HOOK_REGISTER_USER_ARGS_CREATE": 6,
    "KIOU_KF_HOOK_RUN_LOGIN_SEQ_MOVENEXT":    7,
    "KIOU_KF_HOOK_GET_SELF_PROFILE_MOVENEXT": 8,
    "KIOU_KF_HOOK_HTTPMSGINVOKER_SEND_ASYNC": 9,
    # CAVE_OBSERVER hooks (kifu autosave, one per IMatchMode)
    "KIOU_KF_HOOK_KIFU_AI_END":        10,
    "KIOU_KF_HOOK_KIFU_CPUSTREAM_END": 11,
    "KIOU_KF_HOOK_KIFU_LOCAL_END":     12,
    "KIOU_KF_HOOK_KIFU_ONLINE_END":    13,
    "KIOU_KF_HOOK_KIFU_REPLAY_END":    14,
}

# Entry slot indices — one per CAVE_ENTRY row, must mirror Internal.h.
ENTRY_SLOT_INDEX: dict[str, int] = {
    "KIOU_KF_HOOK_SET_TARGET_FRAMERATE":      0,
    "KIOU_KF_HOOK_NSS_SETHASHSIZE":           1,
    "KIOU_KF_HOOK_NSS_SETSKILLEVEL":          2,
    "KIOU_KF_HOOK_NSS_SEARCHFULL":            3,
    "KIOU_KF_HOOK_ACCOUNT_EXISTS":            4,
    "KIOU_KF_HOOK_LOGIN_ARGS_CREATE":         5,
    "KIOU_KF_HOOK_REGISTER_USER_ARGS_CREATE": 6,
    "KIOU_KF_HOOK_RUN_LOGIN_SEQ_MOVENEXT":    7,
    "KIOU_KF_HOOK_GET_SELF_PROFILE_MOVENEXT": 8,
    "KIOU_KF_HOOK_HTTPMSGINVOKER_SEND_ASYNC": 9,
}

ENTRY_SLOT_COUNT    = 10
ENTRY_SLOT_CAPACITY = 16   # reserved sibling room for future entry hooks

# ---------------------------------------------------------------------------
# Cave payload builders
# ---------------------------------------------------------------------------

def build_observer_cave(orig_va, slot_va, displaced_insn, hook_id):
    """Return a ``build(cave_va) -> bytes`` closure for an observer cave.

    W6 carries the hook_id so the single shared observer slot's dispatcher
    can switch on it and route to the right Hook_*.m body.
    """
    if len(displaced_insn) != 4:
        raise ValueError(f"displaced_insn must be 4 bytes; got {len(displaced_insn)}")
    if not (0 <= hook_id <= 0xFFFF):
        raise ValueError(f"hook_id out of MOVZ range: {hook_id}")

    def build(cave_va):
        out = bytearray()
        cur = cave_va

        def emit(insn):
            nonlocal cur
            out.extend(insn)
            cur += 4

        emit(stp_pre_x(29, 30, 31, -0x90))
        emit(stp_off_x(19, 20, 31, 0x10))
        emit(stp_off_x(21, 22, 31, 0x20))
        emit(stp_off_x(0, 1, 31, 0x30))
        emit(stp_off_x(2, 3, 31, 0x40))
        emit(stp_off_x(4, 5, 31, 0x50))
        emit(stp_off_x(6, 7, 31, 0x60))
        emit(add_x_imm(29, 31, 0))
        emit(adrp(16, cur, slot_va))
        emit(ldr_x_imm(16, 16, slot_va & 0xFFF))
        emit(movz_w_imm(6, hook_id))
        emit(blr_x(16))
        emit(ldp_off_x(6, 7, 31, 0x60))
        emit(ldp_off_x(4, 5, 31, 0x50))
        emit(ldp_off_x(2, 3, 31, 0x40))
        emit(ldp_off_x(0, 1, 31, 0x30))
        emit(ldp_off_x(21, 22, 31, 0x20))
        emit(ldp_off_x(19, 20, 31, 0x10))
        emit(ldp_post_x(29, 30, 31, 0x90))
        emit(displaced_insn)
        emit(b_imm(cur, orig_va + 4))

        assert len(out) == CAVE_PAYLOAD_SIZE
        return bytes(out)

    return build


_ENTRY_HEAD_INSNS = 7
_ENTRY_TAIL_BYTES = 8
_ENTRY_PAD_INSNS  = (CAVE_PAYLOAD_SIZE - _ENTRY_HEAD_INSNS * 4 - _ENTRY_TAIL_BYTES) // 4


def build_entry_cave(orig_va, slot_va, displaced_insn, slot_index):
    """Return a ``build(cave_va) -> bytes`` closure for an entry cave.

    Each entry cave has its own slot at ENTRY_SLOT_BASE_RVA + slot_index*8;
    cave just BLRs that slot's function pointer and RETs to the caller.
    """
    if len(displaced_insn) != 4:
        raise ValueError(f"displaced_insn must be 4 bytes; got {len(displaced_insn)}")
    if not (0 <= slot_index <= 0xFFFF):
        raise ValueError(f"slot_index out of MOVZ range: {slot_index}")

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
        for _ in range(_ENTRY_PAD_INSNS):
            emit(_NOP)
        emit(displaced_insn)
        emit(b_imm(cur, orig_va + 4))

        assert len(out) == CAVE_PAYLOAD_SIZE
        return bytes(out)

    return build


def payload_for_site(site, prologue_bytes, hook_id_name, kind,
                     hook_slot_rva, entry_slot_base_rva):
    """Return the appropriate cave builder closure for a site row."""
    if kind == CAVE_OBSERVER:
        return build_observer_cave(
            site, hook_slot_rva, prologue_bytes, HOOK_IDS[hook_id_name]
        )
    if kind == CAVE_ENTRY:
        idx = ENTRY_SLOT_INDEX[hook_id_name]
        return build_entry_cave(
            site, entry_slot_base_rva + idx * 8, prologue_bytes, idx
        )
    raise AssertionError(f"unknown cave kind {kind!r}")


# ---------------------------------------------------------------------------
# build_exports — assemble the public patch surface from per-version data.
# ---------------------------------------------------------------------------

def build_exports(sites, afk_site, afk_orig_8, hook_slot_rva, entry_slot_base_rva):
    """Build PATCHES, CAVE_PATCHES, and _SITES from per-version data."""
    from tools.encode import mov_w0_imm_ret

    patches = [
        (
            afk_site,
            bytes.fromhex(afk_orig_8),
            mov_w0_imm_ret(0),
            "IsAfkEnabled: return false (MOVZ W0,#0; RET)",
        ),
    ]

    cave_patches = [
        (
            site,
            bytes.fromhex(prologue_hex),
            payload_for_site(
                site, bytes.fromhex(prologue_hex), hook_id_name, kind,
                hook_slot_rva, entry_slot_base_rva,
            ),
            f"{label}: route to KiouForge {kind} cave ({hook_id_name})",
        )
        for site, prologue_hex, hook_id_name, kind, label in sites
    ]

    sites_index = [
        (HOOK_IDS[hook_id_name], site_rva, prologue_hex, label)
        for site_rva, prologue_hex, hook_id_name, kind, label in sites
    ]

    return patches, cave_patches, sites_index
