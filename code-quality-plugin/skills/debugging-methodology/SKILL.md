---
model: opus
name: Debugging Methodology
description: Systematic debugging approach with tool recommendations for memory, performance, and system-level issues.
allowed-tools: Bash, Read, Grep, Glob
created: 2025-12-27
modified: 2025-12-27  # Added eBPF tracing
reviewed: 2025-12-27
---

# Debugging Methodology

Systematic approach to finding and fixing bugs.

## Core Principles

1. **Occam's Razor** - Start with the simplest explanation
2. **Binary Search** - Isolate the problem area systematically
3. **Preserve Evidence** - Understand state before making changes
4. **Document Hypotheses** - Track what was tried and didn't work

## Debugging Workflow

```
1. Understand → What is expected vs actual behavior?
2. Reproduce → Can you trigger the bug reliably?
3. Locate → Where in the code does it happen?
4. Diagnose → Why does it happen? (root cause)
5. Fix → Minimal change to resolve
6. Verify → Confirm fix works, no regressions
```

## Common Bug Patterns

| Symptom | Likely Cause | Check First |
|---------|--------------|-------------|
| TypeError/null | Missing null check | Input validation |
| Off-by-one | Loop bounds, array index | Boundary conditions |
| Race condition | Async timing | Await/promise handling |
| Import error | Path/module resolution | File paths, exports |
| Type mismatch | Wrong type passed | Function signatures |
| Flaky test | Timing, shared state | Test isolation |

## System-Level Tools

### Memory Analysis
```bash
# Valgrind (C/C++/Rust)
valgrind --leak-check=full --show-leak-kinds=all ./program
valgrind --tool=massif ./program  # Heap profiling

# Python
python -m memory_profiler script.py
```

### Performance Profiling
```bash
# Linux perf
perf record -g ./program
perf report
perf top  # Real-time CPU usage

# Python
python -m cProfile -s cumtime script.py
```

### System Tracing (Traditional)
```bash
# System calls (ptrace-based, high overhead)
strace -f -e trace=all -p PID

# Library calls
ltrace -f -S ./program

# Open files/sockets
lsof -p PID

# Memory mapping
pmap -x PID
```

### eBPF Tracing (Modern, Production-Safe)

eBPF is the modern replacement for strace/ptrace-based tracing. Key advantages:
- **Low overhead**: Safe for production use
- **No recompilation**: Works on running binaries
- **Non-intrusive**: Doesn't stop program execution
- **Kernel-verified**: Bounded execution, can't crash the system

```bash
# BCC tools (install: apt install bpfcc-tools)
# Trace syscalls with timing (like strace but faster)
sudo syscount -p PID              # Count syscalls
sudo opensnoop -p PID             # Trace file opens
sudo execsnoop                    # Trace new processes
sudo tcpconnect                   # Trace TCP connections
sudo funccount 'vfs_*'            # Count kernel function calls

# bpftrace (install: apt install bpftrace)
# One-liner tracing scripts
sudo bpftrace -e 'tracepoint:syscalls:sys_enter_open { printf("%s %s\n", comm, str(args->filename)); }'
sudo bpftrace -e 'uprobe:/bin/bash:readline { printf("readline\n"); }'

# Trace function arguments in Go/other languages
sudo bpftrace -e 'uprobe:./myapp:main.handleRequest { printf("called\n"); }'
```

**eBPF Tool Hierarchy**:
| Level | Tool | Use Case |
|-------|------|----------|
| High | BCC tools | Pre-built tracing scripts |
| Medium | bpftrace | One-liner custom traces |
| Low | libbpf/gobpf | Custom eBPF programs |

**When to use eBPF over strace**:
- Production systems (strace adds 10-100x overhead)
- Long-running traces
- High-frequency syscalls
- When you can't afford to slow down the process

### Network Debugging
```bash
# Packet capture
tcpdump -i any port 8080

# Connection status
ss -tuln
netstat -tuln
```

## Language-Specific Debugging

### Python
```python
# Quick debug
import pdb; pdb.set_trace()

# Better: ipdb or pudb
import ipdb; ipdb.set_trace()

# Print with context
print(f"{var=}")  # Python 3.8+
```

### JavaScript/TypeScript
```javascript
// Browser/Node
debugger;

// Structured logging
console.log({ var1, var2, context: 'function_name' });
```

### Rust
```rust
// Debug print
dbg!(&variable);

// Backtrace on panic
RUST_BACKTRACE=1 cargo run
```

## Debugging Questions

When stuck, ask:
1. What changed recently that could cause this?
2. Does it happen in all environments or just one?
3. Is the bug in my code or a dependency?
4. What assumptions am I making that might be wrong?
5. Can I write a minimal reproduction?

## Anti-Patterns to Avoid

- **Shotgun debugging**: Random changes hoping something works
- **Printf debugging only**: Use proper debuggers when available
- **Fixing symptoms**: Find root cause, not just band-aids
- **Skipping reproduction**: Always reproduce before fixing
- **Not testing the fix**: Verify the fix actually works
