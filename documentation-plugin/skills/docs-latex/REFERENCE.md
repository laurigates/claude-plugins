# LaTeX Reference Patterns

Detailed LaTeX templates and patterns for the `/docs:latex` skill.

## Complete Document Preamble

```latex
\documentclass[a4paper,11pt]{report}

% Encoding and fonts
\usepackage[utf8]{inputenc}
\usepackage[T1]{fontenc}
\usepackage{lmodern}

% Page layout
\usepackage[margin=2.5cm]{geometry}
\setlength{\headheight}{14pt}

% Typography
\usepackage{microtype}
\usepackage{parskip}

% Colors
\usepackage{xcolor}
\definecolor{critical}{HTML}{DC2626}
\definecolor{high}{HTML}{EA580C}
\definecolor{medium}{HTML}{CA8A04}
\definecolor{low}{HTML}{16A34A}
\definecolor{info}{HTML}{2563EB}
\definecolor{warning}{HTML}{D97706}
\definecolor{success}{HTML}{059669}
\definecolor{linkcolor}{HTML}{1D4ED8}
\definecolor{codebackground}{HTML}{F3F4F6}

% Tables
\usepackage{booktabs}
\usepackage{longtable}
\usepackage{tabularx}
\usepackage{multirow}

% Lists
\usepackage{enumitem}

% Headers and footers
\usepackage{fancyhdr}
\pagestyle{fancy}
\fancyhf{}
\fancyhead[L]{\leftmark}
\fancyhead[R]{\thepage}

% Section styling
\usepackage{titlesec}
\titleformat{\chapter}[display]
  {\normalfont\huge\bfseries}{\chaptertitlename\ \thechapter}{20pt}{\Huge}
\titlespacing*{\chapter}{0pt}{-20pt}{40pt}

% Hyperlinks
\usepackage{hyperref}
\hypersetup{
  colorlinks=true,
  linkcolor=linkcolor,
  urlcolor=linkcolor,
  citecolor=linkcolor,
  pdfborder={0 0 0}
}

% Icons
\usepackage{fontawesome5}

% Math symbols (for checkboxes)
\usepackage{amssymb}

% Graphics
\usepackage{graphicx}

% Code listings
\usepackage{listings}
\lstset{
  backgroundcolor=\color{codebackground},
  basicstyle=\ttfamily\small,
  breaklines=true,
  frame=single,
  rulecolor=\color{gray!30},
  numbers=left,
  numberstyle=\tiny\color{gray},
  tabsize=2
}

% Callout boxes
\usepackage[most]{tcolorbox}
\newtcolorbox{infobox}[1][]{
  colback=info!5,colframe=info,
  title=\faInfoCircle\ Info,
  fonttitle=\bfseries,#1
}
\newtcolorbox{warningbox}[1][]{
  colback=warning!5,colframe=warning,
  title=\faExclamationTriangle\ Warning,
  fonttitle=\bfseries,#1
}
\newtcolorbox{successbox}[1][]{
  colback=success!5,colframe=success,
  title=\faCheckCircle\ Success,
  fonttitle=\bfseries,#1
}
\newtcolorbox{criticalbox}[1][]{
  colback=critical!5,colframe=critical,
  title=\faBolt\ Critical,
  fonttitle=\bfseries,#1
}

% Diagrams
\usepackage{tikz}
\usepackage{pgfplots}
\pgfplotsset{compat=1.18}
\usetikzlibrary{shapes,arrows,positioning,calc,patterns,decorations.markings}
```

## TikZ Visualization Templates

### Phase Timeline (Roadmap)

```latex
\begin{figure}[htbp]
\centering
\begin{tikzpicture}[
  phase/.style={
    rectangle, rounded corners=5pt, minimum width=2.2cm, minimum height=1cm,
    text centered, font=\small\bfseries, text=white
  }
]
  % Timeline arrow
  \draw[->,very thick,gray!50] (-0.5,0) -- (14,0);

  % Phase boxes
  \node[phase,fill=info] (p1) at (1.5,1.5) {Phase 1};
  \node[phase,fill=success] (p2) at (5,1.5) {Phase 2};
  \node[phase,fill=warning] (p3) at (8.5,1.5) {Phase 3};
  \node[phase,fill=critical] (p4) at (12,1.5) {Phase 4};

  % Connectors to timeline
  \foreach \x in {1.5,5,8.5,12} {
    \draw[thick,gray] (\x,0.1) -- (\x,0.8);
  }

  % Date labels
  \node[below,font=\small] at (1.5,-0.2) {Q1 2026};
  \node[below,font=\small] at (5,-0.2) {Q2 2026};
  \node[below,font=\small] at (8.5,-0.2) {Q3 2026};
  \node[below,font=\small] at (12,-0.2) {Q4 2026};

  % Descriptions
  \node[below=0.1cm,font=\scriptsize,text width=2.2cm,text centered] at (p1.south) {Foundation};
  \node[below=0.1cm,font=\scriptsize,text width=2.2cm,text centered] at (p2.south) {Core Build};
  \node[below=0.1cm,font=\scriptsize,text width=2.2cm,text centered] at (p3.south) {Optimization};
  \node[below=0.1cm,font=\scriptsize,text width=2.2cm,text centered] at (p4.south) {Production};
\end{tikzpicture}
\caption{Project Roadmap Timeline}
\end{figure}
```

