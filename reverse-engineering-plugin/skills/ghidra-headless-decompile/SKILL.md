---
name: ghidra-headless-decompile
description: Batch-decompile a binary with Ghidra headless and grep the output. Use when reverse-engineering a PE/ELF/firmware binary from the CLI — export decompiled C for every function, dump xrefs or call graphs. Covers the Ghidra 12 Jython-to-PyGhidra break (scripts are Java now) and the project lock.
user-invocable: false
allowed-tools: Bash(analyzeHeadless *), Bash(rg *), Bash(awk *), Read, Write, Grep, Glob, TodoWrite
created: 2026-11-17
modified: 2026-11-17
reviewed: 2026-11-17
---

# Ghidra Headless Decompilation

Drive Ghidra from the shell to reverse-engineer a binary at scale: import once,
then run scripts that export decompiled C, call graphs, or xrefs to flat files
you `rg` through. The alternative — clicking through the GUI — does not scale to
hundreds of functions and is not reproducible.

`analyzeHeadless` lives at `<ghidra>/support/analyzeHeadless`. On Homebrew:
`/opt/homebrew/Cellar/ghidra/*/libexec/support/analyzeHeadless` (resolve the
newest). `ghidraRun` on `PATH` points at the install's `bin/`.

## Scripts are Java, not Python (Ghidra 12+)

Ghidra 12 dropped Jython and switched to **PyGhidra**, which `analyzeHeadless`
does not ship with. A `.py` postScript fails with:

```
ERROR SCRIPT ERROR: *.py : Ghidra was not started with PyGhidra. Python is not available
```

Write post-scripts as Java `GhidraScript` subclasses (`DumpC.java`, no package).
`analyzeHeadless` compiles them on the fly. This is the single most common
headless footgun on a current install.

## Import once, then process

```sh
# First run: import + auto-analyze (slow, once).
analyzeHeadless <proj-dir> <proj-name> -import /abs/path/to/binary \
  -scriptPath <script-dir> -postScript DumpC <abs-out.c>

# Later runs against the same project: -process (not -import), skip re-analysis.
analyzeHeadless <proj-dir> <proj-name> -process binary \
  -noanalysis -scriptPath <script-dir> -postScript OtherScript ...
```

- A second `-import` of the same file fails (already in project). Use `-process`,
  or `-overwrite` to re-import.
- `-noanalysis` skips re-running the analyzers; auto-analysis only needs to run
  once.
- Ghidra projects hold an **exclusive lock** — do not run two `analyzeHeadless`
  invocations against the same project concurrently; the second fails
  project-locked. Serialize Ghidra; parallelize the *analysis* of its output
  instead (see "Pre-dump, then dispatch").

## Dump every function's C to one greppable file

`DumpC.java` — the workhorse. Decompile all functions, write C with a
`// ==== name @ addr ====` header per function:

```java
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.program.model.listing.*;
import ghidra.util.task.ConsoleTaskMonitor;
import java.io.*;

public class DumpC extends GhidraScript {
    public void run() throws Exception {
        String out = getScriptArgs().length > 0 ? getScriptArgs()[0] : "/tmp/dump.c";
        DecompInterface ifc = new DecompInterface();
        ifc.setSimplificationStyle("decompile");
        ifc.openProgram(currentProgram);
        ConsoleTaskMonitor mon = new ConsoleTaskMonitor();
        PrintWriter w = new PrintWriter(new FileWriter(out));
        for (Function f : currentProgram.getFunctionManager().getFunctions(true)) {
            DecompileResults r = ifc.decompileFunction(f, 60, mon);
            if (r != null && r.decompileCompleted()) {
                w.println("// ==== " + f.getName() + " @ " + f.getEntryPoint() + " ====");
                w.println(r.getDecompiledFunction().getC());
            }
        }
        w.close();
        ifc.dispose();           // always dispose
        println("DUMPED_FUNCTIONS=" + currentProgram.getFunctionManager().getFunctionCount());
    }
}
```

Then the answer is usually one `rg` away:

```sh
rg -n 'GetBiosKey|0x4d53445f' dump.c           # a string, a constant
rg -n 'DAT_005054b0\s*=[^=]' dump.c             # who WRITES a global
awk 'NR<=L && /^\/\/ ====/{h=$0} NR==L{print h}' L=<lineno> dump.c  # enclosing function
```

## Ghidra 12 API gotchas

- `ReferenceManager.getReferencesTo(addr)` returns a `ReferenceIterator`, not an
  array — drain it into a `List` before sizing or re-iterating.
- Auto-analysis misses functions reached only via a stored data pointer
  (a `WndProc` registered by writing its address to a global). Promote with
  `new CreateFunctionCmd(toAddr(0x...L)).applyTo(currentProgram)`, confirm with
  `getFunctionManager().getFunctionContaining(addr) != null`, then decompile.
- Filter CRT/library noise when walking call graphs (MSVC: names starting `__`,
  or `_` + lowercase — `_malloc`, `__ioinit`): they flood any BFS from entry and
  add nothing to program logic.

## Pre-dump, then dispatch

When a question wants parallel analysis ("characterise N functions"), do **one**
Ghidra run that emits all needed artifacts to flat files, then dispatch
read-only agents over the pre-computed files. This sidesteps the project lock and
makes each agent's input self-contained. Always **grep the existing dumps before
a new run** — a prior wave's dump often already holds the function or global, and
the planned Ghidra run is unnecessary. Say in the brief what is already dumped so
the agent does not re-derive it.

## Related

- `tools-plugin:binary-analysis` — strings/binwalk/objdump triage before Ghidra.
- `firmware-dump-region-map` — carve the right region out of a firmware image
  before importing it here.
- `agent-patterns-plugin:exclusive-lock-dispatch` — the general pattern behind
  the project-lock serialization.
