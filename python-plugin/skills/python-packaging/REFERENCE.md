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
