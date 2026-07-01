# On-device smoke test via Frida

Automate the end-to-end verification we currently do by hand after every
`make deploy`: launch → login → start CPU match → resign → confirm no
crash + kifu file was written. Run as a scriptable `make smoke` target
against a paired JB device.

## Motivation

Every non-trivial change to KIOU-Hook / KiouForge risks breaking one of
three things:

- **Startup** — hook wiring, cave layout, chinlan dylib load order.
  Currently verified by tailing `kiouforge.log` for `[CHINLAN] all
  hooks installed` and checking `/var/mobile/Library/Logs/CrashReporter/`
  for a fresh `.ips`.
- **Core play loop** — resign path (observer cave → dispatcher →
  HookXxxEnd → kifu writer). Currently verified by manually starting a
  CPU game, playing a move or two, resigning, then SSH-ing to check
  the resulting kifu file.
- **Account flows** — login, account switch. Currently verified by
  UI navigation.

Manual verification is slow and easy to skip. We have already regressed
resign-time behaviour twice in this session because "it builds fine"
did not imply "it survives a match end". A scripted smoke check flips
that failure mode to CI-detectable.

We deliberately do *not* aim for coverage of every screen — this
document scopes a **single happy-path smoke test** whose goal is to
catch cave / hook / RVA breakage before it reaches the device in
practice. Broader flows can layer on the same harness later.

## Scope

### In scope

- A Frida script (`scripts/smoke/kiou_smoke.js`) that:
  1. Attaches to `com.neconome.shogi`.
  2. Confirms `[CHINLAN] all hooks installed` was logged since launch.
  3. Drives login → CPU match start → play N moves → resign via a mix
     of presenter-level il2cpp calls and uGUI `Button.onClick.Invoke`.
  4. Confirms the expected side effects (kifu file present under
     Documents/KiouForge, log lines matching the flow, no new
     CrashReporter entries).
- A `make smoke` target that packages `make deploy` + Frida spawn +
  pass/fail summary.
- A support module (`scripts/smoke/on_device.py`) that fetches log
  tails and `.ips` files over SSH and diffs them against pre-run
  baselines.

### Out of scope (deferred)

- Multi-mode coverage (AI / LocalPvP / OnlinePvP / RecordReplay).
  Only CPUStreamMode is included — the other modes reuse the same
  cave / dispatcher machinery so a single mode covers the regression
  surface. Adding more modes is a copy-paste extension.
- Login-with-real-account flows. The smoke uses the pre-provisioned
  KiouForge account already on the test device.
- Any UI screen not on the login → CPU戦 → resign path. Settings
  panel, kifu viewer (post-SQLite migration), account switcher tests
  are their own follow-ups.
- Real production-signing runs. The smoke assumes a JB device with a
  developer-provisioned KIOU install. Non-JB / TestFlight paths need
  a different harness (Corellium, XCUITest via re-signed IPA) that is
  out of scope for this repo.

## Prerequisites

- **JB device** paired to the dev host via SSH (`root@$THEOS_DEVICE_IP`),
  same setup `make deploy` already uses.
- **frida-server** running on device. Standard tweak — installable
  via a `.deb` in `/opt/procursus/bin/frida-server` for rootless.
  Bring-up: `ssh root@device 'frida-server --listen 0.0.0.0:27042 &'`.
  Not persistent across reboots by default; the `make smoke` target
  starts it if missing.
- **Frida CLI + node bindings on host** (`bun add frida-node
  frida-il2cpp-bridge`, or `pip install frida-tools` if we go Python).
  The design below is bun-based to match KiouForge's existing tool
  chain in `shared/tools/`.
- **`assets/1.0.2/dump.cs.index.json`** (already checked in) — Frida
  script reads class + method names from it so RVAs never appear
  literally in the script (they change per app version).

## Architecture

### Layer 1 — host runner (`scripts/smoke/run.sh`)

Bash entry point invoked by `make smoke`. Responsibilities:

1. Baseline snapshot: SSH to device, capture the current tail of
   `/var/mobile/Containers/Data/Application/<UUID>/Documents/Logs/kiouforge.log`
   and the list of `.ips` files with timestamps.
2. Ensure frida-server is up (start if not).
3. Spawn: `frida -U -f com.neconome.shogi -l kiou_smoke.js
   --runtime=v8 --no-pause -o smoke.out`.
4. Wait up to 90 s for the script to emit either `SMOKE PASS` or
   `SMOKE FAIL: <reason>` on stdout, or a timeout / crash.
