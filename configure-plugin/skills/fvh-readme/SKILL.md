---
created: 2025-12-17
modified: 2025-12-17
reviewed: 2025-12-17
---

# FVH README Standards (v2025.1)

This skill provides README.md templates and standards for FVH projects.

## Overview

A well-structured README is the front door to your project. It should:
- Immediately communicate what the project does
- Look professional with proper branding
- Provide clear getting started instructions
- Be scannable with good visual hierarchy

## Template Styles

### Minimal Style

Best for: Libraries, small utilities, internal tools

```markdown
# project-name

[![License](https://img.shields.io/github/license/OWNER/REPO)](LICENSE)

Brief description of what this project does.

## Installation

```bash
npm install package-name
```

## Usage

```javascript
import { feature } from 'package-name';
feature();
```

## License

MIT
```

### Standard Style (Recommended)

Best for: Most projects, applications, services

```markdown
<div align="center">

<img src="assets/logo.png" alt="Project Logo" width="128">

# Project Name

**A compelling tagline that explains the project's purpose**

[![License](https://img.shields.io/github/license/OWNER/REPO)](LICENSE)
[![GitHub stars](https://img.shields.io/github/stars/OWNER/REPO)](https://github.com/OWNER/REPO/stargazers)
[![CI](https://img.shields.io/github/actions/workflow/status/OWNER/REPO/ci.yml?branch=main)](https://github.com/OWNER/REPO/actions)
[![TypeScript](https://img.shields.io/badge/TypeScript-5.x-blue)]()

</div>

## Features

- **Feature One** - Description of the first key capability
- **Feature Two** - Description of the second key capability
- **Feature Three** - Description of the third key capability
- **Feature Four** - Description of the fourth key capability

## Tech Stack

| Category | Technology |
|----------|------------|
| Runtime | Bun 1.x |
| Framework | Fastify |
| Frontend | React 18, Vite |
| Database | SQLite (Drizzle ORM) |
| Testing | Vitest, Playwright |

## Getting Started

### Prerequisites

- [Bun](https://bun.sh) >= 1.0
- [Node.js](https://nodejs.org) >= 20 (optional)

### Installation

```bash
# Clone the repository
git clone https://github.com/OWNER/REPO.git
cd REPO

# Install dependencies
bun install

