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
modified: 2026-02-08
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
- Available .md files: !`find . -maxdepth 2 -name '*.md' -not -name 'CHANGELOG.md' -not -name 'README.md' 2>/dev/null | head -10`

## Parameters

- `<file>`: Path to the Markdown source file (required)
- `--no-compile`: Generate `.tex` file only, skip PDF compilation
- `--visualizations`: Include TikZ/PGFPlots diagrams (timelines, charts, risk matrices)
- `--report-type`: Document structure preset
  - `roadmap`: Phase-based roadmap with timeline visualization
  - `lifecycle`: Project lifecycle with release charts and velocity graphs
  - `general`: Standard professional document (default)

## Execution

### Phase 1: Analyze Markdown Source

Read the source Markdown file and extract:
- Document title and metadata
- Section hierarchy (map `#` levels to LaTeX chapters/sections)
- Tables (convert to `booktabs` format)
- Lists (itemize/enumerate)
- Code blocks (lstlisting/minted)
- Callout blocks or blockquotes (map to `tcolorbox` environments)
- Priorities or status indicators (map to color-coded markers)
- Numerical data suitable for visualization

### Phase 2: Generate LaTeX Document

Create a `.tex` file adjacent to the source with these components:

**Document class and packages:**
```latex
\documentclass[a4paper,11pt]{report}

% Core packages
\usepackage[utf8]{inputenc}
\usepackage[T1]{fontenc}
\usepackage{lmodern}
\usepackage[margin=2.5cm]{geometry}
\usepackage{hyperref}
\usepackage{xcolor}
\usepackage{booktabs}
\usepackage{longtable}
\usepackage{enumitem}
\usepackage{fancyhdr}
\usepackage{titlesec}
\usepackage{tcolorbox}
\usepackage{fontawesome5}
\usepackage{amssymb}
\usepackage{graphicx}

% Visualization packages (when --visualizations)
\usepackage{tikz}
\usepackage{pgfplots}
\pgfplotsset{compat=1.18}
\usetikzlibrary{shapes,arrows,positioning,calc,patterns}
```

**Color definitions:**
```latex
\definecolor{critical}{HTML}{DC2626}
\definecolor{high}{HTML}{EA580C}
\definecolor{medium}{HTML}{CA8A04}
\definecolor{low}{HTML}{16A34A}
\definecolor{info}{HTML}{2563EB}
\definecolor{warning}{HTML}{D97706}
\definecolor{success}{HTML}{059669}
```

**Custom environments:**
```latex
\newtcolorbox{infobox}{colback=info!5,colframe=info,title=\faInfoCircle\ Info}
\newtcolorbox{warningbox}{colback=warning!5,colframe=warning,title=\faExclamationTriangle\ Warning}
\newtcolorbox{successbox}{colback=success!5,colframe=success,title=\faCheckCircle\ Success}
```

**Header/footer setup:**
```latex
\setlength{\headheight}{14pt}
\pagestyle{fancy}
\fancyhf{}
\fancyhead[L]{\leftmark}
\fancyhead[R]{\thepage}
\fancyfoot[C]{\small Document Title}
```

### Markdown-to-LaTeX Conversion Rules

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

### Priority/Status Color Mapping

Map status indicators found in the source to colored markers:

```latex
% Inline priority markers
\newcommand{\critical}{\textcolor{critical}{\faBolt\ Critical}}
\newcommand{\highpri}{\textcolor{high}{\faExclamationCircle\ High}}
\newcommand{\mediumpri}{\textcolor{medium}{\faMinusCircle\ Medium}}
\newcommand{\lowpri}{\textcolor{low}{\faCheckCircle\ Low}}
```

### Phase 3: Add Visualizations (when --visualizations or data suggests it)

Choose appropriate visualizations based on document content:

