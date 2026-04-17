"""Human-readable report rendering for the audit."""

from __future__ import annotations

import json

from rich.console import Console
from rich.table import Table

from vault_agent.analyzers.audit import VaultAudit


def render_terminal(audit: VaultAudit, console: Console | None = None) -> None:
    """Pretty-print the audit summary to the given console."""
    console = console or Console()
    fm = audit.frontmatter
    lnk = audit.links
    graph = audit.graph
    stubs = audit.stubs
    mocs = audit.mocs
    dups = audit.duplicates
    h = audit.health

    console.rule(f"[bold]Vault audit — {audit.vault_root}[/bold]")
    console.print(
        f"Total notes: [bold]{fm.total_notes}[/bold]   "
        f"Health: [bold]{h.total}[/bold]/100 "
        f"(tags={h.tags} links={h.links} orphans={h.orphans} stubs={h.stubs} mocs={h.mocs})"
    )

    t = Table(title="Frontmatter & tag findings", show_edge=False)
    t.add_column("Issue", justify="left")
    t.add_column("Count", justify="right")
    t.add_row("No frontmatter", str(len(fm.notes_without_frontmatter)))
    t.add_row("Legacy id: field", str(len(fm.notes_with_legacy_id)))
    t.add_row("Bare placeholder tag (📝/🌱)", str(len(fm.notes_with_bare_placeholder)))
    t.add_row("Null tag values", str(len(fm.notes_with_null_tags)))
    t.add_row("No tags at all", str(len(fm.notes_with_no_tags)))
    t.add_row("> 5 tags", str(len(fm.notes_over_tagged)))
    t.add_row("Templater leakage", str(len(fm.notes_with_templater_leak)))
    t.add_row("Corrupt emoji bytes", str(len(fm.notes_with_corrupt_emoji)))
    t.add_row("FVH missing context", str(len(fm.fvh_notes_missing_context)))
    console.print(t)

    t = Table(title="Links", show_edge=False)
    t.add_column("Issue", justify="left")
    t.add_column("Count", justify="right")
    t.add_row("Total wikilinks", str(lnk.total_wikilinks))
    t.add_row("Broken", str(lnk.broken_count))
    t.add_row("Ambiguous instances", str(lnk.ambiguous_count))
    t.add_row("Ambiguous basenames", str(len(lnk.ambiguous_basenames)))
    console.print(t)

    if lnk.top_broken(10):
        t = Table(title="Top broken targets", show_edge=False)
        t.add_column("Target")
        t.add_column("Instances", justify="right")
        for target, count in lnk.top_broken(10):
            t.add_row(target, str(count))
        console.print(t)

    t = Table(title="Graph", show_edge=False)
    t.add_column("Issue", justify="left")
    t.add_column("Count", justify="right")
    t.add_row("Meaningful orphans", str(len(graph.meaningful_orphans)))
    t.add_row("Expected orphans (Inbox, daily)", str(len(graph.expected_orphans)))
    console.print(t)

    t = Table(title="Stubs (FVH/z)", show_edge=False)
    t.add_column("Class", justify="left")
    t.add_column("Count", justify="right")
    for cls, count in stubs.count_by_class().items():
        t.add_row(cls, str(count))
    console.print(t)

    t = Table(title="MOCs", show_edge=False)
    t.add_column("Metric", justify="left")
    t.add_column("Value", justify="right")
    t.add_row("Total MOCs", str(len(mocs.mocs)))
    t.add_row("Legacy-tagged MOCs", str(len(mocs.legacy_tagged_mocs)))
    t.add_row("Missing MOC candidates", str(len(mocs.missing_moc_candidates)))
    console.print(t)

    if mocs.coverage_by_category:
        t = Table(title="Coverage by tag category", show_edge=False)
        t.add_column("Category")
        t.add_column("Tagged notes", justify="right")
        t.add_column("Unlinked", justify="right")
        for cov in mocs.coverage_by_category[:12]:
            t.add_row(
                cov.category, str(cov.tagged_note_count), str(cov.unlinked_note_count)
            )
        console.print(t)

    t = Table(title="Duplicates", show_edge=False)
    t.add_column("Issue", justify="left")
    t.add_column("Count", justify="right")
    t.add_row("Basename collisions", str(len(dups.basename_collisions)))
    t.add_row("Untitled placeholders", str(len(dups.untitled_placeholders)))
    console.print(t)


def render_json(audit: VaultAudit) -> str:
    return json.dumps(audit.to_dict(), indent=2, default=str)


def render_markdown(audit: VaultAudit) -> str:
    fm = audit.frontmatter
    lnk = audit.links
    graph = audit.graph
    stubs = audit.stubs
    mocs = audit.mocs
    dups = audit.duplicates
    h = audit.health

    lines: list[str] = []
    lines.append(f"# Vault audit — {audit.vault_root}\n")
    lines.append(
        f"**Total notes:** {fm.total_notes}   "
        f"**Health:** {h.total}/100 "
        f"(tags={h.tags}, links={h.links}, orphans={h.orphans}, stubs={h.stubs}, mocs={h.mocs})\n"
    )

    lines.append("## Frontmatter\n")
    lines.append(f"- No frontmatter: {len(fm.notes_without_frontmatter)}")
    lines.append(f"- Legacy `id:` field: {len(fm.notes_with_legacy_id)}")
    lines.append(f"- Bare placeholder tag: {len(fm.notes_with_bare_placeholder)}")
    lines.append(f"- Null tags: {len(fm.notes_with_null_tags)}")
    lines.append(f"- Templater leakage: {len(fm.notes_with_templater_leak)}")
    lines.append(f"- Corrupt emoji: {len(fm.notes_with_corrupt_emoji)}")
    lines.append(f"- FVH missing context: {len(fm.fvh_notes_missing_context)}")
    lines.append("")

    lines.append("## Links\n")
    lines.append(f"- Total wikilinks: {lnk.total_wikilinks}")
    lines.append(f"- Broken: {lnk.broken_count}")
    lines.append(f"- Ambiguous instances: {lnk.ambiguous_count}")
    if lnk.top_broken(10):
        lines.append("\n### Top broken targets\n")
        lines.append("| Target | Instances |")
        lines.append("|---|---|")
        for target, count in lnk.top_broken(10):
            lines.append(f"| `[[{target}]]` | {count} |")
    lines.append("")

    lines.append("## Graph\n")
    lines.append(f"- Meaningful orphans: {len(graph.meaningful_orphans)}")
    lines.append(f"- Expected orphans: {len(graph.expected_orphans)}")
    lines.append("")

    lines.append("## Stubs (FVH/z)\n")
    for cls, count in stubs.count_by_class().items():
        lines.append(f"- {cls}: {count}")
    lines.append("")

    lines.append("## MOCs\n")
    lines.append(f"- Total MOCs: {len(mocs.mocs)}")
    lines.append(f"- Legacy-tagged MOCs: {len(mocs.legacy_tagged_mocs)}")
    lines.append(f"- Missing MOC candidates: {len(mocs.missing_moc_candidates)}")
    lines.append("")

    lines.append("## Duplicates\n")
    lines.append(f"- Basename collisions: {len(dups.basename_collisions)}")
    lines.append(f"- Untitled placeholders: {len(dups.untitled_placeholders)}")

    return "\n".join(lines) + "\n"