# Start development server
bun run dev
```

### Development Commands

```bash
bun run dev      # Start development server
bun run build    # Build for production
bun run test     # Run tests
bun run lint     # Run linter
```

## Project Structure

```
project-name/
├── src/
│   ├── client/          # Frontend React application
│   │   ├── components/  # UI components
│   │   └── stores/      # State management
│   ├── server/          # Backend Fastify server
│   │   ├── routes/      # API endpoints
│   │   └── services/    # Business logic
│   └── shared/          # Shared types and utilities
├── tests/               # Test files
├── docs/                # Documentation
└── README.md
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the [MIT License](LICENSE).
```

### Detailed Style

Best for: Open source projects, documentation-heavy projects, developer tools

Includes everything from Standard plus:
- Architecture diagrams (Mermaid)
- API reference section
- Detailed configuration options
- Changelog link
- Security policy
- Code of conduct reference

## Badge Reference

### Repository Status Badges

```markdown
<!-- License -->
[![License](https://img.shields.io/github/license/OWNER/REPO)](LICENSE)

<!-- Stars -->
[![Stars](https://img.shields.io/github/stars/OWNER/REPO)](https://github.com/OWNER/REPO/stargazers)

<!-- Forks -->
[![Forks](https://img.shields.io/github/forks/OWNER/REPO)](https://github.com/OWNER/REPO/network/members)

<!-- Issues -->
[![Issues](https://img.shields.io/github/issues/OWNER/REPO)](https://github.com/OWNER/REPO/issues)

<!-- Last Commit -->
[![Last Commit](https://img.shields.io/github/last-commit/OWNER/REPO)](https://github.com/OWNER/REPO/commits)
```

### CI/CD Status Badges

```markdown
<!-- GitHub Actions -->
[![CI](https://img.shields.io/github/actions/workflow/status/OWNER/REPO/ci.yml?branch=main&label=CI)](https://github.com/OWNER/REPO/actions)

<!-- With specific workflow -->
[![Build](https://img.shields.io/github/actions/workflow/status/OWNER/REPO/build.yml?branch=main&label=build)](https://github.com/OWNER/REPO/actions/workflows/build.yml)

<!-- Codecov -->
[![codecov](https://codecov.io/gh/OWNER/REPO/branch/main/graph/badge.svg)](https://codecov.io/gh/OWNER/REPO)
```

### Package Registry Badges

```markdown
<!-- npm -->
[![npm](https://img.shields.io/npm/v/PACKAGE)](https://www.npmjs.com/package/PACKAGE)
[![npm downloads](https://img.shields.io/npm/dm/PACKAGE)](https://www.npmjs.com/package/PACKAGE)

<!-- PyPI -->
[![PyPI](https://img.shields.io/pypi/v/PACKAGE)](https://pypi.org/project/PACKAGE/)
[![Python Version](https://img.shields.io/pypi/pyversions/PACKAGE)](https://pypi.org/project/PACKAGE/)

<!-- Crates.io -->
[![Crates.io](https://img.shields.io/crates/v/PACKAGE)](https://crates.io/crates/PACKAGE)
[![docs.rs](https://docs.rs/PACKAGE/badge.svg)](https://docs.rs/PACKAGE)

<!-- Go -->
[![Go Reference](https://pkg.go.dev/badge/github.com/OWNER/REPO.svg)](https://pkg.go.dev/github.com/OWNER/REPO)
```

### Technology Badges

```markdown
<!-- Runtime/Language -->
[![TypeScript](https://img.shields.io/badge/TypeScript-5.x-3178C6?logo=typescript&logoColor=white)]()
[![Python](https://img.shields.io/badge/Python-3.12-3776AB?logo=python&logoColor=white)]()
[![Rust](https://img.shields.io/badge/Rust-1.75+-DEA584?logo=rust&logoColor=white)]()
[![Go](https://img.shields.io/badge/Go-1.22-00ADD8?logo=go&logoColor=white)]()

<!-- Runtime -->
[![Bun](https://img.shields.io/badge/Bun-1.x-f9f1e1?logo=bun&logoColor=black)]()
[![Node.js](https://img.shields.io/badge/Node.js-20+-339933?logo=node.js&logoColor=white)]()
[![Deno](https://img.shields.io/badge/Deno-1.x-000000?logo=deno&logoColor=white)]()

<!-- Frameworks -->
[![React](https://img.shields.io/badge/React-18-61DAFB?logo=react&logoColor=black)]()
[![Vue](https://img.shields.io/badge/Vue-3-4FC08D?logo=vue.js&logoColor=white)]()
[![Fastify](https://img.shields.io/badge/Fastify-4-000000?logo=fastify&logoColor=white)]()
[![FastAPI](https://img.shields.io/badge/FastAPI-0.100+-009688?logo=fastapi&logoColor=white)]()
```

## Logo Guidelines

### Recommended Specifications

- **Format**: PNG (with transparency) or SVG
- **Size**: 128x128px to 512x512px
- **Location**: `assets/logo.png` or `assets/icon.svg`

### Centering Logo

```markdown
<div align="center">
<img src="assets/logo.png" alt="Project Name" width="128">
</div>
```

### Using Emoji as Placeholder

If no logo exists:

```markdown
<div align="center">

# 🚀 Project Name

</div>
```

Common project type emojis:
- 🚀 - General/deployment tools
- 🛠️ - Developer tools
- 📊 - Data/analytics
- 🔒 - Security
- 🌐 - Web applications
- 📱 - Mobile apps
- 🤖 - AI/ML projects
- 📦 - Package/library

## Section Guidelines

### Features Section

Write features as benefits, not just capabilities:

**Good:**
```markdown
- **Automatic Scanner Detection** - Discovers eSCL-compatible scanners via mDNS without manual configuration
- **Smart Photo Separation** - Intelligently detects and crops multiple photos from a single scan using edge analysis
```

**Avoid:**
```markdown
- Uses mDNS for scanner discovery
- Has edge detection algorithm
```

### Tech Stack Section

Use a table for clarity:

```markdown
| Category | Technology |
|----------|------------|
| Runtime | Bun 1.x |
| Server | Fastify 4 |
| Frontend | React 18, Tailwind CSS |
| Database | SQLite (Drizzle ORM) |
```

### Getting Started Section

Always include:
1. Prerequisites with version requirements
2. Clone instructions
3. Install dependencies command
4. Run command
5. (Optional) Environment setup

### Project Structure Section

- Keep it to 2-3 levels deep
- Only show meaningful directories
- Add brief comments for non-obvious folders

```
project/
├── src/           # Source code
├── tests/         # Test files
├── docs/          # Documentation
└── scripts/       # Build/dev scripts
```

## Project Type Specific Templates

### CLI Tool

```markdown
## Installation

```bash
# With npm
npm install -g tool-name

# With Bun
bun install -g tool-name

# Or run directly
npx tool-name
```

## Usage

```bash
tool-name <command> [options]

Commands:
  init     Initialize a new project
  build    Build the project
  deploy   Deploy to production

Options:
  -h, --help     Show help
  -v, --version  Show version
```
```

### Library/Package

```markdown
## Installation

```bash
npm install package-name
# or
bun add package-name
```

## Usage

```typescript
import { feature } from 'package-name';

const result = feature({
  option: 'value'
});
```

## API

### `feature(options)`

Description of the function.

**Parameters:**
- `options.key` (string) - Description

**Returns:** `ReturnType` - Description
```

### Web Application

```markdown
## Demo

🌐 [Live Demo](https://demo.example.com)

## Screenshots

<div align="center">
<img src="docs/screenshots/dashboard.png" alt="Dashboard" width="600">
</div>

## Environment Variables

Create a `.env` file:

```env
DATABASE_URL=postgresql://...
API_KEY=your-api-key
```
```

## Compliance Checklist

### Minimal Style
- [ ] Title (h1)
- [ ] Description (1-2 sentences)
- [ ] License badge
- [ ] Installation instructions
- [ ] Basic usage example
- [ ] License section

### Standard Style (all of minimal plus)
- [ ] Logo or emoji header
- [ ] 3+ badges (license, stars, CI)
- [ ] Features section (4+ items)
- [ ] Tech stack table
- [ ] Prerequisites
- [ ] Development commands
- [ ] Project structure
- [ ] Contributing mention

### Detailed Style (all of standard plus)
- [ ] Architecture diagram
- [ ] API reference or link
- [ ] Configuration options
- [ ] Changelog link
- [ ] Security policy mention
- [ ] Code of conduct mention

## Cookiecutter Integration

For creating entire new projects from templates, consider using [cookiecutter](https://cookiecutter.readthedocs.io/):

```bash
# Install cookiecutter
pip install cookiecutter
# or
uv tool install cookiecutter

# Create project from template
cookiecutter https://github.com/your-org/project-template
```

Cookiecutter is ideal for:
- Creating multiple projects with consistent structure
- Organization-wide project templates
- Including not just README but entire project scaffolding

The `/configure:readme` command is better for:
- Updating existing projects
- Generating README for projects that already have code
- Compliance checking of existing READMEs
