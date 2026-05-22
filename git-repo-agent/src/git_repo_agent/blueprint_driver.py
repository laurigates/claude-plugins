"""Blueprint state-machine driver.

Runs the blueprint lifecycle as a deterministic sequence of discrete
``ClaudeSDKClient`` sessions — one compiled skill per session — rather
than a single monolithic subagent prompt. See ADR-006.

Each phase:
    1. Reads filesystem state to decide whether to skip.
    2. Loads exactly one compiled skill as its system prompt.
    3. Opens a fresh ``ClaudeSDKClient``, sends a focused prompt, streams.
    4. Lets subsequent phases read updated disk state.

Advantages over the old single-Task approach:
    * No prompt bloat: only the active skill's content is loaded.
    * Guaranteed ordering: Python sequences the steps; the LLM cannot
      skip ``sync-ids`` or ``adr-validate``.
    * Per-phase model tiering.
    * Resumable: disk artifacts persist across phase failures.

Related:
    * ``prompts/compiler.py`` — ``get_compiled_skill()``.
    * ``orchestrator.py`` — uses ``_stream_messages_collecting`` pattern.
    * ADR-003 — two-phase ``ClaudeSDKClient`` precedent.
    * ADR-006 — this design.
"""

from __future__ import annotations

import json
import subprocess
from dataclasses import dataclass, field
from pathlib import Path

from claude_agent_sdk import (
    AssistantMessage,
    ClaudeAgentOptions,
    ClaudeSDKClient,
    ResultMessage,
    TextBlock,
    ToolUseBlock,
)
from rich.console import Console

from .prompts.compiler import get_compiled_skill

_console = Console()


# --------------------------------------------------------------------------
# Project-size sniff (issue #1355)
# --------------------------------------------------------------------------
#
# Heavy derive-* phases produce process documentation that dwarfs tiny
# projects. A 5-line Python loader stub with one feat commit does not need
# 8 ADRs and a TRP — those are reverse-engineered from already-existing
# CLAUDE.md content and pad the repo with hundreds of lines of ceremony.
#
# A "tiny single-feat project" is detected by two cheap signals:
#
#   - `git log --grep '^fix' | wc -l` == 0 (no bug-fix commits)
#   - `git log --pretty=oneline | wc -l` < `_TINY_COMMIT_THRESHOLD`
#
# When tiny, the derive-tests phase is a no-op by definition (no fixes
# means no regressions to capture). When also single-feat (`feat` count
# == 1), derive-adr / derive-prd / derive-rules / feature-tracker-sync
# add little signal — the CLAUDE.md + README already describe the project
# and reverse-engineering a multi-option ADR table from one feat commit is
# noise.

_TINY_COMMIT_THRESHOLD = 10
# Phases that are skipped when the repo has zero `fix:` commits — these
# pure regression-capture phases have nothing to mine on a clean history.
_SKIP_PHASES_NO_FIXES: frozenset[str] = frozenset({"derive_tests"})

# Phases skipped when the project is tiny AND has one or zero `feat:`
# commits. These produce reverse-engineered process docs from already-
# existing CLAUDE.md/README content for projects that don't need them.
_SKIP_PHASES_TINY_SINGLE_FEAT: frozenset[str] = frozenset(
    {"derive_adr", "derive_prd", "derive_rules", "feature_tracker_sync"}
)


def _git_commit_count(repo_path: Path, *grep_args: str) -> int | None:
    """Count git commits matching ``grep_args``. ``None`` on git failure.

    Used to sniff project size without paying the cost of full ``git log``
    parsing. Returns ``None`` (not 0) on failure so the caller can treat
    "unknown" as "don't gate" — never silently strip phases because of a
    broken git invocation.
    """
    try:
        result = subprocess.run(
            ["git", "log", "--pretty=oneline", *grep_args],
            cwd=repo_path,
            capture_output=True,
            text=True,
            timeout=5,
        )
    except (subprocess.SubprocessError, OSError):
        return None
    if result.returncode != 0:
        return None
    return sum(1 for line in result.stdout.splitlines() if line.strip())


