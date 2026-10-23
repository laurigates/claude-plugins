# Dependency resolver - specification

Implement `resolver.py` (Python 3.13, standard library only) with:

    parse_version(s: str) -> Version         # totally ordered, hashable; str(v) == s
    satisfies(version: str, range: str) -> bool
    resolve(registry: dict, requirements: dict) -> dict
    class InvalidRange(ValueError)            # str(e) == "invalid range '<range>'"
    class ResolutionError(Exception)
    class CycleError(ResolutionError)

## Versions

`MAJOR.MINOR.PATCH` with non-negative decimal integers, optionally followed by
`-PRERELEASE`, a dot-separated list of identifiers (`[0-9A-Za-z-]+`).
Ordering follows SemVer 2.0 section 11: compare MAJOR, MINOR, PATCH numerically;
a version with a prerelease is lower than the same version without one;
prerelease identifiers are compared left to right - numeric identifiers
numerically, others lexically by ASCII, numeric < non-numeric, and a shorter
list is lower when all preceding identifiers are equal. Example ascending
order: `1.0.0-alpha < 1.0.0-alpha.1 < 1.0.0-alpha.beta < 1.0.0-beta.2 <
1.0.0-beta.11 < 1.0.0-rc.1 < 1.0.0 < 1.9.0 < 1.10.0`.

## Ranges

    range       := set ( "||" set )*          whitespace around "||" is optional
    set         := comparator ( " "+ comparator )*
    comparator  := "*" | op? partial          no whitespace between op and partial
    op          := ">=" | "<=" | ">" | "<" | "=" | "^" | "~"
    partial     := N | N "." N | N "." N "." N | N "." N "." N "-" PRERELEASE

A range is satisfied if any of its sets is; a set is satisfied if all of its
comparators are. Leading/trailing whitespace of the whole range is ignored.
Anything not matching the grammar (e.g. `^1.x`, `>= 1.0.0`, `1.2.3.4`, `~>1`,
an empty set) raises `InvalidRange`.

Comparator meaning (missing components of a partial are filled with 0 unless
stated otherwise):

| Comparator | Meaning |
|------------|---------|
| `*` | any version |
| `1.2.3`, `=1.2.3` | exactly 1.2.3 |
| `1.2`, `=1.2` | `>=1.2.0 <1.3.0` |
| `1`, `=1` | `>=1.0.0 <2.0.0` |
| `>1.2`, `>=1.2`, `<1.2`, `<=1.2` | compare against 1.2.0 |
| `~1.2.3`, `~1.2` | `>=1.2.x <1.3.0` |
| `~1` | `>=1.0.0 <2.0.0` |
| `^1.2.3` | `>=1.2.3 <2.0.0` |
| `^0.2.3` | `>=0.2.3 <0.3.0` |
| `^0.0.3` | `>=0.0.3 <0.0.4` |

Caret rule in general: the upper bound increments the left-most non-zero
component among the components that were *written*; if all written
components are zero, it increments the last written one (`^0` -> `<1.0.0`,
`^0.0` -> `<0.1.0`, `^1.2` -> `<2.0.0`, `^0.0.0` -> `<0.0.1`). Upper bounds
never carry a prerelease.

**Prereleases.** A version that has a prerelease tag satisfies a set only if
it satisfies all comparators of the set by ordering AND at least one
comparator of that set was written with a prerelease version having the same
MAJOR.MINOR.PATCH. So `^1.0.0` and `*` never match `1.1.0-beta`, while
`>=1.1.0-alpha <2.0.0` matches `1.1.0-beta` but not `1.2.0-beta`.

## Registry and requirements

    registry     = {package_name: {version_string: {dependency_name: range}}}
    requirements = {package_name: range}          # the root's direct requirements

The result maps every *needed* package to the chosen version string. A package
is needed if it is in `requirements` or is a dependency of a chosen version.
Packages that are not needed must not appear.

## Resolution algorithm (normative - the result must be exactly this one)

Depth-first search with backtracking over partial assignments:

1. Among needed packages that are not assigned yet, take the one whose name is
   alphabetically smallest (Python string order).
2. Its candidates are its registry versions that satisfy the root requirement
   on it (if any) and the ranges placed on it by every already-assigned
   version's dependencies, tried from highest to lowest version.
3. A candidate is skipped if one of its dependencies is unknown to the
   registry, has an invalid range, or names an already-assigned package whose
   assigned version does not satisfy that range.
4. Assign the first acceptable candidate and continue from step 1; if the
   remaining search fails, undo and try the next candidate. If no candidate
   leads to a complete assignment, this step fails (backtrack).
5. The first complete assignment found is the result.

## Errors

Checked in this order, the first applicable one is raised:

1. A root requirement with an invalid range: `ResolutionError("invalid range
   '<range>' for '<name>'")` (root requirements are examined in name order).
2. A root requirement naming a package not in the registry:
   `ResolutionError("unknown package '<name>'")` (name order).
3. A root requirement no registry version satisfies:
   `ResolutionError("no version of '<name>' satisfies '<range>'")` (name order).
4. The search fails: `ResolutionError("no solution for requirements: " +
   ", ".join(f"{name} {range}" for name, range in sorted(requirements.items())))`.
5. The resolved graph (edges from each chosen package to its dependencies)
   contains a cycle: `CycleError("dependency cycle: " + " -> ".join(...))`
   listing `name@version` nodes along the cycle and repeating the first node at
   the end, e.g. `dependency cycle: a@1.0.0 -> b@2.1.0 -> a@1.0.0`. The cycle
   reported is found by a depth-first search that starts at the alphabetically
   smallest package lying on any cycle, visits dependencies in alphabetical
   order, never revisits a node, and stops at the first path that returns to
   the start. A package depending on itself is the cycle `a@1.0.0 -> a@1.0.0`.
   (Cycles are only checked after a resolution was found; they do not cause
   backtracking.)

Ranges written in `requirements` are reported exactly as given (not stripped).
