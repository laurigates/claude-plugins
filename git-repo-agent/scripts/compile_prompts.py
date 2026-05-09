#!/usr/bin/env python3
"""CLI tool for inspecting/debugging compiled subagent prompts.

Writes compiled prompts to disk or checks if previously-generated files
are up-to-date. Runtime compilation is handled by
git_repo_agent.prompts.compiler — this script is a thin wrapper for
debugging and inspection.

Usage:
    python scripts/compile_prompts.py              # write to generated/
    python scripts/compile_prompts.py --check      # verify output matches runtime
    python scripts/compile_prompts.py --stdout      # print to stdout
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

# Allow running from scripts/ without installing the package
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))

from git_repo_agent.prompts.compiler import (  # noqa: E402
    SUBAGENT_SKILLS,
    _generated_skill_path,
    compile_skill,
    get_compiled_prompt,
)

REPO_ROOT = Path(__file__).resolve().parent.parent
PLUGINS_ROOT = REPO_ROOT.parent
OUTPUT_DIR = REPO_ROOT / "src" / "git_repo_agent" / "prompts" / "generated"
SKILLS_OUTPUT_DIR = OUTPUT_DIR / "skills"


def _collect_blueprint_phase_skills() -> list[str]:
    """Return every ``skill_relpath`` referenced by the blueprint driver.

    Parses ``blueprint_driver.py`` statically rather than importing it —
    the driver pulls in ``claude_agent_sdk`` at module load, which the
    build script does not need.
    """
    import re

    driver_src = (
        REPO_ROOT / "src" / "git_repo_agent" / "blueprint_driver.py"
    ).read_text(encoding="utf-8")
    return sorted(set(re.findall(r'skill_relpath="([^"]+)"', driver_src)))


def _process_skill(
    skill_relpath: str, *, check: bool, stdout: bool
) -> tuple[bool, bool]:
    """Compile ``skill_relpath``; return (handled, stale)."""
    source = PLUGINS_ROOT / skill_relpath
    if not source.exists():
        # Standalone install: source not present. Nothing to write or check.
        return False, False
    compiled = compile_skill(source)
    if stdout:
        print(f"=== {skill_relpath} ===")
        print(compiled)
        return True, False
    output_path = _generated_skill_path(skill_relpath)
    rel = output_path.relative_to(REPO_ROOT)
    if check:
        if not output_path.exists():
            print(f"MISSING: {rel}")
            return True, True
        if output_path.read_text(encoding="utf-8") != compiled:
            print(f"STALE: {rel}")
            return True, True
        print(f"OK: {rel}")
        return True, False
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(compiled, encoding="utf-8")
    print(f"Generated {rel} ({compiled.count(chr(10))} lines)")
    return True, False


def main() -> int:
    parser = argparse.ArgumentParser(description="Inspect compiled subagent prompts")
    parser.add_argument(
        "--check",
        action="store_true",
        help="Check if generated files match runtime output (exit 1 if stale)",
    )
    parser.add_argument(
        "--stdout",
        action="store_true",
        help="Print compiled prompts to stdout instead of writing files",
    )
    args = parser.parse_args()

    if args.stdout:
        for name in SUBAGENT_SKILLS:
            compiled = get_compiled_prompt(name)
            print(f"=== {name} ===")
            print(compiled)
        for skill_relpath in _collect_blueprint_phase_skills():
            _process_skill(skill_relpath, check=False, stdout=True)
        return 0

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    SKILLS_OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    stale = False

    for name in SUBAGENT_SKILLS:
        output_path = OUTPUT_DIR / f"{name}_skills.md"
        compiled = get_compiled_prompt(name)

        if args.check:
            if not output_path.exists():
                print(f"MISSING: {output_path.relative_to(REPO_ROOT)}")
                stale = True
            elif output_path.read_text(encoding="utf-8") != compiled:
                print(f"STALE: {output_path.relative_to(REPO_ROOT)}")
                stale = True
            else:
                print(f"OK: {output_path.relative_to(REPO_ROOT)}")
        else:
            output_path.write_text(compiled, encoding="utf-8")
            lines = compiled.count("\n")
            print(f"Generated {output_path.relative_to(REPO_ROOT)} ({lines} lines)")

    for skill_relpath in _collect_blueprint_phase_skills():
        _, this_stale = _process_skill(
            skill_relpath, check=args.check, stdout=False
        )
        stale = stale or this_stale

    if args.check and stale:
        print("\nGenerated files are stale (runtime compilation handles this automatically).")
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
