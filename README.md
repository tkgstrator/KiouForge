<h1 align="center">KiouForge</h1>

<p align="center">
  <img src="icon.webp" alt="KiouForge icon" width="180" />
</p>

<p align="center">
  <em>Local quality-of-life tuning for <strong>KIOU</strong>.<br/>
  Adjust frame-rate, suppress false AFK warnings, autosave kifu files,<br/>
  and strengthen the on-device post-game kifu analysis engine — all client-side, zero server impact.</em>
</p>

<p align="center">
  <img alt="version" src="https://img.shields.io/badge/version-v0.2.0-2f80ed?style=flat-square" />
  <img alt="targets KIOU" src="https://img.shields.io/badge/targets-KIOU%201.0.1%E2%80%931.0.2-ff66a3?style=flat-square" />
  <img alt="platform" src="https://img.shields.io/badge/platform-iOS%2013.0%2B-blue?style=flat-square" />
  <img alt="arch" src="https://img.shields.io/badge/arch-arm64%20rootless-555?style=flat-square" />
  <img alt="runs" src="https://img.shields.io/badge/runs-client--side%20only-1f9d55?style=flat-square" />
  <img alt="scope" src="https://img.shields.io/badge/scope-post--game%20analysis%20%26%20QoL-1f9d55?style=flat-square" />
</p>

[日本語版はこちら](README.ja.md)

---

