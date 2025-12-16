---
name: python-packaging
description: |
  Build and publish Python packages with uv and modern build tools. Covers uv build,
  uv publish, pyproject.toml, versioning, entry points, and PyPI publishing.
  Use when user mentions building packages, publishing to PyPI, uv build, uv publish,
  package distribution, or Python wheel/sdist creation.
---

# Python Packaging

Quick reference for building and publishing Python packages with UV and modern build tools.

## When This Skill Applies

- Building Python packages (wheels, sdists)
- Publishing to PyPI or private indexes
- Package versioning
- Build system configuration
- Editable installations

## Quick Reference

### Building Packages

```bash
# Build package
uv build

# Build specific formats
uv build --wheel
uv build --sdist

# Output location: dist/
```

### Publishing

```bash
# Publish to PyPI
uv publish

# With token
uv publish --token $PYPI_TOKEN

# To Test PyPI
uv publish --publish-url https://test.pypi.org/legacy/
```

### Package Structure

```
my-package/
├── pyproject.toml
├── README.md
├── LICENSE
├── src/
│   └── my_package/
│       ├── __init__.py
│       ├── __version__.py
│       └── main.py
└── tests/
```

## pyproject.toml Configuration

```toml
[project]
name = "my-package"
version = "0.1.0"
description = "A great package"
readme = "README.md"
requires-python = ">=3.11"
license = {text = "MIT"}
authors = [
    {name = "Your Name", email = "you@example.com"}
]
keywords = ["python", "package"]
classifiers = [
    "Development Status :: 4 - Beta",
    "Intended Audience :: Developers",
    "Programming Language :: Python :: 3",
    "Programming Language :: Python :: 3.11",
]

dependencies = [
    "requests>=2.31.0",
]

[project.optional-dependencies]
dev = ["pytest", "ruff", "mypy"]

[project.urls]
Homepage = "https://github.com/user/my-package"
Documentation = "https://my-package.readthedocs.io"
Repository = "https://github.com/user/my-package.git"
Issues = "https://github.com/user/my-package/issues"

[project.scripts]
my-cli = "my_package.cli:main"

[build-system]
requires = ["uv_build>=0.9.2,<0.10.0"]
build-backend = "uv_build"
```

## Versioning

```toml
[project]
version = "0.1.0"  # Manual versioning

# Dynamic versioning (from git tags)
dynamic = ["version"]

[tool.uv]
version-provider = "git"
```

## Entry Points

```toml
[project.scripts]
my-cli = "my_package.cli:main"

[project.gui-scripts]
my-gui = "my_package.gui:main"

[project.entry-points."my_plugin"]
plugin1 = "my_package.plugins:plugin1"
```

## Build Backends

### UV Build (default)

```toml
[build-system]
requires = ["uv_build>=0.9.2,<0.10.0"]
build-backend = "uv_build"
```

### Setuptools

```toml
[build-system]
requires = ["setuptools>=68", "wheel"]
build-backend = "setuptools.build_meta"
```

### Hatchling

```toml
[build-system]
requires = ["hatchling>=1.18"]
build-backend = "hatchling.build"
```

## Common Workflows

### Publish to PyPI

```bash
# 1. Build
uv build

# 2. Check built packages
ls dist/

# 3. Publish
uv publish --token $PYPI_TOKEN
```

### Test PyPI First

```bash
# Publish to Test PyPI
uv publish --publish-url https://test.pypi.org/legacy/ \
           --token $TEST_PYPI_TOKEN

# Test installation
pip install --index-url https://test.pypi.org/simple/ my-package
```

## Package Classifiers

Common classifiers:

```toml
classifiers = [
    # Development Status
    "Development Status :: 3 - Alpha",
    "Development Status :: 4 - Beta",
    "Development Status :: 5 - Production/Stable",

    # Audience
    "Intended Audience :: Developers",
    "Intended Audience :: Science/Research",

    # License
    "License :: OSI Approved :: MIT License",

    # Python Versions
    "Programming Language :: Python :: 3",
    "Programming Language :: Python :: 3.11",
    "Programming Language :: Python :: 3.12",

    # Framework
    "Framework :: Django",
    "Framework :: FastAPI",

    # Topic
    "Topic :: Software Development :: Libraries",
    "Topic :: Scientific/Engineering",
]
```

Full list: https://pypi.org/classifiers/

## See Also

- `uv-project-management` - Project setup and dependencies
- `python-development` - Core Python patterns
- `uv-workspaces` - Building workspace packages

## References

- UV build: https://docs.astral.sh/uv/guides/publish/
- PyPI: https://pypi.org/
- Detailed guide: See REFERENCE.md
