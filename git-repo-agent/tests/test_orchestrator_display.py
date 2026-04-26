"""Tests for orchestrator display and PR content helpers."""

from git_repo_agent.orchestrator import (
    _build_maintain_phase2_prompt,
    _build_onboard_phase2_prompt,
    _build_pr_content,
    _build_pr_title,
    _extract_fixed_items,
    _extract_report_section,
    _normalize_subject,
    _phase2_system_prompt,
    _tool_detail,
)


class TestToolDetail:
    def test_bash_command(self):
        assert _tool_detail("Bash", {"command": "git status"}) == "git status"

    def test_bash_truncates_long(self):
        cmd = "x" * 200
        result = _tool_detail("Bash", {"command": cmd})
        assert len(result) <= 120
        assert result.endswith("...")

    def test_read_file_path(self):
        assert _tool_detail("Read", {"file_path": "/foo/bar.py"}) == "/foo/bar.py"

    def test_edit_file_path(self):
        assert _tool_detail("Edit", {"file_path": "/foo/bar.py"}) == "/foo/bar.py"

    def test_write_file_path(self):
        assert _tool_detail("Write", {"file_path": "/foo/bar.py"}) == "/foo/bar.py"

    def test_glob_pattern(self):
        assert _tool_detail("Glob", {"pattern": "**/*.py"}) == "**/*.py"

    def test_grep_pattern_only(self):
        assert _tool_detail("Grep", {"pattern": "TODO"}) == "TODO"

    def test_grep_pattern_with_path(self):
        assert _tool_detail("Grep", {"pattern": "TODO", "path": "src/"}) == "TODO in src/"

    def test_agent_description(self):
        assert _tool_detail("Agent", {"description": "explore code"}) == "explore code"

    def test_todowrite_empty(self):
        assert _tool_detail("TodoWrite", {"todos": []}) == ""

    def test_unknown_tool_shows_first_short_value(self):
        assert _tool_detail("CustomTool", {"query": "hello"}) == "hello"

    def test_unknown_tool_skips_long_values(self):
        assert _tool_detail("CustomTool", {"data": "x" * 200}) == ""

    def test_empty_inputs(self):
        assert _tool_detail("Bash", {}) == ""


class TestExtractReportSection:
    def test_empty(self):
        assert _extract_report_section("") == ""

    def test_extracts_from_heading(self):
        output = "Some preamble\n## Health Score\nScore: 85/100\n## Findings\n- Fixed linting"
        result = _extract_report_section(output)
        assert "## Health Score" in result
        assert "## Findings" in result
        assert "preamble" not in result

    def test_maintenance_heading(self):
        output = "# Maintenance Report\nAll good"
        result = _extract_report_section(output)
        assert "# Maintenance Report" in result

    def test_no_headings(self):
        assert _extract_report_section("just plain text\nno headings") == ""


class TestExtractFixedItems:
    def test_empty(self):
        assert _extract_fixed_items("") == []

    def test_no_fixed_section(self):
        report = "## Maintenance Report\n\nHealth Score: 85/100"
        assert _extract_fixed_items(report) == []

    def test_extracts_issues_fixed_bullets(self):
        report = (
            "## Maintenance Report\n"
            "### Issues Fixed\n"
            "- Add install section to README.md\n"
            "- Configure ESLint with default rules\n"
            "### Remaining Issues\n"
            "- Fix failing auth tests\n"
        )
        assert _extract_fixed_items(report) == [
            "Add install section to README.md",
            "Configure ESLint with default rules",
        ]

    def test_skips_placeholder_items(self):
        report = "### Issues Fixed\n- <list of auto-fixed items>\n"
        assert _extract_fixed_items(report) == []

    def test_matches_changes_made_heading(self):
        report = "### Changes Made\n- Update CLAUDE.md with project conventions\n"
        assert _extract_fixed_items(report) == [
            "Update CLAUDE.md with project conventions"
        ]


class TestNormalizeSubject:
    def test_lowercases_first_char(self):
        assert _normalize_subject("Add install section") == "add install section"

    def test_preserves_acronyms(self):
        assert _normalize_subject("CI workflow updated") == "CI workflow updated"

    def test_strips_trailing_period(self):
        assert _normalize_subject("add feature.") == "add feature"

    def test_truncates_long_subjects(self):
        long = "a" * 120
        result = _normalize_subject(long)
        assert len(result) <= 72
        assert result.endswith("...")


