# Step 2: Auto-Detect Related Issues

Moved verbatim from `SKILL.md` Step 2. Run it unless `--skip-issue-detection` or `--issue` was passed.

### Step 2: Auto-Detect Related Issues (unless --skip-issue-detection or --issue provided)

**Purpose**: Automatically identify open GitHub issues that the staged changes may fix or close.

1. **Analyze staged changes**:
   - Get list of changed files: `git diff --cached --name-only`
   - Extract modified directories, file names, and content patterns
   - Identify error messages, function names, or keywords in the diff

2. **Match against open issues**:
   - Review the open issues from context (or fetch with `gh issue list --state open`)
   - Score each issue based on:
     - **High confidence**: File path mentioned in issue body, error message match
     - **Medium confidence**: Directory/component match, keyword overlap
     - **Low confidence**: Label matches changed area (e.g., `bug` label + fix changes)

3. **Report detected issues**:
   ```
   Detected potentially related issues:

   HIGH CONFIDENCE:
   - #123 "Login fails with invalid token" → Fixes #123
     Match: Changes to src/auth/token.ts, issue mentions token validation

   MEDIUM CONFIDENCE:
   - #456 "Improve error messages" → Refs #456
     Match: Error handling changes in src/auth/

   Suggested closing keywords for commit message:
   Fixes #123
   Refs #456
   ```

4. **Determine appropriate keywords**:
   - Use `Fixes #N` for bug fixes that fully resolve the issue
   - Use `Closes #N` for features that complete the issue
   - Use `Refs #N` for partial progress or related changes
   - See **github-issue-autodetect** skill for decision tree

5. **Confirm with user** (if uncertain):
   - For high-confidence matches, include automatically
   - For medium-confidence, suggest and confirm
   - For low-confidence, mention but let user decide
