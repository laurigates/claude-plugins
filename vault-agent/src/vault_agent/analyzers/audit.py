"""Top-level audit: run every analyzer, return a merged report."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from vault_agent.analyzers.duplicates import DuplicateReport, analyze_duplicates
from vault_agent.analyzers.frontmatter import FrontmatterReport, analyze_frontmatter
from vault_agent.analyzers.graph import GraphReport, analyze_graph
from vault_agent.analyzers.health import HealthScore, compute_health
from vault_agent.analyzers.links import LinkReport, analyze_links
from vault_agent.analyzers.mocs import MocReport, analyze_mocs
from vault_agent.analyzers.stubs import StubReport, analyze_stubs
from vault_agent.analyzers.vault_index import VaultIndex, scan


@dataclass
class VaultAudit:
    vault_root: Path
    index: VaultIndex
    frontmatter: FrontmatterReport
    links: LinkReport
    graph: GraphReport
    stubs: StubReport
    mocs: MocReport
    duplicates: DuplicateReport
    health: HealthScore

    def to_dict(self) -> dict:
        return {
            "vault_root": str(self.vault_root),
            "total_notes": self.frontmatter.total_notes,
            "frontmatter": self.frontmatter.to_dict(),
            "links": self.links.to_dict(),
            "graph": self.graph.to_dict(),
            "stubs": self.stubs.to_dict(),
            "mocs": self.mocs.to_dict(),
            "duplicates": self.duplicates.to_dict(),
            "health": self.health.to_dict(),
        }


def run_audit(vault_root: Path | str) -> VaultAudit:
    index = scan(vault_root)
    fm = analyze_frontmatter(index)
    lnk = analyze_links(index)
    graph = analyze_graph(index)
    stubs = analyze_stubs(index)
    mocs = analyze_mocs(index)
    dups = analyze_duplicates(index)
    health = compute_health(
        frontmatter=fm, links=lnk, graph=graph, stubs=stubs, mocs=mocs
    )
    return VaultAudit(
        vault_root=index.vault_root,
        index=index,
        frontmatter=fm,
        links=lnk,
        graph=graph,
        stubs=stubs,
        mocs=mocs,
        duplicates=dups,
        health=health,
    )
