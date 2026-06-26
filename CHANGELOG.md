# Changelog

All notable changes to KiouForge are documented here.

## [Unreleased]

## [0.2.1] — 2026-06-26

### Changed

- Extracted the shared KIOU binary catalog (RVAs, hook-id enum, cave geometry) and the account/gRPC hook implementations into a new private submodule `IPA-Patch/KIOU-Hook`, mounted at `vendor/KIOU-Hook/`. KiouForge cherry-picks the `.m` files it compiles in via the Makefile and uses the new name-based hook API (`KIOUHookOrig` / `KIOUHookInstall` / `KIOUHookSiteAddr`) so shared hook bodies never reference RVAs or slot enums directly. Behavior unchanged.
- Renamed the `Sources/KiouForge` subdirectories to PascalCase for consistency with the rest of the project layout.
- Dropped the `KF` prefix from the KIOU-Hook catalog identifiers in favour of the `KIOU_HOOK_` namespace; bumped the `vendor/KIOU-Hook` submodule to `99f86a9`.
- Bumped the Chinlan and Kanade submodules to their latest `master`.

## [0.2.0] — 2026-06-25

### Added

- **Account Switching** — KIOU has no official account switcher; this captures every login automatically and lets you swap saved accounts from the settings sheet without resetting the app. The **New Register** mode bypasses KIOU's Reset button to create a fresh account.
- **KIOU 1.0.2 support** — `TARGET_VERSION` env var selects `v1_0_1` / `v1_0_2` (default 1.0.2). All 15 hook RVAs re-verified against the 1.0.2 Mach-O.

### Changed

- Restructured recipes into a version-aware layout: shared cave builders and slot indices in `recipes/common.py`, per-version RVAs in `recipes/v1_0_*.py`.
- Bumped the chinlan hook slot count from 6 to 11 to accommodate the five account-switching hooks.
- README / README.ja gained a feature × version compatibility matrix; supported targets are now 1.0.1–1.0.2.

### Compatibility

- KIOU 1.0.1 and 1.0.2. Account Switching requires 1.0.2.

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

- `.deb` (JB rootless), `-jailed.dylib` (TrollStore), `-chinlan.dylib` (Patched IPA build), and `SHA256SUMS`.
- Patched IPA itself is **not** distributed — build locally via `make ipa DECRYPTED_IPA=...`.
