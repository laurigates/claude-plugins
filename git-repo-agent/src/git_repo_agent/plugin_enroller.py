"""Plugin-enrollment logic for ``git-repo-agent new``.

Writes ``.claude/settings.json`` with:

- ``extraKnownMarketplaces.claude-plugins`` — enrolls the laurigates/claude-plugins
  marketplace so the repo's first Claude Code session already sees it
- ``enabledPlugins`` — stack-appropriate plugins pre-enabled
- ``permissions.allow`` — common baseline + stack-specific Bash patterns

The stack-indicator → plugin mapping is the source of truth for non-interactive
(pre-Claude-session) plugin selection. It mirrors
``configure-plugin/skills/configure-claude-plugins/SKILL.md`` — see the drift
test in ``tests/test_plugin_enroller.py``.
"""

from __future__ import annotations

from pathlib import Path
from typing import Iterable, Mapping, MutableMapping


MARKETPLACE_KEY = "claude-plugins"
MARKETPLACE_REPO = "laurigates/claude-plugins"


# Always enabled regardless of detected stack. Extends SKILL.md's
# "configure-plugin, health-plugin, hooks-plugin" baseline with two more
# plugins that `new` repos consistently benefit from:
#   - blueprint-plugin: the repo gets a PRD on day one
#   - tools-plugin: covers jq/rg/fd which the agent uses during onboarding
ALWAYS_ON_PLUGINS: tuple[str, ...] = (
    "configure-plugin",
    "health-plugin",
    "hooks-plugin",
    "blueprint-plugin",
    "tools-plugin",
)

# Per stack-indicator additions. Keep in sync with the "Recommended Plugins"
# table in configure-plugin/skills/configure-claude-plugins/SKILL.md (Step 2).
STACK_PLUGINS: Mapping[str, tuple[str, ...]] = {
    "python": (
        "python-plugin",
        "testing-plugin",
        "code-quality-plugin",
        "git-plugin",
    ),
    "typescript": (
        "typescript-plugin",
        "testing-plugin",
        "code-quality-plugin",
        "git-plugin",
    ),
    "javascript": (
        "typescript-plugin",
        "testing-plugin",
        "code-quality-plugin",
        "git-plugin",
    ),
    "rust": (
        "rust-plugin",
        "testing-plugin",
        "code-quality-plugin",
        "git-plugin",
    ),
    "docker": ("container-plugin",),
    "github-actions": ("github-actions-plugin",),
    "esp-idf": (
        "code-quality-plugin",
        "testing-plugin",
        "container-plugin",
        "git-plugin",
    ),
    "esphome": (
        "python-plugin",
        "code-quality-plugin",
        "git-plugin",
    ),
}


# Always-present Bash patterns in permissions.allow.
_COMMON_PERMISSIONS: tuple[str, ...] = (
    "Bash(git:*)",
    "Bash(gh:*)",
    "Bash(pre-commit:*)",
    "Bash(gitleaks:*)",
    "Bash(python3:*)",
)

# Stack-specific permissions, keyed by stack indicator. Mirrors the
# "Stack-aware permissions.allow baseline" table in SKILL.md.
_STACK_PERMISSIONS: Mapping[str, tuple[str, ...]] = {
    "python": (
        "Bash(uv:*)",
        "Bash(uvx:*)",
        "Bash(ruff:*)",
        "Bash(ty:*)",
        "Bash(pytest:*)",
    ),
    "typescript": (
        "Bash(npm:*)",
        "Bash(pnpm:*)",
        "Bash(bun:*)",
        "Bash(tsc:*)",
        "Bash(eslint:*)",
        "Bash(prettier:*)",
        "Bash(vitest:*)",
    ),
    "javascript": (
        "Bash(npm:*)",
        "Bash(pnpm:*)",
        "Bash(bun:*)",
        "Bash(eslint:*)",
        "Bash(prettier:*)",
        "Bash(vitest:*)",
    ),
    "go": (
        "Bash(go:*)",
        "Bash(gofmt:*)",
        "Bash(golangci-lint:*)",
    ),
    "rust": (
        "Bash(cargo:*)",
        "Bash(rustc:*)",
        "Bash(clippy:*)",
        "Bash(rustfmt:*)",
    ),
    "docker": (
        "Bash(docker:*)",
        "Bash(docker compose:*)",
    ),
    "esp-idf": (
        "Bash(idf.py:*)",
        "Bash(esptool:*)",
        "Bash(clang-format:*)",
        "Bash(cppcheck:*)",
        "Bash(docker:*)",
        "Bash(docker compose:*)",
        "Bash(just:*)",
        "Bash(make:*)",
    ),
    "esphome": (
        "Bash(esphome:*)",
        "Bash(uv:*)",
        "Bash(uvx:*)",
    ),
}


