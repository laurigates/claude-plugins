"""Helpers the vault-stubs subagent calls before merging stale_duplicates (#1070).

These don't invoke the LLM — they're the deterministic safety checks the
subagent's prompt instructs it to run before overwriting anything.
"""

from __future__ import annotations

import textwrap
from pathlib import Path

import pytest

from vault_agent.fixers.stub_rewriter import (
    CANONICAL_REDIRECT_TEMPLATE,
    body_digest,
    section_headings,
    unique_sections,
    verify_canonical_phrase_present,
)


SAMPLE_FVH = textwrap.dedent(
    """
    ---
    tags:
      - devops
    ---

    # ArgoCD

    ## Installation

    Install ArgoCD with helm. Pin the chart version.

    ## FVH-specific notes

    On our cluster the ingress host is argocd.forum.fi.

    ## Troubleshooting

    If pods fail to reconcile, check the resource quotas.
    """
).lstrip()

SAMPLE_ZETTEL = textwrap.dedent(
    """
    ---
    tags:
      - 🛠️/devops
    ---

    # ArgoCD

    GitOps controller for Kubernetes.

    ## Installation

    Install ArgoCD with helm. Pin the chart version.

    ## Troubleshooting

    If pods fail to reconcile, check the resource quotas.
    """
).lstrip()


class TestSectionHeadings:
    def test_extracts_h2_only(self) -> None:
        body = "# Top\n\n## One\ntext\n\n### sub\n\n## Two\ntext"
        assert section_headings(body) == ["One", "Two"]

    def test_strips_frontmatter(self) -> None:
        body = "---\nfoo: bar\n---\n\n## Real\nstuff"
        assert section_headings(body) == ["Real"]


class TestUniqueSections:
    def test_flags_fvh_specific_section(self) -> None:
        uniq = unique_sections(SAMPLE_FVH, SAMPLE_ZETTEL)
        assert uniq == ["FVH-specific notes"]

    def test_empty_when_full_subset(self) -> None:
        # Source is a strict subset of the destination.
        src = "## A\nhello world\n\n## B\nfoo bar"
        dst = "Preamble.\n\n## A\nhello world\n\n## B\nfoo bar\n\n## C\nunique to dst"
        assert unique_sections(src, dst) == []


class TestVerifyCanonicalPhrase:
    def test_passes_when_source_phrases_in_destination(self) -> None:
        assert verify_canonical_phrase_present(SAMPLE_FVH, SAMPLE_ZETTEL) is True

    def test_fails_when_destination_has_no_shared_phrase(self) -> None:
        fvh = "## Installation\n\nInstall via apt-get. Works on Debian."
        zettel = "## Basics\n\nCompletely different topic about Kafka streams."
        assert verify_canonical_phrase_present(fvh, zettel) is False

    def test_near_empty_source_passes_vacuously(self) -> None:
        # A 1-word source has no distinguishable phrase; we return True
        # to avoid false negatives rather than refuse every near-empty
        # redirect conversion.
        assert verify_canonical_phrase_present("# Foo", "Completely different") is True


class TestBodyDigest:
    def test_stable_for_whitespace_differences(self) -> None:
        a = "## A\n\nhello  world\n"
        b = "## A\nhello world"
        assert body_digest(a) == body_digest(b)

    def test_varies_for_substantive_differences(self) -> None:
        a = "## A\nhello world"
        b = "## A\nhello venus"
        assert body_digest(a) != body_digest(b)


class TestCanonicalRedirectTemplate:
    def test_renders_basename(self, tmp_path: Path) -> None:
        rendered = CANONICAL_REDIRECT_TEMPLATE.format(basename="Kafka")
        assert "[[Zettelkasten/Kafka|Kafka]]" in rendered
        assert "tags: [redirect]" in rendered
