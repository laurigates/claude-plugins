# Test Fixtures

Test fixtures for validating reusable GitHub Action workflows.

## Structure

```
test-fixtures/
├── security/              # Phase 1: Security
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
├── quality/               # Phase 2: Code Quality
│   ├── code-smell/        # Code smell detection test cases
│   │   ├── long-function.ts    # 60+ line function
│   │   ├── deep-nesting.js     # 5+ levels of nesting
│   │   ├── magic-numbers.ts    # Unexplained numeric literals
│   │   ├── empty-catch.js      # Empty catch blocks, console.log
│   │   └── clean-code.ts       # Well-structured code
│   ├── typescript/        # TypeScript strictness test cases
│   │   ├── any-usage.ts        # Explicit any types
│   │   ├── non-null-assertion.ts # user!.name patterns
│   │   ├── missing-return-type.ts # Functions without return types
│   │   └── strict-code.ts      # Properly typed code
│   └── async/             # Async pattern test cases
│       ├── floating-promise.ts # Promises not awaited or handled
│       ├── missing-catch.js    # Promise chains without .catch()
│       ├── promise-constructor.ts # new Promise(async ...) anti-pattern
│       └── proper-async.ts     # Correct async patterns
└── a11y/                  # Phase 3: Accessibility (planned)
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