class TestBuildPrTitle:
    def test_no_fixed_items_falls_back(self):
        assert _build_pr_title("maintain", []) == "chore: automated maintain run"

    def test_single_fixed_item_becomes_subject(self):
        title = _build_pr_title("maintain", ["Add install section to README"])
        assert title == "chore: add install section to README"

    def test_multiple_fixed_items_summarised(self):
        title = _build_pr_title("maintain", ["a", "b", "c"])
        assert title == "chore: apply 3 automated maintain fixes"


class TestBuildPrContent:
    def test_descriptive_title_from_fixed_items(self):
        output = (
            "## Maintenance Report\n"
            "### Issues Fixed\n"
            "- Add install section to README.md\n"
        )
        title, body = _build_pr_content("maintain", output)
        assert title == "chore: add install section to README.md"
        assert "## Maintenance Report" in body
        assert "Add install section to README.md" in body

    def test_onboard_uses_onboarding_heading(self):
        output = "## Onboarding Report\nAll good"
        _, body = _build_pr_content("onboard", output)
        assert "## Onboarding Report" in body
        assert "## Maintenance Report" not in body

    def test_diagnose_uses_diagnostics_heading(self):
        output = "## Diagnostics Report\nAll good"
        _, body = _build_pr_content("diagnose", output)
        assert "## Diagnostics Report" in body
        assert "## Maintenance Report" not in body

    def test_without_report(self):
        title, body = _build_pr_content("onboard", "")
        assert title == "chore: automated onboard run"
        assert "## Summary" in body
        assert "Automated onboard" in body

    def test_fallback_for_no_headings(self):
        title, body = _build_pr_content("maintain", "no headings here")
        assert title == "chore: automated maintain run"
        assert "## Summary" in body

    def test_report_without_fixed_section_still_uses_report_body(self):
        output = "## Health Score\n85/100"
        title, body = _build_pr_content("maintain", output)
        assert title == "chore: automated maintain run"
        assert "## Maintenance Report" in body
        assert "85/100" in body


FINDINGS_FIXTURE = (
    "1. [docs] README missing install section — auto-fixable\n"
    "2. [security] Dependency CVE-2025-0001 — report-only\n"
    "3. [quality] ESLint not configured — auto-fixable"
)


class TestBuildMaintainPhase2Prompt:
    """Regression tests for the interactive-maintain Phase 2 bug.

    See ADR-003 Revision 2026-04-12 — Phase 2 used to silently skip tool
    calls because it inherited the Phase 1 "stop after findings" anchor.
    The fix passes a fresh, self-contained prompt that embeds findings +
    user selection and instructs the agent to execute.
    """

    def test_embeds_findings_verbatim(self):
        prompt = _build_maintain_phase2_prompt(
            FINDINGS_FIXTURE, "all", "maintain/2026-04-12"
        )
        assert FINDINGS_FIXTURE in prompt

    def test_embeds_user_selection(self):
        prompt = _build_maintain_phase2_prompt(
            FINDINGS_FIXTURE, "1,3", "maintain/2026-04-12"
        )
        assert "1,3" in prompt

    def test_all_selection_instructs_execution(self):
        prompt = _build_maintain_phase2_prompt(
            FINDINGS_FIXTURE, "all", "maintain/2026-04-12"
        )
        # Agent must be told to make tool calls, not re-analyze or stop.
        assert "Apply exactly those fixes" in prompt
        assert "tool calls" in prompt
        assert "maintain/2026-04-12" in prompt
        assert "Do NOT create new branches" in prompt

    def test_none_selection_skips_fixes(self):
        prompt = _build_maintain_phase2_prompt(FINDINGS_FIXTURE, "none", None)
        assert "not to apply any fixes" in prompt
        assert "Skip Step 4" in prompt
        # No worktree note when nothing will be committed.
        assert "Do NOT create new branches" not in prompt

    def test_empty_selection_treated_as_none(self):
        prompt = _build_maintain_phase2_prompt(FINDINGS_FIXTURE, "", None)
        assert "not to apply any fixes" in prompt

    def test_does_not_inherit_phase1_stop_anchor(self):
        # The Phase 1 system prompt tells the agent to "end your response
        # after presenting the numbered findings list". Phase 2 must not
        # repeat that instruction, or the agent will wrap up without
        # making any tool calls (the original bug).
        prompt = _build_maintain_phase2_prompt(
            FINDINGS_FIXTURE, "all", "maintain/2026-04-12"
        )
        assert "end your response after presenting" not in prompt.lower()
        # Explicit anti-instruction should be present instead.
        assert "Execute now" in prompt

    def test_all_forbids_asking_questions(self):
        prompt = _build_maintain_phase2_prompt(
            FINDINGS_FIXTURE, "all", "maintain/2026-04-12"
        )
        assert "Do not ask the user any questions" in prompt


