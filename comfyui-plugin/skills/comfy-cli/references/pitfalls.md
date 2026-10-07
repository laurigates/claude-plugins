# comfy CLI — Pitfalls

Failure modes of the `comfy` CLI on a systemd-managed install, each with its symptom and fix. Entry point: [`../SKILL.md`](../SKILL.md) § Pitfalls.

## Pitfalls

- **`comfy run` rejects UI workflow JSON.** It needs the API-format export.
  The error is unhelpful — usually a JSON parse failure or
  `KeyError: 'class_type'`. If a workflow is imported from
  `user/default/workflows/`, those are *UI* exports — re-export through the
  web UI as API format first.
- **`--port 8188` is required for `comfy run` here.** The CLI defaults to
  hitting the port the *CLI* would launch on, not the systemd unit's port.
  Without `--port`, the run hangs until `--timeout`.
- **`comfy node install <repo-url>` is registry-only.** It takes a registry
  name (matched against ComfyUI-Manager's `custom-node-list.json`), not a
  GitHub URL. To install from a URL, `git clone` into `custom_nodes/` and
  `comfy node fix <dirname>` to install its requirements.
- **`comfy node install <node-id>` 404s with `Node 'X@unknown' not found` for
  recently-published nodes.** The default channel checks the bundled
  ComfyUI-Manager `custom-node-list.json`, which is rebuilt on a separate
  cadence from the comfy registry itself. New publishes — and any version
  still in `NodeVersionStatusPending` while the auto security scan runs —
  aren't there yet. Workaround: `comfy node registry-install <node-id>`
  (hidden subcommand) downloads the published `node.zip` straight from
  `cdn.comfy.org` via the registry API at
  `api.comfy.org/nodes/<id>/versions` — same artifact, bypasses the
  curated list. Use this for first-party installs of your own packs right
  after `comfy node publish`.
- **`NodeVersionStatusPending` transitions to `Active` automatically.**
  Every published version is held as `Pending` until the (private)
  automated security scan finishes — no publisher action required, just
  wait (observed ≤ a few hours). Check status with
  `curl -s 'https://api.comfy.org/nodes/<id>/versions' | jq '.[] | {version,status}'`.
  Until it transitions, `comfy node install` won't see it but
  `comfy node registry-install` will.
- **`NodeVersionStatusFlagged` does NOT auto-clear** (distinct from
  Pending). The scan flagged the version; it stays non-installable and
  `comfy node install` falls back to the older Active version. The public
  API exposes no reason — it's only on `registry.comfy.org`. Republishing
  re-runs the scan; flags can be false positives (an identical change
  flagged some laurigates packs but not their siblings). Full
  publishing/status playbook: `.claude/rules/comfy-registry-publishing.md`.
- **A green `comfy node publish` can still ship a broken tarball.** For
  TS-built packs the registry `node.zip` shipped an empty `web/dist/`
  (dead frontend) for weeks despite passing runs — root cause was
  `publish-node-action@v1` lacking `skip_checkout`. Always verify by
  downloading the `node.zip` from the version's `downloadUrl` and checking
  for `web/dist/index.js`. See `comfy-registry-publishing.md`.
- **Restart is not automatic.** `comfy node install/update/uninstall` modifies
  `custom_nodes/` but does not signal the running server. New nodes don't
  load until the service restarts. The CLI prints a "restart required"
  notice; honor it via `! sudo systemctl restart comfyui.service` (the agent
  can't `sudo` — ask the user).
- **`comfy model download` ignores this install's family-subfolder
  convention.** Project `CLAUDE.md` requires placement under
  `models/<category>/<family>/...`. The CLI takes a `--relative-path` but
  no awareness of family layout, so prefer the
  `hf download → /tmp/staging → mv` recipe in project `CLAUDE.md` for any
  model that has a family folder. `comfy model download` is acceptable for
  one-off files at category root (e.g. a `.pth` upscaler going to
  `models/upscale_models/`).
- **`comfy model remove`** physically deletes files. If a workflow still
  references the model, it crashes on next run. Prefer `mv` to a backup dir
  for anything you might want back.
- **Updating comfy-cli.** When the CLI prints a "New version available"
  notice on each invocation, upgrade via `uv tool upgrade comfy-cli`
  (per global tool-installation priority — uv tool replaced the prior
  pipx install here). Verify with `comfy --version`. Don't
  `pip install --upgrade` against the system Python or the ComfyUI
  `.venv/` — the binary is a uv-tool symlink to its own isolated venv
  at `~/.local/share/uv/tools/comfy-cli/`, so pip-into-other-interpreters
  is a no-op for the `comfy` command. If a stray `comfy-cli` is still
  installed inside the ComfyUI `.venv/` from a previous era, uninstall
  it (`.venv/bin/python -m pip uninstall -y comfy-cli`) — the in-venv
  copy is unused now that uv tool owns the symlinks.
- **`comfy node update`'s post-install pip uses the WRONG venv.** The
  ComfyUI-Manager subprocess that handles `requirements.txt` for newly-
  updated nodes is invoked with `comfy-cli`'s `sys.executable`
  (`~/.local/pipx/venvs/comfy-cli/bin/python`), not the install's `.venv/`.
  Symptom: post-update logs show `EXECUTE => ['~/.local/pipx/
  venvs/comfy-cli/bin/python', '-m', 'uv', 'pip', 'install', ...]`, and
  the new packages don't appear in `.venv/bin/python -m pip list`. Fix:
  loop over `custom_nodes/*/requirements.txt` and reinstall against the
  correct interpreter (see "Safe mass node update" recipe). The same bug
  affects `comfy node fix` and `comfy node install` for the same reason.
- **transformers 5.x breaks the diffusers/peft chain.** ComfyUI core's
  `requirements.txt` is `transformers>=4.50.3` with no upper bound, so
  any pip re-resolve may pull `transformers==5.x`. transformers 5.0
  removed `HybridCache` and `FLAX_WEIGHTS_NAME`; `peft<0.18` and most
  installed `diffusers` releases (≤0.35.x as of 2026-05) import those
  symbols at the top level, so half the diffusion-using custom nodes
  (`brushnet`, `hunyuanvideowrapper`, `fluxtrainer`, `HiDream-Sampler`,
  `FramePackWrapper`, `nunchaku`, …) fail with
  `ImportError: cannot import name 'HybridCache' from 'transformers'`.
  Fix: `pip install 'transformers>=4.50.3,<5'` (and optionally
  `pip install --upgrade peft` to 0.19+ for forward compatibility).
  Re-pin after every core upgrade until either (a) ComfyUI core adds
  `transformers<5` upper-bound, or (b) installed diffusers/peft releases
  support transformers 5.x.
- **ComfyUI-Manager-installed packs are tarball snapshots, not git
  clones.** The Manager pulls registry zip/tarballs and unpacks into
  `custom_nodes/<name>/`, with no `.git` directory. So `git pull` /
  `git log` won't work, and the version is pinned to whatever the
  registry served at install time — often weeks behind upstream master.
  Before patching a pack's source, check upstream: a closed issue with a
  recent release tag may already contain the fix. Quick recipes:

    ```sh
    # See current upstream of one file without cloning
    gh api repos/<owner>/<repo>/contents/<path> --jq '.content' | base64 -d

    # Install/upgrade pack from upstream master, replacing the snapshot
    rm -rf custom_nodes/<dir-name>
    git -C custom_nodes clone https://github.com/<owner>/<RepoName>
    ./.venv/bin/python -m pip install -r custom_nodes/<RepoName>/requirements.txt
    ```

  After a fresh clone, the dir name is the GitHub repo's CamelCase form
  (e.g. `ComfyUI-Thumbnails`), not Manager's lowercase form. That can
  matter — see the next pitfall.
- **Custom-node JS hardcodes the GitHub CamelCase dir name in relative
  imports.** ComfyUI serves a pack's `web/` at
  `/extensions/<dir-name>/...`, where `<dir-name>` is the on-disk
  directory. Many packs' JS does `import "../../<RepoName>/js/foo.js"`
  with the GitHub CamelCase name — fine for a fresh `git clone`, broken
  when ComfyUI-Manager normalized the dir to lowercase. Symptom: console
  errors on relative imports / `[vite:preloadError]` / 404s on the
  pack's own JS in the network tab. Fix: rename the dir to match the JS
  imports (`mv custom_nodes/<lower> custom_nodes/<RepoName>`), then
  restart the service. (Do not also fix the JS — upstream churns it.)
- **Reading the right service boot in `journalctl`.** `journalctl -u
  comfyui.service -b` is *system* boot, not service restart — every
  ComfyUI run since the last reboot is in there. Filter to the current
  service run by `MainPID`:

    ```sh
    PID=$(systemctl show comfyui.service -p MainPID --value)
    journalctl _PID=$PID --no-pager
    ```

  Or `--since "$(systemctl show comfyui.service -p ActiveEnterTimestamp
  --value | cut -d' ' -f2-)"` if filtering by date. The `-b` form will
  silently match the *first* "Import times for custom nodes:" block,
  which is whichever ComfyUI run came first after the last reboot — a
  trap when comparing pre/post update.
