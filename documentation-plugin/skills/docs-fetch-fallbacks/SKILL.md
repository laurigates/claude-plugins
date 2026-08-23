---
name: docs-fetch-fallbacks
description: "WebFetch 404/403/timeout/empty-SPA fallback ladder: strip query, raw.githubusercontent, `gh api`, docs-source-at-a-pinned-tag, context7/WebSearch. Use when a doc or GitHub URL fetch fails or returns a page with no content."
allowed-tools: WebFetch, WebSearch, Bash(gh api *), Read
created: 2026-08-19
modified: 2026-08-21
reviewed: 2026-08-21
---

# /docs:fetch-fallbacks

A failed `WebFetch` is not a signal to retry the same URL. Re-issuing an
identical request costs a round trip and returns the identical failure — the
path is wrong, the resource is gated, or the host is slow, and none of those
change between attempts. Read the failure signature, apply the fallback that
matches it, and stop at two attempts.

## Execution

### Step 1: Read the failure signature

Note the status **and** the URL shape before acting — the same status means
different things depending on where it lands:

| Observed | What it actually means |
|---|---|
| `404` on a URL carrying `?ref=`, `?v=`, or tracking params | The path is fine; the query is not |
| `404` on `github.com/<owner>/<repo>/blob/<ref>/<path>` | An HTML view URL, not a content URL |
| `404` on a repo path with no host problem | The content is reachable through the API, not the web UI |
| `403` with an empty body on a public docs page | Bot/UA gating, not authorization |
| `403` on a `github.com` URL | The resource needs authentication |
| A timeout with no status at all | Host slow or unreachable — needs a different source, not a retry |
| **No status at all**, and the answer says the page had no content ("I don't have access to the content", "you've only provided the heading") | The fetch **succeeded**. The page is client-rendered and the served HTML is an empty shell — see Step 4 |

### Step 2: Apply the matching fallback

| Failure | Try |
|---|---|
| 404 on a docs page with `?ref=…` | Strip query string |
| 404 on a GitHub blob URL | Switch to `raw.githubusercontent.com` URL |
| 404 on a repo path | `gh api repos/<owner>/<repo>/contents/<path>` |
| 403 on a public docs page | Try once with a different UA or a search engine |
| 403 on a GitHub URL | Use `gh api` (authenticated) |
| Timeout | One retry, then fall back to context7 / WebSearch |
| 200 with an empty shell (SPA) | Fetch the docs **source** from the project's repo at a pinned tag (Step 4) |

If two attempts both fail, surface the failure in the response — do
not loop.

### Step 3: Worked example — a GitHub blob URL

`WebFetch` returns 404 on:

```
https://github.com/laurigates/claude-plugins/blob/main/README.md?plain=1
```

Two things are wrong at once. Fix them cheapest-first rather than jumping to
the authenticated call:

1. **Strip the query** → still 404, so the query was not the whole problem.
2. **Swap the host** →
   `https://raw.githubusercontent.com/laurigates/claude-plugins/main/README.md`
   — this is the fetch that succeeds for a public repo.
3. **Still 404 or 403?** The repo is private or rate-limited. Authenticate
   instead of guessing at more URL shapes:

```bash
gh api repos/laurigates/claude-plugins/contents/README.md \
  -H "Accept: application/vnd.github.raw+json"
```

That is attempt two. There is no attempt three.

For the full URL → `gh` command mapping (pulls, issues, commits, contents at a
given ref), see `git-plugin:gh-cli-agentic` § GitHub URL Resolution — it owns
that table. This skill covers only the recovery path after a fetch has failed.

### Step 4: The SPA case — a 200 that carries no content

Every signature above is an *error*. This one is not: the request succeeds, the
status is 200, and the HTML is a shell that a browser would fill in with
JavaScript. Nothing in the result says "empty page" — instead the answer says it
cannot see the content and asks you to paste it. That reads as a broken *fetcher*
and invites a retry, which returns the identical shell.

**The tell is the answer's shape, not a status code**: it reports receiving only
a heading or a title, and asks for the documentation to be provided. Two of those
in a row on the same host means the host is client-rendered — stop fetching it.

**The fallback is the docs' source, not the docs' URL.** Most such sites render
markdown that lives in a public repo, so fetch that file instead — and pin the
ref to the version you actually depend on, which is strictly better than the
"latest" the site would have shown you.

| Rendered site | Source to fetch instead |
|---|---|
| `registry.terraform.io/providers/<org>/<name>/<version>/docs/resources/<r>` | `raw.githubusercontent.com/<org>/terraform-provider-<name>/v<version>/website/docs/r/<r>.html.markdown` |
| A docs site with an "Edit this page" link | Follow that link — it points at the source file |
| A project site backed by `docs/` in its repo | `raw.githubusercontent.com/<org>/<repo>/<tag>/docs/<path>.md` |

Worked example — verifying a Terraform resource's arguments and import ID format:

```bash
curl -fsSL "https://raw.githubusercontent.com/integrations/terraform-provider-github/v6.12.0/website/docs/r/team_members.html.markdown"
```

The tag matches the constraint in `versions.tf`, so the arguments read are the
arguments that version accepts — a correctness gain over the registry page, not
merely a workaround for it.

When no repo backs the site, context7 is the fallback source for a named library
(Step 5), and it handles JS-rendered docs that a raw fetch cannot.

### Step 5: Surface the failure

If the fallback also fails, say so in the response: name the URL, the status,
and the fallback already tried. A third attempt with a cosmetically different
URL is the failure mode this skill exists to prevent — the caller can supply a
working URL far more cheaply than you can guess one.

When the content is documentation for a named library or framework, context7
and `WebSearch` are the fallback *source*, not another attempt at the same URL.
