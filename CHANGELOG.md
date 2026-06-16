# Changelog

All notable changes to KiouForge are documented here.

## [Unreleased]

### Added
- **Analysis Depth** — slider for the search depth used by the post-game
  kifu analysis engine (retail default 15, range 1–36). Implemented by
  hooking `NativeSyncSession.SearchFull` with a struct-return aware C
  signature so the arm64 `x8` sret pointer the caller set is preserved.

## [0.1.0] — Initial release

### Added
- **FPS Override** — extends the retail 30/60 preset to
  `{15, 24, 30, 45, 60, 90, 120}`. Slider in settings. >60 fps requires
  a ProMotion device and the Patched IPA build (which adds
  `CADisableMinimumFrameDurationOnPhone` automatically).
- **AFK Guard** — suppresses the false AFK warning and auto-surrender that
  fire during long-think sessions.
- **Analysis Tune** — raises the Hash and Skill parameters used by the
  on-device Rshogi NNUE engine during post-game kifu analysis. Retail
  defaults (16 MB / skill 20) are preserved on a fresh install; users raise
  them via the settings sheet.
- Right-edge swipe gesture to open the settings sheet.
- Title-screen version stamp (`+ (commit)`).
- Three distribution flavors: JB rootless `.deb`, jailed Dobby-static
  `.dylib`, Patched IPA (iOS 18 CSM-safe binpatch).
