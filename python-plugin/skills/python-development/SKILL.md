---
name: python-development
description: |
  Core Python development concepts, idioms, best practices, and language features.
  Covers Python 3.10+ features, type hints, async/await, and Pythonic patterns.
  For running scripts, see uv-run. For project setup, see uv-project-management.
  Use when user mentions Python, type hints, async Python, decorators, context managers,
  or writing Pythonic code.
allowed-tools: Glob, Grep, Read, WebFetch, TodoWrite, WebSearch, BashOutput, KillShell, Edit, Write, NotebookEdit, Bash
---

# Python Development

Core Python language concepts, idioms, and best practices.

## Core Expertise

- **Python Language**: Modern Python 3.10+ features and idioms
- **Best Practices**: Pythonic code, design patterns, SOLID principles
- **Debugging**: Interactive debugging and profiling techniques
- **Performance**: Optimization strategies and profiling
- **Async Programming**: async/await patterns and asyncio

## Modern Python Features (3.10+)

### Type Hints

```python
# Modern syntax (Python 3.10+)
def process_items(
    items: list[str],                    # Not List[str]
    mapping: dict[str, int],             # Not Dict[str, int]
    optional: str | None = None,         # Not Optional[str]
) -> tuple[bool, str]:                   # Not Tuple[bool, str]
    """Process items with modern type hints."""
    return True, "success"

# Type aliases
type UserId = int
type UserDict = dict[str, str | int]

def get_user(user_id: UserId) -> UserDict:
    return {"id": user_id, "name": "Alice"}
```

### Pattern Matching (3.10+)

```python
def handle_command(command: dict) -> str:
    match command:
        case {"action": "create", "item": item}:
            return f"Creating {item}"
        case {"action": "delete", "item": item}:
            return f"Deleting {item}"
        case {"action": "list"}:
            return "Listing items"
        case _:
            return "Unknown command"
```

### Structural Pattern Matching

```python
def process_response(response):
    match response:
        case {"status": 200, "data": data}:
            return process_success(data)
        case {"status": 404}:
            raise NotFoundError()
        case {"status": code} if code >= 500:
            raise ServerError(code)
```

## Python Idioms

### Context Managers

```python
# File handling
with open("file.txt") as f:
    content = f.read()

# Custom context manager
from contextlib import contextmanager

@contextmanager
def database_connection():
    conn = create_connection()
    try:
        yield conn
    finally:
        conn.close()

with database_connection() as conn:
    conn.execute("SELECT * FROM users")
```

### List Comprehensions

```python
# List comprehension
squares = [x**2 for x in range(10)]

# Dict comprehension
word_lengths = {word: len(word) for word in ["hello", "world"]}

# Set comprehension
unique_lengths = {len(word) for word in ["hello", "world", "hi"]}

# Generator expression
sum_of_squares = sum(x**2 for x in range(1000000))  # Memory efficient
```

### Iterators and Generators

```python
def fibonacci():
    a, b = 0, 1
    while True:
        yield a
        a, b = b, a + b

# Use generator
fib = fibonacci()
first_ten = [next(fib) for _ in range(10)]

# Generator expression
even_squares = (x**2 for x in range(10) if x % 2 == 0)
```

## Debugging

### Interactive Debugging

```python
import pdb

def problematic_function():
    value = calculate()
    pdb.set_trace()  # Debugger breakpoint
    return process(value)
```

```bash
# Debug on error
python -m pdb script.py

# pytest with debugger
uv run pytest --pdb                     # Drop into pdb on failure
uv run pytest --pdb --pdbcls=IPython.terminal.debugger:TerminalPdb
```

### Performance Profiling

```bash
# CPU profiling
uv run python -m cProfile -s cumtime script.py | head -20

# Line-by-line profiling (temporary dependency)
uv run --with line-profiler kernprof -l -v script.py

# Memory profiling (temporary dependency)
uv run --with memory-profiler python -m memory_profiler script.py

# Real-time profiling (ephemeral tool)
uvx py-spy top -- python script.py

# Quick profiling with scalene
uv run --with scalene python -m scalene script.py
```

