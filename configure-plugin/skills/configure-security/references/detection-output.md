# Detection Script Output

Used by Step 2 (detect project languages and security posture) to read the `configure-security.sh` output, and by Step 5 to decide whether CodeQL can run.

## Keys

The `KEY=VALUE` lines
report language detection (`LANG_JS`, `LANG_PYTHON`, `LANG_RUST`, `LANG_GO`) and
the presence matrix (`DEPENDABOT`, `RENOVATE`, `DEPENDENCY_AUTOMATION`, `CODEQL`,
`CODEQL_AVAILABLE`, `CODEQL_AVAILABILITY_REASON`, `GITLEAKS_CONFIG`, `GITLEAKS_RULES`,
`SECURITY_POLICY`, `TRUFFLEHOG`, `DEPENDENCY_REVIEW`, `SECURITY_LAYERS_PRESENT`).

## Secret-detection rules

`GITLEAKS_CONFIG` says only that `.gitleaks.toml` exists. `GITLEAKS_RULES` says
whether it loads any rules, and only a rule-loading config counts toward
`SECURITY_LAYERS_PRESENT`. gitleaks takes rules from `[[rules]]` tables and from
`[extend]` alone, and it auto-discovers `.gitleaks.toml` in the scanned directory,
so an allowlist-only file turns the pre-commit hook and gitleaks-action into scans
that pass every time.

| `GITLEAKS_RULES` | Config shape | Finding |
|---|---|---|
| `default` | `[extend] useDefault = true`, as a table, dotted `extend.useDefault` or inline table; keys in any case, bare or quoted (`["extend"]`); the value `true`, a quoted `"true"` / `"True"` / `"TRUE"` / `"t"` / `"T"` / `"1"`, or a non-zero decimal number | none |
| `extend-path` | `[extend] path = "<file>"`; the script does not follow the path | none |
| `custom` | own `[[rules]]` (or `[["rules"]]`), no `[extend]` | none |
| `none` | `[allowlist]` / `[[allowlists]]` only, or a `useDefault` gitleaks reads as false (`false`, `"false"`, `0`) | `SEVERITY=WARN TYPE=inert_secret_detection`; fix by adding `[extend]` / `useDefault = true` above the allowlist |
| `absent` | no `.gitleaks.toml` | `SEVERITY=WARN TYPE=missing_secret_detection` |

Some spellings load rules in gitleaks 8.30.1 but report `none`, a false WARN on a
working config: a root-level `rules = [ { ... } ]` array instead of `[[rules]]`
tables, and a `useDefault` written as a hex, octal or binary literal, as `inf` or
`nan`, or as a triple-quoted string. Case 5e of `scripts/tests/test-configure-security.sh` runs
every fixture through the real gitleaks and fails on any verdict it disagrees with.

## CodeQL availability

`CODEQL_AVAILABLE` (`yes`/`no`/`unknown`) says whether CodeQL can run here at all;
`CODEQL_AVAILABILITY_REASON` says how that was decided. It gates the severity of
a missing SAST layer:

| `CODEQL_AVAILABLE` | Finding when `CODEQL=false` | Read it as |
|---|---|---|
| `yes` | `SEVERITY=WARN TYPE=missing_sast` | a real gap — code scanning is enabled, or the repo is public (CodeQL is free there) |
| `no` | `SEVERITY=INFO TYPE=sast_unavailable` | code security is **not enabled here**, so a CodeQL workflow would 403 on every run. The API cannot say whether the org is unlicensed or merely has the setting off, so offer both: enable code scanning in the repo's security settings where the plan allows it, otherwise a SARIF-free scanner |
| `unknown` | `SEVERITY=WARN TYPE=missing_sast` | not determined (`no-remote`, `not-github`, `gh-missing`, `gh-unauthenticated`, `timeout`, `api-error`, `repo-not-found`, `status-field-absent`, `status-unrecognised`, `mktemp-failed`, `opt-out`, `not-probed`) — treat the WARN as provisional |

The probe is the script's only network call and runs only when `CODEQL=false`; a
repo that already has the workflow reports `not-probed`.
`CONFIGURE_SECURITY_NO_GHAS_PROBE=1` skips it and `CONFIGURE_SECURITY_GH_TIMEOUT`
bounds it (default 8s).
