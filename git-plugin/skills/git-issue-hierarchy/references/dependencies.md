# Dependency Management

Moved verbatim from `SKILL.md` Step 3. Read for `--deps`, `--blocking`, `--block`, `--blocked-by`, and `--unblock`.

#### Dependency Management

Dependencies use GitHub's native `dependencies/blocked_by` and
`dependencies/blocking` endpoints. They appear in the issue sidebar under
"Relationships" and mark the blocked issue with a "Blocked" badge on project
boards. Both endpoints require the target issue's **node id** (`.id` on the
issue payload), not the human-readable issue number.

**Add "blocked by" relationship (`--blocked-by <N>`): parent is blocked by N**

```bash
# Resolve the blocker's node id
BLOCKER_ID=$(gh api repos/$OWNER/$REPO_NAME/issues/$N --jq '.id')

# Record the dependency on the parent
gh api repos/$OWNER/$REPO_NAME/issues/$PARENT/dependencies/blocked_by \
  -f issue_id=$BLOCKER_ID
```

**Add "blocks" relationship (`--block <N>`): parent blocks issue N**

The API is one-directional — write the relationship on the *blocked* side:

```bash
# Resolve the parent's node id
PARENT_ID=$(gh api repos/$OWNER/$REPO_NAME/issues/$PARENT --jq '.id')

# Record on issue N that it is blocked by the parent
gh api repos/$OWNER/$REPO_NAME/issues/$N/dependencies/blocked_by \
  -f issue_id=$PARENT_ID
```

**Remove relationship (`--unblock <N>`):**

Look up which side carries the link, then delete it. The `DELETE` path takes
the stored dependency's `{issue_id}` segment:

```bash
# Is the parent blocked by N?
gh api repos/$OWNER/$REPO_NAME/issues/$PARENT/dependencies/blocked_by \
  --jq ".[] | select(.number == $N) | .id"

# Or does the parent block N?
gh api repos/$OWNER/$REPO_NAME/issues/$N/dependencies/blocked_by \
  --jq ".[] | select(.number == $PARENT) | .id"

# Delete whichever is present
gh api repos/$OWNER/$REPO_NAME/issues/$ISSUE/dependencies/blocked_by/$DEP_ID \
  -X DELETE
```

**List what the parent blocks (`--blocking`):**

```bash
gh api repos/$OWNER/$REPO_NAME/issues/$PARENT/dependencies/blocking \
  --jq '.[] | "#\(.number) \(.state) \(.title)"'
```

**Show dependency graph (`--deps`):**

Combine both dependency endpoints with the sub-issues summary. Do not parse
issue bodies — the native API is authoritative:

```bash
# What blocks the parent
gh api repos/$OWNER/$REPO_NAME/issues/$PARENT/dependencies/blocked_by \
  --jq '.[] | "#\(.number) \(.state) \(.title)"'

# What the parent blocks
gh api repos/$OWNER/$REPO_NAME/issues/$PARENT/dependencies/blocking \
  --jq '.[] | "#\(.number) \(.state) \(.title)"'

# Sub-issues (composition, not ordering)
gh api repos/$OWNER/$REPO_NAME/issues/$PARENT/sub_issues \
  --jq '.[] | "#\(.number) \(.state) \(.title)"'
```

Render output as:

```
#42 Refactor authentication
├── Blocked by: #40 Database migration (✓ closed)
├── Blocks:     #45 Deploy auth v2 (○ open)
└── Sub-issues:
    ├── #43 ✓ Extract token validation
    └── #44 ○ Add refresh token support
```

Surface `Blocked by` entries that are still `open` prominently — those are
what prevent the parent from starting.
