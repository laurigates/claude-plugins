---
created: 2025-12-17
modified: 2026-11-13
reviewed: 2026-02-08
description: "Slim README.md (badges, quick start, docs index) with the detail moved into docs/ pages. Use when creating or auditing a README, splitting a long one, or adding badges."
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite, WebSearch
args: "[--check-only] [--fix] [--badges <shields|custom>] [--no-logo]"
argument-hint: "[--check-only] [--fix] [--badges <shields|custom>] [--no-logo]"
name: configure-readme
---

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Creating a README.md for a new project from scratch | Editing specific README content — use direct file editing |
| Splitting a long README into a slim README plus `docs/` pages | Writing detailed API documentation — use `/configure:docs` |
| Auditing a README against the slim shape (header, description, quick start, docs index, licence) | Creating a GitHub Pages documentation site — use `/configure:github-pages` |
| Adding shields.io badges or a documentation index table | Writing a changelog — use release-please automation via conventional commits |
| Ensuring the quick start uses the correct install command for the detected stack | Only need to update a single section — edit the file directly |

## The Slim Shape

The README is the only template. It is read on the repository page, on package
registries and often inside release archives, so it stays short and points into
`docs/` for everything else.

| README.md keeps | `docs/` gets (only pages that have content) |
|-----------------|---------------------------------------------|
| Header: logo or banner, title, badges | `usage.md` — command line, configs, outputs, recipes |
| What the project does, in two or three sentences | `configuration.md` — options, environment variables, config files |
| Quick start: install, one example command, an outputs table where the tool writes files | `architecture.md` (or `pipeline.md`) — stages, components, technology |
| Documentation index: a table linking each `docs/` page | `development.md` — building, checks, project layout, contributing, releases |
| Licence | |

Sections such as Features, Tech Stack, Usage reference, Configuration,
Architecture, Project Structure, Development, Contributing and Releases belong
in `docs/`. A README that carries them is non-compliant, and the fix moves them.

## Context

- Project root: !`pwd`
- Project name: !`basename $(pwd)`
- README exists: !`find . -maxdepth 1 -name 'README.md'`
- Docs pages: !`find . -maxdepth 2 -path './docs/*.md'`
- Package files: !`find . -maxdepth 1 \( -name 'package.json' -o -name 'pyproject.toml' -o -name 'Cargo.toml' -o -name 'go.mod' \)`
- Git remotes: !`git remote -v`
- License file: !`find . -maxdepth 1 -name 'LICENSE*'`
- Assets directory: !`find . -maxdepth 2 -type d \( -name 'assets' -o -name 'public' -o -name 'images' \)`
- Logo files: !`find . -maxdepth 3 -type f \( -name 'logo*' -o -name 'icon*' \)`

## Parameters

Parse from `$ARGUMENTS`:

- `--check-only`: Report compliance against the slim shape without modifications (CI/CD mode)
- `--fix`: Apply the split and README rewrite without prompting
- `--badges <shields|custom>`: Badge style preference (default: shields)
- `--no-logo`: Skip the logo even if assets exist

## Execution

Execute this README configuration workflow:

### Step 1: Detect project metadata

Read name, description, version, licence, repository and keywords from the
detected package file (`package.json`, `pyproject.toml`, `Cargo.toml`, or the
module path in `go.mod`). With no package file, fall back to the directory name,
the first line of the existing README, the git remote URL and the LICENSE file.
Package file formats are in [REFERENCE.md](REFERENCE.md).

### Step 2: Inventory the README and docs/

1. Read README.md and classify each `##` section with the section-to-page map in
   [REFERENCE.md](REFERENCE.md): **keep** (header, description, quick start,
   documentation index, licence) or **move** (and to which `docs/` page).
2. Check the kept parts: description is two or three sentences; quick start has
   an install command and one example command; the documentation index links
   every `docs/` page; badges and a licence are present.
3. Read the existing `docs/*.md` pages so moved content merges into them instead
   of duplicating.
