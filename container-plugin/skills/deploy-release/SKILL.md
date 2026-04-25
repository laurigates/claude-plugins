---
created: 2025-12-16
modified: 2026-04-25
reviewed: 2026-04-25
allowed-tools: Read, Write, Edit, Bash(git *), Bash(gh release *), Bash(gh pr *), TodoWrite
args: <version> [--draft] [--prerelease]
argument-hint: <version> [--draft] [--prerelease]
disable-model-invocation: true
description: |
  Create and publish releases using release-please automation or manual GitHub releases.
  Use when the user wants to cut a release, create a version tag, publish a GitHub release,
  or set up release-please manifest configuration.
name: deploy-release
---

# Release Creation Command

Create GitHub releases using release-please automation or manual release workflows for containerized applications.

## When to Use This Skill

| Use this skill when... | Use `deploy-handoff` instead when... |
|---|---|
| Cutting a new release from `main` and tagging a version | Documenting an already-deployed service for another developer or client |
| Setting up or auditing release-please automation and manifests | Generating access URLs, monitoring links, and onboarding checklists for a deployed resource |
| Publishing a manual GitHub release, draft, or pre-release | Producing handoff prose for a ticket rather than cutting a version |
| Driving the version-tag side of a containerized release pipeline | Building or hardening container images themselves (use `container-development`) |

## Context

- Git remotes: !`git remote -v`
- Branch: !`git branch --show-current`
- Recent tags: !`git tag --sort=-v:refname -l 'v*' --format='%(refname:short)' -n5`
- Last release commit: !`git log --oneline --max-count=5`
- Release config: !`find . -maxdepth 1 -name 'release-please-config.json'`
- Manifest: !`find . -maxdepth 1 -name '.release-please-manifest.json'`
- Changelog: !`find . -maxdepth 1 -name 'CHANGELOG.md'`

## Parameters

Parse from `$ARGUMENTS`:

- `$1` (VERSION): Semantic version string (e.g., `1.2.0`, `v2.0.0-rc.1`)
- `--draft`: Create release as draft (not published)
- `--prerelease`: Mark as pre-release

## Execution

Execute this release workflow:

### Step 1: Determine release strategy

Check whether the project uses release-please or manual releases:

1. If `release-please-config.json` exists, use the **release-please workflow**
2. If no release-please config exists, use the **manual release workflow**

### Step 2a: Release-please workflow

If release-please is configured:

1. Verify conventional commits exist since last release tag
2. Check for an open release PR: `gh pr list --label "autorelease: pending" --json number,title,url`
3. If a release PR exists, report its status and URL
4. If no release PR exists, explain that release-please creates PRs automatically from conventional commits
5. Provide guidance on merging the release PR to trigger the release

### Step 2b: Manual release workflow

If no release-please config:

1. Validate the VERSION argument follows semver format
2. Check that the working tree is clean: `git status --porcelain`
3. Confirm the branch is main or master
4. Create the release with:
   ```
   gh release create v<VERSION> --title "v<VERSION>" --generate-notes
   ```
5. Add `--draft` flag if `--draft` was passed
6. Add `--prerelease` flag if `--prerelease` was passed

### Step 3: Set up release-please (if requested)

If the user asks to set up release-please automation:

1. Create `release-please-config.json` with manifest release type:
   ```json
   {
     "$schema": "https://raw.githubusercontent.com/googleapis/release-please/main/schemas/config.json",
     "release-type": "simple",
     "packages": {
       ".": {
         "component": "<project-name>",
         "extra-files": [
           {"type": "json", "path": "package.json", "jsonpath": "$.version"}
         ],
         "changelog-sections": [
           {"type": "feat", "section": "Features"},
           {"type": "fix", "section": "Bug Fixes"},
           {"type": "perf", "section": "Performance"},
           {"type": "refactor", "section": "Code Refactoring"},
           {"type": "docs", "section": "Documentation"}
         ]
       }
     }
   }
   ```
2. Create `.release-please-manifest.json` with current version:
   ```json
   {
     ".": "0.0.0"
   }
   ```
3. Recommend adding the release-please GitHub Action workflow

### Step 4: Report results

Print a summary including:
- Release version and URL (if created)
- Release PR status (if release-please)
- Next steps for the user

## Release-Please GitHub Action

Recommended workflow for automation:

```yaml
name: Release
on:
  push:
    branches: [main]

permissions:
  contents: write
  pull-requests: write

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: googleapis/release-please-action@v4
        with:
          config-file: release-please-config.json
          manifest-file: .release-please-manifest.json
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| List recent tags | `git tag --sort=-v:refname -l 'v*' -n5` |
| Check release PRs | `gh pr list --label "autorelease: pending" --json number,title,url` |
| Latest release | `gh release view --json tagName,publishedAt,url` |
| Create release | `gh release create v1.0.0 --generate-notes` |
| Create draft | `gh release create v1.0.0 --draft --generate-notes` |
| Create prerelease | `gh release create v1.0.0-rc.1 --prerelease --generate-notes` |
| List all releases | `gh release list --json tagName,isLatest,isDraft,isPrerelease` |
| Commits since tag | `git log v1.0.0..HEAD --oneline` |

## Quick Reference

| Flag | Description |
|------|-------------|
| `--draft` | Create as draft release (not visible publicly) |
| `--prerelease` | Mark as pre-release version |
| `--generate-notes` | Auto-generate release notes from commits |
| `--notes-file FILE` | Use file contents as release notes |
| `--target BRANCH` | Target branch for the release tag |

## Related Skills

- `deploy-handoff` - Generate deployment handoff documentation
- `container-development` - Container image construction and optimization
