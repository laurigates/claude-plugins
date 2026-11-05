# Custom Git Merge Drivers — Reference

Detail moved out of [SKILL.md](SKILL.md): a minimal driver skeleton that implements the contract and the [design rules](SKILL.md#design-rules-for-a-structural-driver).

## Minimal driver skeleton

A minimal skeleton with the contract in place (fill in `merge()`):

```python
#!/usr/bin/env python3
import json, subprocess, sys
from pathlib import Path

class Conflict(Exception): pass

def merge(base, ours, theirs):
    if ours == theirs: return ours
    if base == ours: return theirs
    if base == theirs: return ours
    # dicts: recurse per key; field policies here; otherwise:
    raise Conflict()

def line_merge(o, a, b):
    rc = subprocess.run(["git", "merge-file", "-L", "ours", "-L", "base",
                         "-L", "theirs", a, o, b]).returncode
    if rc == 0:
        try: json.loads(Path(a).read_text()); return 0
        except ValueError: pass
    return 1  # never > 128

def main(o, a, b, *_):
    try:
        load = lambda p: json.loads(Path(p).read_text() or "null")
        result = merge(load(o), load(a), load(b))
    except (ValueError, Conflict):
        return line_merge(o, a, b)
    Path(a).write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n")
    return 0

sys.exit(main(*sys.argv[1:]))
```