**KIOU (棋桜)** is an online shogi game by 株式会社ネコノメ, available on the
[App Store](https://apps.apple.com/jp/app/%E6%A3%8B%E6%A1%9C/id6755948307).

KiouForge is a local quality-of-life extension for **KIOU** that unlocks
settings the retail client doesn't expose — frame-rate presets, AFK warning
suppression, post-game kifu analysis tuning, and kifu autosave. Every change
runs on-device and never touches the server or affects live match play.

<p align="center">
  <img src="docs/screenshots/kiou-title.webp" alt="KIOU title screen" width="200" />
  <img src="docs/screenshots/kiou-home.webp" alt="KIOU home screen" width="200" />
  <img src="docs/screenshots/settings-main.webp" alt="KiouForge settings sheet" width="200" />
  <img src="docs/screenshots/settings-kifu-autosave.webp" alt="Kifu Autosave per-mode sub-screen" width="200" />
</p>

## Features

| Toggle | What it does |
|---|---|
| **FPS Override** | Extends the retail 30/60 preset list to `{15, 24, 30, 45, 60, 90, 120}` fps. `>60` requires a ProMotion device; see [Performance](#performance) notes. |
| **AFK Guard** | Suppresses the "no input detected" warning and the automatic surrender that follows. The retail timer fires after ~60 s of no input. Useful during long-think or analysis sessions. |
| **Analysis Tune** | Raises the depth, hash, and skill parameters the on-device Rshogi NNUE engine uses **for post-game kifu analysis only**. Has no effect during live matches. |
| **Kifu Autosave** | Automatically exports a `.kif` file to `Documents/KiouForge/` when any match ends. Filename includes timestamp, mode, player names (Unicode — Japanese names preserved as-is), and starting position. Per-mode toggles (AI, CPU Stream, Local PvP, Online PvP, Record/Replay) are available in the sub-screen; all modes default to on. |
| **Account Switching** | Save and switch between multiple KIOU accounts without resetting the app. Accounts are captured automatically on login. Tap **Account → Active** in the settings sheet to view the list, tap a row to switch (app navigates to the title screen automatically). **New Register** creates a fresh account without going through KIOU's Reset button. |

## Performance

The frame-rate stepper cycles through `{15, 24, 30, 45, 60, 90, 120}`.
Default is **60** (retail value) so a fresh install changes nothing.

| Preset | Use-case |
|---|---|
| 15 / 24 | Aggressive battery saver |
| 30 | Low-power, retail-low |
| 45 | Balanced |
| 60 | Retail default |
| 90 / 120 | ProMotion devices only (iPhone 13 Pro+ / iPad Pro M1+) |

Achieving >60 fps requires:
1. A ProMotion device.
2. The patched IPA build (the Chinlan pipeline adds
   `CADisableMinimumFrameDurationOnPhone = true` to Info.plist automatically).

## Engine

The post-game analysis button (on the kifu detail screen) runs the
on-device **Rshogi NNUE engine** (`NativeSyncSession`) locally. KIOU ships
with conservative defaults:

| Parameter | Retail default | Range |
|---|---|---|
| `Analysis Depth` | 15 | 1 – 36 |
| `Analysis Hash` | 16 MB | 16 / 64 / 128 / 256 / 512 / 1024 MB |
| `Analysis Skill` | 20 (max) | 1 – 20 |

Higher depth and hash give a stronger analysis at the cost of longer run
time (depth scales roughly exponentially in branching factor). Skill level
20 is already the maximum; lower values intentionally weaken the engine.

These parameters apply **only to the post-game review screen**. During a live
match the engine runs with its built-in defaults — Analysis Tune has no
effect on in-match AI support or move suggestions.

## Kifu Autosave

When a match ends, KiouForge writes a standard KIF 2.0 file to
`Documents/KiouForge/` in the app's sandbox (visible in the Files app and
Filza).

**Filename format:**

```
{timestamp}_{mode}_{black}vs{white}_{startpos}.kif
```

| Segment | Example | Notes |
|---|---|---|
| `timestamp` | `20260614T234500` | UTC, ISO 8601 basic format |
| `mode` | `OnlinePvPMode` | See mode names in the Features table |
| `black` / `white` | `田中太郎vs佐藤花子` | Player names as-is; only `/` and control characters are stripped |
| `startpos` | `startpos` | `startpos` for the standard initial position, `sfen-<8 hex>` for handicap games, `unknown` if unresolvable |

**File contents:**

Standard KIF 2.0 (UTF-8, no BOM) compatible with PiyoShogi, Shogi Browser Q,
KifuCloud, and other Japanese kifu viewers. Includes player names, start
date/time, time control, and ending reason where available.

## Settings UI

Right-edge swipe → settings sheet with four sections:
- **Features** — one toggle per row in the [Features](#features) table.
  Tapping the **Kifu Autosave** row drills into a sub-screen with
  per-mode toggles (AI Match, CPU Stream, Local PvP, Online PvP,
  Record/Replay). The master toggle and the per-mode toggle must both be
  on for autosave to fire in that mode.
- **Performance** — FPS stepper.
- **Engine** — Analysis Depth / Analysis Hash / Analysis Skill steppers.
- **About** — repo link, author X handle, build commit.

All values persist between launches.

## Account Switching

KIOU itself has **no official account linking** — once you uninstall the app
or wipe the device, the deviceId is gone and your account is unrecoverable.
KiouForge fills that gap by recording every account that passes through
`LoginAsync` and persisting the identifiers to `NSUserDefaults`. The saved
list survives app updates, and since you can export it, your accounts
survive **device transfers** too.

**How it works:**

1. On first launch after install, the currently-logged-in account is captured
   from `UserSaveDataExtensions.AccountExists`.
2. On every successful login, `RunLoginSequenceAsync.MoveNext` records the
   `LoginReply` (deviceId, userName, userId from `JWT.sub`).
3. From the settings sheet → **Account → Active** you can see all saved
   accounts and tap one to switch. KiouForge arms a `pending_device_id`
   substitution; the next `LoginArgs.Create` call silently swaps the
   `deviceId` argument so the server returns the chosen account's session.
4. **New Register** arms a fresh UUID and routes the next launch into the
   name-entry flow — creating a new account without touching KIOU's own
   Reset button (which can trigger server-side rebinding of the existing
   account's UUID).

`distinctId` (TDAnalytics keychain UUID) is intentionally **not** touched
during a switch — overriding it causes a `-40004` auth failure.

### Export / import

The accounts screen has a **share button** (top right) that writes
`kf_accounts.json` to a temp file and opens the system share sheet. The
JSON is plain — each entry has `uuid`, `userName`, `openId`, `userId`,
`distinctId`, `savedAt`, and an optional `ranks` array.

Use cases:

- **Backup** — save the JSON to Files / iCloud / your Mac before reinstalling.
- **Device transfer** — export from the old device, then on the new device
  drop the JSON into `Library/Preferences/<bundle>.plist` (under the
  `kiou_forge.account.accounts` key) and your saved accounts move with you.
- **Recovery** — even if KIOU itself loses the deviceId, the UUID stored in
  your exported JSON can be replayed via the **Active** account list to log
  back into the original account.

This is the closest thing to "account linking" KIOU has — and it's entirely
client-side.

## Compatibility

KIOU is an online game — it updates frequently and old versions stop working
server-side. The recommended target is always the **latest supported version**.

### Feature × version matrix

| Feature | 1.0.1 (build 11) | 1.0.2 (build 12) |
|---|:---:|:---:|
| FPS Override | ✓ | ✓ |
| AFK Guard | ✓ | ✓ |
| Analysis Tune | ✓ | ✓ |
| Kifu Autosave | ✓ | ✓ |
| **Account Switching** | — | ✓ |

Account Switching requires hook sites introduced in 1.0.2; the Jailed/JB build
always targets the **latest** version only (RVAs are pinned at compile time).
The Patched IPA build selects the recipe at build time via `TARGET_VERSION`.

### Platform

| | |
|---|---|
| **Latest supported KIOU** | `1.0.2` (CFBundleVersion 12) |
| **KIOU minimum iOS** | 10.0 (`MinimumOSVersion` in app bundle) |
| **KiouForge minimum iOS** | 13.0 (requires `UIWindowScene`) |
| **Tested on** | iOS 15.0 – 26, arm64 |
| **Distribution** | Jailbroken `.deb`, TrollStore jailed `.dylib`, Patched IPA (Sideloadly / AltStore) |

## Build

### Jailbroken device (rootless)

`make package install` transfers and installs the `.deb` over SSH.
Requires OpenSSH on both sides — `openssh-server` on the device (install
via Sileo/Zebra) and `ssh` on the host.

```sh
make package
make package install THEOS_DEVICE_IP=<device-ip>
```

### Jailed dylib (TrollStore)

TrollStore is only supported on specific iOS versions. Check the
[supported versions table](https://ios.cfw.guide/installing-trollstore/)
before proceeding.

```sh
make jailed
# -> packages/jailed/KiouForge.dylib
```

Stage inside the decrypted KIOU `.app/Frameworks/`, add an `LC_LOAD_DYLIB`,
and install via TrollStore.

### Patched IPA (Sideload)

For devices where TrollStore is unavailable. Install the patched IPA with
[Sideloadly](https://sideloadly.io/) or [AltStore](https://altstore.io/).

Requires a **decrypted** KIOU IPA (e.g. obtained via [palera1n](https://palera.in/) +
Filza, or [TrollDecrypt](https://github.com/donato-fiore/TrollDecrypt)). The
App Store download is FairPlay-encrypted and cannot be patched directly.

```sh
# default (1.0.2)
mkdir -p assets/1.0.2
cp ~/Downloads/Kiou-1.0.2.ipa assets/1.0.2/
make ipa
# -> packages/ipa/KiouForge-patched.ipa

# target a specific version
make ipa TARGET_VERSION=1.0.1
```

Before building after editing hook sites or after a KIOU update:

```sh
# verify current recipe against a specific version's dump + IPA
PYTHONPATH=shared:. TARGET_VERSION=1.0.2 python3 -m tools.verify_sites \
  --recipe recipes \
  --index  assets/1.0.2/dump.cs.index.json \
  --ipa    assets/1.0.2/Kiou-1.0.2.ipa
```

