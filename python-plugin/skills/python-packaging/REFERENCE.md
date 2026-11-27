# Python Packaging - Comprehensive Reference

Complete guide to building and publishing Python packages.

## Building Packages

UV simplifies the build process:

```bash
# Build both wheel and sdist
uv build

# Build only wheel
uv build --wheel

# Build only source distribution
uv build --sdist

# Output: dist/
# - my_package-0.1.0-py3-none-any.whl
# - my_package-0.1.0.tar.gz
```

---

## Publishing

### PyPI

```bash
# Set token
export PYPI_TOKEN="pypi-..."

# Publish
uv publish --token $PYPI_TOKEN

# Or use .pypirc
uv publish
```

### Test PyPI

```bash
export TEST_PYPI_TOKEN="pypi-..."

uv publish \
  --publish-url https://test.pypi.org/legacy/ \
  --token $TEST_PYPI_TOKEN
```

### Private Index

```bash
uv publish \
  --publish-url https://private.pypi.org/simple/ \
  --token $PRIVATE_TOKEN
```

---

## Renaming a Published Package

Renaming a package already on PyPI (old name `<old>`, new name `<new>`) takes
five steps in this order. Each one was found the hard way or nearly missed on a
rename released 2026-11-25.

### 1. Trusted publishers: add before you rename

PyPI trusted publishing is bound to the GitHub owner, repository and workflow,
and PyPI matches the OIDC claims exactly; its docs do not say whether a
repository ID is used. Renaming the GitHub repository therefore breaks the
publisher on the old project.

- **Add** a second publisher for the new repository name to `<old>` before the
  repository rename, and keep the old publisher until after it.
- Register a **pending publisher** for `<new>`. A pending publisher does not
  reserve the name, so publish soon after registering it.

### 2. Publish each project in its own step

The minted OIDC token is scoped to every project that trusts the publisher
(docs.pypi.org, trusted-publisher internals). The docs do not say how one
`pypa/gh-action-pypi-publish` step routes files to two projects, so publish them
in separate steps, each with its own `packages-dir:`, `<new>` first.

### 3. The tombstone release under the old name

Publish one last release of `<old>` as a shim:

- It depends on `<new>>=<version>` and keeps the old console script.
- It writes its rename notice to **stderr only**. For a stdio server (an MCP
  server, for example) one byte on stdout breaks the protocol.
- `<new>` drops the old console script. Two installed distributions that
  declare the same console script overwrite each other's launcher.
- Gate the tombstone publish job on the exact release tag, and add a tripwire
  test that fails once the version moves past that tag
  (`testing-plugin:test-tripwire`), so the job and the shim package get removed.

### 4. Hold the release PR

With release-please, publishing runs from the tag. Land the removal and rename
PRs first and keep the release PR blocked (a label plus a comment) until the new
name is in `pyproject.toml`.

### 5. Verify both names with a fresh cache

With an empty cache (`UV_CACHE_DIR=$(mktemp -d)`), `uvx <new>@latest` and
`uvx <old>@latest` must both start and do their job (for an MCP server, answer
an `initialize` request), and the installed version must be the new one. An
index can serve the previous version for a few minutes after upload:
`github-actions-plugin:release-artifact-verification` § 5 has the simple-index
and installed-version checks.

---

## Package Metadata

All metadata goes in `pyproject.toml`:

```toml
[project]
name = "my-package"
version = "1.0.0"
description = "Short description"
readme = "README.md"
requires-python = ">=3.11"
license = {text = "MIT"}
authors = [{name = "Author", email = "email@example.com"}]
keywords = ["keyword1", "keyword2"]
classifiers = [...]
dependencies = [...]

[project.urls]
Homepage = "https://github.com/user/repo"
Documentation = "https://docs.example.com"
```

---

## Build Systems

Choose a build backend:

1. **uv_build** (recommended) - Fast, simple
2. **setuptools** - Traditional, widely supported
3. **hatchling** - Modern, feature-rich
4. **flit** - Minimal, simple
5. **poetry-core** - Poetry projects

---

## Versioning Strategies

### Manual

```toml
[project]
version = "1.0.0"
```

### Dynamic (Git tags)

```toml
[project]
dynamic = ["version"]

[tool.uv]
version-provider = "git"
```

### Semantic Versioning

- **Major**: Breaking changes (1.0.0 → 2.0.0)
- **Minor**: New features (1.0.0 → 1.1.0)
- **Patch**: Bug fixes (1.0.0 → 1.0.1)

---

## Best Practices

1. Use src/ layout
2. Include comprehensive README
3. Add license file
4. Test on Test PyPI first
5. Use semantic versioning
6. Include type hints
7. Document public API
8. Add classifiers

---

## References

- **UV Publishing**: https://docs.astral.sh/uv/guides/publish/
- **PyPI**: https://pypi.org/
- **PEP 621**: https://peps.python.org/pep-0621/ (pyproject.toml metadata)
