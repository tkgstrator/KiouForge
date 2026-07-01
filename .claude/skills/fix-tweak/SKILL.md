---
name: fix-tweak
description: |
  End-to-end Tweak crash repair pipeline for this project. Pulls crash
  reports + in-app logs from the JB device, fans them through
  crash-log-analyzer and cave-rva-verifier subagents, then (with user
  consent) invokes tweak-fixer to apply patches. Orchestration only;
  the heavy lifting lives in scripts and subagents.
allowed-tools: Bash, Read, AskUserQuestion, Agent, TaskCreate, TaskUpdate, Edit
---

# /fix-tweak — Tweak Crash Repair Pipeline

This skill is **orchestration only**. Every real task is delegated to a
dedicated asset:

| Stage | Owner | Kind |
| --- | --- | --- |
| 1. Log collection      | `.claude/scripts/pull_crash.sh` | deterministic shell script |
| 2. Crash analysis      | `crash-log-analyzer` | subagent |
| 3. CAVE/RVA verification | `cave-rva-verifier` | subagent |
| 4. Code repair         | `tweak-fixer` | subagent |

You (the orchestrator) MUST forward each stage's output to the next
stage **verbatim** — do not summarize, reformat, or drop fields.
Summarization happens once, in the final human-facing report.

---

## Step 0 — Initial intake

If `$ARGUMENTS` contains any text, treat it as a free-form note
(reproduction steps or fix intent) and pass it as `userContext.note`
to every downstream stage.

If `$ARGUMENTS` is empty, issue exactly ONE `AskUserQuestion`:

- `Run silently (recommended)` — proceed through pull_crash → analyze
  → verify automatically, ask for consent before applying any patch.
- `I want to add reproduction steps` — collect 1-2 lines via Other.

Do NOT ask for device IP, bundle ID, target files, or version.
`pull_crash.sh` resolves all of these deterministically from the
project's Tweak filter plist and environment.

---

## Stage 1 — Log collection

Run the script directly. Show its stdout to the user unchanged.

```bash
.claude/scripts/pull_crash.sh
```

From the trailing summary, capture the `output:` path (e.g.
`logs/crashes/com-neconome-shogi-20260626-184500`) and store it as
`crashDir` for the next stages. Use the absolute form
(`$(pwd)/logs/crashes/...`) when forwarding.

Failure handling:
- exit 1 (SSH unreachable) → tell the user the device is offline and
  stop. Do not attempt fallback.
- exit 2 (missing prerequisite, e.g. cannot resolve prefix or IP) →
  show the script's stderr verbatim and stop. The user resupplies
  `--ip` or `--prefix` and re-runs.
- `crashreporter/*.ips` count is zero → report "no crash reports
  found for this bundle prefix; was the crash actually triggered?"
  and stop.

---

## Stage 2 — Crash analysis

Spawn the `crash-log-analyzer` subagent via the `Agent` tool.

```json
{
  "subagent_type": "crash-log-analyzer",
  "description": "Analyze crash report and in-app logs",
  "prompt": "crashDir=<absolute-path>\nfocusReport=<filename-or-blank>\nuserContext=<note-from-step-0>"
}
```

Conventions for the `prompt`:
- Always use absolute paths. The subagent's working directory is the
  repo root.
- `focusReport` is blank unless the user named a specific `.ips`.
- `userContext` carries the Step 0 note (or `""` if none).

Save the returned JSON as `analysis`. From
`analysis.hypotheses[0].evidence`, extract any hook names of the form
`KIOU_HOOK_NAME_*` or `KFHook[A-Z]\w*` and collect them as the
`suspectHooks` list for Stage 3. If the leading hypothesis names no
hook explicitly, pass `suspectHooks=[]` (Stage 3 will sweep).

---

## Stage 3 — CAVE/RVA verification

Spawn the `cave-rva-verifier` subagent.