### Risk Matrix

```latex
\begin{figure}[htbp]
\centering
\begin{tikzpicture}[scale=0.9]
  % Grid cells with colors
  % Row 1 (Low likelihood)
  \fill[green!20] (0,0) rectangle (2,2);
  \fill[green!20] (2,0) rectangle (4,2);
  \fill[yellow!20] (4,0) rectangle (6,2);
  % Row 2 (Medium likelihood)
  \fill[green!20] (0,2) rectangle (2,4);
  \fill[yellow!20] (2,2) rectangle (4,4);
  \fill[orange!20] (4,2) rectangle (6,4);
  % Row 3 (High likelihood)
  \fill[yellow!20] (0,4) rectangle (2,6);
  \fill[orange!20] (2,4) rectangle (4,6);
  \fill[red!20] (4,4) rectangle (6,6);

  % Grid lines
  \draw[gray!50] (0,0) grid[step=2] (6,6);
  \draw[thick] (0,0) rectangle (6,6);

  % Axis labels
  \node[below,font=\small] at (1,0) {Low};
  \node[below,font=\small] at (3,0) {Medium};
  \node[below,font=\small] at (5,0) {High};
  \node[below=0.5cm,font=\bfseries] at (3,0) {Impact};

  \node[left,font=\small,rotate=90] at (0,1) {Low};
  \node[left,font=\small,rotate=90] at (0,3) {Medium};
  \node[left,font=\small,rotate=90] at (0,5) {High};
  \node[left=0.5cm,font=\bfseries,rotate=90] at (0,3) {Likelihood};

  % Risk items (customize per document)
  \node[font=\scriptsize,text width=1.8cm,text centered] at (5,5) {Vendor lock-in};
  \node[font=\scriptsize,text width=1.8cm,text centered] at (3,3) {Scope creep};
  \node[font=\scriptsize,text width=1.8cm,text centered] at (1,1) {Minor delays};
\end{tikzpicture}
\caption{Risk Assessment Matrix}
\end{figure}
```

### Test Pyramid

```latex
\begin{figure}[htbp]
\centering
\begin{tikzpicture}[scale=0.8]
  % Unit tests (base)
  \fill[green!30] (-4,0) -- (4,0) -- (2.67,2) -- (-2.67,2) -- cycle;
  \node[font=\bfseries] at (0,1) {Unit Tests};
  \node[font=\small] at (0,0.3) {Fast, Isolated};

  % Integration tests (middle)
  \fill[yellow!30] (-2.67,2) -- (2.67,2) -- (1.33,4) -- (-1.33,4) -- cycle;
  \node[font=\bfseries] at (0,3) {Integration};
  \node[font=\small] at (0,2.3) {Service Boundaries};

  % E2E tests (top)
  \fill[red!30] (-1.33,4) -- (1.33,4) -- (0,6) -- cycle;
  \node[font=\bfseries] at (0,4.8) {E2E};

  % Count labels
  \node[right,font=\small] at (4.2,1) {e.g. 500+ tests};
  \node[right,font=\small] at (2.9,3) {e.g. 100 tests};
  \node[right,font=\small] at (1.5,5) {e.g. 20 tests};
\end{tikzpicture}
\caption{Testing Pyramid}
\end{figure}
```

### Bar Chart (PGFPlots)

