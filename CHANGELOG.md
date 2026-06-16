# Changelog

All notable changes to KiouForge are documented here.

## [Unreleased]

## [0.1.0] — 2026-06-16

Initial release.

### Added

- **FPS Override** — extends the retail 30/60 preset to `{15, 24, 30, 45, 60, 90, 120}`. >60 fps requires a ProMotion device + Patched IPA build.
- **AFK Guard** — suppresses the false AFK warning and auto-surrender during long-think sessions.
- **Analysis Tune** — raises Depth / Hash / Skill on the on-device Rshogi NNUE engine for post-game kifu analysis. Retail defaults preserved on fresh install.
- **Kifu Autosave** — writes a standard KIF 2.0 file to `Documents/KiouForge/` on match end. Per-mode toggles (AI / CPU Stream / Local PvP / Online PvP / Record/Replay).
- Right-edge swipe gesture to open the settings sheet.
- Version label in the settings About footer.

### Artifacts

- `.deb` (JB rootless), `-jailed.dylib` (TrollStore), `-binpatch.dylib` (Patched IPA build), and `SHA256SUMS`.
- Patched IPA itself is **not** distributed — build locally via `make ipa DECRYPTED_IPA=...`.