@dataclass(frozen=True)
class ProjectSize:
    """Result of the project-size sniff.

    All counts are ``None`` when git failed (treat as "unknown — don't
    gate"). When all three are populated, the booleans below reflect the
    gating decisions for the issue #1355 heuristic.
    """

    total_commits: int | None
    feat_commits: int | None
    fix_commits: int | None

    @property
    def is_known(self) -> bool:
        return (
            self.total_commits is not None
            and self.feat_commits is not None
            and self.fix_commits is not None
        )

    @property
    def has_no_fixes(self) -> bool:
        """True when the repo has zero ``fix:`` commits (and we know it)."""
        return self.is_known and self.fix_commits == 0

    @property
    def is_tiny_single_feat(self) -> bool:
        """True for short-history single-feat projects (and we know it).

        Tiny = fewer than ``_TINY_COMMIT_THRESHOLD`` commits total.
        Single-feat = one or zero ``feat:`` commits.
        """
        return (
            self.is_known
            and self.total_commits < _TINY_COMMIT_THRESHOLD
            and self.feat_commits is not None
            and self.feat_commits <= 1
        )


def sniff_project_size(repo_path: Path) -> ProjectSize:
    """Sniff a repo's git history to size the blueprint phase chain.

    Returns a :class:`ProjectSize` with ``None`` fields if git is
    unavailable or the repo has no commits yet — callers should treat
    unknown as "don't gate" and run every phase.
    """
    total = _git_commit_count(repo_path)
    feat = _git_commit_count(repo_path, "--grep=^feat", "-E")
    fix = _git_commit_count(repo_path, "--grep=^fix", "-E")
    return ProjectSize(total_commits=total, feat_commits=feat, fix_commits=fix)


# --------------------------------------------------------------------------
# Phase registry
# --------------------------------------------------------------------------


@dataclass(frozen=True)
class Phase:
    """One step in the blueprint lifecycle."""

    name: str
    skill_relpath: str
    model: str  # "haiku" | "sonnet" | "opus"
    # Human-readable one-line instruction for the LLM. The compiled skill
    # is the system prompt; this is the actual user-turn query.
    invocation: str