### Built-in Debugging Tools

```python
# Trace execution
import sys

def trace_calls(frame, event, arg):
    if event == 'call':
        print(f"Calling {frame.f_code.co_name}")
    return trace_calls

sys.settrace(trace_calls)

# Memory tracking
import tracemalloc

tracemalloc.start()
# ... code to profile
snapshot = tracemalloc.take_snapshot()
top_stats = snapshot.statistics('lineno')
for stat in top_stats[:10]:
    print(stat)
```

## Async Programming

### Basic async/await

```python
import asyncio

async def fetch_data(url: str) -> dict:
    async with httpx.AsyncClient() as client:
        response = await client.get(url)
        return response.json()

async def main():
    result = await fetch_data("https://api.example.com")
    print(result)

asyncio.run(main())
```

### Concurrent Tasks

```python
async def process_multiple():
    # Run concurrently
    results = await asyncio.gather(
        fetch_data("url1"),
        fetch_data("url2"),
        fetch_data("url3"),
    )
    return results

# With timeout
async def with_timeout():
    try:
        result = await asyncio.wait_for(fetch_data("url"), timeout=5.0)
    except asyncio.TimeoutError:
        print("Request timed out")
```

## Design Patterns

### Dependency Injection

```python
from typing import Protocol

class Database(Protocol):
    def query(self, sql: str) -> list: ...

def get_users(db: Database) -> list:
    return db.query("SELECT * FROM users")
```

### Factory Pattern

```python
def create_handler(handler_type: str):
    match handler_type:
        case "json":
            return JSONHandler()
        case "xml":
            return XMLHandler()
        case _:
            raise ValueError(f"Unknown handler: {handler_type}")
```

### Decorator Pattern

```python
from functools import wraps
import time

def timer(func):
    @wraps(func)
    def wrapper(*args, **kwargs):
        start = time.time()
        result = func(*args, **kwargs)
        end = time.time()
        print(f"{func.__name__} took {end - start:.2f}s")
        return result
    return wrapper

@timer
def slow_function():
    time.sleep(1)
```

## Best Practices

### SOLID Principles

**Single Responsibility:**
```python
# Bad: Class does too much
class User:
    def save(self): pass
    def send_email(self): pass
    def generate_report(self): pass

# Good: Separate concerns
class User:
    def save(self): pass

class EmailService:
    def send_email(self, user): pass

class ReportGenerator:
    def generate(self, user): pass
```

### Fail Fast

```python
def process_data(data: dict) -> str:
    # Validate early
    if not data:
        raise ValueError("Data cannot be empty")
    if "required_field" not in data:
        raise KeyError("Missing required field")

    # Process with confidence
    return data["required_field"].upper()
```

### Functional Approach

```python
# Prefer immutable transformations
def process_items(items: list[int]) -> list[int]:
    return [item * 2 for item in items]  # New list

# Over mutations
def process_items_bad(items: list[int]) -> None:
    for i in range(len(items)):
        items[i] *= 2  # Mutates input
```

## Project Structure (src layout)

```
my-project/
├── pyproject.toml
├── README.md
├── src/
│   └── my_project/
│       ├── __init__.py
│       ├── core.py
│       ├── utils.py
│       └── models.py
└── tests/
    ├── conftest.py
    ├── test_core.py
    └── test_utils.py
```

## See Also

- **uv-run** - Running scripts, temporary dependencies, PEP 723
- **uv-project-management** - Project setup and dependency management
- **uv-tool-management** - Installing CLI tools globally
- **python-testing** - Testing with pytest
- **python-code-quality** - Linting and type checking with ruff/mypy
- **python-packaging** - Building and publishing packages
- **uv-python-versions** - Managing Python interpreters

## References

- Python docs: https://docs.python.org/3/
- Type hints: https://docs.python.org/3/library/typing.html
- Async: https://docs.python.org/3/library/asyncio.html
- Detailed guide: See REFERENCE.md
