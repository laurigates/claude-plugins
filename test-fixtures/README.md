# Test Fixtures

Test fixtures for validating reusable GitHub Action workflows.

## Structure

```
test-fixtures/
├── security/
│   ├── secrets/           # Secrets detection test cases
│   │   ├── fake-api-key.js     # Fake AWS, Stripe, GitHub tokens
│   │   ├── fake-password.py    # Hardcoded passwords, connection strings
│   │   └── clean-file.ts       # Clean file (no secrets)
│   ├── owasp/             # OWASP vulnerability test cases
│   │   ├── sql-injection.js    # SQL injection patterns
│   │   ├── xss-vulnerable.tsx  # XSS patterns (innerHTML, dangerouslySetInnerHTML)
│   │   ├── command-injection.py # Command injection (os.system, subprocess)
│   │   └── clean-code.ts       # Secure code patterns
│   └── deps/              # Dependency vulnerability test cases
│       └── package.json        # Outdated packages with known CVEs
├── quality/               # Code quality test cases (Phase 2)
└── a11y/                  # Accessibility test cases (Phase 3)
```

## Purpose

These fixtures are used by the test workflow (`.github/workflows/test-reusable-workflows.yml`) to:

1. **Validate detection** - Ensure workflows catch known issues
2. **Prevent false negatives** - Test patterns should trigger detection
3. **Confirm clean files pass** - Clean patterns should not trigger alerts

## Important Notes

- All secrets in these files are **FAKE** and for testing only
- Vulnerable code patterns are intentionally insecure for testing
- Do not use any patterns from `owasp/` in production code
- The `deps/package.json` contains outdated versions on purpose

## Adding New Fixtures

When adding test fixtures:

1. Create files with obvious, detectable patterns
2. Include a clean file as a negative test case
3. Add comments explaining what should be detected
4. Update the test workflow to include new fixture paths
