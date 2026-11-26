---
name: local-run-handoff
description: Hand a probe, test or repro to the user's own machine as a one-command bundle and read the verdict back. Use when a check needs the user's workstation, OS, account or hardware.
allowed-tools: Read, Write, Edit, Glob, Bash(bash ${CLAUDE_SKILL_DIR}/scripts/new-probe.sh *), TodoWrite
created: 2026-11-26
modified: 2026-11-26
reviewed: 2026-11-26
---

# Local-Run Handoff

Some checks cannot run where the agent runs: they need the user's workstation,
a signed-in account, a marketplace install, macOS, real hardware, or a human
looking at a prompt. This skill turns such a check into a self-contained bundle
the user runs with one command, whose verdict comes back without copy-paste.
The same bundle format carries bug repros.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|---|---|
| The check needs the user's machine, OS, account or hardware | The agent can run it itself; run it |
| A repro must be confirmed on a real install, or shared with another machine or upstream | Choosing a probe's identifiers and control → `probe-input-integrity` |
| The work should run unattended on the user's machine with no human step | A Remote Control session the harness offers fits better |

## Bundle contract

```
$LOCAL_PROBES_DIR/             # unset: claude-probes/ in the home directory
  justfile                     # run <slug> [--clip] [--no-notify], list, latest, archive [days]
  lib/report.sh                # sourced by every run.sh: header, verdict, outbound channels
  lib/probes.sh                # run/list/archive logic behind the justfile
  <yyyymmdd>-<slug>/
    run.sh  README.md  .handoff.json  fixtures/  results/
```

`run.sh` prints `=== PROBE ===` (name, ref, host, OS), `=== RESULTS ===`, then
`=== VERDICT ===` with exactly one `STATUS=<CODE> <meaning>. Next: <step>.`
The same lines go to `results/summary.txt`. Exit codes: `0` decided, `1`
`ERROR` (missing tool), `2` `INCONCLUSIVE` (control failed or nothing decided),
`3` `SKIP` (wrong OS for `REQUIRES_OS`).

## Execution

Execute this handoff:

### Step 1: Confirm the check must run locally

State in one line why the agent cannot run it here. If it can, run it instead.

### Step 2: Scaffold the bundle

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/new-probe.sh --slug <slug> --question "<the one question>" --ref <owner/repo#N> --os <any|darwin|linux>
```

Add `--repro` for a bug repro (codes `REPRODUCED` / `NOT_REPRODUCED`), or
`--codes 'CODE=meaning;CODE=meaning'` for custom verdicts. Pass `--root` when
`LOCAL_PROBES_DIR` is unset and the user has a preferred folder; ask once and
offer to save the answer as a rule in their own config.

Where the bundle is written depends on where the agent runs:

| Agent runs | Write the bundle |
|---|---|
| On the user's machine | Straight into the probe root |
| In the cloud, with the user's probe folder attached | Scaffold with `--root` pointing at the attached folder, or scaffold locally and copy the directory through the folder tools |
| In the cloud, no folder access | Push the bundle to a scratch branch and hand over a `git fetch` + run line |

### Step 3: Write the probe logic

Fill the control arm and the test arm in `run.sh`. The control is a case whose
outcome is known; without it a negative result cannot be told from a broken
setup (`agent-patterns-plugin:probe-input-integrity`). Write raw output to
`results/`, emit short facts with `log`, and finish every path with `verdict`.
Fill the README verdict table's "Next step" column. Run `bash -n run.sh`.

### Step 4: Pick the return channel

Record it in `.handoff.json` (`--notify-pr`, `--notify-session`) so `run.sh`
fires it after the verdict. Outbound channels run only after a secret scan of
`results/` (gitleaks, else a token-shape regex); a hit skips them with a WARN.

| Requesting session | Channel | Wakes the session |
|---|---|---|
| Cloud session with the probe folder attached | Read `results/summary.txt` through the folder after the user says "done" | No |
| Any session watching a PR | `--notify-pr owner/repo#N`: the summary is posted as a PR comment | Yes, through PR activity |
| Local session on the same machine | `--notify-session <name>`: a headless `claude -p` sends `SendMessage` to that listed name | Yes (unverified) |
| User wants it pasted | `just run <slug> --clip` copies `summary.txt` only | No; overwrites the clipboard |

A headless `claude -p` lists only local sessions, so `--notify-session` cannot
reach a cloud session (probed 2026-11; [REFERENCE.md](REFERENCE.md) § Return
channels).

### Step 5: Hand over one line

Give the user exactly the `RUN=` line the scaffolder printed, plus what the
codes mean in one sentence. Do not ask them to paste output when a channel
returns it.

### Step 6: Collect and act

On the wake, or when the user says "done", read `results/summary.txt` and the
raw files it points to. Quote the evidence where the decision is recorded (the
issue or PR), then act on the verdict. Treat `INCONCLUSIVE` as a setup defect to
fix, never as a result.

If the harness offers a one-shot scheduled wake-up, schedule one check about
30 minutes out that reads `summary.txt` through the folder, and stop there if
it is still missing.

## Housekeeping

`just list` shows each probe's status, age and ref. `just archive` moves
decided probes older than 14 days into `archive/`; pending, `INCONCLUSIVE` and
`ERROR` probes stay. Sharing a repro upstream: run the README and `run.sh`
through `documentation-plugin:public-export-sanitization` and
`agent-patterns-plugin:cold-read-gate` first.

For the channel evidence and the cross-machine notes, see
[REFERENCE.md](REFERENCE.md).
