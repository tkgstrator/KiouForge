# Kifu SQLite storage + in-app viewer

Move .kif output away from loose files under `Documents/KiouForge/` to a
single SQLite database plus an in-app viewer sheet reachable from the
existing right-edge-swipe settings surface.

## Motivation

Current shape (`Sources/KiouForge/Kif/Writer.m::KIOUKifWriterEmit`):

- On resign / match end, generate a KIF text via `KIOUKifTextFromGameController`
  and write it as UTF-8 to `Documents/KiouForge/<timestamp>_<mode>_<b>vs<w>_<startpos>.kif`.
- Filenames encode metadata so the Files app view is somewhat browsable,
  but the naming scheme is long, non-searchable, and locale-fragile
  (Japanese names inside filenames survive APFS but confuse some
  external viewers).

Pain points:

- No in-app browsing. Users must open Files, dig into the tweak's
  Documents directory, and pick a file with a long name.
- No filtering by date / mode / opponent.
- No delete UI — pruning old kifu is a manual Files.app job.
- No share / export UI — moving a kifu to another shogi viewer app
  needs Files.app copy dance.
- Filename length keeps growing as we add match metadata.

Target shape:

- Store the KIF blob plus metadata in `Documents/KiouForge/kifu.sqlite`.
- Add a "棋譜一覧" entry to the settings sheet that opens a list view
  backed by the database.
- Detail view shows the KIF text with a share sheet handoff (so
  PiyoShogi / Shogi Browser Q can still consume it).

## Scope

### In scope

- SQLite schema + `KifuStorage` wrapper that owns opening, migrations,
  insert-on-match-end, list, fetch-by-id, delete.
- `KifuListSheet` view controller (UITableView) + `KifuDetailSheet`
  (UITextView + share button).
- One entry in the existing settings sheet routing into
  `KifuListSheet`.
- Replace the file write in `KIOUKifWriterEmit` with a
  `KifuStorage` insert.
- Migration: on first launch after upgrade, scan the existing
  `Documents/KiouForge/*.kif`, insert each into the DB, delete the
  source file. Guard with a "migrated" flag so it only runs once.

### Out of scope (deferred)

- Cloud sync / iCloud kifu library.
- Multi-user separation (one DB per KIOU account).
- Search over move sequences.
- Editing the KIF blob in-app.

## Design

### Storage layer — `Sources/KiouForge/Storage/KifuStorage.{h,m}`

Uses the iOS-provided `sqlite3` C API — link with `-lsqlite3`
(add to Makefile `TWEAK_NAME_LDFLAGS`). No FMDB / GRDB / external
dependency; keeps the tweak self-contained.

Public API:

```objc
// Open/close (singleton, opens on first use, closes at dylib unload).
sqlite3 *KifuStorageDatabase(void);

// Insert a game record. Returns 0 on success, sqlite errcode otherwise.
// Caller keeps ownership of NSStrings; the wrapper copies as needed.
int KifuStorageInsert(NSString *modeName,
                      NSString *blackName,
                      NSString *whiteName,
                      NSString *startposSeg,
                      NSString *kifText,
                      NSDate   *playedAt);

// Enumerate all games most-recent-first. Rows are lightweight
// dictionaries: id, played_at (NSDate), mode, black, white, startpos.
// KIF text is intentionally excluded — fetched lazily by detail view.
NSArray<NSDictionary *> *KifuStorageList(NSUInteger limit, NSUInteger offset);

// Fetch a single row including the KIF blob for the detail view.
NSDictionary *KifuStorageFetch(int64_t rowId);

// Delete a row.
BOOL KifuStorageDelete(int64_t rowId);
```

Schema (SQL run at `KifuStorageDatabase` open time):

```sql
CREATE TABLE IF NOT EXISTS games (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    played_at   TEXT    NOT NULL,   -- ISO 8601 UTC
    mode        TEXT    NOT NULL,
    black       TEXT    NOT NULL,
    white       TEXT    NOT NULL,
    startpos    TEXT    NOT NULL,   -- "startpos" | "sfen-<hex>" | "unknown"
    kif_text    TEXT    NOT NULL,
    created_at  TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE INDEX IF NOT EXISTS games_played_at_idx ON games(played_at DESC);
```

`kif_text` stays UTF-8 (the file version already is). No blob column —
text keeps the schema greppable via `sqlite3` CLI for debugging.

Migration table for future schema bumps:

```sql
CREATE TABLE IF NOT EXISTS meta (
    key   TEXT PRIMARY KEY,
    value TEXT
);
```

Initial insert: `meta('schema_version', '1')`. Migrations bump this and
apply ALTER statements in sequence.

Threading: everything runs on the caller's thread. Match-end fires on
the game's async continuation — the actual sqlite write completes in
microseconds so no queue needed. Detail view's fetch happens on the
main thread; already inside a UITableView cell tap handler which is
fine.

### File → DB migration — one-shot at first launch

`KifuStorageMigrateLegacyFiles()` called from `installUnityHooks` once
per session, guarded by `meta('legacy_files_migrated', '1')`:

- Enumerate `Documents/KiouForge/*.kif` via `NSFileManager`.
- For each: parse filename `<ts>_<mode>_<b>vs<w>_<startpos>.kif` into
  fields; read text via `stringWithContentsOfFile:`; call
  `KifuStorageInsert`; delete source with `removeItemAtPath:`.
- Set the flag even on partial failure so a broken file doesn't keep
  triggering migration attempts.

If the filename doesn't parse cleanly, insert with best-effort
placeholders (`mode="unknown"` etc.) and log the discrepancy — losing
metadata is better than losing the kifu.

