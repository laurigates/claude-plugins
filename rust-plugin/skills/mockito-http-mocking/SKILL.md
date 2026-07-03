---
created: 2026-07-03
modified: 2026-07-03
name: mockito-http-mocking
description: "mockito HTTP mocking for Rust integration tests: expectation semantics, mock matching order, and taming polling clients against instant mock servers. Use when mocking an HTTP API in Rust tests, when a wait-until-matched loop hangs, or when tests pass alone but hang under concurrent load."
user-invocable: false
allowed-tools: Bash, Read, Grep, Glob
---

# mockito-http-mocking - HTTP API Mocking in Rust Tests

mockito spins up a real local HTTP server per test and matches incoming
requests against declared mocks. Two of its semantics are routinely
misread, and one interaction with polling clients produces hangs that only
appear under concurrent load. All three were debugged live against a
teloxide long-polling bot (truenas-ai-sentinel PR #12); the patterns apply
to any Rust client that re-requests an endpoint in a loop.

## When to Use This Skill

| Use this skill when... | Use sibling skill instead when... |
|---|---|
| Mocking an HTTP API (Bot APIs, REST backends) in integration tests | Running/parallelizing the tests -- use `cargo-nextest` |
| A `matched()` wait loop hangs or a mock "never gets hit" | Authoring async test code in general -- use `rust-development` |
| Tests pass alone but hang/flake when the suite runs concurrently | Measuring coverage of the tests -- use `cargo-llvm-cov` |
| Layering specific and catch-all mocks on one path | |

## Semantics That Bite

### 1. `matched()` means "hit count EQUALS the expectation" — not "was hit"

The default expectation is **exactly 1**. A mock hit twice makes
`matched()` return `false` again, so a wait-until-matched loop that raced
past one hit silently un-matches:

```rust
// Wrong for anything a client may hit repeatedly: matched() flips back
// to false on the second hit.
let m = server.mock("POST", "/x").with_body("ok").create_async().await;

// Right: "at least once" is what a readiness wait actually means.
let m = server.mock("POST", "/x").with_body("ok")
    .expect_at_least(1).create_async().await;
while !m.matched_async().await { tokio::time::sleep(Duration::from_millis(50)).await; }
```

Reserve exact `expect(n)` / `expect(0)` for the final `assert_async()`
after the client has been stopped — `expect(0)` plus a settle delay is the
correct shape for "this endpoint must never be called".

### 2. Mocks match in creation order — first match wins

When several mocks cover the same method + path, mockito uses the **first
created** mock whose matchers accept the request. Create specific
body-matched mocks **before** the catch-all:

```rust
// Specific first: requests carrying {"offset":2} get the empty response...
let drained = server.mock("POST", "/api/poll")
    .match_body(Matcher::PartialJsonString(r#"{"offset":2}"#.into()))
    .with_body(r#"{"ok":true,"result":[]}"#)
    .create_async().await;
// ...everything else falls through to the catch-all batch.
let batch = server.mock("POST", "/api/poll")
    .with_body(one_update_json())
    .create_async().await;
```

`Matcher::PartialJsonString` compares **values**, not just keys —
`{"offset":0,...}` does *not* match a `{"offset":2}` partial. Verify with a
raw `reqwest` probe when in doubt; guessing the matching semantics from a
failing dispatcher test conflates several failure modes.

## Polling Clients Against an Instant Mock Server

Real long polling holds the HTTP connection server-side. mockito responds
**instantly**, so a long-poll client (`getUpdates`-style loops, SQS-style
receive loops) degenerates into a hot request loop at ~100% CPU. Two
consequences:

- The flood starves everything sharing the runtime/machine — tests that
  pass in isolation **hang under concurrent suite load** (the tell:
  `cargo nextest run --test x <one_test>` passes in milliseconds, the full
  run gets killed after minutes with SIGTERM, and `ps` shows the test
  binary spinning at 100% CPU).
- Graceful-shutdown paths that wait for the poll loop to notice a stop
  flag may never get scheduled.

### Fix A: make the "drained" mock trigger the client's error backoff

Respond **500** on the post-consumption poll request. Well-behaved clients
(teloxide, most SDKs) back off exponentially on errors, turning the hot
loop into a gentle retry — while the mock still counts as matched, which
is usually the "update was consumed" signal the test waits on:

```rust
let drained = server.mock("POST", "/api/poll")
    .match_body(Matcher::PartialJsonString(r#"{"offset":2}"#.into()))
    .with_status(500)
    .with_body(r#"{"ok":false,"error_code":500,"description":"drained (test backoff)"}"#)
    .expect_at_least(1)
    .create_async().await;
```

### Fix B: `task.abort()` instead of graceful shutdown in tests

A test does not need to prove graceful shutdown on every run. After the
awaited assertion signal fires, cancel the client task outright:

```rust
wait_until_matched(&send).await;
task.abort();
let _ = task.await;            // JoinError::is_cancelled — expected
send.assert_async().await;
```

Keep one dedicated test for graceful shutdown if the shutdown path itself
is under test; don't pay its flake risk in every dispatcher test.

## Client-Specific Notes

- **teloxide** `Polling` sends `{"offset":0,"timeout":N}` on its **first**
  request — the offset field is present, not absent. Body matchers and
  "no offset yet" assumptions must account for it. Method paths are
  PascalCase: `/bot<token>/GetUpdates`, `/GetMe`, `/SendMessage`.
- **Dispatcher-driven bots** fetch `GetMe` at startup — mock it or the
  dispatcher never polls.

## Diagnosis Checklist

| Symptom | Likely cause |
|---|---|
| Wait loop times out though the endpoint was clearly called | `matched()` vs expectation mismatch — use `expect_at_least(1)` |
| Specific mock never matches; catch-all serves everything | Catch-all was created first — reorder |
| Test passes alone, hangs in the full suite; binary at 100% CPU | Hot poll loop — apply Fix A + Fix B |
| Client errors repeatedly right after startup | A required bootstrap call (e.g. `GetMe`) has no mock |

When the failure resists reasoning, probe empirically: point the client at
a raw `tokio::net::TcpListener` that logs request lines and bodies — five
minutes of captured traffic beats an hour of guessing what the client
sends.