**Timeline (for roadmaps with phases):**
```latex
\begin{tikzpicture}[scale=1.2]
  % Draw timeline arrow
  \draw[->,thick] (0,0) -- (12,0);
  % Phase markers
  \foreach \x/\label/\dates in {
    1.5/Phase 1/Q1,
    4.5/Phase 2/Q2,
    7.5/Phase 3/Q3,
    10.5/Phase 4/Q4} {
    \draw[thick] (\x,0.2) -- (\x,-0.2);
    \node[above] at (\x,0.3) {\textbf{\label}};
    \node[below] at (\x,-0.3) {\small\dates};
  }
\end{tikzpicture}
```

**Bar/pie charts (for release or metric data):**
```latex
\begin{tikzpicture}
\begin{axis}[
  ybar, bar width=15pt,
  xlabel={Category}, ylabel={Count},
  symbolic x coords={A,B,C,D},
  xtick=data, nodes near coords
]
\addplot coordinates {(A,10) (B,25) (C,15) (D,8)};
\end{axis}
\end{tikzpicture}
```

**Risk matrix (for documents with risk/impact data):**
```latex
\begin{tikzpicture}
  \fill[green!20] (0,0) rectangle (2,2);
  \fill[yellow!20] (2,0) rectangle (4,2);
  \fill[yellow!20] (0,2) rectangle (2,4);
  \fill[orange!20] (2,2) rectangle (4,4);
  \fill[red!20] (4,2) rectangle (6,4);
  % Labels and axes
\end{tikzpicture}
```

**Test pyramid (for QA/testing documents):**
```latex
\begin{tikzpicture}
  \fill[green!30] (-3,0) -- (3,0) -- (2,1.5) -- (-2,1.5) -- cycle;
  \node at (0,0.75) {\textbf{Unit Tests}};
  \fill[yellow!30] (-2,1.5) -- (2,1.5) -- (1,3) -- (-1,3) -- cycle;
  \node at (0,2.25) {\textbf{Integration}};
  \fill[red!30] (-1,3) -- (1,3) -- (0,4.5) -- cycle;
  \node at (0,3.5) {\textbf{E2E}};
\end{tikzpicture}
```

### Phase 4: Compile to PDF

**Install LaTeX toolchain if not available:**
```bash
apt-get update && apt-get install -y texlive-latex-extra texlive-fonts-recommended \
  texlive-fonts-extra texlive-science latexmk
```

**Compile with two passes for cross-references:**
```bash
pdflatex -interaction=nonstopmode DOCUMENT.tex
pdflatex -interaction=nonstopmode DOCUMENT.tex
```

Two passes are required to resolve:
- Table of contents
- Cross-references (`\ref`, `\pageref`)
- Hyperlinks
- Page numbers in headers

**Common compilation fixes:**

| Error | Fix |
|-------|-----|
| Missing `amssymb` | Add `\usepackage{amssymb}` |
| Missing `eurosym` | Add `\usepackage{eurosym}` or replace `€` with `\texteuro{}` |
| Header height warning | Add `\setlength{\headheight}{14pt}` |
| Undefined control sequence | Check package imports match used commands |
| Missing font | Install `texlive-fonts-extra` |

### Phase 5: Repository Cleanup

Add LaTeX build artifacts to `.gitignore` if not already present:

```
# LaTeX build artifacts
*.aux
*.log
*.out
*.toc
*.lof
*.lot
*.fls
*.fdb_latexmk
*.synctex.gz
*.bbl
*.blg
*.nav
*.snm
*.vrb
```

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
| Check PDF page count | `pdfinfo FILE.pdf 2>/dev/null \| grep Pages` |
| Check PDF file size | `ls -lh FILE.pdf` |
| Install toolchain | `apt-get install -y texlive-latex-extra texlive-fonts-recommended texlive-fonts-extra texlive-science` |
| Errors only | `pdflatex -interaction=nonstopmode FILE.tex 2>&1 \| grep -E "^!" \| head -10` |

For detailed LaTeX patterns, TikZ templates, and package reference, see [REFERENCE.md](REFERENCE.md).