5. Verify from the device side (via `on_device.py`):
   - No new `.ips` file appeared since baseline.
   - `kiouforge.log` gained a line matching `[KIF] wrote \d+ bytes ->`
     within the run window.
   - The named kifu file exists on-device with non-zero length.
6. Emit a single-line summary and exit 0 (pass) or non-zero (fail).

### Layer 2 — Frida script (`scripts/smoke/kiou_smoke.js`)

Uses `frida-il2cpp-bridge` for il2cpp method discovery + invocation.
Structured as a state machine to survive async hook waits without
blowing the timeout budget on any single step:

```
step 1: wait for  [CHINLAN] all hooks installed  (30s cap)
step 2: dispatch CPU戦 start via il2cpp presenter
step 3: wait for MatchController state == InProgress (10s cap)
step 4: submit N=3 moves (either presenter direct or move-input hook)
step 5: dispatch resign via il2cpp
step 6: wait for KIOUKifWriterEmit log line (10s cap)
step 7: verify kifu file appeared under Documents/KiouForge
step 8: exit PASS
```

Each `wait for` step is a polling loop with per-step timeout that
emits a `SMOKE FAIL: step N timeout` if it does not resolve.

Failure modes tracked explicitly:

- Frida attach failed → `SMOKE FAIL: attach`
- `[CHINLAN] all hooks installed` never appears → `SMOKE FAIL:
  hook install`
- Presenter call throws → `SMOKE FAIL: presenter <name> threw:
  <ex>`
- Timeout on any wait step → `SMOKE FAIL: step N timeout`
- Fresh `.ips` appeared → `SMOKE FAIL: crash <ips-name>`

Success is a single line `SMOKE PASS: mode=CPUStreamMode moves=3
kifu=<path>`.

### Layer 3 — device-side glue

Nothing new here — the smoke leans on existing infrastructure:

- Live log server on port 18082 (already implemented in Chinlan) — can
  optionally be tailed by the host as a live signal rather than
  polling the log file.
- `Documents/Logs/kiouforge.log` is where the tweak already writes
  its structured lines; the smoke matches specific ones.
- `Documents/KiouForge/*.kif` is the current storage location.
  Post-SQLite migration this becomes a DB row check instead — see
  the Follow-up section.

## Concrete step-by-step Frida flow

Rough sketch. Actual class / method names verified against dump.cs
during implementation:

```javascript
import Il2Cpp from 'frida-il2cpp-bridge'

async function smoke() {
  await Il2Cpp.initialize()

  // step 1 — hook install banner
  await waitForLogLine('[CHINLAN] all hooks installed', 30_000)

  // step 2 — presenter-level CPU match start
  const HomePresenter = Il2Cpp.domain.assembly('KIOU').image
    .class('Project.Home.HomeUtilityPresenter')
  const presenter = HomePresenter.static.field('s_instance').value
  if (presenter.isNull()) throw new Error('home presenter not spawned')
  presenter.method('StartCpuMatch').invoke(/* difficulty */ 1)

  // step 3 — wait for MatchController.State == InProgress
  const MatchCtrl = Il2Cpp.domain.assembly('KIOU').image
    .class('Project.Match.MatchController')
  await waitFor(() => {
    const ctrl = MatchCtrl.static.field('s_instance').value
    if (ctrl.isNull()) return false
    return ctrl.field('_state').value === /* InProgress */ 2
  }, 10_000)

  // step 4 — play 3 moves via GameController.SubmitMove
  //   (uses same il2cpp method the UI would end up calling)
  for (const usi of ['2g2f', '8c8d', '2f2e']) {
    submitMove(usi)
    await sleep(500)  // let animations settle so onboarding overlays don't gate
  }

  // step 5 — resign via UI button (belt-and-braces path)
  const resignBtn = findButtonByLabel('投了')
  if (resignBtn === null) throw new Error('resign button not found')
  resignBtn.method('get_onClick').invoke().method('Invoke').invoke()

  // step 6 — wait for kifu writer log
  const kifPath = await waitForLogMatch(/\[KIF\] wrote \d+ bytes -> (.+\.kif)/, 10_000)

  send({ status: 'pass', kifu: kifPath })
}
```

`findButtonByLabel` walks the Canvas hierarchy: `Canvas.transform
.GetComponentsInChildren<Button>()` → for each, find the child `Text`
or `TMP_Text` and compare its content.

## `make smoke` target

```make
.PHONY: smoke
smoke: deploy
	@echo "==> starting on-device smoke ($(THEOS_DEVICE_IP))"
	@./scripts/smoke/run.sh \
	  --device       "$(THEOS_DEVICE_IP)" \
	  --user         "$(DEVICE_USER)" \
	  --bundle-id    "$(INSTALLED_IPA_BUNDLE_ID)" \
	  --frida-script "scripts/smoke/kiou_smoke.js" \
	  --log-path     "Documents/Logs/kiouforge.log" \
	  --timeout      90
```

