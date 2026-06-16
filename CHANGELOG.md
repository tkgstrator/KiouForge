# Changelog

All notable changes to KiouForge are documented here.

## [Unreleased]

## [0.1.0] — 2026-06-16

Initial release. / 初回リリース。

### Added / 追加

- **FPS Override** — extends the retail 30/60 preset to
  `{15, 24, 30, 45, 60, 90, 120}`. Stepper in settings. >60 fps requires
  a ProMotion device and the Patched IPA build (which adds
  `CADisableMinimumFrameDurationOnPhone` automatically).
  / 公式の 30/60 プリセットを `{15, 24, 30, 45, 60, 90, 120}` fps に拡張。
  60fps 超は ProMotion 対応デバイス＋Patched IPA ビルド（binpatch が
  `CADisableMinimumFrameDurationOnPhone` を自動付与）が必要。
- **AFK Guard** — suppresses the false AFK warning and auto-surrender that
  fire during long-think sessions.
  / 長考中に発生する「入力なし」警告と自動投了を抑制。
- **Analysis Tune** — raises the Depth, Hash, and Skill parameters used by
  the on-device Rshogi NNUE engine during post-game kifu analysis. Retail
  defaults (depth 15 / 16 MB / skill 20) are preserved on a fresh install;
  users raise them via the settings sheet. Analysis Depth hooks
  `NativeSyncSession.SearchFull` with a struct-return aware C signature so
  the arm64 `x8` sret pointer the caller set is preserved.
  / 対局後の棋譜解析で使われる Rshogi NNUE エンジンの探索深度・ハッシュ・
  強さを引き上げ可能に。公式デフォルト（深度 15 / 16 MB / 強さ 20）は
  初期値として維持。Analysis Depth は `NativeSyncSession.SearchFull` を
  struct-return 対応の C 署名でフックし、arm64 の `x8` sret ポインタを
  保持する実装。
- **Kifu Autosave** — writes a standard KIF 2.0 file to
  `Documents/KiouForge/` when any match ends. Filename includes timestamp,
  mode, player names (Unicode preserved), and starting position. Per-mode
  toggles (AI Match, CPU Stream, Local PvP, Online PvP, Record/Replay) in
  a sub-screen; all modes default to on.
  / 対局終了時に標準 KIF 2.0 形式で `Documents/KiouForge/` に自動保存。
  ファイル名にタイムスタンプ・モード・対局者名（日本語そのまま）・開始
  局面を含む。サブ画面でモード別（AI 対局／CPU 配信／ローカル対局／
  オンライン対局／棋譜再生）にオン/オフ可能。初期値はすべてオン。
- Right-edge swipe gesture to open the settings sheet.
  / 画面右端からのスワイプで設定シートを開けるように。
- Version label in the settings About footer.
  / 設定画面の About フッターにバージョン表示を追加。
- Three distribution flavors: JB rootless `.deb`, jailed Dobby-static
  `.dylib`, Patched IPA (iOS 18 CSM-safe binpatch).
  / 3つの配布形式：JB rootless `.deb`、jailed Dobby-static `.dylib`、
  Patched IPA（iOS 18 の CSM を回避する binpatch ビルド）。

### Release artifacts / リリース成果物

The GitHub Release attaches the `.deb` and both `.dylib` flavors, plus
a `SHA256SUMS` file. The Patched IPA is **not** distributed: it bundles
the decrypted KIOU `UnityFramework`, so operators must build their own
locally via `make ipa DECRYPTED_IPA=...`.

GitHub Release には `.deb`・両方の `.dylib`・`SHA256SUMS` を添付。
Patched IPA は復号済みの KIOU `UnityFramework` を含むため**配布しません**。
各自 `make ipa DECRYPTED_IPA=...` でローカルビルドしてください。