PLAN_FIXTURE = (
    "1. [claude-md] Generate CLAUDE.md with project description and lint commands\n"
    "2. [readme] Generate README.md with quick-start guide\n"
    "3. [linter] Configure Ruff with default rules\n"
    "4. [pre-commit] Set up pre-commit hooks for ruff and gitleaks"
)


class TestBuildOnboardPhase2Prompt:
    """Regression tests for issue #1120 — onboard ended silently when
    `AskUserQuestion` no-ops in SDK subprocess mode. Phase 2 now embeds
    the planning-phase plan and the user's selection in a fresh session.
    See ADR-008.
    """

    def test_embeds_plan_verbatim(self):
        prompt = _build_onboard_phase2_prompt(
            PLAN_FIXTURE, "all", "setup/onboard"
        )
        assert PLAN_FIXTURE in prompt

    def test_embeds_user_selection(self):
        prompt = _build_onboard_phase2_prompt(
            PLAN_FIXTURE, "1,3", "setup/onboard"
        )
        assert "1,3" in prompt

    def test_all_selection_instructs_execution(self):
        prompt = _build_onboard_phase2_prompt(
            PLAN_FIXTURE, "all", "setup/onboard"
        )
        # Agent must be told to make tool calls, not re-plan or stop.
        assert "Execute exactly those steps" in prompt
        assert "tool calls" in prompt
        assert "setup/onboard" in prompt
        assert "Do NOT create new branches" in prompt

    def test_yes_treated_as_apply(self):
        prompt = _build_onboard_phase2_prompt(
            PLAN_FIXTURE, "yes", "setup/onboard"
        )
        # "yes" is a non-none choice so it should route into the execute
        # branch (worktree note included, no skip directive).
        assert "Execute exactly those steps" in prompt
        assert "Do NOT create new branches" in prompt

    def test_none_selection_skips_actions(self):
        prompt = _build_onboard_phase2_prompt(PLAN_FIXTURE, "none", None)
        assert "not to apply any onboarding actions" in prompt
        assert "no changes were applied" in prompt
        # No worktree note when nothing will be committed.
        assert "Do NOT create new branches" not in prompt

    def test_empty_selection_treated_as_none(self):
        prompt = _build_onboard_phase2_prompt(PLAN_FIXTURE, "", None)
        assert "not to apply any onboarding actions" in prompt

    def test_no_keyword_treated_as_none(self):
        prompt = _build_onboard_phase2_prompt(PLAN_FIXTURE, "no", None)
        assert "not to apply any onboarding actions" in prompt

    def test_does_not_inherit_phase1_stop_anchor(self):
        # The Phase 1 system prompt tells the agent to "end your response
        # after presenting the numbered plan". Phase 2 must not repeat
        # that, or the agent will wrap up without tool calls (issue
        # #1120's original failure mode for onboard).
        prompt = _build_onboard_phase2_prompt(
            PLAN_FIXTURE, "all", "setup/onboard"
        )
        assert "end your response after presenting" not in prompt.lower()
        # Explicit anti-instruction should be present instead.
        assert "Execute now" in prompt

    def test_all_forbids_asking_questions(self):
        prompt = _build_onboard_phase2_prompt(
            PLAN_FIXTURE, "all", "setup/onboard"
        )
        assert "Do not ask the user any questions" in prompt


class TestPhase2SystemPrompt:
    def test_appends_override_section(self):
        result = _phase2_system_prompt("# Original system prompt\n\nStop after findings.")
        assert "# Original system prompt" in result
        assert "Phase 2 Override" in result
        assert "make tool calls" in result.lower()

    def test_handles_empty_base(self):
        result = _phase2_system_prompt("")
        assert "Phase 2 Override" in result
