---
model: opus
name: docs-latex
description: |
  Convert Markdown documents to professional LaTeX with TikZ visualizations and compile to PDF.
  Use when the user wants to create a presentation-quality PDF from a Markdown document, generate
  a professional report with diagrams, or convert documentation to print-ready format.
args: <file> [--no-compile] [--visualizations] [--report-type=roadmap|lifecycle|general]
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, TodoWrite
argument-hint: path/to/document.md
created: 2026-02-08
modified: 2026-02-10
reviewed: 2026-02-08
---

# Markdown to LaTeX Conversion

Convert Markdown documents to professional LaTeX with advanced typesetting, TikZ/PGFPlots visualizations, and PDF compilation.

## When to Use This Skill

| Use this skill when... | Use another skill when... |
|------------------------|--------------------------|
| Converting Markdown to presentation-quality PDF | Writing Markdown documentation (`/docs:generate`) |
| Creating reports with diagrams and visualizations | Simple text formatting |
| Generating print-ready strategic documents | Creating HTML documentation |
| Building lifecycle reports with charts and timelines | Syncing existing docs (`/docs:sync`) |

## Context

- Source file exists: !`test -f "$1" && echo "yes" || echo "no"`
- LaTeX installed: !`which pdflatex 2>/dev/null`
- Current directory: !`pwd`
- Available .md files: !`find . -maxdepth 2 -name '*.md' -not -name 'CHANGELOG.md' -not -name 'README.md' 2>/dev/null`

## Parameters

- `<file>`: Path to the Markdown source file (required)
- `--no-compile`: Generate `.tex` file only, skip PDF compilation
- `--visualizations`: Include TikZ/PGFPlots diagrams (timelines, charts, risk matrices)
- `--report-type`: Document structure preset
  - `roadmap`: Phase-based roadmap with timeline visualization
  - `lifecycle`: Project lifecycle with release charts and velocity graphs
  - `general`: Standard professional document (default)

## Execution

Execute this Markdown-to-LaTeX conversion workflow:

### Step 1: Analyze the Markdown source

Read the source Markdown file and extract:
- Document title and metadata
- Section hierarchy (map `#` levels to LaTeX chapters/sections)
- Tables, lists, code blocks, callout blocks, and blockquotes
- Priorities or status indicators for color-coded markers
- Numerical data suitable for visualization

### Step 2: Generate the LaTeX document

Create a `.tex` file adjacent to the source. Use the document preamble, color definitions, custom environments, and conversion rules from [REFERENCE.md](REFERENCE.md).

Apply the Markdown-to-LaTeX conversion rules:

| Markdown | LaTeX |
|----------|-------|
| `# Title` | `\chapter{Title}` |
| `## Section` | `\section{Section}` |
| `### Subsection` | `\subsection{Subsection}` |
| `**bold**` | `\textbf{bold}` |
| `*italic*` | `\textit{italic}` |
| `` `code` `` | `\texttt{code}` |
| `- item` | `\begin{itemize}\item ...\end{itemize}` |
| `1. item` | `\begin{enumerate}\item ...\end{enumerate}` |
| `> quote` | `\begin{tcolorbox}...\end{tcolorbox}` |
| `[text](url)` | `\href{url}{text}` |
| Tables | `booktabs` tables with `\toprule`, `\midrule`, `\bottomrule` |
| Code blocks | `\begin{lstlisting}...\end{lstlisting}` |
| `- [ ]` / `- [x]` | `$\square$` / `$\boxtimes$` (requires `amssymb`) |

### Step 3: Add visualizations (when --visualizations or data suggests it)

Choose appropriate TikZ/PGFPlots visualizations based on document content. Use the visualization templates from [REFERENCE.md](REFERENCE.md):
- **Timeline** for roadmaps with phases
- **Bar/pie charts** for release or metric data
- **Risk matrix** for documents with risk/impact data
- **Test pyramid** for QA/testing documents

### Step 4: Compile to PDF

1. Install LaTeX toolchain if not available:
   ```bash
   apt-get update && apt-get install -y texlive-latex-extra texlive-fonts-recommended \
     texlive-fonts-extra texlive-science latexmk
   ```
2. Compile with two passes for cross-references:
   ```bash
   pdflatex -interaction=nonstopmode DOCUMENT.tex
   pdflatex -interaction=nonstopmode DOCUMENT.tex
   ```
3. If compilation fails, check [REFERENCE.md](REFERENCE.md) for common compilation fixes.

### Step 5: Clean up repository artifacts

Add LaTeX build artifacts to `.gitignore` if not already present: `*.aux`, `*.log`, `*.out`, `*.toc`, `*.lof`, `*.lot`, `*.fls`, `*.fdb_latexmk`, `*.synctex.gz`, `*.bbl`, `*.blg`, `*.nav`, `*.snm`, `*.vrb`.

## Post-actions

1. Report the output PDF path, page count, and file size
2. Summarize what visualizations were generated
3. List any compilation warnings that may need attention
4. Suggest the `.gitignore` additions if not already present

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Check LaTeX installed | `which pdflatex 2>/dev/null` |
| Quick compile | `pdflatex -interaction=nonstopmode -halt-on-error FILE.tex` |
| Full compile (with TOC) | `pdflatex -interaction=nonstopmode FILE.tex && pdflatex -interaction=nonstopmode FILE.tex` |
| Check PDF page count | `pdfinfo FILE.pdf 2>/dev/null` |
| Check PDF file size | `stat -f %z FILE.pdf 2>/dev/null` |
| Install toolchain | `apt-get install -y texlive-latex-extra texlive-fonts-recommended texlive-fonts-extra texlive-science` |
| Errors only | `pdflatex -interaction=nonstopmode FILE.tex 2>&1` |

For detailed LaTeX patterns, TikZ templates, and package reference, see [REFERENCE.md](REFERENCE.md).