```latex
\begin{figure}[htbp]
\centering
\begin{tikzpicture}
\begin{axis}[
  ybar,
  bar width=20pt,
  xlabel={Category},
  ylabel={Count},
  symbolic x coords={Features,Bug Fixes,Performance,Refactoring,Documentation},
  xtick=data,
  x tick label style={rotate=45,anchor=east,font=\small},
  nodes near coords,
  nodes near coords align={vertical},
  ymin=0,
  width=12cm,
  height=7cm,
  enlarge x limits=0.15
]
\addplot[fill=info!60] coordinates {
  (Features,22)
  (Bug Fixes,37)
  (Performance,8)
  (Refactoring,12)
  (Documentation,15)
};
\end{axis}
\end{tikzpicture}
\caption{Release Distribution by Type}
\end{figure}
```

### Pie Chart (PGFPlots)

```latex
\begin{figure}[htbp]
\centering
\begin{tikzpicture}
\pie[
  radius=3,
  text=legend,
  color={info!60, critical!60, success!60, warning!60, gray!40}
]{
  22/Features,
  37/Bug Fixes,
  8/Performance,
  12/Refactoring,
  15/Documentation
}
\end{tikzpicture}
\caption{Release Type Distribution}
\end{figure}
```

Note: Pie charts require `\usepackage{pgf-pie}`. If unavailable, use a bar chart instead.

### Area/Line Chart (Release Velocity)

```latex
\begin{figure}[htbp]
\centering
\begin{tikzpicture}
\begin{axis}[
  area style,
  xlabel={Month},
  ylabel={Releases},
  symbolic x coords={Jan,Feb,Mar,Apr,May,Jun,Jul,Aug,Sep,Oct,Nov,Dec},
  xtick=data,
  x tick label style={rotate=45,anchor=east,font=\small},
  ymin=0,
  width=12cm,
  height=6cm,
  fill opacity=0.3,
  draw opacity=1
]
\addplot+[mark=*,fill=info!30,draw=info] coordinates {
  (Jan,3) (Feb,5) (Mar,8) (Apr,6) (May,2) (Jun,1)
  (Jul,4) (Aug,7) (Sep,9) (Oct,12) (Nov,16) (Dec,4)
} \closedcycle;
\end{axis}
\end{tikzpicture}
\caption{Release Velocity Over Time}
\end{figure}
```

### Gantt-Style Phase Diagram

```latex
\begin{figure}[htbp]
\centering
\begin{tikzpicture}[
  bar/.style={rounded corners=2pt, minimum height=0.6cm, text=white, font=\small\bfseries}
]
  % Y-axis labels
  \foreach \y/\label in {0/Phase 4,1/Phase 3,2/Phase 2,3/Phase 1} {
    \node[left,font=\small] at (0,\y*0.9) {\label};
  }

  % Phase bars (x = months, width = duration)
  \node[bar,fill=info,minimum width=3cm,anchor=west] at (0.5,3*0.9) {Foundation};
  \node[bar,fill=success,minimum width=4cm,anchor=west] at (3,2*0.9) {Build};
  \node[bar,fill=warning,minimum width=3cm,anchor=west] at (6,1*0.9) {Optimize};
  \node[bar,fill=critical,minimum width=2.5cm,anchor=west] at (8.5,0*0.9) {Ship};

  % Month markers
  \foreach \x/\m in {0.5/Jan,2/Mar,4/May,6/Jul,8/Sep,10/Nov} {
    \node[below,font=\scriptsize] at (\x,-0.5) {\m};
  }
  \draw[gray!30] (0.5,-0.3) -- (11,-0.3);
\end{tikzpicture}
\caption{Development Phase Timeline}
\end{figure}
```

## Table Patterns

### Priority Table with Color Indicators

```latex
\begin{table}[htbp]
\centering
\caption{Task Priorities}
\begin{tabular}{@{}llll@{}}
\toprule
\textbf{Task} & \textbf{Priority} & \textbf{Owner} & \textbf{Status} \\
\midrule
Database migration & \textcolor{critical}{\faBolt\ Critical} & Team A & In Progress \\
API versioning & \textcolor{high}{\faExclamationCircle\ High} & Team B & Planned \\
Documentation update & \textcolor{medium}{\faMinusCircle\ Medium} & Team C & Backlog \\
UI polish & \textcolor{low}{\faCheckCircle\ Low} & Team D & Backlog \\
\bottomrule
\end{tabular}
\end{table}
```

### Resource Allocation Table

