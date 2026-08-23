# GitHub Actions Authentication and Security - Reference

Commit-security verification, the full pre-deployment/monitoring/incident-response checklist, and per-provider troubleshooting for Claude Code GitHub Actions workflows.

## Commit Security

**Automatic Commit Signing**:
```yaml
# Commits are automatically signed by Claude Code
permissions:
  contents: write  # Enables signed commits

# Verify commit signature
- run: git verify-commit HEAD
```

**Commit Verification**:
```bash
# Check commit signature
git log --show-signature

# Verify specific commit
git verify-commit <commit-sha>

# Check author
git log --format='%an <%ae>' HEAD^..HEAD
```

## Security Checklist

### Pre-Deployment
- [ ] All credentials use GitHub secrets
- [ ] Explicit `permissions:` block, read-only default + per-job escalation
- [ ] Repo default `GITHUB_TOKEN` permission set to read-only
- [ ] Untrusted run-context values pass through an `env:` var (no `${{ … }}` in `run:`)
- [ ] Third-party actions SHA-pinned (Renovate-managed — see `version-pinning.md`)
- [ ] `/.github/workflows/` listed in `.github/CODEOWNERS` (ownership + auto-requested review; see the caveat below before making it a merge gate)
- [ ] Actions blocked from creating/approving PRs unless a workflow needs it
- [ ] Input validation implemented
- [ ] Branch protection rules enabled
- [ ] Security scanning enabled

#### CODEOWNERS: ownership vs. enforcement

`.github/CODEOWNERS` alone names an owner per path and makes GitHub
auto-request their review — pure upside, enable it anywhere. Turning it into a
merge **gate** is a separate branch-protection setting, "Require review from
Code Owners", and that one needs a look at who the owners are first.

**GitHub does not count a PR author's own approval toward the code-owner
requirement.** So on a repo where the listed owner is also the author of nearly
every PR touching those paths — a solo maintainer, or a path only one
team member ever edits — enabling it means each of those PRs needs a second
reviewer who does not exist, or an admin bypass on every merge. The setting
stops being a review aid and becomes a merge block.

Enable it when the owner list contains someone other than the usual author (a
second maintainer, or a bot account that can approve); leave it off when it does
not, and record that as a decision rather than an oversight. Either way the
CODEOWNERS file keeps earning its place.

### Monitoring
- [ ] Workflow logs reviewed regularly
- [ ] Unusual activity monitored
- [ ] API usage tracked
- [ ] Failed authentication attempts logged
- [ ] Commit signatures verified

### Incident Response
- [ ] Secret rotation procedure documented
- [ ] Access revocation process defined
- [ ] Audit trail maintained
- [ ] Security contact established
- [ ] Recovery plan documented

## Troubleshooting

### Authentication Failures
```bash
# Verify secret exists
# Settings → Secrets and variables → Actions

# Check secret name matches workflow
anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}

# Validate API key format
# Should start with: sk-ant-api03-

# Test API key locally
curl https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -d '{"model":"claude-3-5-sonnet-20241022","max_tokens":10,"messages":[{"role":"user","content":"test"}]}'
```

### Permission Denied Errors
```yaml
# Ensure proper permissions
permissions:
  contents: write       # For code changes
  pull-requests: write  # For PR operations
  issues: write         # For issue operations
  actions: read         # For CI/CD access

# Check branch protection rules
# Settings → Branches → Branch protection rules

# Verify GitHub App installation
# Settings → Installations → Claude
```

### AWS Bedrock Issues
```bash
# Verify IAM role
aws sts get-caller-identity

# Check Bedrock access
aws bedrock list-foundation-models --region us-east-1

# Test OIDC configuration
# Ensure trust policy includes GitHub OIDC provider
```

### Vertex AI Issues
```bash
# Verify service account
gcloud auth list

# Check Vertex AI permissions
gcloud projects get-iam-policy $GCP_PROJECT_ID

# Test Vertex AI access
gcloud ai models list --region=us-central1
```