# Ordered list of phases for onboard.
# Order matters: init must come before derive-*; sync-ids before adr-validate.
ONBOARD_PHASES: tuple[Phase, ...] = (
    Phase(
        name="workspace_scan",
        skill_relpath="blueprint-plugin/skills/blueprint-workspace-scan/SKILL.md",
        model="haiku",
        invocation=(
            "Scan this repository for monorepo child workspaces. Report the "
            "result as a short summary. If no `docs/blueprint/manifest.json` "
            "exists yet (single-repo bootstrap), output "
            "`WORKSPACE_SCAN: single-repo` and stop."
        ),
    ),
    Phase(
        name="init",
        skill_relpath="blueprint-plugin/skills/blueprint-init/SKILL.md",
        model="sonnet",
        invocation=(
            "Initialize the blueprint structure in this repository. Do NOT "
            "ask any questions — if `docs/blueprint/manifest.json` already "
            "exists, skip reinitialization and stop. Otherwise create the "
            "standard blueprint layout (`docs/blueprint/` with `prds/`, "
            "`adrs/`, `rules/`, `manifest.json`, `feature-tracker.md`) using "
            "the latest format version. Proceed without user confirmation."
        ),
    ),
    Phase(
        name="derive_prd",
        skill_relpath="blueprint-plugin/skills/blueprint-derive-prd/SKILL.md",
        model="sonnet",
        invocation=(
            "Derive PRD documents for this project from existing docs, "
            "README, and codebase signals. Write them to "
            "`docs/blueprint/prds/`. Do not ask the user any questions."
        ),
    ),
    Phase(
        name="derive_adr",
        skill_relpath="blueprint-plugin/skills/blueprint-derive-adr/SKILL.md",
        model="sonnet",
        invocation=(
            "Derive ADRs from observable architectural decisions in this "
            "repository (language, framework, test runner, CI system, "
            "package manager, directory structure). Write them to "
            "`docs/blueprint/adrs/`. Do not ask the user any questions."
        ),
    ),
    Phase(
        name="derive_rules",
        skill_relpath="blueprint-plugin/skills/blueprint-derive-rules/SKILL.md",
        model="sonnet",
        invocation=(
            "Derive project-specific rules from git history and established "
            "patterns. Write them to `docs/blueprint/rules/` (or the "
            "rules location defined in the manifest). Do not ask the user "
            "any questions."
        ),
    ),
    Phase(
        name="derive_tests",
        skill_relpath="blueprint-plugin/skills/blueprint-derive-tests/SKILL.md",
        model="sonnet",
        invocation=(
            "Identify untested bug fixes and coverage gaps. Record them as "
            "blueprint artifacts or notes on existing PRDs/ADRs. Do not ask "
            "the user any questions."
        ),
    ),
    Phase(
        name="sync_ids",
        skill_relpath="blueprint-plugin/skills/blueprint-sync-ids/SKILL.md",
        model="haiku",
        invocation=(
            "Assign sequential IDs to any new PRDs/ADRs/rules and update "
            "`docs/blueprint/manifest.json` so every document is registered."
        ),
    ),
    Phase(
        name="adr_validate",
        skill_relpath="blueprint-plugin/skills/blueprint-adr-validate/SKILL.md",
        model="haiku",
        invocation=(
            "Validate ADR relationships and cross-references. Report any "
            "broken links, missing IDs, or inconsistencies. Do not modify "
            "files unless fixing a clear inconsistency."
        ),
    ),
    Phase(
        name="feature_tracker_sync",
        skill_relpath="blueprint-plugin/skills/blueprint-feature-tracker-sync/SKILL.md",
        model="haiku",
        invocation=(
            "Sync the feature tracker with the current set of PRDs and "
            "ADRs so every feature appears in the tracker table."
        ),
    ),
)


# --------------------------------------------------------------------------
# Lifecycle phase registries (invoked via the `blueprint` CLI subcommand)
# --------------------------------------------------------------------------

# Read-only status report: current blueprint version + feature tracker stats.
STATUS_PHASES: tuple[Phase, ...] = (
    Phase(
        name="status",
        skill_relpath="blueprint-plugin/skills/blueprint-status/SKILL.md",
        model="haiku",
        invocation=(
            "Report the current blueprint configuration: format version, "
            "document counts per type, and any available upgrades. Use "
            "`--report-only` semantics — do not prompt the user, do not "
            "modify files."
        ),
    ),
    Phase(
        name="feature_tracker_status",
        skill_relpath="blueprint-plugin/skills/blueprint-feature-tracker-status/SKILL.md",
        model="haiku",
        invocation=(
            "Display feature tracker statistics. If feature tracking is not "
            "enabled (no `docs/blueprint/feature-tracker.json`), say so and "
            "stop — do not create anything. Do not ask the user questions."
        ),
    ),
)

# Migrate the blueprint to the latest format, then re-sync IDs and validate.
UPGRADE_PHASES: tuple[Phase, ...] = (
    Phase(
        name="upgrade",
        skill_relpath="blueprint-plugin/skills/blueprint-upgrade/SKILL.md",
        model="sonnet",
        invocation=(
            "Upgrade the blueprint to the latest format version. Apply all "
            "required migrations without asking the user to confirm each "
            "step. If the blueprint is already at the latest version, say "
            "so and stop."
        ),
    ),
    Phase(
        name="sync_ids",
        skill_relpath="blueprint-plugin/skills/blueprint-sync-ids/SKILL.md",
        model="haiku",
        invocation=(
            "Re-assign sequential IDs after migration and update "
            "`docs/blueprint/manifest.json` so every document is registered."
        ),
    ),
    Phase(
        name="adr_validate",
        skill_relpath="blueprint-plugin/skills/blueprint-adr-validate/SKILL.md",
        model="haiku",
        invocation=(
            "Validate ADR relationships after migration. Report broken "
            "links, missing IDs, or inconsistencies introduced by the "
            "version bump."
        ),
    ),
)

