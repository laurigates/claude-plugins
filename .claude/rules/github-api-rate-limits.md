# GitHub API Rate Limit Best Practices

All skills that use `gh api` must handle rate limits to prevent "Rate limit reached" errors.

## Required Patterns

### 1. Use `--cache` on read-only `gh api` calls

Add `--cache 5m` to all GET requests to avoid redundant API calls on retries or re-runs:

```bash
# Correct
gh api --cache 5m repos/{owner}/{repo}/pulls/$PR/comments --jq '...'

# Incorrect — no caching, wastes rate limit on repeated calls
gh api repos/{owner}/{repo}/pulls/$PR/comments --jq '...'
```

Do NOT use `--cache` on write operations (`-X POST`, `-X PUT`, `-X DELETE`, `-X PATCH`, or `-f` flag).

### 2. Rate limit pre-check for multi-call skills

Skills that make 3+ `gh api` calls should check rate limit first:

```bash
gh api rate_limit --jq '.resources.core | "Remaining: \(.remaining)/\(.limit)"'
```

If remaining < 10, warn the user and consider deferring non-essential calls.

### 3. Retry with backoff on rate limit errors

When a `gh api` call fails with a rate limit error, retry with exponential backoff:

```bash
for i in 1 2 3; do
  result=$(gh api --cache 5m <endpoint> --jq '...' 2>&1) && break
  echo "$result" | grep -qi "rate limit" || break
  echo "Rate limited, waiting $((i * 30))s..."
  sleep $((i * 30))
done
```

### 4. Throttle bulk DELETE loops

When deleting resources in a loop, add a delay between calls:

```bash
# Correct — throttled to avoid rate limits
while read id; do
  gh api -X DELETE "/repos/$REPO/actions/caches/$id"
  sleep 0.5
done

# Incorrect — rapid-fire DELETEs exhaust rate limit
while read id; do
  gh api -X DELETE "/repos/$REPO/actions/caches/$id"
done
```

## Cache Duration Guidelines

| Scenario | Cache Duration |
|----------|---------------|
| Within a single skill execution | `--cache 5m` |
| Data that rarely changes (branches, repo info) | `--cache 1h` |
| Frequently changing data (run status) | `--cache 1m` or no cache |

## Checklist for Skill PRs

When reviewing skills that use `gh api`:

- [ ] All read-only `gh api` calls use `--cache`
- [ ] Skills with 3+ API calls include rate limit pre-check
- [ ] Bulk loops include `sleep` between calls
- [ ] Error handling mentions rate limit retry pattern
- [ ] Write operations (`-X DELETE/POST/PUT/PATCH`) do NOT use `--cache`
