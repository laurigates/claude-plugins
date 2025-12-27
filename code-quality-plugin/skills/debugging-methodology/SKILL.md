---
name: Debugging Methodology
description: Systematic debugging approach with tool recommendations for memory, performance, and system-level issues.
allowed-tools: Bash, Read, Grep, Glob
created: 2025-12-27
modified: 2025-12-27
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

### System Tracing
```bash
# System calls
strace -f -e trace=all -p PID

# Library calls
ltrace -f -S ./program

# Open files/sockets
lsof -p PID

# Memory mapping
pmap -x PID
```

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