```json
{
  "subagent_type": "cave-rva-verifier",
  "description": "Verify CAVE/RVA wiring around the suspected hook(s)",
  "prompt": "repoRoot=<abs>\ntargetVersion=<from-Makefile-or-1.0.2>\nsuspectHooks=[<from-stage-2>]"
}
```

Resolve `targetVersion`:

```bash
grep -oE 'TARGET_VERSION\s*\?=\s*\S+' Makefile | awk -F'=' '{gsub(/ /,"",$2); print $2}'
```

Default to `1.0.2` if extraction fails.

Save the returned JSON as `verification`. Build the combined
`findings[]` list for Stage 4 by merging:

- Every entry of `verification.issues[]` with severity `error` or
  `warning`.
- Any actionable mechanism from `analysis.hypotheses[]` that names a
  specific file:line and is NOT already covered by a `verification`
  issue at the same location.

Each merged finding MUST have these fields:

```json
{
  "id": "FIX-<n>",
  "where": "<file>:<line>",
  "what": "<concrete edit to apply>",
  "rationale": "<why; cite analyzer or verifier evidence by JSON path>"
}
```

Number `id`s sequentially starting at `FIX-1`. Do NOT rewrite the
underlying `what` text — copy it from the source subagent so the
audit trail is preserved.

---

## Stage 4 — Patch application (requires user consent)

Show the merged `findings[]` to the user verbatim, then issue
`AskUserQuestion`:

- `Apply all` — forward every finding to `tweak-fixer`.
- `Pick which to apply` — follow-up `AskUserQuestion` (multiSelect)
  listing each finding by `id` + first 80 chars of `what`.
- `Don't apply` — leave the findings on screen and end the pipeline.

If the user opts in, spawn `tweak-fixer`:

```json
{
  "subagent_type": "tweak-fixer",
  "description": "Apply Tweak fixes",
  "prompt": "findings=<JSON array>\nbuildCheck=make CHINLAN=1 -j4"
}
```

`buildCheck` enables compile verification after edits. Do not omit it
unless the user explicitly requests skipping the build.

When `tweak-fixer` returns, present its result to the user:
- Per-finding `status` (applied / skipped) and `files`.
- `buildCheck.summary` (ok / errors).

Do NOT proceed to packaging, IPA assembly, git commit, push, or PR
creation. Hand control back to the user.

---

## Pipeline control

- Maintain four tasks via `TaskCreate` / `TaskUpdate`, one per stage.
  Set `in_progress` on stage entry, `completed` on success.
- If any stage fails (non-zero exit, subagent returns empty / error
  JSON), stop and report the partial state. Do not skip ahead.
- Never let one subagent's output be paraphrased before reaching the
  next subagent. Pass JSON through.

---

## Hard prohibitions

- Do NOT perform analysis, verification, or code edits yourself. They
  belong to the subagents. Your role is dispatch and aggregation.
- Do NOT ask the user for device IP, bundle ID, target files, or
  Tweak version. `pull_crash.sh` is deterministic; trust it.
- Do NOT invoke `tweak-fixer` without explicit user consent in
  Stage 4.
- Do NOT summarize subagent JSON in a way that drops fields. Pass it
  through; summarize once at the end for the human reader.
- Do NOT run `make ipa`, `make package`, `make jailed`, or any
  packaging target. `tweak-fixer` stops at `make CHINLAN=1` for
  compile verification.
- Do NOT fall back to the global `~/.claude/skills/fix-tweak/SKILL.md`
  generic flow. This project-local SKILL.md is authoritative inside
  this repository.

---

## Asset locations (reference)

- `.claude/scripts/pull_crash.sh` — log collection
- `.claude/agents/crash-log-analyzer.md` — crash analysis subagent
- `.claude/agents/cave-rva-verifier.md` — CAVE/RVA verifier subagent
- `.claude/agents/tweak-fixer.md` — code repair subagent

To change pipeline behavior, edit the asset directly rather than
patching this orchestrator.