```latex
\begin{table}[htbp]
\centering
\caption{Resource Allocation by Phase}
\begin{tabularx}{\textwidth}{@{}lXccc@{}}
\toprule
\textbf{Phase} & \textbf{Focus} & \textbf{Engineers} & \textbf{Duration} & \textbf{Budget} \\
\midrule
Phase 1 & Foundation and setup & 3 & 3 months & \$150K \\
Phase 2 & Core implementation & 5 & 4 months & \$300K \\
Phase 3 & Testing and optimization & 4 & 3 months & \$200K \\
Phase 4 & Launch and stabilization & 3 & 2 months & \$100K \\
\midrule
\textbf{Total} & & \textbf{5 peak} & \textbf{12 months} & \textbf{\$750K} \\
\bottomrule
\end{tabularx}
\end{table>
```

### Checklist Table

```latex
\begin{table}[htbp]
\centering
\begin{tabular}{@{}cl@{}}
\toprule
\textbf{Status} & \textbf{Requirement} \\
\midrule
$\boxtimes$ & User authentication implemented \\
$\boxtimes$ & API endpoints documented \\
$\square$ & Load testing completed \\
$\square$ & Security audit scheduled \\
\bottomrule
\end{tabular}
\end{table}
```

## Callout Box Patterns

### Information Callout

```latex
\begin{infobox}
This section describes the recommended approach for database migration.
Ensure backups are taken before proceeding.
\end{infobox}
```

### Warning Callout

```latex
\begin{warningbox}
Breaking changes in API v3 require all clients to update their authentication headers.
See the migration guide in Appendix A.
\end{warningbox}
```

### Success Callout

```latex
\begin{successbox}
Performance benchmarks show a 75\% reduction in API response times
after implementing the caching layer.
\end{successbox}
```

### Custom Titled Box

```latex
\begin{tcolorbox}[
  colback=blue!5,colframe=blue!50,
  title=\faLightbulb\ Key Decision,
  fonttitle=\bfseries
]
We chose PostgreSQL over MongoDB due to the relational nature of our data model
and the need for ACID transactions.
\end{tcolorbox}
```

## Special Character Handling

| Character | LaTeX Replacement |
|-----------|-------------------|
| `&` | `\&` |
| `%` | `\%` |
| `$` | `\$` |
| `#` | `\#` |
| `_` | `\_` |
| `{` | `\{` |
| `}` | `\}` |
| `~` | `\textasciitilde{}` |
| `^` | `\textasciicircum{}` |
| `\` | `\textbackslash{}` |
| `€` | `\texteuro{}` (requires `eurosym`) or `\EUR{}` |
| `©` | `\copyright{}` |
| `®` | `\textregistered{}` |
| `™` | `\texttrademark{}` |

## Package Dependencies

### Minimal Installation

```bash
apt-get install -y texlive-latex-base texlive-latex-recommended
```

### Full Installation (recommended)

```bash
apt-get install -y texlive-latex-extra texlive-fonts-recommended \
  texlive-fonts-extra texlive-science latexmk
```

### Package-to-Feature Mapping

| Package | Provides |
|---------|----------|
| `booktabs` | Professional tables (`\toprule`, `\midrule`, `\bottomrule`) |
| `longtable` | Tables spanning multiple pages |
| `tabularx` | Tables with auto-width columns |
| `tcolorbox` | Colored callout boxes |
| `tikz` | Programmatic diagrams |
| `pgfplots` | Charts and data visualization |
| `fontawesome5` | Icons (`\faCheck`, `\faBolt`, etc.) |
| `hyperref` | Clickable links and TOC |
| `fancyhdr` | Custom headers/footers |
| `enumitem` | Customizable lists |
| `listings` | Code syntax highlighting |
| `xcolor` | Color definitions |
| `geometry` | Page margins |
| `amssymb` | Math symbols (`\square`, `\boxtimes`) |
| `microtype` | Improved typography (kerning, ligatures) |

## Compilation Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `! LaTeX Error: File 'X.sty' not found` | Missing package | `apt-get install texlive-latex-extra` |
| `! Undefined control sequence` | Missing `\usepackage` | Add the required package import |
| `Package hyperref Warning: Token not allowed` | Special chars in section titles | Use `\texorpdfstring{LaTeX}{text}` |
| `Overfull \hbox` | Content too wide | Reduce table/image width or use `\resizebox` |
| `! Missing $ inserted` | Math symbol outside math mode | Wrap in `$...$` |
| TOC shows `??` | Single compilation pass | Run `pdflatex` twice |
| Fonts look wrong | Missing font packages | Install `texlive-fonts-extra` |
| `! LaTeX Error: Too many unprocessed floats` | Many consecutive figures | Add `\clearpage` or use `[H]` placement |
