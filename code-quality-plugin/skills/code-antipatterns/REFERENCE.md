# Code Anti-patterns Reference

The detection catalog is an **executable ast-grep rule project**, not prose. Each
pattern lives in its own rule file under [`rules/lib/`](rules/lib/) with a
valid/invalid test fixture in [`rules/tests/`](rules/tests/). Run the whole
catalog in one deterministic pass:

```bash
ast-grep scan -c rules/sgconfig.yml --json=compact <path>
```

This file is the **narrative + fallback**: it links each pattern to its rule file
(so the rule `.yml` is the single source of truth for the pattern) and gives the
per-pattern `ast-grep -p` command to run by hand when `ast-grep scan` isn't
available. Do not restate the rule bodies here — edit the `.yml` instead.

## The rule catalog

Rules use `language: tsx` for JS/TS (the Tsx grammar parses `.ts/.tsx/.js/.jsx/
.mjs/.cjs` — see `languageGlobs` in [`rules/sgconfig.yml`](rules/sgconfig.yml))
and `language: python` for Python.

| Rule file | Catches | Fallback one-liner |
|-----------|---------|--------------------|
| [`no-empty-catch.yml`](rules/lib/no-empty-catch.yml) | `try { … } catch (e) {}` | `ast-grep -p 'try { $$$ } catch ($E) { }' --lang ts` |
| [`no-console-log.yml`](rules/lib/no-console-log.yml) | `console.log(…)` left in code | `ast-grep -p 'console.log($$$)' --lang ts` |
| [`no-var.yml`](rules/lib/no-var.yml) | `var x = …` (use let/const) | `ast-grep -p 'var $VAR = $$$' --lang ts` |
| [`no-eval.yml`](rules/lib/no-eval.yml) | `eval(…)` / `new Function(…)` | `ast-grep -p 'eval($$$)' --lang ts` |
| [`no-innerhtml.yml`](rules/lib/no-innerhtml.yml) | `el.innerHTML = …` / `outerHTML` (XSS) | `ast-grep -p '$EL.innerHTML = $$$' --lang ts` |
| [`ts-as-any.yml`](rules/lib/ts-as-any.yml) | `expr as any` | `ast-grep -p '$X as any' --lang ts` |
| [`ts-any-annotation.yml`](rules/lib/ts-any-annotation.yml) | `: any` annotations | (context/selector — see rule file) |
| [`no-magic-number.yml`](rules/lib/no-magic-number.yml) | magic numeric timer delays | `ast-grep -p 'setTimeout($F, $N)' --lang ts` |
| [`vue-props-mutation.yml`](rules/lib/vue-props-mutation.yml) | `props.x = …` | `ast-grep -p 'props.$P = $V' --lang ts` |
| [`py-mutable-default.yml`](rules/lib/py-mutable-default.yml) | `def f(a=[])` / `def f(a={})` | `ast-grep -p 'def $F($A=[]): $$$' --lang py` |
| [`py-bare-except.yml`](rules/lib/py-bare-except.yml) | bare `except:` | (context/selector — see rule file) |
| [`py-global.yml`](rules/lib/py-global.yml) | `global X` | `ast-grep -p 'global $VAR' --lang py` |
| [`py-use-isinstance.yml`](rules/lib/py-use-isinstance.yml) | `type(x) == T` | `ast-grep -p 'type($V) == $T' --lang py` |

## Not in the rule project (agent judgment)

Some catalog concerns are metrics or heuristics, not single-node structural
matches, and stay as agent-judgment passes on the code:

- **Deep nesting / long functions / large parameter lists / cyclomatic
  complexity** — a metric over a body, not a pattern. Use `/code:complexity`.
- **Floating promises / unhandled rejections** — the repo toolchain is
  authoritative; defer to `tsc` + `no-floating-promises`, or the errors track of
  `/code:hidden-failures`. A broad structural rule would flag every call.
- **Hardcoded secrets / SQL & command injection** — string-shaped and
  false-positive-prone; use `gitleaks` / `/code:review` (security) rather than an
  ast-grep literal-match rule.

## Error swallowing is delegated

Empty catch, bare `except`, and floating-promise findings share a severity model,
surfacing recommendations, and privacy redaction with the dedicated scanner.
`no-empty-catch` / `py-bare-except` are flagged here for completeness, but their
**triage and remediation** belong to `/code:hidden-failures --track errors` (whose
own [`rules/`](../code-hidden-failures/rules/) project overlaps on these shared
patterns by design — one canonical source per pattern, per skill).

## Adding a rule

1. Add `rules/lib/<id>.yml` (`id`, `language`, `severity` ∈
   hint/info/warning/error, `message`, `rule`).
2. Add `rules/tests/<id>-test.yml` with `valid:` (clean code — must **not** match)
   and `invalid:` (the anti-pattern — must match).
3. `ast-grep test -c rules/sgconfig.yml --skip-snapshot-tests` must pass.
4. Add a row to the catalog table above.

The regression test
[`scripts/tests/test-rules-project.sh`](scripts/tests/test-rules-project.sh)
(run by `just test-skill-scripts`) fails if a rule ships without a fixture or if
any fixture regresses.
