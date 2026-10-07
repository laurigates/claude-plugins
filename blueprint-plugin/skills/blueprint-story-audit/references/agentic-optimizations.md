# story-audit — Agentic Optimizations

| Context | Command |
|---------|---------|
| Count PRD files | `find docs/prds -maxdepth 1 -name '*.md'` |
| Count test files (TS/JS) | `find . -type f \( -name '*.test.ts' -o -name '*.test.tsx' -o -name '*.spec.ts' \) -not -path '*/node_modules/*'` |
| Count test files (Python) | `find . -type f -name 'test_*.py' -not -path '*/.venv/*'` |
| Find skipped tests | `grep -rn -E "test\.(skip\|todo)\|xit\(\|@pytest.mark.skip" --include='*.test.*' --include='test_*.py'` |
| Detect declared deps | `jq -r '.dependencies // {} \| keys[]' package.json` (or `grep '^[a-z].*=' pyproject.toml`) |
| Check dep is imported | `grep -rln "from <pkg>\|import <pkg>\|require('<pkg>')" --include='*.ts' --include='*.py'` |
| Audit filename | `echo "docs/blueprint/audits/$(date -u +%Y-%m-%d)-story-audit.md"` |
