---
name: git-workflow
description: Fixture git/gh workflow skill for test-skill-shell-commands.sh. Use when testing.
allowed-tools: Bash, Read, Grep
---

## Context

- Branch: !`git branch --show-current`
- CLI: !`claude --version`

## Steps

Use `gh` for GitHub, or run `bash <plugin>/scripts/sync.sh` from the plugin.
Pick the branch `type` first.

```bash
git status --porcelain
git diff --cached --stat
git add path/to/file
git commit -m "fix(x): message; ls -la && more"
head_sha=$(git rev-parse HEAD) && echo "$head_sha"
gh pr create --title "x" --body "y"
git push --force-with-lease
git reset --hard HEAD
rm -rf build
sudo apt-get install -y jq
python3 -c "print(1)"
git -C other/repo log
bun --inspect-brk run.ts
git ls-files | xargs wc -l
ruff check .
docker run --rm -v "$(pwd)/docs:/out" img
timeout 30 git fetch origin
```