# Drift detection: report stale generated content and (non-interactively)
# regenerate or suggest promotion.
SYNC_PHASES: tuple[Phase, ...] = (
    Phase(
        name="sync",
        skill_relpath="blueprint-plugin/skills/blueprint-sync/SKILL.md",
        model="sonnet",
        invocation=(
            "Report the status of generated content (fresh / modified / "
            "stale). Do not interactively prompt — for any modified files, "
            "list them as candidates for `/blueprint:promote` and stop. For "
            "stale files, regenerate them."
        ),
    ),
)

# Monorepo/workspace refresh: re-scan children and refresh rollup stats.
SCAN_PHASES: tuple[Phase, ...] = (
    Phase(
        name="workspace_scan",
        skill_relpath="blueprint-plugin/skills/blueprint-workspace-scan/SKILL.md",
        model="haiku",
        invocation=(
            "Scan the filesystem for child blueprint workspaces and refresh "
            "the root manifest's `workspaces.children` registry with cached "
            "feature-tracker stats. Do not prompt the user."
        ),
    ),
    Phase(
        name="feature_tracker_sync",
        skill_relpath="blueprint-plugin/skills/blueprint-feature-tracker-sync/SKILL.md",
        model="haiku",
        invocation=(
            "Sync the feature tracker with the current workspace roster "
            "so portfolio rollups reflect child updates."
        ),
    ),
    Phase(
        name="feature_tracker_status",
        skill_relpath="blueprint-plugin/skills/blueprint-feature-tracker-status/SKILL.md",
        model="haiku",
        invocation=(
            "Display the refreshed feature tracker statistics and portfolio "
            "rollup. Do not prompt the user."
        ),
    ),
)


# `git-repo-agent new` runs only the init phase. A freshly created repo has
# no source material for the derive-* phases to mine, so running them would
# be noisy at best (ADR-007).
NEW_PHASES: tuple[Phase, ...] = (
    Phase(
        name="init",
        skill_relpath="blueprint-plugin/skills/blueprint-init/SKILL.md",
        model="sonnet",
        invocation=(
            "Initialize the blueprint structure in this brand-new repository. "
            "Create the standard layout (`docs/blueprint/` with `prds/`, "
            "`adrs/`, `rules/`, `manifest.json`, `feature-tracker.md`) using "
            "the latest format version. A seed PRD already exists at "
            "`docs/prds/0001-project-goal.md` — register it in the manifest "
            "rather than regenerating it. Do not ask the user questions."
        ),
    ),
)


# Named registries so the CLI can dispatch by mode name.
PHASE_REGISTRIES: dict[str, tuple[Phase, ...]] = {
    "onboard": ONBOARD_PHASES,
    "new": NEW_PHASES,
    "status": STATUS_PHASES,
    "upgrade": UPGRADE_PHASES,
    "sync": SYNC_PHASES,
    "scan": SCAN_PHASES,
}


# --------------------------------------------------------------------------
# Single-skill commands (no args)
# --------------------------------------------------------------------------

ADR_LIST_PHASES: tuple[Phase, ...] = (
    Phase(
        name="adr_list",
        skill_relpath="blueprint-plugin/skills/blueprint-adr-list/SKILL.md",
        model="haiku",
        invocation=(
            "List every ADR under `docs/blueprint/adrs/` as a markdown "
            "table with columns ID, Title, Status, Date, Domain. Print the "
            "table to stdout. Do not modify any files."
        ),
    ),
)

DERIVE_PLANS_PHASES: tuple[Phase, ...] = (
    Phase(
        name="derive_plans",
        skill_relpath="blueprint-plugin/skills/blueprint-derive-plans/SKILL.md",
        model="sonnet",
        invocation=(
            "Derive PRDs, ADRs, and PRPs from git history and existing "
            "documentation. Write artifacts under `docs/blueprint/`. Do "
            "not ask the user questions."
        ),
    ),
)