def select_plugins(
    stack_indicators: Iterable[str],
    *,
    extra_plugins: Iterable[str] = (),
) -> list[str]:
    """Compute the enabled-plugin set for a given stack.

    Combines ``ALWAYS_ON_PLUGINS`` with per-indicator additions from
    ``STACK_PLUGINS`` and any user-supplied ``extra_plugins``, then returns
    a sorted deduplicated list.

    Unknown stack indicators are silently ignored (callers are expected to
    validate input separately if they want to warn).
    """
    chosen: set[str] = set(ALWAYS_ON_PLUGINS)
    for indicator in stack_indicators:
        chosen.update(STACK_PLUGINS.get(indicator, ()))
    chosen.update(extra_plugins)
    return sorted(chosen)


def select_permissions(stack_indicators: Iterable[str]) -> list[str]:
    """Compute the permissions.allow list for a given stack.

    Combines the common baseline with per-indicator entries; deduplicated,
    preserving common-entries-first order.
    """
    ordered: list[str] = list(_COMMON_PERMISSIONS)
    seen: set[str] = set(ordered)
    for indicator in stack_indicators:
        for entry in _STACK_PERMISSIONS.get(indicator, ()):
            if entry not in seen:
                ordered.append(entry)
                seen.add(entry)
    return ordered


def build_settings_json(
    plugins: Iterable[str],
    permissions: Iterable[str],
    *,
    existing: Mapping | None = None,
) -> dict:
    """Build the ``.claude/settings.json`` contents.

    If ``existing`` is supplied (a previously parsed settings.json), non-
    conflicting fields are preserved: ``hooks``, ``env``, and any top-level
    keys we don't own. For the keys we do manage (``permissions.allow``,
    ``extraKnownMarketplaces``, ``enabledPlugins``) we merge rather than
    replace, so a re-run never drops entries the caller added by hand.
    """
    out: dict = dict(existing) if existing else {}

    # --- permissions ---------------------------------------------------
    perms = dict(out.get("permissions") or {})
    allow = list(perms.get("allow") or [])
    for entry in permissions:
        if entry not in allow:
            allow.append(entry)
    perms["allow"] = allow
    out["permissions"] = perms

    # --- extraKnownMarketplaces ---------------------------------------
    marketplaces = dict(out.get("extraKnownMarketplaces") or {})
    marketplaces.setdefault(
        MARKETPLACE_KEY,
        {
            "source": {"source": "github", "repo": MARKETPLACE_REPO},
            "autoUpdate": True,
        },
    )
    out["extraKnownMarketplaces"] = marketplaces

    # --- enabledPlugins -----------------------------------------------
    enabled: MutableMapping[str, bool] = dict(out.get("enabledPlugins") or {})
    for plugin in plugins:
        enabled[f"{plugin}@{MARKETPLACE_KEY}"] = True
    out["enabledPlugins"] = dict(sorted(enabled.items()))

    return out


def write_settings_json(
    target_dir: Path,
    plugins: Iterable[str],
    permissions: Iterable[str],
) -> Path:
    """Write (or merge) ``<target_dir>/.claude/settings.json``.

    Returns the path of the written file.
    """
    import json

    settings_dir = target_dir / ".claude"
    settings_dir.mkdir(parents=True, exist_ok=True)
    settings_path = settings_dir / "settings.json"

    existing = None
    if settings_path.exists():
        existing = json.loads(settings_path.read_text(encoding="utf-8"))

    data = build_settings_json(plugins, permissions, existing=existing)
    settings_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    return settings_path