### List sheet — `Sources/KiouForge/UI/KifuListSheet.{h,m}`

```objc
@interface KifuListSheet : UIViewController <UITableViewDataSource, UITableViewDelegate>
+ (void)presentFromViewController:(UIViewController *)parent;
@end
```

- `UITableView` with plain-style cells:
  - Left: `played_at` formatted as `2026/07/02 01:56` (ja_JP locale).
  - Center: `mode` short label ("CPU" / "AI" / "対局" / "リプレイ").
  - Right: `<black> vs <white>` truncated to 24 chars.
  - Startpos badge (small chip) when non-standard.
- Swipe-to-delete calls `KifuStorageDelete` and reloads.
- Row tap pushes `KifuDetailSheet` with the row id.
- Empty state: friendly centered label + hint about resigning a match.
- Modal presentation via `UISheetPresentationController` with
  `.medium()` and `.large()` detents so users can peek then expand.

### Detail sheet — `Sources/KiouForge/UI/KifuDetailSheet.{h,m}`

```objc
@interface KifuDetailSheet : UIViewController
+ (instancetype)detailForRowId:(int64_t)rowId;
@end
```

- `UITextView` (read-only, monospaced) showing the KIF blob.
- Nav bar right item: `UIActivityViewController` share sheet with the
  KIF text — hands off to any registered UTI-aware app.
- Nav bar left item: close.
- Long-press on text → copy-all shortcut.

Filename for external share stays `<ts>_<mode>_<b>vs<w>.kif` (built
from row fields) so downstream apps see the familiar name even though
the local storage is DB-backed.

### Settings entry — `Sources/KiouForge/Hook/SettingsUI.m`

Add a row above the existing feature toggles:

```
┌─ 棋譜 ─────────────────────────
│  棋譜一覧 ......................  ›
└────────────────────────────────
```

Tapping presents `KifuListSheet` as a sheet on top of the settings
modal. Nothing else in the settings surface changes.

### Writer integration — `Sources/KiouForge/Kif/Writer.m`

`KIOUKifWriterEmit` collapses to roughly:

```objc
NSString *KIOUKifWriterEmit(void *gameCtrl, void *matchConfig,
                            void *stateStore, const char *matchModeTag) {
    NSString *kif = KIOUKifTextFromGameController(gameCtrl, matchConfig,
                                                  stateStore, matchModeTag);
    if (kif.length == 0) return nil;

    NSString *modeName = matchModeTag ? @(matchModeTag) : @"unknown";
    NSString *opponents = KIOUKifDescribeOpponents(matchConfig, stateStore);
    NSString *startpos = KIOUKifDescribeStartpos(gameCtrl);
    NSArray  *sides = [opponents componentsSeparatedByString:@"vs"];
    NSString *black = sides.count > 0 ? sides[0] : @"unknown";
    NSString *white = sides.count > 1 ? sides[1] : @"unknown";

    KifuStorageInsert(modeName, black, white, startpos, kif, [NSDate date]);
    return nil;  // caller only used the return value for a log line
}
```

Existing log lines stay for parity; the "wrote 204 bytes -> path"
message becomes "inserted rowId=X len=Y bytes".

## File tree diff

```
Sources/KiouForge/
├── Storage/
│   ├── KifuStorage.h        (new)
│   └── KifuStorage.m        (new)
├── UI/
│   ├── KifuListSheet.h      (new)
│   ├── KifuListSheet.m      (new)
│   ├── KifuDetailSheet.h    (new)
│   └── KifuDetailSheet.m    (new)
├── Kif/
│   └── Writer.m             (modified: file write → KifuStorageInsert)
├── Hook/
│   └── SettingsUI.m         (modified: add 棋譜一覧 row)
├── Internal.h               (modified: forward-decls for the new modules)
└── Tweak.m                  (modified: KifuStorageMigrateLegacyFiles call)

Makefile                     (modified: -lsqlite3 + new .m files)
```

## Estimate

- ~300-400 lines total across the new/modified files.
- Objective-C UIKit boilerplate is the bulk (KifuListSheet + KifuDetailSheet).
- SQLite wrapper is thin — the sqlite3 C API is verbose but the actual
  logic per call is 10-15 lines.
- No new external dependency.
- 1-2 focused sessions once implementation starts.

## Risks

- **SQLite corruption on abnormal exit.** Wrap inserts in
  `BEGIN IMMEDIATE / COMMIT` and set `PRAGMA journal_mode=WAL` so a
  mid-write crash leaves the DB consistent.
- **Migration losing files.** Only delete source `.kif` after the
  insert commits successfully. Set the migration flag *inside* the
  same transaction as the last insert so a partial run is retryable.
- **UIKit view controller lifetime on top of a modal Settings.**
  Present via the current top-most view controller
  (`UIApplication.keyWindow.rootViewController.presentedViewController`),
  not the settings VC directly, so dismissing the outer sheet doesn't
  yank the list sheet mid-interaction.
- **KIF text getting very large on long replays.** SQLite handles
  megabyte TEXT columns fine; UITextView is the bottleneck. Cap the
  detail view's `text` length at 100 KB and offer a "share full file"
  button if truncated. Not expected to hit in normal play (average
  kifu is ~200 bytes).

## Open questions

- Retention policy? Keep everything forever, or auto-purge past N
  entries? Default: forever, add a manual "全削除" button in settings.
- Should the migration also copy `.kif` files to a backup subfolder
  before deleting, for one release? Safer, but adds complexity. Vote:
  no — the DB is the new source of truth, and files are trivially
  recoverable via share sheet.
- Sheet presentation icon: `SF Symbols` `list.bullet.rectangle` vs
  `doc.text`. Not blocking.