GENERATE_RULES_PHASES: tuple[Phase, ...] = (
    Phase(
        name="generate_rules",
        skill_relpath="blueprint-plugin/skills/blueprint-generate-rules/SKILL.md",
        model="sonnet",
        invocation=(
            "Generate project-specific rules from the PRDs under "
            "`docs/blueprint/prds/`. Write them to `.claude/rules/`. "
            "Support path-specific rules via `paths` frontmatter. Do not "
            "ask the user questions."
        ),
    ),
)


PHASE_REGISTRIES.update(
    {
        "adr-list": ADR_LIST_PHASES,
        "derive-plans": DERIVE_PLANS_PHASES,
        "generate-rules": GENERATE_RULES_PHASES,
    }
)


# --------------------------------------------------------------------------
# Dynamic phase factories (arg-taking commands)
# --------------------------------------------------------------------------


def make_prp_create_phase(feature: str) -> Phase:
    """Build a one-shot phase that creates a PRP for ``feature``.

    Args:
        feature: Feature slug such as ``auth-oauth2`` or
            ``api-rate-limiting``. Will be embedded in the prompt.
    """
    return Phase(
        name="prp_create",
        skill_relpath="blueprint-plugin/skills/blueprint-prp-create/SKILL.md",
        model="sonnet",
        invocation=(
            f"Create a PRP (Product Requirement Prompt) for the feature "
            f"`{feature}`. Perform systematic research, assemble curated "
            "context, and define validation gates. Write the PRP under "
            "`docs/blueprint/prps/`. Do not ask the user questions — if "
            "ambiguities remain, record them as TODOs inside the PRP and "
            "continue."
        ),
    )


def make_prp_execute_phase(prp_name: str) -> Phase:
    """Build a one-shot phase that executes an existing PRP."""
    return Phase(
        name="prp_execute",
        skill_relpath="blueprint-plugin/skills/blueprint-prp-execute/SKILL.md",
        model="sonnet",
        invocation=(
            f"Execute the PRP named `{prp_name}` using the validation-loop "
            "TDD workflow. Run each validation gate to green before "
            "proceeding. Do not ask the user questions — if a gate cannot "
            "be satisfied, stop and report the blocker."
        ),
    )


def make_work_order_phase(
    from_issue: int | None = None, publish: bool = True
) -> Phase:
    """Build a one-shot phase that creates an isolated work order."""
    hints: list[str] = []
    if from_issue is not None:
        hints.append(f"Create the work order from GitHub issue #{from_issue}.")
    if not publish:
        hints.append("Do not publish the work order — keep it local only.")
    hint_text = (" " + " ".join(hints)) if hints else ""
    return Phase(
        name="work_order",
        skill_relpath="blueprint-plugin/skills/blueprint-work-order/SKILL.md",
        model="sonnet",
        invocation=(
            "Create a work order with minimal context suitable for isolated "
            "subagent execution." + hint_text + " Do not ask the user "
            "questions — infer the scope from the issue body or existing "
            "PRDs."
        ),
    )


def make_promote_phase(target: str) -> Phase:
    """Build a one-shot phase that promotes generated content to custom."""
    return Phase(
        name="promote",
        skill_relpath="blueprint-plugin/skills/blueprint-promote/SKILL.md",
        model="haiku",
        invocation=(
            f"Promote the generated artifact `{target}` to the custom "
            "layer so future regeneration preserves local modifications. "
            "Mark the entry as acknowledged in the manifest. Do not ask "
            "the user questions."
        ),
    )


# --------------------------------------------------------------------------
# Driver
# --------------------------------------------------------------------------


@dataclass
class DriverOptions:
    """Runtime flags for the blueprint driver.

    ``size_aware`` enables the issue #1355 heuristic: derive-* phases
    that would reverse-engineer process docs from already-existing
    CLAUDE.md/README content are skipped when the repo is tiny and
    has no bug-fix history to mine. Set to ``False`` to force the
    full chain (useful for testing or when you really want the
    docs).
    """

    dry_run: bool = False
    skip: frozenset[str] = frozenset()  # phase names to skip by policy
    non_interactive: bool = False  # suppress AskUserQuestion tool
    max_turns_per_phase: int = 20
    size_aware: bool = True


