# comfy-registry-lifecycle — The Registry Security Scan

What makes a published version `Flagged`, how to read the scan reasons from the public API, the known issue classes, how to shrink the scanned surface, and how to appeal. Entry point: [`../SKILL.md`](../SKILL.md).

## The security scan: what flags, what the reasons mean, how to shrink the surface

Learned across an 11-pack flag epidemic (2026-06/07; appeal:
Comfy-Org/registry-backend#180, third-party confirmations in
Comfy-Org/ComfyUI-Manager#2927):

- **Any finding flags the version — severity is irrelevant.** A single
  `info`-severity yara match (e.g. `os.environ.get(...)` or a
  `requests.get` in an API client) produces `Flagged`, which blocks
  distribution. There is no self-service resolution path.
- **Reasons are on the public API — behind an undocumented param.**
  `GET api.comfy.org/nodes/<id>/versions?include_status_reason=true`
  returns per-version `status_reason` JSON (issue_type, scanner,
  file_path, line, description, admin_tags); without the param the field
  is scrubbed. Scanner *notifications* post to the Comfy Org Discord
  `SUPPORT/#security-review-council` channel; the
  `registry.comfy.org/admin/nodeversions` links in them are **staff-only
  (403)** and the publisher dashboard shows nothing. Poll the API — no
  Discord access needed (the scaffold's `registry-health.yml` does this
  and writes the findings into its tracking issue).
- **Known issue classes** (from `status_reason` payloads):
  - `python_network_operations` (`yara_scan`) — any
    `urllib`/`requests`/socket use in shipped `.py`, including dev
    scripts that should never have shipped. Siblings:
    `python_environment_manipulation` (`os.environ`),
    `python_command_injection_risk` (`subprocess`).
  - `vendored_unknown` (`provenance_scan`) — "Vendored file detected
    but upstream origin could not be identified". Fires on **any
    bundler-built `web/dist` file**, including bundles of the repo's
    own `src/` with no third-party code at all (comfyui-touch-shim
    evidence, 2026-07) — not just inlined `node_modules` deps. Every
    TS-built pack hits this class on every publish until Comfy-Org can
    attribute bundler output; only the appeal path clears it.
- **Shrink the scan surface mechanically:**
  - `.comfyignore` must exclude every dev-only path — and it silently
    rots: a `scripts/` directory added *after* the ignore file was
    written shipped a `urllib` dev tool and flagged the version. Pair
    the ignore file with a `tests/test_publish_hygiene.py` that
    simulates the comfy-cli tarball (git-tracked − `.comfyignore` +
    `[tool.comfy] includes`, via `pathspec`) and fails on unclassified
    shipped paths or scanner-tripwire patterns in shipped Python. The
    scaffold now emits both.
  - **Publish bundled first-party deps with real provenance**: the
    shared kit must carry a `LICENSE` file and a `license` field in
    `package.json` (an unlicensed npm package is unclassifiable — that
    was true of comfy-modal-kit until comfy-modal-kit#17) plus npm
    provenance attestation. Open the built bundle with a `bun build
    --banner` comment attributing what is inlined.
  - Runtime code whose *function* is scanner-hostile (a manager pack
    doing registry lookups, installs, env feature-gates) cannot be
    trimmed — allowlist it in the hygiene test with a justification and
    cite it in the appeal.
- **Appeal via Discord first — it's processed faster.** Post the
  re-review request in a **persistent per-publisher thread** (e.g.
  `Publisher <name> — re-review`) in the Comfy Org Discord
  `SUPPORT/#security-review-council` channel, not as a loose channel
  message: the channel is a firehose of automated flagged-release
  notifications, so a bare message is unfindable within hours and a
  multi-round appeal (a reply days later, the next release re-flagged)
  loses its history. Reuse the same thread for every appeal. Keep the
  message under the 2,000-char limit with no markdown tables — fitting a
  multi-pack appeal usually costs several trim passes, so put the
  version-ID table and per-finding detail in a GitHub issue on
  `Comfy-Org/registry-backend` as the durable record and have the
  Discord message link to it rather than duplicate it.
- **Then verify by publishing**: a republish re-runs the scan, so the
  definitive test of any fix is the next release's verdict via
  `api.comfy.org/nodes/<id>/versions?include_status_reason=true`.
