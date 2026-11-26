# Local-Run Handoff — Reference

## Return channels

What each channel does, and what was measured. Probes ran 2026-11-26 on a
macOS workstation signed in with a claude.ai subscription (no API-key, Bedrock
or Vertex variables set), Claude Code 2.1.33x.

| Channel | Data back | Wakes the requester | Status |
|---|---|---|---|
| `results/summary.txt` read through an attached device folder | Full | No; the user says "done" | Worked: the requesting cloud session read raw JSON results directly |
| PR comment from `report.sh` (`.notify.pr`) | Summary, raw on disk | Yes, when the session is subscribed to the PR | PR activity events wake a subscribed session; the comment path itself is a plain `gh pr comment` |
| Headless `claude -p` + `SendMessage` to a local session name | One-line summary + path | Yes | Local sessions are listed by `ListAgents` in `-p` mode; delivery not yet observed |
| Headless `claude -p` + `SendMessage` to a cloud session title | — | — | **Refused**: `No agent named '<title>' is reachable.` `ListAgents` listed only local sessions |
| Interactive `claude` (with and without `--remote-control`) listing cloud sessions | — | — | No cloud rows in either case; the Remote Control run may have listed before it connected |
| Clipboard (`pbcopy`, `wl-copy`, `xclip -selection clipboard`) | Summary | No | Works; overwrites whatever the user was copying, so opt-in only |
| Secret gist, scratch branch | Full | No (a branch with a watched PR does) | Not wired into `report.sh`; use by hand for large repros |
| Session inbound webhook (`watch_url`) | — | — | Not usable: only the artifact service can sign deliveries |

When a later client lists cloud sessions in `-p` mode, `--notify-session` can
target them too; nothing else in the bundle changes.

## Writing a good probe

- **One question per probe.** Two questions need two verdicts, so two probes.
- **A control arm that exercises the same mechanism.** For a permissions probe,
  the control runs the same command under an allow rule; for a plugin-load
  probe, the control loads a plugin known to work. A control that only proves
  the tool starts does not separate "unsupported" from "misconfigured".
- **Headless where possible.** `claude -p ... --output-format json` gives a
  machine-readable result, `permission_denials`, and cost. A check that needs a
  human (does a prompt appear?) ends with a yes/no the user types into the
  README, and the verdict says so.
- **Pin the cheap model for model calls inside a probe** (`--model haiku`) unless
  the behaviour under test depends on the model.
- **Raw output to `results/`, facts to `log`.** The summary is what travels;
  the raw files are what the requester quotes as evidence.

## Cross-machine use

`REQUIRES_OS` (`darwin`, `linux`, `any`) makes `run.sh` exit `3` with `SKIP`
on the wrong host, and the handoff line should name which machine to use. For
a probe that needs both, write `run.sh` to branch on `probe_os` and report the
OS in its verdict.

A bundle is self-contained: copy the probe directory plus the root `lib/` to
another machine, or push it to a branch. Repros that need a repository clone it
into `fixtures/` from a `REPO=` and `REF=` named in `run.sh`, never from a path
on one machine.

## Root migration

`new-probe.sh --update-lib` rewrites the root `justfile` and `lib/` from the
skill's templates and leaves probe directories alone. Older ad-hoc probes
without `.handoff.json` still show in `just list` once moved into
`<yyyymmdd>-<slug>/` directories; their `run.sh` keeps working unchanged.
