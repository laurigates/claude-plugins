# Mutation Testing — Four Ways a Hand-Rolled Harness Misreports

Detail for [SKILL.md](../SKILL.md) § Hand-rolled harnesses report LESS than Stryker and mutmut do. §1–§3 are false CAUGHT results; §4 is a false MISSED.

### 1. An earlier check masks the one under test

```
run(mutate_frame_count, "check P: off-grid length")
  -> CAUGHT: "beat 'x' asks for 20 words in 5.42 s (3.69 words/s, ceiling 3.0)"
```

Reported as caught; the message is from **check N**, a words-per-second rule that
fires before the grid check ever runs. Check P was never exercised. The mutation
tripped a different assertion on the way past.

**Always print and read the failure message, never just the pass/fail.** If the
message does not name the check you are testing, the mutation did not reach it.

### 2. The mutation has to be one ONLY the target check can see

Fixing [§ 1](#1-an-earlier-check-masks-the-one-under-test) is not "mutate harder" — it is choosing a mutation that no
earlier check can intercept:

| Testing | Bad mutation | Works |
|---|---|---|
| an off-grid frame count | any beat (a talky one trips the words/sec check first) | a **wordless** beat |
| a cast-shrink rule | a beat whose prose also names the removed character (trips the alias check) | a beat where only the count changes |

This is the same discipline as isolating a variable in an A/B: the mutation is
the independent variable, and anything else it perturbs is a confound.

### 3. Mutating a table leaves import-time derived state stale

The subtlest one, and it caused two of the three maskings. Modules commonly build
lookup dicts from a table **at import**:

```python
SEGMENTS = (...)
_SEG_OF = {beat: name for name, beats, _ in SEGMENTS for beat in beats}
```

Monkeypatching `SEGMENTS` in the harness leaves `_SEG_OF` describing the *old*
table, so the first check that consults it fails with a stale-lookup error —
masking everything downstream:

```python
mod.SEGMENTS = new_table
mod._SEG_OF = {b: n for n, ids, _ in mod.SEGMENTS for b in ids}   # REQUIRED
```

**Rebuild every derived structure you can find, or reload the module.** Grep for
comprehensions over the table you mutated.

### 4. The mutated file was never imported

The mirror of §§ 1–3. Those are all **false CAUGHT** — a mutation
reported killed by an assertion other than the intended one. This one is
**false MISSED**: the harness edits a file the run never loads, and reports a
coverage hole that does not exist.

A 25-row harness over a builder + loader pair staged six named files into a temp
directory, wrote the mutated copy over one of them, and put the real source
directory on `PYTHONPATH` so the remaining imports would resolve. First run:
`25 mutations, 15 mismatches`. Twelve of the fifteen were every row mutating
*one* of the two files, each `expect=CAUGHT got=MISSED 0 red`. The natural
reading — "those twelve assertions are vacuous, go strengthen the tests" — is
wrong. They were running the pristine source.

**The tell is the control row.** A `META reject-all` mutation inserts a
hard-wired `err.add()` at the top of the function under test, and it reported
`MISSED` with `0 red`. A suite that does not go red against a hard-wired failure
is not a weak suite — it is proof the harness is not running the file it edited.

The mechanism was an ordinary, otherwise harmless idiom in a *sibling* module,
staged from the real directory:

```python
sys.path.insert(0, str(Path(__file__).resolve().parent))
```

`__file__` there is the **real** directory, so importing that sibling re-inserts
the real directory at `sys.path[0]`, ahead of the temp directory. The builder
imports the sibling before it imports the loader, so the loader — the mutated
file — resolved to the unmutated copy for every later import. Printing resolved
paths inside the run confirms it:

```
PATH0: ['/tmp/tmp.GcJ4RTwCg7', '/tmp/tmp.GcJ4RTwCg7', '/mnt/.../lab/scripts', ...]
B: /tmp/tmp.GcJ4RTwCg7/build_...py        <- staged copy, mutated rows worked
C-in-modules: /mnt/.../lab/scripts/dataputki_content.py   <- REAL file
```

The four rows mutating the *other* file worked correctly, because that file was
staged and imported directly. That mix is what made the report look plausible
rather than broken.

**Stage the whole directory and pass no search path at all.** With no second
copy anywhere on the path there is nothing for an import to bind to:

```python
shutil.copytree(SRC, td, dirs_exist_ok=True,
                ignore=shutil.ignore_patterns("__pycache__", "*.pyc", ".pytest_cache"))
env = {k: v for k, v in os.environ.items() if k != "PYTHONPATH"}
```

After that change: 25 mutations, 0 mismatches, every row caught by its intended
test and the CONTROL correctly missed. A per-file copy list also encodes an
import graph that nothing checks — it stops being correct the moment someone
adds an import.

**This is not Python-specific.** Any runtime that resolves by search path has
the same shape — a second copy of the unmutated code reachable ahead of the one
you edited:

| Runtime | The second copy binds via |
|---|---|
| Python | `PYTHONPATH`, or a `sys.path.insert` inside any imported module |
| Node | `NODE_PATH`, or `node_modules` resolution walking up from the real file |
| Go | `GOPATH` |
| Ruby | `RUBYLIB` |
| Perl | `PERL5LIB` |
| A binary under test | `PATH` — a stub shadowed by a real command of the same name |

The `PATH` row is issue #2451 in this repo: the `bash-antipatterns` probe for
`sg` matched shadow-utils' `sg` instead of ast-grep.
