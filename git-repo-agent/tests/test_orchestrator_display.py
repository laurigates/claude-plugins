"""Tests for orchestrator display and PR content helpers."""

from git_repo_agent.orchestrator import _tool_detail, _extract_report_section, _build_pr_content


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


class TestBuildPrContent:
    def test_with_report(self):
        title, body = _build_pr_content("maintain", "## Health Score\n85/100")
        assert title == "chore: maintain repository"
        assert "## Maintenance Report" in body
        assert "85/100" in body

    def test_without_report(self):
        title, body = _build_pr_content("onboard", "")
        assert title == "chore: onboard repository"
        assert "## Summary" in body
        assert "Automated onboard" in body

    def test_fallback_for_no_headings(self):
        title, body = _build_pr_content("maintain", "no headings here")
        assert "## Summary" in body
