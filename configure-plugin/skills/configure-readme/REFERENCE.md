# configure-readme Reference

Slim README and `docs/` page templates, the section-to-page map, badge
reference, and report formats. (Absorbed the former `readme-standards`
reference skill.)

## Why slim

A long README (features, tech stack, getting started, usage, structure,
development, contributing) grows past 200 lines on a project with real users.
It is hard to scan, and the same file is rendered on package registries and
often shipped inside release archives. The slim README answers three questions
(what is it, how do I try it, where is the rest) and links into `docs/` for
everything else. One user-facing CLI went from 215 README lines to 65 with this
split.

## Section-to-Page Map

Classify each `##` section of an existing README by its heading and content.
Create a `docs/` page only when at least one section maps to it.

| README section (common headings) | Action | Destination |
|----------------------------------|--------|-------------|
| Logo, title, tagline, badges | keep | README header |
| Description, About, Overview | keep, trim to 2–3 sentences | README |
| Installation, Getting Started, Quick Start | keep install + one example; move the rest | README Quick Start, remainder to `docs/usage.md` |
| Documentation, Docs | keep, rebuild as the index table | README |
| License, Licence | keep | README |
| Features, Highlights | move | `docs/usage.md` (intro) or `docs/architecture.md` when it describes internals |
| Usage, CLI, Commands, Examples, Recipes, Outputs | move | `docs/usage.md` |
| Configuration, Options, Environment Variables, Settings | move | `docs/configuration.md` |
| Architecture, Pipeline, How It Works, Tech Stack, Design | move | `docs/architecture.md` (or `docs/pipeline.md` for a staged tool) |
| Project Structure, Layout | move | `docs/development.md` |
| Development, Building, Testing, Linting, Checks | move | `docs/development.md` |
| Contributing, Releases, Changelog | move | `docs/development.md` (link CONTRIBUTING.md / CHANGELOG.md when they exist) |
| API, API Reference | move | `docs/api.md`, or the generated reference from `/configure:docs` |
| Demo, Screenshots | keep one screenshot or link in the header; move galleries | `docs/usage.md` |
| Status, Roadmap, FAQ, Troubleshooting | move | `docs/usage.md` (FAQ, troubleshooting) or `docs/development.md` (status, roadmap) |

An unknown heading goes to the page whose topic it shares; ask with
AskUserQuestion when two pages fit equally.

## Slim README Template

````markdown
<div align="center">

<img src="assets/logo.png" alt="PROJECT_NAME logo" width="128" height="128">

# PROJECT_NAME

