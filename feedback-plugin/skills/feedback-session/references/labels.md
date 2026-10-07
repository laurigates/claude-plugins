# feedback-session: label checks (Steps 1b and 1c)

**1b. Check whether labels are IaC-managed**

Run: `gh label list -R $TARGET_REPO --json name,description --jq '.[].description'` (omit `-R` if no explicit target).

Scan the output for IaC indicators in any label description:
- Keywords: `terraform`, `pulumi`, `cdk`, `managed by`, `do not create`, `iac`, `infrastructure`

Also check for labels.tf in the cwd: look for files matching `**/labels.tf` or `**/labels.yaml` patterns using Glob.

If IaC indicators are found **or** `labels.tf` / `labels.yaml` exist in the working tree:
- Display a warning:
  ```
  ⚠ IaC-managed labels detected in <repo>.
  The `session-feedback` and `positive-feedback` labels cannot be created
  via `gh label create` — they are managed declaratively and creating them
  out-of-band would cause drift.
  ```
- Use AskUserQuestion to ask: **How would you like to proceed?**
  Options:
  1. **Proceed without session-feedback labels** — issues will be created with only `bug`/`enhancement` labels; add the two labels to your IaC definition to backfill.
  2. **Use a different target repo** — enter an `owner/repo` where you can create labels freely (e.g. `laurigates/claude-plugins`).
  3. **Abort** — stop here.

  If user chooses option 2, set `$TARGET_REPO` to their input and re-run step 1b for the new repo.
  If user chooses option 3, exit.
  If user chooses option 1, set `$SKIP_SESSION_LABELS=true` and continue.

**1c. Create missing labels (only when not IaC-managed)**

Skip this step if `$SKIP_SESSION_LABELS=true`.

1. Check if `session-feedback` exists: `gh label list --json name --jq '.[].name' | grep -q session-feedback`
2. If missing: `gh label create session-feedback --description "Feedback from session analysis" --color "d876e3"`
3. Check if `positive-feedback` exists similarly.
4. If missing: `gh label create positive-feedback --description "Skills that worked well" --color "0e8a16"`
