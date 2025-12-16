# VectorCode Pattern Reference

Common include and exclude patterns for different project types.

## Pattern Syntax

VectorCode uses gitignore-style glob patterns:
- `*` matches any string (except `/`)
- `**` matches any string including `/` (recursive)
- `?` matches any single character
- `[abc]` matches one character from set
- `!pattern` negates a pattern (include despite exclusion)

## Include Patterns by Language

### Python
```gitignore
**/*.py
**/*.pyi
**/pyproject.toml
**/setup.py
**/setup.cfg
**/requirements.txt
**/Pipfile
**/poetry.lock
**/.python-version
```

### JavaScript/TypeScript
```gitignore
**/*.js
**/*.jsx
**/*.ts
**/*.tsx
**/*.mjs
**/*.cjs
**/package.json
**/package-lock.json
**/tsconfig.json
**/jsconfig.json
**/.nvmrc
```

### Rust
```gitignore
**/*.rs
**/Cargo.toml
**/Cargo.lock
**/rust-toolchain.toml
```

### Go
```gitignore
**/*.go
**/go.mod
**/go.sum
**/go.work
```

### Ruby
```gitignore
**/*.rb
**/*.rake
**/Gemfile
**/Gemfile.lock
**/.ruby-version
**/Rakefile
```

### Java/Kotlin
```gitignore
**/*.java
**/*.kt
**/*.kts
**/pom.xml
**/build.gradle
**/build.gradle.kts
**/settings.gradle
**/gradle.properties
```

### C/C++
```gitignore
**/*.c
**/*.cpp
**/*.cc
**/*.cxx
**/*.h
**/*.hpp
**/*.hxx
**/CMakeLists.txt
**/Makefile
**/meson.build
```

### Shell Scripts
```gitignore
**/*.sh
**/*.bash
**/*.zsh
**/*.fish
```

### Configuration Files
```gitignore
**/*.yaml
**/*.yml
**/*.json
**/*.toml
**/*.ini
**/*.conf
**/*.config
**/.env.example
```

### Documentation
```gitignore
**/*.md
**/*.rst
**/*.txt
**/README*
**/CHANGELOG*
**/LICENSE*
**/CONTRIBUTING*
```

### Infrastructure as Code
```gitignore
**/*.tf
**/*.tfvars
**/Dockerfile
**/docker-compose.yml
**/docker-compose.yaml
**/*.nomad
**/Vagrantfile
```

### CI/CD
```gitignore
.github/workflows/*.yml
.github/workflows/*.yaml
.gitlab-ci.yml
.circleci/config.yml
azure-pipelines.yml
**/Jenkinsfile
```

## Common Exclude Patterns

### Package Managers & Dependencies
```gitignore
node_modules/
vendor/
third_party/
.bundle/
bower_components/
jspm_packages/
packages/
.pnpm-store/
```

### Build Artifacts
```gitignore
dist/
build/
out/
target/
bin/
obj/
*.exe
*.dll
*.so
*.dylib
*.class
*.o
*.a
*.lib
```

### Python Artifacts
```gitignore
__pycache__/
*.py[cod]
*$py.class
.Python
.venv/
venv/
env/
ENV/
.pytest_cache/
.mypy_cache/
.ruff_cache/
*.egg-info/
.eggs/
pip-cache/
```

### Node.js Artifacts
```gitignore
.npm/
.yarn/
.cache/
.parcel-cache/
.next/
.nuxt/
.vuepress/dist/
.serverless/
.fusebox/
```

### IDE & Editor Files
```gitignore
.vscode/
.idea/
*.swp
*.swo
*~
.DS_Store
Thumbs.db
*.sublime-project
*.sublime-workspace
```

### Version Control
```gitignore
.git/
.svn/
.hg/
```

### Test Coverage & Reports
```gitignore
coverage/
.coverage
htmlcov/
.nyc_output/
*.lcov
```

### Logs & Temporary Files
```gitignore
*.log
logs/
*.tmp
*.temp
tmp/
temp/
```

### Documentation Build Outputs
```gitignore
docs/_build/
site/
_site/
.docusaurus/
```

### Rust Specific
```gitignore
target/
Cargo.lock
**/*.rs.bk
```

### Go Specific
```gitignore
*.test
*.out
vendor/
```

### Java Specific
```gitignore
.gradle/
.m2/
*.jar
*.war
*.ear
```

### Database Files
```gitignore
*.db
*.sqlite
*.sqlite3
```

### Environment & Secrets
```gitignore
.env
.env.local
.env.*.local
*.pem
*.key
secrets/
```

## Project Type Detection Heuristics

### Detection Rules

**Python Project:**
- Has `pyproject.toml`, `setup.py`, or `requirements.txt`
- OR has `*.py` files in root or `src/`

**Node.js Project:**
- Has `package.json`
- OR has `node_modules/` directory

**Rust Project:**
- Has `Cargo.toml`
- OR has `*.rs` files

**Go Project:**
- Has `go.mod` or `go.sum`
- OR has `*.go` files

**Ruby Project:**
- Has `Gemfile` or `*.gemspec`
- OR has `*.rb` files

**Java/Kotlin Project:**
- Has `pom.xml`, `build.gradle`, or `build.gradle.kts`

**C/C++ Project:**
- Has `CMakeLists.txt` or `Makefile`
- OR has `*.c`, `*.cpp` files

**Infrastructure/DevOps:**
- Has `Dockerfile`, `*.tf`, or `docker-compose.yml`

## Multi-Language Projects

For repositories containing multiple languages:
1. Detect all project types present
2. Combine include patterns from all detected types
3. Use union of exclude patterns
4. Prioritize more specific patterns

Example for Python + Node.js monorepo:
```gitignore
# Python
**/*.py
**/pyproject.toml

# Node.js
**/*.js
**/*.ts
**/package.json

# Shared config
**/*.yaml
**/*.json

# Exclude both ecosystems
node_modules/
__pycache__/
dist/
```

## Special Cases

### Monorepos
For monorepos with multiple projects:
```gitignore
# Include all projects
packages/*/src/**/*.ts
apps/*/src/**/*.ts

# Exclude all build outputs
packages/*/dist/
apps/*/dist/
```

### Documentation Sites
For projects with separate documentation:
```gitignore
# Include docs
docs/**/*.md
docs/**/*.mdx

# Exclude built docs
docs/_build/
docs/.vuepress/dist/
```

### Test Files
Include tests for comprehensive code search:
```gitignore
**/*.test.js
**/*.spec.js
**/*.test.ts
**/*.spec.ts
**/test_*.py
**/*_test.go
```

Exclude if you want production code only:
```gitignore
**/*.test.*
**/*.spec.*
**/tests/
**/test/
**/__tests__/
```

## Performance Tips

1. **Be Specific**: Use `src/**/*.ts` instead of `**/*.ts` when possible
2. **Exclude Early**: Large directories like `node_modules/` should be excluded first
3. **Be Distinct**: Include only non-overlapping patterns
4. **Test Patterns**: Use `vectorcode ls` to verify what gets indexed
5. **Iterate**: Start narrow and expand as needed

## Pattern Testing

Verify patterns work as expected:
```bash
# List what would be included
vectorcode ls

# Check specific file
vectorcode query "filename:your-file.py"

# Test after adding pattern
echo "new-pattern" >> vectorcode.include
vectorcode vectorise .
vectorcode ls
```