[![License](https://img.shields.io/github/license/OWNER/REPO)](LICENSE)
[![CI](https://img.shields.io/github/actions/workflow/status/OWNER/REPO/ci.yml?branch=main&label=CI)](https://github.com/OWNER/REPO/actions)
[![Release](https://img.shields.io/github/v/release/OWNER/REPO)](https://github.com/OWNER/REPO/releases)

</div>

PROJECT_NAME does WHAT for WHOM. One sentence on how it works or what makes it
different. Optionally one sentence on scope or status.

## Quick Start

```bash
INSTALL_COMMAND
EXAMPLE_COMMAND
```

| Output | Contents |
|--------|----------|
| `OUTPUT_FILE_1` | What the file holds |
| `OUTPUT_FILE_2` | What the file holds |

## Documentation

| Page | Contents |
|------|----------|
| [Usage](docs/usage.md) | Command line, configs, outputs, recipes |
| [Configuration](docs/configuration.md) | Options and environment variables |
| [Architecture](docs/architecture.md) | Stages, components, technology |
| [Development](docs/development.md) | Building, checks, layout, contributing, releases |

## License

[LICENSE_TYPE](LICENSE)
````

Template rules:

- Drop the outputs table when the tool writes no files (a library, a service).
- List only the `docs/` pages that exist in the documentation index.
- A multi-step install (for example a Homebrew tap: `brew tap`, then
  `brew install`) stays in the Quick Start block; alternative install methods
  go to `docs/usage.md`.
- Library: the example is a three-to-five-line import-and-call snippet in the
  project's language instead of a shell command.
- Web application: the example is the run command plus the local URL; a live
  demo link goes in the header.

## docs/ Page Templates

Each page opens with a `#` title and a one-line statement of what it covers.
Moved sections keep their text and drop one heading level.

### docs/usage.md

````markdown
# Usage

How to run PROJECT_NAME: the command line, configs, outputs and common recipes.
Start with the [Quick Start](../README.md#quick-start) if you have not
installed it yet.

## Command line

```bash
PROJECT_NAME <command> [options]
```

| Command | Purpose |
|---------|---------|
| `COMMAND` | What it does |

## Outputs

## Recipes
````

### docs/configuration.md

````markdown
# Configuration

Every option PROJECT_NAME reads, where it reads it from, and the defaults.

| Option | Environment variable | Default | Purpose |
|--------|----------------------|---------|---------|
````

### docs/architecture.md

````markdown
# Architecture

How PROJECT_NAME is built: its stages or components and the technology behind
them.

## Stages

## Technology

| Category | Technology |
|----------|------------|
````

### docs/development.md

````markdown
# Development

Building PROJECT_NAME from source, running the checks, the project layout,
and how changes are contributed and released.

## Building

```bash
INSTALL_DEPS_COMMAND
BUILD_COMMAND
```

## Checks

```bash
TEST_COMMAND
LINT_COMMAND
```

## Layout

```
PROJECT_NAME/
├── src/      # Source code
├── tests/    # Tests
└── docs/     # Documentation
```

## Contributing

## Releases
````

## Link Check

`scripts/check-readme-links.sh --project-dir <dir>` resolves every relative
link in the project's Markdown files (README.md, `docs/`, and any other `*.md`,
such as skills that cite README sections). It skips external URLs, code spans,
fenced code, and `node_modules`/`vendor`/`target`/`dist`/`build`/`.venv`.

| Key | Meaning |
|-----|---------|
| `FILES_SCANNED` | Markdown files read |
| `LINKS_CHECKED` | Relative links resolved |
| `BROKEN_LINKS` | Links whose file or directory does not exist |
| `BROKEN_ANCHORS` | Links whose `#anchor` matches no heading (GitHub slug rules) or `<a id>` in the target |
| `STATUS` | `OK` (exit 0) or `ERROR` (exit 1); `REASON=` names the first finding |

Each finding is an `ISSUES:` row with `TYPE=broken_link|broken_anchor|readme_missing`,
`FILE=`, `LINE=` and `TARGET=`. The usual fix after a split is to point the link
at the new page: `README.md#configuration` becomes `docs/configuration.md`.

## Package File Format Examples

### package.json (JavaScript/TypeScript)

```javascript
{
  "name": "project-name",
  "description": "Project description",
  "version": "1.0.0",
  "license": "MIT",
  "repository": { "url": "github:owner/repo" },
  "keywords": ["keyword1", "keyword2"]
}
```

### pyproject.toml (Python)

```toml
[project]
name = "project-name"
description = "Project description"
version = "1.0.0"
license = "MIT"
keywords = ["keyword1", "keyword2"]

[project.urls]
Repository = "https://github.com/owner/repo"
```

### Cargo.toml (Rust)

```toml
[package]
name = "project-name"
description = "Project description"
version = "1.0.0"
license = "MIT"
repository = "https://github.com/owner/repo"
keywords = ["keyword1", "keyword2"]
```

### go.mod (Go)

```
module github.com/owner/repo
```

## Compliance Report Format

```
README.md Compliance Report (slim shape)
========================================
Project: [name]
README lines: [N]

Kept in README:
  Header (logo/banner)   [PASS | MISSING | N/A (no assets)]
  Title                  [PASS | MISSING]
  Badges                 [PASS | PARTIAL | MISSING]
  Description            [PASS | TOO LONG | MISSING]   (2–3 sentences)
  Quick start            [PASS | PARTIAL | MISSING]    (install + one example)
  Documentation index    [PASS | INCOMPLETE | MISSING] (links every docs/ page)
  License                [PASS | MISSING]

Detail sections still in README:
  Features               MOVE → docs/usage.md
  Tech Stack             MOVE → docs/architecture.md
  Development            MOVE → docs/development.md

docs/ pages:
  docs/usage.md          [EXISTS | WILL CREATE]
  docs/development.md    [EXISTS | WILL CREATE]

Links (check-readme-links.sh):
  STATUS=[OK | ERROR]  BROKEN_LINKS=[N]  BROKEN_ANCHORS=[N]

References to README sections outside README.md: [N]

Overall: [X issues found]
```

A quick start that has an install command but no example command is
`PARTIAL`, not `MISSING`.

## Results Report Format

```
README.md Configuration Results
===============================
Project: [name]
README: [old] → [new] lines

Moved:
  Features, Usage        → docs/usage.md (created)
  Tech Stack             → docs/architecture.md (created)
  Development, Contributing, Project Structure → docs/development.md (merged)

README now holds: header, badges, description, quick start, documentation index, license

References repointed:
  skills/status/SKILL.md:12  README.md#status → docs/development.md#status

Link check: STATUS=OK (LINKS_CHECKED=[N])

Next Steps:
  - Review the moved text for sentences that assumed the README context
  - Add a logo or banner to assets/ (optional)
  - Run /configure:github-pages to publish docs/ as a site (optional)
```

## Badge URL Patterns

### Standard Shields.io Badges

| Badge Type | URL Pattern |
|------------|-------------|
| License | `https://img.shields.io/github/license/OWNER/REPO` |
| Stars | `https://img.shields.io/github/stars/OWNER/REPO` |
| Forks | `https://img.shields.io/github/forks/OWNER/REPO` |
| Issues | `https://img.shields.io/github/issues/OWNER/REPO` |
| CI Status | `https://img.shields.io/github/actions/workflow/status/OWNER/REPO/WORKFLOW.yml` |
| Version | `https://img.shields.io/github/v/release/OWNER/REPO` |
| npm | `https://img.shields.io/npm/v/PACKAGE` |
| PyPI | `https://img.shields.io/pypi/v/PACKAGE` |
| Crates.io | `https://img.shields.io/crates/v/PACKAGE` |

### Runtime/Tech Badges

| Technology | Badge URL |
|------------|-----------|
| Bun | `https://img.shields.io/badge/runtime-Bun-f9f1e1` |
| Node.js | `https://img.shields.io/badge/node-%3E%3D20-brightgreen` |
| TypeScript | `https://img.shields.io/badge/TypeScript-5.x-blue` |
| Python | `https://img.shields.io/badge/python-3.12-blue` |
| Rust | `https://img.shields.io/badge/rust-1.75+-orange` |
| Go | `https://img.shields.io/badge/go-1.22-00ADD8` |

Keep the badge row to three to five badges; a version, CI and licence badge
cover most projects.

## Logo Guidelines

- **Format**: PNG (with transparency) or SVG
- **Size**: 128x128px to 512x512px; a banner can be wider
- **Location**: `assets/logo.png` or `assets/icon.svg`
- **Centering**: `<div align="center"><img src="assets/logo.png" alt="Project Name" width="128"></div>`

### Placeholder Logo

When no logo exists, use a centered title, optionally with a project-type emoji:

```markdown
<div align="center">

# 🚀 PROJECT_NAME

</div>
```

| Emoji | Project type |
|-------|--------------|
| 🚀 | General/deployment tools |
| 🛠️ | Developer tools |
| 📊 | Data/analytics |
| 🔒 | Security |
| 🌐 | Web applications |
| 📱 | Mobile apps |
| 🤖 | AI/ML projects |
| 📦 | Package/library |

Tools for creating logos:
- [Shields.io](https://shields.io) for custom badges
- [Simple Icons](https://simpleicons.org) for technology icons
- AI image generators for custom logos

## Section Writing Standards

### Description — say what it does, for whom

**Good:**
```markdown
widget-cli turns scanner output into searchable photo albums. It discovers
eSCL scanners on the local network and crops each photo out of a multi-photo
scan.
```

**Compare — implementation-focused (less effective):**
```markdown
A Rust CLI using mDNS and an edge-detection algorithm.
```

### Features in docs/usage.md — write benefits, not implementation

```markdown
- **Automatic Scanner Detection** - Discovers eSCL-compatible scanners via mDNS without manual configuration
- **Smart Photo Separation** - Detects and crops multiple photos from a single scan
```

### Layout in docs/development.md — keep it scannable

- 2-3 levels deep, only meaningful directories, brief comments for
  non-obvious folders

## Cookiecutter Integration

For creating entire new projects from templates, consider
[cookiecutter](https://cookiecutter.readthedocs.io/) (`uv tool install
cookiecutter`, then `cookiecutter <template-url>`). Cookiecutter is ideal for
organization-wide templates and whole-project scaffolding; `/configure:readme`
is better for updating existing projects and compliance-checking existing
READMEs.
