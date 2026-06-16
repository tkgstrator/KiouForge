<h1 align="center">KiouForge</h1>

<p align="center">
  <em>Local quality-of-life tuning for <strong>KIOU</strong>.<br/>
  Adjust frame-rate, suppress false AFK warnings, and strengthen the<br/>
  on-device post-game kifu analysis engine — all client-side, zero server impact.</em>
</p>

<p align="center">
  <img alt="version" src="https://img.shields.io/badge/version-v0.1.0-2f80ed?style=flat-square" />
  <img alt="targets KIOU" src="https://img.shields.io/badge/targets-KIOU%201.0.1%20(11)-ff66a3?style=flat-square" />
  <img alt="platform" src="https://img.shields.io/badge/platform-iOS%2015.0%E2%80%9326-blue?style=flat-square" />
  <img alt="arch" src="https://img.shields.io/badge/arch-arm64%20rootless-555?style=flat-square" />
  <img alt="runs" src="https://img.shields.io/badge/runs-client--side%20only-1f9d55?style=flat-square" />
  <img alt="scope" src="https://img.shields.io/badge/scope-authorized%20testing%20only-c69214?style=flat-square" />
</p>

---

KiouForge is a local quality-of-life tweak for **KIOU** targeting **authorized
penetration testing only**. It adjusts runtime behavior the retail client
exposes no user controls for — frame-rate presets, AFK warning suppression,
and the search parameters used by the **on-device post-game kifu analysis
engine** — without modifying any game data or server state.

### Client-side only

Every change KiouForge makes happens inside the app on your device. It never:

- crafts, replays, proxies, or intercepts any network request,
- modifies currency, paid items, or any server-stored entity,
- affects live match play (hint arrows, move suggestions, game rules),
- changes the result or fairness of any match.

Toggling every switch off and relaunching the app returns it to a fully
vanilla state.

## Features

| Toggle | What it does |
|---|---|
| **FPS Override** | Extends the retail 30/60 preset list to `{15, 24, 30, 45, 60, 90, 120}` fps. `>60` requires a ProMotion device; see [Performance](#performance) notes. |
| **AFK Guard** | Suppresses the "no input detected" warning and the automatic surrender that follows. The retail timer fires after ~60 s of no input. Useful during long-think or analysis sessions. |
| **Analysis Tune** | Raises the depth, hash, and skill parameters the on-device Rshogi NNUE engine uses **for post-game kifu analysis only**. Has no effect during live matches. |

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
2. The patched IPA build (the binpatch pipeline adds
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

`SearchFull` returns a `SyncSearchResult` struct (arm64 uses an `x8` sret
register the caller sets before BL). The depth hook declares its C return
type as the matching struct so the compiler routes the orig() result back
through that same sret pointer correctly — no asm shim needed.

## Settings UI

Right-edge swipe → settings sheet with four sections:
- **Features** — one toggle per row in the [Features](#features) table.
- **Performance** — FPS stepper.
- **Engine** — Analysis Depth / Analysis Hash / Analysis Skill steppers.
- **About** — repo link, author X handle, build commit.

All values persist between launches.

## Non-goals

KiouForge explicitly does **not**:

- unlock in-match hint arrows, best-move overlays, or any live-play assist,
- bypass the premium kifu analysis subscription gate,
- equip characters or skins the account does not own,
- unlock voice lines, cosmetic items, or decoration supplies,
- unlock AI Special Support or any combat advantage,
- modify server-stored account data of any kind,
- send any request or replay to the KIOU backend.

If you need any of the above for authorized testing, see the sibling
tweak **KiouEditor**.

## Compatibility

| | |
|---|---|
| **KIOU app version** | `1.0.1` (`CFBundleVersion` 11) |
| **iOS** | 15.0 – 26, arm64. Jailbroken `.deb`, TrollStore-injected jailed `.dylib`, or Patched IPA (works on TrollStore / Sideloadly / AltStore). |

All hook sites are RVA-pinned to this exact KIOU build. After a KIOU update
the RVAs will drift. See [`docs/porting.md`](docs/porting.md).

## Build

### Jailbroken device (rootless)

```sh
make package
make package install THEOS_DEVICE_IP=<device-ip>
```

### Jailed dylib (TrollStore)

```sh
make jailed
# -> packages/jailed/KiouForge.dylib
```

Stage inside the decrypted KIOU `.app/Frameworks/`, add an `LC_LOAD_DYLIB`,
and install via TrollStore.

### Patched IPA (TrollStore / Sideloadly / AltStore)

```sh
mkdir -p assets
cp ~/Downloads/Kiou-1.0.1.ipa assets/
make ipa
# -> packages/ipa/KiouForge-binpatch.ipa
```

Before building after editing hook sites or after a KIOU update:

```sh
PYTHONPATH=shared:. python3 -m tools.verify_sites \
  --recipe recipes.kiouforge \
  --index  assets/dump.cs.index.json \
  --ipa    assets/Kiou-1.0.1.ipa
```

## Documentation

- [`docs/porting.md`](docs/porting.md) — re-deriving RVAs after a KIOU update.
- [`docs/binpatch.md`](docs/binpatch.md) — Patched IPA pipeline notes.
- [`docs/analysis_depth.md`](docs/analysis_depth.md) — planned depth-tuning
  implementation (sret-aware hook or alternate interception point).
