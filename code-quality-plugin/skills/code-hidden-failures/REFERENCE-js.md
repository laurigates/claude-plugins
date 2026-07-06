# Reference — JavaScript / TypeScript Error Swallowing

> **Detection lives in the rule project, not here.** The structural patterns
> (empty catch, empty `.catch`, `void`-ignore) are executable ast-grep rules —
> [`js-empty-catch.yml`](rules/lib/js-empty-catch.yml),
> [`js-promise-catch-empty.yml`](rules/lib/js-promise-catch-empty.yml),
> [`js-void-ignore.yml`](rules/lib/js-void-ignore.yml) — run in one pass via
> `ast-grep scan -c rules/sgconfig.yml`. This file is the **judgment reference**:
> allowlist, severity promotion, and remediation templates. The heuristic
> patterns below (floating promises, error-boundary silence) stay
> toolchain-deferred / Grep-based.

Detection rules for `.js`, `.jsx`, `.ts`, `.tsx`, `.mjs`, `.cjs`. Use
`sg` (ast-grep) for structural matching where possible; fall back to Grep
for the heuristic ones.

## Patterns

| ID | ast-grep pattern | Default severity |
|----|------------------|------------------|
| `js-empty-catch` | `try { $$$ } catch ($E) {}` | Medium |
| `js-catch-only-comment` | `try { $$$ } catch ($E) { /* $$ */ }` | Medium |
| `js-promise-catch-empty` | `$EXPR.catch(() => {})` / `$EXPR.catch(() => null)` | Medium |
| `js-promise-catch-ignore` | `$EXPR.catch(($E) => {})` | Medium |
| `js-floating-promise` | Top-level `await`-less call returning a Promise with no `.then` / `.catch` | Medium |
| `js-void-ignore` | `void $EXPR()` where `$EXPR` returns a Promise | Medium |
| `js-try-log-swallow` | `catch ($E) { console.log($E) }` — logs, no rethrow | Low (if UI-layer) / Medium |
| `js-swallow-rethrow` | `catch ($E) { logger.error($E); throw $E }` | **Low** (correct pattern) |
| `js-error-boundary-silence` | React `componentDidCatch` with no logging or state update | High |

### ast-grep commands

The structural patterns above are the executable rules in
[`rules/lib/`](rules/lib/) (`js-empty-catch`, `js-promise-catch-empty`,
`js-void-ignore`) — run them as one pass with
`ast-grep scan -c rules/sgconfig.yml --json=compact <path>`. As a per-pattern
fallback when `ast-grep scan` is unavailable, the equivalent one-liners are
`sg -p 'try { $$$ } catch ($E) { }' --lang ts`,
`sg -p '$EXPR.catch(() => {})' --lang ts`, and `sg -p 'void $EXPR($$$)' --lang ts`.

For floating promises the repo's own toolchain is authoritative — defer to
`tsc --noImplicitAny` + `no-floating-promises` ESLint rule when configured;
only report a finding when neither is present.

## Allowlist (classify as Low)

| Pattern | Why |
|---------|-----|
| `catch ($E) { /* intentionally ignored: <reason> */ }` | Explicit documented decision |
| `catch` block that calls any `log*` / `console.error` / `Sentry.captureException` AND rethrows | Logs + rethrow is correct |
| `.catch(() => defaultValue)` where `defaultValue` is a literal and the call site uses it | Fallback value, not suppression |
| `catch` inside a `finally`-cleanup path, where the primary error is already propagating | Don't double-throw |

## Severity promotion

Promote to **High** if the swallowed expression matches any of:

- `fetch(`, `axios.`, `client.`, `api.` calls whose result drives writes
- `.save(` / `.insert(` / `.update(` / `.delete(` (ORM methods)
- Any call inside a handler named `onSubmit`, `onSave`, `onPublish`,
  `onDeploy`, `onPurchase`, `onPayment`
- Auth / token refresh calls: `refreshToken`, `verifyToken`, `signIn`,
  `signOut`

## Remediation templates

### Frontend empty catch → toast + console.error

```typescript
// Before
try {
  await saveProfile(data);
} catch (e) {}

// After
try {
  await saveProfile(data);
} catch (e) {
  console.error('saveProfile failed', e); // TODO(error-swallowing): review wording
  toast.error('Could not save profile. Please try again.');
}
```

### Backend empty catch → structured log + re-raise

```typescript
// Before
try {
  await db.insert(...);
} catch (e) {}

// After
try {
  await db.insert(...);
} catch (e) {
  logger.error({ err: e, op: 'db.insert' }, 'insert failed');
  throw e; // let the request handler return 5xx
}
```

### Library → propagate

Libraries should almost never catch-and-discard. Delete the try/catch and
let the caller decide.

### `.catch(() => {})` → typed fallback

```typescript
// Before
const user = await fetchUser(id).catch(() => {});

// After
const user = await fetchUser(id).catch((err) => {
  console.error('fetchUser failed', err);
  return null;           // explicit sentinel callers must handle
});
```

## Framework-specific notes

### React

- `componentDidCatch` without logging is always **High** — it silences an
  entire subtree.
- `useEffect(() => { asyncFn(); }, [])` without a `.catch` is a floating
  promise.

### Node / Express

- An error-handling middleware that calls `next()` instead of `next(err)`
  after a `catch` is suppressing — flag as Medium.

### Vue

- `errorCaptured` returning `false` without logging = High.
