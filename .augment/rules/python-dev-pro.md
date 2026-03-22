---
type: "agent_requested"
description: "Modern Python 3.14+ Coding Guidelines"
---

# Python 3.14+ coding guidelines for AI agents

**Target audience:** AI coding agents generating Python for greenfield projects.
**Minimum version:** Python 3.14.0 (stable, released October 7, 2025).
**Forward-looking:** Python 3.15 alpha features (targeting October 2026) are included and clearly labeled.

Python 3.14 is the most significant release in years. Template strings fundamentally change how agents should generate code that handles user input. Deferred annotations eliminate an entire class of forward-reference hacks. Free-threaded Python is officially supported, making true multi-core threading viable for the first time. This document provides concrete, copy-pasteable patterns for every major feature, organized as a lookup reference.

---

## Table of contents

1. [Project bootstrap & tooling](#1-project-bootstrap--tooling-20252026-best-practices)
2. [Template strings (t-strings) — PEP 750](#2-template-strings-t-strings--pep-750)
3. [Deferred evaluation of annotations — PEP 649/749](#3-deferred-evaluation-of-annotations--pep-649--pep-749)
4. [Concurrency: the new landscape](#4-concurrency-the-new-landscape)
5. [Type system & typing improvements](#5-type-system--typing-improvements)
6. [Performance features (experimental)](#6-performance-features-experimental)
7. [New standard library features](#7-new-standard-library-features)
8. [Syntax & language changes](#8-syntax--language-changes)
9. [Python 3.15 alpha — forward-looking features](#9-python-315-alpha--forward-looking-features)
10. [Migration patterns & anti-patterns](#10-migration-patterns--anti-patterns)
11. [Security best practices for 3.14](#11-security-best-practices-for-314)

---

## 1. Project bootstrap & tooling (2025–2026 best practices)

### uv replaces pip, virtualenv, pyenv, and poetry `[3.14 stable]`

**uv** (v0.10+, by Astral) is the recommended all-in-one tool for Python project management. Written in Rust, it is 10–100× faster than pip and handles Python version management, virtual environments, dependency resolution, locking, and publishing in a single binary.

```bash
# Install uv
curl -LsSf https://astral.sh/uv/install.sh | sh

# Install Python 3.14 (normal and free-threaded builds)
uv python install 3.14
uv python install 3.14t          # free-threaded build

# Create a new project
uv init my-project --python 3.14 --lib
cd my-project

# Add dependencies
uv add httpx pydantic
uv add --dev pytest ruff pyright

# Run commands inside the managed environment
uv run python main.py
uv run pytest
uv run ruff check .

# Lock and sync
uv lock
uv sync

# Test with free-threaded Python
uv run --python 3.14t python -c "import sys; print(sys._is_gil_enabled())"
```

**Do this / Not that:**

```bash
# ✅ Do: use uv for everything
uv add requests
uv run pytest
uv python install 3.14

# ❌ Not: use pip + virtualenv + pyenv separately
pip install requests
python -m venv .venv
pyenv install 3.14.0
```

### ruff replaces Black, isort, flake8, and pylint `[3.14 stable]`

**ruff** (v0.14+) is a single Rust-based linter and formatter with 800+ rules and explicit Python 3.14 support, including t-string syntax awareness.

```toml
# pyproject.toml — ruff configuration for 3.14
[tool.ruff]
target-version = "py314"
line-length = 88

[tool.ruff.lint]
select = [
    "E", "W",    # pycodestyle
    "F",         # pyflakes
    "I",         # isort
    "UP",        # pyupgrade (suggests 3.14 idioms)
    "B",         # flake8-bugbear (B012 flags finally-block issues)
    "SIM",       # flake8-simplify
    "S",         # flake8-bandit (security)
    "RUF",       # ruff-specific rules
    "PT",        # flake8-pytest-style
    "PERF",      # perflint
]

[tool.ruff.lint.per-file-ignores]
"tests/**/*.py" = ["S101"]  # allow assert in tests

[tool.ruff.format]
quote-style = "double"
docstring-code-format = true
```

Ruff 0.14+ is aware that Python 3.14 defers annotation evaluation natively, so the `flake8-type-checking` (TCH) rules account for annotations no longer needing `TYPE_CHECKING` guards. Ruff also emits a syntax error if t-strings are implicitly concatenated with non-t-strings.

### Type checking: pyright recommended, ty emerging `[3.14 stable]`

**Pyright** (v1.1.408+) has the most complete 3.14 support: PEP 750 t-string types, PEP 649 deferred annotations, PEP 758 bare except syntax. It changed its default Python version to 3.14.

**ty** (v0.0.23+, Astral, beta since December 2025) is 10–60× faster than mypy/Pyright, written in Rust. It is transformatively fast but has lower conformance accuracy (~15% test pass rate vs Pyright's higher coverage). Monitor for production readiness.

**mypy** (v1.19+) supports 3.14, including mypyc compilation, but is slower and has less complete PEP 750 support.

```toml
# pyproject.toml — type checker configuration
[tool.pyright]
pythonVersion = "3.14"
typeCheckingMode = "standard"

[tool.mypy]
python_version = "3.14"
strict = true
```

**Recommendation:** Use **Pyright** as the primary type checker for new 3.14 projects. Add **ty** for speed during development if its accuracy is sufficient for your codebase.

### pytest for 3.14 `[3.14 stable]`

pytest 9.0+ officially supports Python 3.14. For free-threaded testing, use **pytest-run-parallel** and **pytest-timeout**.

```toml
[tool.pytest.ini_options]
testpaths = ["tests"]
addopts = "-ra -q --strict-markers --tb=short"
markers = ["slow: slow tests", "thread_unsafe: not parallel-safe"]
faulthandler_timeout = 300
```

**Caveat:** `tmp_path`, `capsys`, and `monkeypatch` fixtures are NOT thread-safe. The pytest maintainers have explicitly ruled out making pytest itself thread-safe. Use `pytest-run-parallel` for thread-safety validation and `pytest-repeat` for catching race conditions.

```bash
# Test with free-threaded Python
PYTHON_GIL=0 uv run --python 3.14t pytest -x -v --parallel-threads=auto
```

### Complete pyproject.toml for a greenfield 3.14 project

```toml
[project]
name = "my-project"
version = "0.1.0"
description = "A modern Python 3.14 project"
readme = "README.md"
license = "MIT"
requires-python = ">=3.14"
authors = [{ name = "Your Name", email = "[email protected]" }]
dependencies = [
    "httpx>=0.27",
    "pydantic>=2.10",
]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[dependency-groups]
dev = [
    "pytest>=9.0",
    "pytest-cov>=6.0",
    "pytest-timeout>=2.3",
    "ruff>=0.14",
    "pyright>=1.1.400",
]

[tool.ruff]
target-version = "py314"
line-length = 88

[tool.ruff.lint]
select = ["E", "W", "F", "I", "UP", "B", "SIM", "S", "RUF", "PT", "PERF"]

[tool.ruff.lint.per-file-ignores]
"tests/**/*.py" = ["S101"]

[tool.ruff.format]
quote-style = "double"
docstring-code-format = true

[tool.pyright]
pythonVersion = "3.14"
typeCheckingMode = "standard"

[tool.pytest.ini_options]
testpaths = ["tests"]
addopts = "-ra -q --strict-markers"
faulthandler_timeout = 300
```

---

## 2. Template strings (t-strings) — PEP 750

Template strings are the flagship feature of Python 3.14. They use the `t"..."` prefix and return a `string.templatelib.Template` object instead of `str`, enabling safe, structured string processing. **Interpolations are evaluated eagerly** (like f-strings) but the result is a structured template, not a concatenated string. `[3.14 stable]`

### Basic syntax and how t-strings differ from f-strings

```python
from string.templatelib import Template, Interpolation

name = "World"

# f-string → str (immediate concatenation)
greeting_str = f"Hello {name}!"      # "Hello World!"

# t-string → Template (structured, not concatenated)
greeting_tpl = t"Hello {name}!"      # Template object
type(greeting_tpl)                    # <class 'string.templatelib.Template'>
```

**Valid prefix combinations:** `t"..."`, `T"..."`, `rt"..."`, `tr"..."` (raw template).
**Invalid combinations:** `ft"..."`, `tf"..."`, `bt"..."` — **SyntaxError**.

**Critical design point:** `Template` has no useful `__str__()`. Calling `str(template)` does NOT render it. You **must** process a template through a function to produce output. This is intentional — it forces deliberate, safe handling.

### The string.templatelib module

```python
from string.templatelib import Template, Interpolation

name = "Pythonista"
site = "example.com"
template = t"Hello, {name}! Welcome to {site}!"

# Template attributes
template.strings         # ('Hello, ', '! Welcome to ', '!')
template.interpolations  # (Interpolation('Pythonista', 'name', None, ''),
                         #  Interpolation('example.com', 'site', None, ''))
template.values          # ('Pythonista', 'example.com')

# Invariant: len(strings) == len(interpolations) + 1, always

# Interpolation attributes
interp = template.interpolations[0]
interp.value       # 'Pythonista'  — the evaluated result
interp.expression  # 'name'        — the source text
interp.conversion  # None          — !a, !r, !s, or None
interp.format_spec # ''            — format spec string
```

### Iterating and processing templates

`Template.__iter__()` yields `str` and `Interpolation` objects interleaved, omitting empty strings:

```python
from string.templatelib import Template, Interpolation

# Pattern 1: isinstance checks
def render(template: Template) -> str:
    parts: list[str] = []
    for item in template:
        if isinstance(item, Interpolation):
            parts.append(str(item.value))
        else:
            parts.append(item)
    return "".join(parts)

# Pattern 2: Structural pattern matching (preferred)
def render_match(template: Template) -> str:
    parts = []
    for item in template:
        match item:
            case str() as s:
                parts.append(s)
            case Interpolation(value, _, conversion, format_spec):
                value = _convert(value, conversion)
                value = format(value, format_spec)
                parts.append(str(value))
    return "".join(parts)

def _convert(value, conversion):
    match conversion:
        case "a": return ascii(value)
        case "r": return repr(value)
        case "s": return str(value)
        case _: return value
```

### Practical pattern: safe HTML rendering

```python
from string.templatelib import Template, Interpolation
import html as html_module

def html(template: Template) -> str:
    """Render template with HTML-escaped interpolations."""
    parts = []
    for item in template:
        if isinstance(item, Interpolation):
            parts.append(html_module.escape(str(item.value)))
        else:
            parts.append(item)  # static parts are trusted
    return "".join(parts)

# ✅ Do: use t-strings for HTML with user input
evil = "<script>alert('xss')</script>"
result = html(t"<p>{evil}</p>")
# "<p>&lt;script&gt;alert('xss')&lt;/script&gt;</p>" — XSS prevented

# ❌ Not: use f-strings for HTML with user input
result = f"<p>{evil}</p>"
# "<p><script>alert('xss')</script></p>" — XSS vulnerability!
```

### Practical pattern: SQL query builder

```python
from string.templatelib import Template, Interpolation

def sql(template: Template) -> tuple[str, tuple]:
    """Convert t-string to parameterized SQL query."""
    parts = []
    params = []
    for item in template:
        if isinstance(item, Interpolation):
            parts.append("?")
            params.append(item.value)
        else:
            parts.append(item)
    return "".join(parts), tuple(params)

# ✅ Do: t-string SQL — safe from injection
name = "Robert'; DROP TABLE users;--"
query, params = sql(t"SELECT * FROM users WHERE name = {name}")
# query  = "SELECT * FROM users WHERE name = ?"
# params = ("Robert'; DROP TABLE users;--",)
cursor.execute(query, params)  # safe — DB driver escapes params

# ❌ Not: f-string SQL — injection vulnerability
query = f"SELECT * FROM users WHERE name = '{name}'"
cursor.execute(query)  # SQL injection!
```

### Practical pattern: structured logging

```python
import json
import logging
from string.templatelib import Template, Interpolation

def log_structured(template: Template) -> str:
    """Render template as human text + structured JSON context."""
    text_parts, context = [], {}
    for item in template:
        if isinstance(item, Interpolation):
            text_parts.append(str(item.value))
            context[item.expression] = item.value
        else:
            text_parts.append(item)
    return f"{''.join(text_parts)} >>> {json.dumps(context)}"

action, amount, item = "traded", 42, "shrubs"
msg = log_structured(t"User {action}: {amount} {item}")
# "User traded: 42 shrubs >>> {"action": "traded", "amount": 42, "item": "shrubs"}"
```

### Type annotations for functions accepting templates

```python
from string.templatelib import Template

def render_html(template: Template) -> str: ...
def execute_query(query: Template) -> list[dict]: ...
def log_message(msg: Template) -> None: ...
```

### Ecosystem adoption

**psycopg3** (v3.3+) has native t-string support for PostgreSQL queries:

```python
# psycopg3 t-string support
cursor.execute(t"SELECT * FROM mytable WHERE id = {id}")
# Equivalent to: cursor.execute("SELECT * FROM mytable WHERE id = %s", (id,))

# Format specifiers: :s (auto), :b (binary), :t (text), :i (identifier)
cursor.execute(t"SELECT * FROM {table:i} WHERE id = {id}")
```

**tdom** (by PEP 750 co-author Dave Peck) provides JSX-like HTML templating with auto-escaping. **tstr** provides cross-version t-string backport and utilities. **Pyright 1.1.402+** has first-class template string type analysis.

### Template concatenation rules

```python
# ✅ Template + Template → Template
result = t"Hello " + t"{name}"

# ✅ Implicit concatenation
result = t"Hello " t"{name}"

# ❌ Template + str → TypeError
result = t"Hello " + "World"  # TypeError!

# ✅ Wrap str in Template to concatenate
from string.templatelib import Template
result = t"Hello " + Template("World")
```

### When NOT to use t-strings

Use f-strings, not t-strings, when you just need a simple formatted string with no safety concerns. T-strings add overhead (Template + Interpolation object creation) and require explicit processing. Never use `print(t"...")` directly — it prints the Template repr, not rendered text. Reserve t-strings for cases where you need to **intercept interpolated values** before assembly: HTML, SQL, logging, DSLs.

---

## 3. Deferred evaluation of annotations — PEP 649 / PEP 749

Annotations on functions, classes, and modules are **no longer evaluated eagerly** in Python 3.14. They are stored as `__annotate__` functions and evaluated lazily on first access. This is the biggest typing ecosystem change in years. `[3.14 stable]`

### Forward references now work without quotes

```python
# ✅ Do: Python 3.14 — just write annotations naturally
from dataclasses import dataclass

@dataclass
class TreeNode:
    value: int
    left: TreeNode | None = None    # no quotes needed!
    right: TreeNode | None = None   # forward ref resolved lazily

# ❌ Not: pre-3.14 hacks
from __future__ import annotations  # deprecated — don't use in 3.14+ code

@dataclass
class TreeNode:
    value: int
    left: "TreeNode | None" = None  # string quotes — unnecessary in 3.14
```

### The new annotationlib module

```python
from annotationlib import get_annotations, Format

def func(arg: Undefined):
    pass

# Format.VALUE — evaluate to runtime values (may raise NameError)
get_annotations(func, format=Format.VALUE)
# Raises: NameError: name 'Undefined' is not defined

# Format.FORWARDREF — undefined names become ForwardRef proxies
get_annotations(func, format=Format.FORWARDREF)
# {'arg': ForwardRef('Undefined', owner=<function func at ...>)}

# Format.STRING — return string representations
get_annotations(func, format=Format.STRING)
# {'arg': 'Undefined'}
```

**Do this / Not that:**

```python
# ✅ Do: use annotationlib.get_annotations() — the canonical way
from annotationlib import get_annotations, Format
annots = get_annotations(MyClass, format=Format.VALUE)

# ❌ Not: use inspect.get_annotations() — superseded
import inspect
annots = inspect.get_annotations(obj)  # still works but not recommended

# ❌ Not: access __annotations__ directly
annots = my_class.__annotations__  # works but triggers evaluation
```

### Impact on runtime introspection libraries

**dataclasses** uses `annotationlib.get_annotations()` with `FORWARDREF` format internally — forward references work automatically. **Pydantic v2.12+** supports PEP 649/749 semantics; forward references no longer need quotes. Pydantic v1 is NOT compatible with Python 3.14. **FastAPI** benefits transitively through Pydantic. **attrs** works if updated to use the new annotationlib protocol.

### Edge cases and gotchas

Side effects in annotations now execute when annotations are **accessed**, not when the function is defined:

```python
def f(x: print("evaluated!")): ...
# Nothing printed yet!
f.__annotations__  # NOW prints "evaluated!"
```

`from __future__ import annotations` still works in 3.14 but is unnecessary for new code. It will emit `DeprecationWarning` after Python 3.13 reaches end-of-life (~2029) and eventually become a `SyntaxError`.

**`typing.Union` is no longer cached** — `Union[int, str] is Union[int, str]` is now `False`. Use `==` for comparison instead of `is`.

---

## 4. Concurrency: the new landscape

Python 3.14 offers three distinct concurrency models, each with different isolation and performance characteristics.

### 4a. Free-threaded Python (no GIL) — PEP 779 `[3.14 stable]`

Free-threaded Python is **officially supported** (Phase 2) but remains an optional, separate build. The GIL is still enabled by default in the standard build. Single-threaded performance penalty is **~5–10%** (down from ~40% in 3.13), and memory overhead is **~15–20%**.

```bash
# Install free-threaded Python
uv python install 3.14t

# Verify free-threading is active
uv run --python 3.14t python -c "
import sys
print(f'Free-threaded build: {sys.flags.free_threading}')
print(f'GIL enabled: {sys._is_gil_enabled()}')
"
```

**True multi-core parallelism with threads:**

```python
import time
from concurrent.futures import ThreadPoolExecutor

def cpu_task(n):
    """CPU-bound work that benefits from true parallelism."""
    return sum(i * i for i in range(n))

# ✅ Do: ThreadPoolExecutor on free-threaded Python — true parallelism
with ThreadPoolExecutor(max_workers=4) as pool:
    start = time.perf_counter()
    results = list(pool.map(cpu_task, [10_000_000] * 4))
    elapsed = time.perf_counter() - start
    # ~4x faster on free-threaded vs GIL-enabled for CPU-bound work
```

**Thread safety rules:** CPython will not crash, but compound operations are NOT atomic:

```python
import threading

# ❌ Not: shared mutable state without locks — race condition
counter = 0
def increment():
    global counter
    counter += 1  # read + add + write is NOT atomic

# ✅ Do: use a lock for shared mutable state
lock = threading.Lock()
counter = 0
def safe_increment():
    global counter
    with lock:
        counter += 1
```

**GIL control at runtime:**

```bash
# Force GIL on (for debugging) in a free-threaded build
PYTHON_GIL=1 python3.14t my_script.py

# Force GIL off
PYTHON_GIL=0 python3.14t my_script.py
```

**Important caveat:** If a C extension not marked as free-thread-safe is imported, the interpreter **automatically re-enables the GIL** for the entire process lifetime. A warning is printed. Check compatibility at py-free-threading.github.io/tracking/.

**Adaptive executor pattern:**

```python
import sys
from concurrent.futures import ThreadPoolExecutor, ProcessPoolExecutor

def get_parallel_executor(max_workers=4):
    """Choose the best executor based on GIL status."""
    if hasattr(sys, "_is_gil_enabled") and not sys._is_gil_enabled():
        return ThreadPoolExecutor(max_workers=max_workers)
    return ProcessPoolExecutor(max_workers=max_workers)
```

### 4b. Multiple interpreters — concurrent.interpreters (PEP 734) `[3.14 stable]`

Each interpreter has its own GIL, providing true multi-core parallelism with **strong isolation** (separate globals, imports, builtins). Think "threads with opt-in sharing."

```python
from concurrent import interpreters

# Create and run code in a sub-interpreter
interp = interpreters.create()
interp.exec('print("Hello from sub-interpreter!")')

# Call a function in a sub-interpreter
def compute(x):
    return x * x

result = interp.call(compute, 12)  # 144
interp.close()
```

**InterpreterPoolExecutor — familiar concurrent.futures interface:**

```python
from concurrent.futures import InterpreterPoolExecutor

def heavy_computation(n):
    return sum(range(n))

# ✅ Do: use InterpreterPoolExecutor for isolated parallel work
with InterpreterPoolExecutor(max_workers=4) as pool:
    results = list(pool.map(heavy_computation, [10**6, 10**7, 10**8]))
```

**Cross-interpreter communication via Queue:**

```python
from concurrent import interpreters

queue = interpreters.create_queue()
interp = interpreters.create()
interp.prepare_main(q=queue)

interp.exec("""
for i in range(5):
    q.put(f"message {i}")
q.put(None)
""")

while (msg := queue.get()) is not None:
    print(f"Received: {msg}")
```

**Shareable types** (without pickle): `None`, `True`, `False`, `int`, `float`, `str`, `bytes`, `tuple` of these, `memoryview`, `concurrent.interpreters.Queue`. Everything else is copied via pickle.

### 4c. Asyncio improvements `[3.14 stable]`

Python 3.14 adds CLI tools for inspecting running async applications and programmatic call graph introspection:

```bash
# Inspect tasks in a running process (zero intrusion, read-only)
python -m asyncio ps <PID>
python -m asyncio pstree <PID>   # hierarchical tree view, detects deadlocks
```

```python
import asyncio

# Programmatic introspection from within async code
async def debug_tasks():
    asyncio.print_call_graph()                     # print current task graph
    graph = asyncio.capture_call_graph()            # capture as data structure

# ✅ Do: name your tasks for debuggability
asyncio.create_task(my_coro(), name="fetch-users")

# ❌ Not: unnamed tasks
asyncio.create_task(my_coro())  # shows as "Task-1" in introspection
```

### Choosing the right concurrency model

| Model | Best for | Isolation | Parallelism | Communication |
|---|---|---|---|---|
| **Free-threaded (3.14t)** | CPU-bound, shared-memory | None | True multi-core | Shared objects + locks |
| **Interpreters** | Isolated parallelism | Strong | True multi-core | Queue, pickle |
| **asyncio** | I/O-bound concurrency | None | Single-core* | await, Queue |
| **multiprocessing** | Maximum isolation | Complete (OS processes) | True multi-core | Pipes, shared memory |

*On free-threaded Python, multiple event loops can run in parallel across threads.

---

## 5. Type system & typing improvements

### Union type unification `[3.14 stable]`

`typing.Union[X, Y]` and `X | Y` now produce **identical `types.UnionType` instances**. Previously they were different types.

```python
import typing, types

# Both produce the same type now
assert type(typing.Union[int, str]) is types.UnionType
assert type(int | str) is types.UnionType

# ⚠️ Breaking: Union objects are no longer cached
typing.Union[int, str] is typing.Union[int, str]  # False!

# ✅ Do: use == for comparison
typing.Union[int, str] == typing.Union[int, str]  # True
```

### TypeVar evaluate methods `[3.14 stable]`

TypeVar, ParamSpec, TypeVarTuple, and TypeAliasType gain `evaluate_*` methods for introspection with the new Format system:

```python
from typing import TypeVar
from annotationlib import call_evaluate_function, Format

T = TypeVar("T", bound=int)
call_evaluate_function(T.evaluate_bound, Format.VALUE)   # <class 'int'>
call_evaluate_function(T.evaluate_bound, Format.STRING)  # 'int'

T2 = TypeVar("T2", int, str)
call_evaluate_function(T2.evaluate_constraints, Format.VALUE)  # (int, str)

# Type aliases
type Alias = list[int]
call_evaluate_function(Alias.evaluate_value, Format.VALUE)  # list[int]
```

### Annotation format in inspect.signature `[3.14 stable]`

```python
import inspect
from annotationlib import Format

def func(x: int) -> str: ...

sig = inspect.signature(func, annotation_format=Format.STRING)
```

### Impact on type checkers `[3.14 stable]`

Type checkers (mypy, Pyright) analyze source via AST, not runtime values, so PEP 649 does not significantly affect them. However, forward references in annotations no longer produce false positives, and `from __future__ import annotations` is no longer required for forward-reference support in 3.14+ codebases.

**Quoting is still needed outside annotations** in some cases:

```python
# ✅ No quotes needed in annotations (3.14+)
def f(x: MyClass) -> None: ...

# Quotes still needed for old TypeAlias syntax
from typing import TypeAlias
MyAlias: TypeAlias = "MyClass"  # still needs quotes

# But the type statement (3.12+) doesn't need quotes
type MyAlias = MyClass  # already uses deferred evaluation
```

---

## 6. Performance features (experimental)

### 6a. Experimental JIT compiler — PEP 744 `[3.14 experimental]`

The JIT uses "copy-and-patch" compilation to translate bytecode into machine code at runtime. Official macOS and Windows binaries now include JIT support, but it remains disabled by default.

```bash
# Enable JIT at runtime
PYTHON_JIT=1 python my_script.py
python -X jit my_script.py

# Build from source with JIT
./configure --enable-experimental-jit
```

**Current performance:** Ranges from **10% slower to 20% faster** depending on workload. The warmup threshold was increased from 16 loops (3.13) to **4,096** (3.14), so code must run longer before JIT kicks in. **Not recommended for production.** Free-threaded builds do NOT support JIT in 3.14.

```python
# Check JIT status
import sys
if hasattr(sys, "_jit"):
    print(f"JIT available: {sys._jit}")
```

### 6b. Tail-call interpreter `[3.14 stable]`

A new internal interpreter that replaces the monolithic C switch-case dispatch with small tail-calling C functions, yielding a **3–5% geometric mean speedup** on pyperformance. Requires Clang 19+ on x86-64 or AArch64.

```bash
# Build with tail-call interpreter
./configure --with-tail-call-interp --enable-optimizations --with-lto
```

**This is NOT Python-level tail call optimization.** Recursion semantics are unchanged. It is purely an internal CPython dispatch optimization. uv-managed Python 3.14 from python-build-standalone includes this automatically.

### 6c. Incremental garbage collector `[3.14 stable]`

The GC is now incremental, reducing maximum pause times by **an order of magnitude** for larger heaps. Only two generations remain (young and old, down from three).

```python
import gc

# gc.collect(1) now means "incremental pass" — NOT "collect generation 1"
gc.collect(0)  # collect young generation
gc.collect(1)  # incremental pass on old generation
gc.collect(2)  # full collection (same as gc.collect())
```

### 6d. Other performance improvements `[3.14 stable]`

- **`textwrap.dedent()`**: ~2.4× faster
- **`uuid3`/`uuid5`**: ~40% faster; **`uuid4`**: ~30% faster
- **zlib on Windows**: Now uses zlib-ng (faster implementation)
- **Import time**: Improved for `asyncio`, `base64`, `csv`, `pickle`, `socket`, `subprocess`, `threading`, `tomllib`, `zipfile`, and many more
- **Free-threaded single-thread penalty**: Reduced to ~5–10% (from ~40% in 3.13)

---

## 7. New standard library features

### compression.zstd — PEP 784 `[3.14 stable]`

New `compression` package provides Zstandard compression. Existing modules are re-exported under `compression.*` (old names NOT deprecated for ≥5 years).

```python
from compression import zstd

data = b"Hello, Zstandard! " * 1000

# One-shot compress/decompress
compressed = zstd.compress(data, level=3)
original = zstd.decompress(compressed)

# File I/O
import compression.zstd
with compression.zstd.open("data.zst", "wb") as f:
    f.write(data)

with compression.zstd.open("data.zst", "rb") as f:
    content = f.read()

# Integration with tarfile
import tarfile
with tarfile.open("archive.tar.zst", "w:zst") as tar:
    tar.add("myfile.txt")
```

```python
# ✅ Do: use compression.zstd from the stdlib
from compression import zstd
compressed = zstd.compress(data)

# ❌ Not: install third-party zstandard package for basic needs
# pip install zstandard  # no longer necessary for basic usage
```

### pathlib.Path.copy() and Path.move() `[3.14 stable]`

```python
from pathlib import Path

# ✅ Do: use Path methods directly
Path("source.txt").copy("destination.txt")
Path("mydir").copy("mydir_backup")  # recursive copy
Path("old.txt").move("new.txt")

# ❌ Not: import shutil for basic file operations
import shutil
shutil.copy2("source.txt", "destination.txt")  # old way
```

### pdb remote debugging `[3.14 stable]`

```bash
# Attach pdb to a running process — no code changes needed
python -m pdb -p <PID>
```

pdb now has **syntax highlighting** and uses `sys.monitoring` as its default backend. The debugger can be attached without restarting the target process.

### Zero-overhead external debugger interface — PEP 768 `[3.14 stable]`

```python
import sys

# Execute a Python script in another running process
sys.remote_exec(pid, "/path/to/debug_script.py")
```

Zero runtime overhead when not in use. Security controls: `PYTHON_DISABLE_REMOTE_DEBUG=1`, `-X disable-remote-debug`, or `--without-remote-debug` build flag.

### UUID versions 6–8 `[3.14 stable]`

```python
import uuid

uuid.uuid6()  # reordered time-based (sortable)
uuid.uuid7()  # Unix epoch time-based (RECOMMENDED for new applications)
uuid.uuid8(bytes(16))  # custom/experimental

# ✅ Do: use uuid7() for database primary keys — sortable, no MAC leak
record_id = uuid.uuid7()

# ❌ Not: use uuid1() which leaks your MAC address
record_id = uuid.uuid1()
```

### Bracket-less except — PEP 758 `[3.14 stable]`

```python
# ✅ Do: clean, no parentheses (3.14+)
try:
    connect()
except TimeoutError, ConnectionRefusedError:
    handle_error()

# ⚠️ Parentheses still REQUIRED with 'as' clause
try:
    connect()
except (TimeoutError, ConnectionRefusedError) as e:
    handle_error(e)
```

### finally block safety — PEP 765 `[3.14 stable]`

`return`, `break`, `continue` that exit a `finally` block now emit `SyntaxWarning` (may become `SyntaxError` in future versions):

```python
# ❌ Not: return in finally — silently swallows exceptions
def bad():
    try:
        raise ValueError("important!")
    finally:
        return 42  # SyntaxWarning! Swallows the ValueError

# ✅ Do: handle control flow outside finally
def good():
    result = None
    try:
        result = do_work()
    except ValueError:
        result = fallback()
    finally:
        cleanup()  # no return/break/continue here
    return result
```

### Other notable stdlib additions `[3.14 stable]`

- **`heapq` max-heap functions**: `heapify_max()`, `heappush_max()`, `heappop_max()`, `heapreplace_max()`, `heappushpop_max()`
- **`http.server.HTTPSServer`**: HTTPS support with `--tls-cert` and `--tls-key` CLI options
- **`argparse`**: Color help text, `suggest_on_error` parameter for typo suggestions
- **`hmac`**: Built-in HMAC using formally verified HACL* code
- **`map(strict=True)`**: New `strict` keyword argument (like `zip(strict=True)`)
- **`float.from_number()` / `complex.from_number()`**: New class methods
- **`ast.compare()`**: Compare AST nodes; `copy.replace()` support for AST nodes
- **`memoryview`** is now a generic type (supports subscription)

---

## 8. Syntax & language changes

### Improved error messages `[3.14 stable]`

Python 3.14 provides significantly better diagnostic messages:

```python
>>> improt math
# SyntaxError: invalid syntax. Did you mean 'import'?

>>> pritn("hello")
# NameError: name 'pritn' is not defined. Did you mean 'print'?
```

Better detection of unterminated strings, incompatible prefixes, `elif` after `else`, and async/sync context manager mismatches.

### REPL improvements `[3.14 stable]`

The REPL now features **real-time syntax highlighting**, import tab-completion, multiline editing with history, and colorized tracebacks. Stdlib CLI tools also gain color: `unittest` (red/green), `argparse` (colorful help), `json.tool` (pretty-print), `calendar` (current day highlight), `pdb` (syntax highlighting).

```bash
# Disable color if needed
NO_COLOR=1 python           # standard no-color env var
PYTHON_COLORS=0 python      # Python-specific
PYTHON_BASIC_REPL=1 python  # use basic REPL entirely
```

### The -c flag auto-dedents code `[3.14 stable]`

```bash
python -c "
    import sys
    print(sys.version)
"
# Works in 3.14 — auto-dedented. Previously required flush-left code.
```

### Fun Easter egg `[3.14 stable]`

On Unix, Python 3.14 virtual environments include a `𝜋thon` alias — a pi tribute for version 3.14.

---

## 9. Python 3.15 alpha — forward-looking features

**All features in this section are `[3.15 alpha]` and subject to change. Python 3.15 beta 1 (feature freeze) is May 5, 2026. Final release target: October 1, 2026.**

### PEP 810: explicit lazy imports `[3.15 alpha]`

A new `lazy` soft keyword defers module loading until first use. The module is replaced by a lightweight proxy object that transparently loads on access.

```python
lazy import json
lazy from pathlib import Path

print("Starting up...")               # json/pathlib NOT loaded yet
data = json.loads('{"key": "value"}') # json loads HERE on first use
p = Path(".")                         # pathlib loads HERE
```

**Performance impact:** **50–70% startup time reduction** for CLI tools in practice, with **30–40% memory savings**. The `lazy` keyword is only allowed at module scope — `SyntaxError` inside functions, classes, or try/except blocks. `lazy from module import *` is also a `SyntaxError`.

**Global control:**

```bash
# Enable lazy imports globally
python -X lazy_imports=all my_app.py
PYTHON_LAZY_IMPORTS=all python my_app.py
```

**Gotcha:** Errors surface at **first use**, not at import time. This is why the `lazy` keyword is explicit — it signals to readers that failures are deferred.

### PEP 798: unpacking in comprehensions `[3.15 alpha]`

Star unpacking now works inside list, set, dict comprehensions, and generator expressions:

```python
# Flatten nested lists
lists = [[1, 2], [3, 4], [5]]
[*L for L in lists]    # [1, 2, 3, 4, 5]

# Union of sets
sets = [{1, 2}, {2, 3}, {3, 4}]
{*s for s in sets}     # {1, 2, 3, 4}

# Merge dicts (last wins)
dicts = [{"a": 1}, {"b": 2}, {"a": 3}]
{**d for d in dicts}   # {"a": 3, "b": 2}
```

```python
# ✅ Do (3.15+): intuitive unpacking syntax
flat = [*chunk for chunk in nested_list]

# ❌ Not: unintuitive nested comprehension
flat = [x for chunk in nested_list for x in chunk]

# ❌ Not: itertools.chain.from_iterable
import itertools
flat = list(itertools.chain.from_iterable(nested_list))
```

### PEP 686: UTF-8 default encoding `[3.15 alpha]`

Python 3.15 uses **UTF-8 as the default text encoding** for all I/O when no explicit encoding is specified. This mainly affects Windows (Unix already uses UTF-8 in most locales).

```python
# Before 3.15: encoding depended on locale (cp1252 on Windows)
open("file.txt")

# Python 3.15: always UTF-8 unless explicitly specified
open("file.txt")  # UTF-8

# To get old locale-based behavior explicitly
open("file.txt", encoding="locale")

# Disable globally
# PYTHONUTF8=0 or python -X utf8=0
```

**Best practice for cross-version code:** Always specify `encoding` explicitly.

### PEP 799: Tachyon profiler (profiling.sampling) `[3.15 alpha]`

A new statistical sampling profiler with **virtually zero overhead**, capable of sampling at up to **1,000,000 Hz**. No code modification needed — attach to running processes by PID.

```bash
# Attach to running process and generate a flame graph
python -m profiling.sampling attach --pid 12345 --flamegraph output.html

# Profile a script with CPU time mode
python -m profiling.sampling run my_script.py --mode cpu --pstats

# Real-time TUI profiler (top-like)
python -m profiling.sampling run -m my_module --live
```

Modes: wall-clock, CPU time, GIL-holding time, exception handling time. Output formats: pstats, collapsed stacks, flame graph HTML, Firefox Profiler (gecko), heatmap, live TUI. The `profile` module is deprecated in 3.15 and scheduled for removal in 3.17.

### JIT compiler maturation `[3.15 alpha]`

The JIT has been substantially improved: **4–5% geometric mean improvement** over standard interpreter on x86-64 Linux, **7–8% on AArch64 macOS**. New features include basic register allocation, constant propagation, ~80% JIT coverage, and an overhauled tracing frontend. Free-threading support in JIT is in pre-beta status.

### Other confirmed 3.15 features `[3.15 alpha]`

- **mimalloc as default allocator** for raw memory allocations — especially benefits free-threaded builds
- **Base64 encoding 2× faster, decoding 3× faster**; Ascii85/Base85/Z85 rewritten in C (two orders of magnitude faster)
- **Tail-calling interpreter on Windows** (MSVC 18): 15–20% speedup on pyperformance
- **PEP 814: `frozendict` built-in type** — immutable, hashable dict; `frozendict(x=1, y=2)`
- **PEP 728**: TypedDict with typed extra items
- **PEP 747**: `TypeForm` for annotating type forms

---

## 10. Migration patterns & anti-patterns

### Always do this in 3.14+ (checklist)

- **Write forward references without quotes** in annotations — they resolve lazily
- **Remove `from __future__ import annotations`** in 3.14-only codebases
- **Use `annotationlib.get_annotations()`** instead of `inspect.get_annotations()` or `__annotations__`
- **Use `uuid.uuid7()`** for new database primary keys (sortable, no MAC leak)
- **Use `compression.zstd`** from the stdlib instead of third-party zstandard packages
- **Use t-strings** for any string processing involving untrusted input (HTML, SQL, shell)
- **Use `Path.copy()` and `Path.move()`** instead of `shutil.copy2()` and `shutil.move()`
- **Name asyncio tasks** with `name=` for debuggability
- **Use `except A, B:` without parentheses** when no `as` clause is needed
- **Use `==` (not `is`)** for `typing.Union` comparison
- **Set `target-version = "py314"`** in ruff configuration
- **Use `uv`** for project management, dependency resolution, and Python version management

### Never do this anymore (checklist)

- **Never use `from __future__ import annotations`** in new 3.14-only code
- **Never quote forward references** in annotations — `"MyClass"` → `MyClass`
- **Never use f-strings for SQL queries** — use t-strings with parameterized queries
- **Never use f-strings for HTML with user input** — use t-strings with escaping
- **Never call `str()` on a Template** expecting rendered output — process it through a function
- **Never use `return`/`break`/`continue` in `finally` blocks** — now emits `SyntaxWarning`
- **Never use `uuid.uuid1()`** for new code — leaks MAC address; use `uuid7()`
- **Never use `int.__trunc__()`** — removed; implement `__int__()` or `__index__()`
- **Never use `NotImplemented` in boolean context** — now raises `TypeError`
- **Never use `gc.collect(1)` expecting "collect generation 1"** — semantics changed to incremental
- **Never use `typing.Union[X, Y] is typing.Union[X, Y]`** — identity comparison is now `False`

### Key deprecations to avoid `[3.14 stable]`

| Deprecated | Replacement | Timeline |
|---|---|---|
| `from __future__ import annotations` | Just write annotations naturally | DeprecationWarning after 3.13 EOL |
| `threading.RLock()` with arguments | `threading.RLock()` (no args) | Error in 3.15 |
| `types.CodeType.co_lnotab` | `co_lines()` / `co_linetable` | May be removed in 3.15 |
| `typing._UnionGenericAlias` | `types.UnionType` | Removal in 3.17 |
| `profile` module | `profiling.tracing` (cProfile) | Removal in 3.17 `[3.15 alpha]` |
| PGP signatures for releases | Sigstore verification | Removed in 3.14 (PEP 761) |

### Removed in 3.14

- **`ast.Num`, `ast.Str`, `ast.Bytes`, `ast.NameConstant`, `ast.Ellipsis`** — removed (use `ast.Constant`)
- **`int()` delegating to `__trunc__()`** — must implement `__int__()` or `__index__()`
- **`NotImplemented` in boolean context** — now `TypeError` (was `DeprecationWarning`)
- Various deprecated APIs in `argparse`, `asyncio`, `email`, `importlib.abc`, `itertools`, `pathlib`, `sqlite3`, `urllib`

---

## 11. Security best practices for 3.14

### T-strings eliminate injection vulnerabilities by design `[3.14 stable]`

The fundamental security improvement: t-strings **structurally separate static code from dynamic values**, making it impossible to accidentally concatenate untrusted input into SQL, HTML, or shell commands without explicit processing.

```python
# SQL injection prevention (see Section 2 for full pattern)
query, params = sql(t"SELECT * FROM users WHERE name = {name}")
cursor.execute(query, params)

# XSS prevention (see Section 2 for full pattern)
output = html(t"<p>{user_input}</p>")

# Key insight: Template objects cannot be used where str is expected.
# They MUST be processed through a function — forcing safe handling.
```

### Sigstore replaces PGP for release verification — PEP 761 `[3.14 stable]`

```bash
# ✅ Do: verify Python releases with Sigstore
pip install sigstore
python -m sigstore verify identity \
    --cert-identity "thomas@python.org" \
    --cert-oidc-issuer "https://github.com/login/oauth" \
    Python-3.14.0.tar.xz.sigstore

# ❌ Not: look for PGP .asc files — no longer provided
```

### Free-threading thread safety `[3.14 stable]`

With the GIL disabled, races that were masked before now manifest. Always use `threading.Lock` for shared mutable state. Prefer `InterpreterPoolExecutor` when you need parallelism with strong isolation — interpreters cannot accidentally share mutable state.

### Subinterpreter isolation `[3.14 stable]`

Each interpreter has isolated globals, imports, and builtins. Use interpreters for plugin systems or untrusted code execution. **Caveat:** This is not security sandboxing — C extensions can violate isolation within the same process. For hard security boundaries, use OS-level process isolation.

### Remote debugging security `[3.14 stable]`

The PEP 768 debugger interface has zero overhead when not in use but requires elevated privileges to attach. Disable in hardened deployments:

```bash
# Disable remote debugging
PYTHON_DISABLE_REMOTE_DEBUG=1 python production_server.py
python -X disable-remote-debug production_server.py
```

Build-time: `./configure --without-remote-debug`. CPython 3.14 now enables recommended security compiler flags by default (`--disable-safety` to opt out).

### HMAC with formally verified cryptography `[3.14 stable]`

```python
import hmac, hashlib

# Python 3.14's HMAC uses formally verified HACL* code
# (cryptographic library verified with the F* proof assistant)
mac = hmac.new(b"secret-key", b"message", hashlib.sha256).hexdigest()
```

---

*This document covers Python 3.14.0 (stable, October 7, 2025) through the Python 3.15 alpha cycle (targeting October 2026). Features marked `[3.14 stable]` are production-ready. Features marked `[3.14 experimental]` are opt-in and may change. Features marked `[3.15 alpha]` are subject to change until Python 3.15 beta 1 (May 5, 2026). Consult the official documentation at docs.python.org and peps.python.org for authoritative details.*
