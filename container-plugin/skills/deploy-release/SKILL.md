---
model: opus
created: 2025-12-16
modified: 2025-12-16
reviewed: 2025-12-16
allowed-tools: Read, Write, Edit, Bash(git *), mcp__github__create_release, mcp__github__get_latest_release, TodoWrite
argument-hint: <version> [--draft] [--prerelease]
description: Create and publish a new release
name: deploy-release
---

# Release Setup Command

- Set up release-please release automation
- Manifest based release
- Configure to update release number in all relevant files using the extra-files directive