Depends on `deploy` so the smoke always runs against the current
patched IPA. Fails loudly (exit code 1) on any assertion break so it
can gate `git push` / a CI pipeline.

## Verification checklist (host side)

The host runner asserts every one of these after Frida exits:

1. **Frida output**: single `SMOKE PASS: ...` line, no `SMOKE FAIL`.
2. **No new crash**: `find /var/mobile/Library/Logs/CrashReporter/
   -name 'KIOU-*.ips' -newer <baseline>` returns empty.
3. **Log evidence**: `grep '\[KIF\] wrote' kiouforge.log` gained ≥ 1
   line since baseline.
4. **Kifu artifact**: `stat` on the reported kifu path returns
   `size > 0` and `mtime > baseline`.
5. **Log clean-up**: `grep 'FATAL' kiouforge.log` returns nothing.

Any one failing → `FAIL` with the specific reason logged.

## Directory layout

```
scripts/
└── smoke/
    ├── run.sh              # host entrypoint
    ├── on_device.py        # ssh helpers for log / .ips diff
    ├── kiou_smoke.js       # Frida script
    └── package.json        # bun deps (frida-il2cpp-bridge, frida-node)
```

## Estimated effort

- **Frida script**: 200-300 lines JS. Discovering the exact presenter
  method names (StartCpuMatch, SubmitMove, ResignAsync) via dump.cs
  is the biggest unknown — count on 1-2 hours of exploration.
- **run.sh + on_device.py**: 100-150 lines total.
- **First green run**: half a day if the presenter API is close to
  what dump.cs advertises; ~1 day if move submission needs
  reimplementing (some moves route through async input handlers that
  are not directly callable).
- **CI hookup**: adding a self-hosted runner with a paired device is
  its own project; not tackled here.

## Risks

- **Frida attach flakes on JB device.** `frida-server` sometimes
  needs a re-launch after reboot. Runner handles the "not running"
  case explicitly; user-visible failures still map to "SSH says
  frida-server crashed" rather than false test failures.
- **Presenter signatures change per app version.** The script pins
  to 1.0.2 today; when 1.0.3 lands, presenter method names or
  signatures may drift. Mitigation: keep the mapping (presenter,
  method, args) in a small YAML config file, loaded per
  `TARGET_VERSION`.
- **UI onboarding overlays block button taps.** First launch shows a
  tutorial overlay; the smoke should either dismiss it via il2cpp
  presenter or run on an already-onboarded device (default in dev).
  Add a step 0 that checks + dismisses if present.
- **Timing sensitivity.** Match end fires async — the log line +
  kifu write may lag the resign call by ~100-500 ms. Keep the wait
  budget at 10 s per async step, don't tighten prematurely.
- **False negatives from JB-side races.** trollstorehelper install +
  app launch can race; add a 3 s post-deploy grace before Frida
  attach to avoid attaching before the app's constructor even ran.

## Follow-ups

- **Post-SQLite migration**: step 7 (kifu file check) turns into
  `sqlite3 kifu.sqlite 'SELECT id FROM games ORDER BY id DESC LIMIT
  1'` returning a row whose `played_at` is newer than baseline. Same
  guarantee, different transport.
- **Multi-mode coverage**: replicate the flow for AI / Local /
  Replay modes once the CPU path is stable. Each mode adds ~30
  lines of Frida glue.
- **Live signal via port 18082**: the current design polls the log
  file over SSH. If start-up latency becomes an issue, switch to
  streaming `nc device 18082` and matching lines as they arrive —
  the tweak already speaks that protocol.

## Open questions

- Do we also want a **negative test** — deploy an intentionally
  broken build and confirm the smoke correctly reports `FAIL`? That
  would give us confidence the pass path isn't just returning early.
  Suggests keeping a tiny "regression fixture" branch that reverts
  one hook and running smoke against it periodically.
- How much presenter reflection to bake into the script vs. a
  reusable Frida library? Once we have 2-3 smokes, factor out a
  `scripts/smoke/lib/il2cpp_helpers.js`. Not blocking for MVP.
- Is `frida-il2cpp-bridge` the right dependency, or do we prefer the
  raw Frida `Il2Cpp` API? The bridge is more ergonomic but adds a
  layer to keep updated with Frida versions. Preference: bridge for
  now, revisit if it ever blocks a Frida upgrade.
