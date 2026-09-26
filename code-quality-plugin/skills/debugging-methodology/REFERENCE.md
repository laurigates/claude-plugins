# Debugging Methodology - Reference

System-level tracing/profiling tools and language-specific debugger commands.

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