@dataclass
class PhaseResult:
    name: str
    status: str  # "ok" | "skipped" | "error"
    message: str = ""
    text: str = ""


@dataclass
class DriverResult:
    phases: list[PhaseResult] = field(default_factory=list)

    @property
    def succeeded(self) -> bool:
        return all(p.status != "error" for p in self.phases)


class BlueprintDriver:
    """Deterministic phase sequencer for the blueprint lifecycle.

    Usage::

        driver = BlueprintDriver(repo_path, DriverOptions(dry_run=False))
        result = await driver.run()
        if not result.succeeded:
            ...
    """

    def __init__(self, repo_path: Path, options: DriverOptions | None = None) -> None:
        self.repo_path = repo_path
        self.options = options or DriverOptions()
        self._project_size: ProjectSize | None = None

    @property
    def project_size(self) -> ProjectSize:
        """Lazily-sniffed project size used by ``_artifact_skip_reason``.

        Cached on the driver so we run ``git log`` once per ``run()``
        call rather than re-shelling per phase.
        """
        if self._project_size is None:
            self._project_size = sniff_project_size(self.repo_path)
        return self._project_size

    async def run(self, phases: tuple[Phase, ...] = ONBOARD_PHASES) -> DriverResult:
        result = DriverResult()
        _console.print(
            f"[bold]Blueprint driver[/bold] → {len(phases)} phase(s) "
            f"in [cyan]{self.repo_path}[/cyan]"
        )
        if self.options.dry_run:
            _console.print("[yellow]DRY RUN — no filesystem writes[/yellow]")
        if self.options.size_aware:
            size = self.project_size
            if size.is_known and (size.has_no_fixes or size.is_tiny_single_feat):
                _console.print(
                    f"[dim]Project sniff: total={size.total_commits} "
                    f"feat={size.feat_commits} fix={size.fix_commits} — "
                    f"size-aware gating active (issue #1355).[/dim]"
                )

        for phase in phases:
            if self._should_skip(phase):
                _console.print(
                    f"[dim]  • {phase.name}: skipped (policy)[/dim]"
                )
                result.phases.append(
                    PhaseResult(name=phase.name, status="skipped", message="policy")
                )
                continue

            skip_reason = self._artifact_skip_reason(phase)
            if skip_reason is not None:
                _console.print(
                    f"[dim]  • {phase.name}: skipped ({skip_reason})[/dim]"
                )
                result.phases.append(
                    PhaseResult(name=phase.name, status="skipped", message=skip_reason)
                )
                continue

            _console.print(f"[bold cyan]  ▶ {phase.name}[/bold cyan] ({phase.model})")
            try:
                text = await self._run_phase(phase)
                result.phases.append(
                    PhaseResult(name=phase.name, status="ok", text=text)
                )
            except Exception as exc:  # noqa: BLE001
                _console.print(
                    f"[red]  ✗ {phase.name} failed: {exc}[/red]"
                )
                result.phases.append(
                    PhaseResult(name=phase.name, status="error", message=str(exc))
                )
                # A failed phase doesn't stop the sequence — later phases
                # may still make progress, and the user gets a full report.

        return result

    # ----- skip policy --------------------------------------------------

    def _should_skip(self, phase: Phase) -> bool:
        return phase.name in self.options.skip

    def _artifact_skip_reason(self, phase: Phase) -> str | None:
        """Check disk state to decide whether a phase can be skipped.

        Keep this logic conservative — when in doubt, run the phase.
        The skills themselves are idempotent.
        """
        manifest_json = self.repo_path / "docs" / "blueprint" / "manifest.json"
        if phase.name == "init" and manifest_json.exists():
            return "manifest exists"

        # Monorepo-only phases: skip when workspaces registry is absent
        # and we're not actually in a monorepo root.
        if phase.name == "workspace_scan":
            # Always run — the phase itself short-circuits if single-repo.
            return None

        # Size-aware gating (issue #1355).
        if self.options.size_aware:
            size = self.project_size
            if (
                size.has_no_fixes
                and phase.name in _SKIP_PHASES_NO_FIXES
            ):
                return "no fix: commits in history (size-aware)"
            if (
                size.is_tiny_single_feat
                and phase.name in _SKIP_PHASES_TINY_SINGLE_FEAT
            ):
                return (
                    f"tiny single-feat project "
                    f"({size.total_commits} commits, "
                    f"{size.feat_commits} feat) — size-aware"
                )

        return None

    # ----- phase execution ----------------------------------------------

    async def _run_phase(self, phase: Phase) -> str:
        try:
            skill_content = get_compiled_skill(phase.skill_relpath)
        except FileNotFoundError as exc:
            raise RuntimeError(f"missing skill: {exc}") from exc

        system_prompt = (
            f"# Blueprint phase: {phase.name}\n\n"
            "You are executing a single phase of the blueprint lifecycle. "
            "Focus only on the steps in the skill below. Do not ask the "
            "user questions — this is a non-interactive pipeline. Do not "
            "invoke other skills or phases. Commit nothing; the outer "
            "orchestrator handles git state.\n\n"
            f"## Skill: {Path(phase.skill_relpath).parent.name}\n\n"
            f"{skill_content}\n"
        )

        allowed_tools = ["Read", "Write", "Edit", "Bash", "Glob", "Grep", "TodoWrite"]

        options = ClaudeAgentOptions(
            system_prompt=system_prompt,
            cwd=str(self.repo_path),
            max_turns=self.options.max_turns_per_phase,
            allowed_tools=allowed_tools,
            permission_mode="acceptEdits",
            model=phase.model,
            env={
                "CLAUDECODE": "",
                "DRY_RUN": str(self.options.dry_run),
                "BLUEPRINT_PHASE": phase.name,
            },
        )

        prompt = self._build_prompt(phase)

        collected: list[str] = []
        async with ClaudeSDKClient(options) as client:
            await client.query(prompt)
            async for message in client.receive_response():
                self._display(message, collected)

        return "\n".join(collected)

    def _build_prompt(self, phase: Phase) -> str:
        parts = [
            phase.invocation,
            f"Working directory: {self.repo_path}.",
        ]
        if self.options.dry_run:
            parts.append(
                "DRY RUN — describe what you would change and where, but "
                "do NOT write or edit any files."
            )
        # Pass a minimal blueprint state hint so phases can adapt without
        # re-scanning the filesystem from scratch.
        hint = self._state_hint()
        if hint:
            parts.append(hint)
        return " ".join(parts)

    def _state_hint(self) -> str:
        blueprint_dir = self.repo_path / "docs" / "blueprint"
        manifest_json = blueprint_dir / "manifest.json"
        if not manifest_json.exists():
            return "State: blueprint is not yet initialized."
        try:
            manifest = json.loads(manifest_json.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            return f"State: {manifest_json} exists but could not be parsed."
        version = manifest.get("format_version") or manifest.get("version")
        doc_count = len(manifest.get("documents", []) or [])
        return (
            f"State: blueprint already initialized (format_version={version}, "
            f"{doc_count} document(s) in manifest)."
        )

    # ----- streaming output ---------------------------------------------

    @staticmethod
    def _display(message, collected: list[str]) -> None:
        if isinstance(message, AssistantMessage):
            for block in message.content:
                if isinstance(block, TextBlock):
                    _console.print(block.text)
                    collected.append(block.text)
                elif isinstance(block, ToolUseBlock):
                    _console.print(
                        f"[dim]    Tool: {block.name}[/dim]",
                        highlight=False,
                    )
        elif isinstance(message, ResultMessage):
            if message.is_error:
                _console.print(f"[red]    error: {message.result}[/red]")
            if message.total_cost_usd:
                _console.print(
                    f"[dim]    cost: ${message.total_cost_usd:.4f}[/dim]"
                )