4. Find files that point at README sections:
   `rg -n 'README(\.md)?(#|\s*§)' --glob '!node_modules'` plus prose such as
   "see the README". Each hit that names a section being moved needs repointing.

### Step 3: Report compliance

Run the link check and print the compliance report (format in
[REFERENCE.md](REFERENCE.md)): PASS / PARTIAL / MISSING for each kept part, and
`MOVE → docs/<page>.md` for each detail section still in the README.

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/check-readme-links.sh"
```

If `--check-only` is set, stop here.

### Step 4: Move the detail sections into docs/

Unless `--fix` is set, confirm the planned moves with AskUserQuestion first.

1. Create only the `docs/` pages that receive content; a project with no
   configuration gets no `configuration.md`.
2. Move each section's text as written, demoting headings one level under the
   page's `#` title. Merge into an existing page rather than creating a second
   one on the same topic.
3. Generate the project layout for `development.md` with
   `tree -L 2 -I 'node_modules|target|__pycache__|.git|dist|build' --dirsfirst`.
4. Fix relative links inside moved text: a link that was `src/x.py` from the
   root is `../src/x.py` from `docs/`.

### Step 5: Write the slim README

Write README.md from the slim template in [REFERENCE.md](REFERENCE.md): header
with logo (unless `--no-logo` or no asset exists) and badges, two or three
sentences, quick start, documentation index table, licence. Take the install and
example commands from the detected stack:

| Package Manager | Install | Run | Test | Build |
|----------------|---------|-----|------|-------|
| npm/bun (package.json) | Read `scripts` from package.json | `npm run dev` | `npm test` | `npm run build` |
| uv/poetry (pyproject.toml) | `uv sync` / `poetry install` | `uv run python -m pkg` | `uv run pytest` | - |
| cargo (Cargo.toml) | `cargo install --path .` | `cargo run` | `cargo test` | `cargo build --release` |
| go (go.mod) | `go install ./...` | `go run .` | `go test ./...` | `go build` |

Test and build commands go in `docs/development.md`, not the README.

### Step 6: Repoint references and verify links

1. Update every hit from Step 2.4 to the section's new page, for example
   `README.md#configuration` becomes `docs/configuration.md`, and prose that
   cites a README section by name cites the new page instead.
2. Re-run `check-readme-links.sh` and fix each `broken_link` / `broken_anchor`
   row until it reports `STATUS=OK`.

### Step 7: Update standards tracking

Update `.project-standards.yaml`, and remove a `readme_style` key left by an
earlier version of this skill (the slim shape is the only template):

```yaml
components:
  readme: "2026.11"
  readme_has_logo: true|false
  readme_badges: ["license", "ci", "version"]
  readme_docs_pages: ["usage", "development"]
```

### Step 8: Report results

Print the files written, the sections moved and where, the references repointed,
and the final link-check status. Results format in [REFERENCE.md](REFERENCE.md).

## Output

Provide:
1. Compliance report against the slim shape
2. The slim README.md and each `docs/` page written or updated
3. References repointed, and the link-check result
4. Suggestions (logo, badges, missing quick-start example)

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick compliance check | `/configure:readme --check-only` |
| Split and rewrite without prompting | `/configure:readme --fix` |
| Check relative links and anchors | `bash "${CLAUDE_SKILL_DIR}/scripts/check-readme-links.sh" --project-dir .` |
| Find references to README sections | `rg -n 'README(\.md)?(#\|\s*§)' --glob '!node_modules'` |
| Generate project tree | `tree -L 2 -I 'node_modules\|target\|__pycache__\|.git\|dist\|build' --dirsfirst` |

## See Also

- `/configure:docs` - Configure code documentation standards
- `/configure:github-pages` - Set up documentation hosting
- `/configure:all` - Run all compliance checks
- [REFERENCE.md](REFERENCE.md) - Slim README and docs/ page templates, section-to-page map, badge reference, report formats
