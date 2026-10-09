# AI Review — Cause 3: A Real Finding It Could Not Publish

Evidence for the Cause 3 section of [SKILL.md](../SKILL.md): a check that
blocks a merge on a finding nobody can read.

## A worked case where the finding was real

> Evidence (2026-08, pal-mcp-server#76): three `owasp / scan` runs reported
> 1, then **2**, then 1 criticals — the middle one on a byte-identical commit —
> with 8/6/13 denials, $5.44 total, and zero comments. The finding was real:
> `estimate_file_tokens` stat'd caller-supplied paths with no validation, and a
> change in that same PR had just started reporting per-file sizes in the
> rejection — turning it into an existence-and-size oracle for the files
> `is_dangerous_path` protects (`/etc/passwd` read back as 2,669 tokens).
> Found only by reading the code. Fixed in laurigates/.github#47/#48.

The 1 → 2 → 1 sequence on one commit is why a delta between runs is never
evidence that a fix worked.
