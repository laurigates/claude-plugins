#!/usr/bin/env python3
"""
Sync plugin configuration files.

Ensures release-please-config.json, .release-please-manifest.json, and
.claude-plugin/marketplace.json stay in sync with actual plugin directories.

Usage:
    python scripts/sync-plugin-configs.py          # Check mode (CI)
    python scripts/sync-plugin-configs.py --fix    # Fix mode (auto-heal)
"""

import argparse
import json
import sys
from pathlib import Path

# Default config for new plugins in release-please-config.json
DEFAULT_CHANGELOG_SECTIONS = [
    {"type": "feat", "section": "Features"},
    {"type": "fix", "section": "Bug Fixes"},
    {"type": "perf", "section": "Performance"},
    {"type": "refactor", "section": "Code Refactoring"},
    {"type": "docs", "section": "Documentation"},
]

# Category mapping based on keywords (used when creating marketplace entries)
CATEGORY_KEYWORDS = {
    "infrastructure": ["kubernetes", "terraform", "docker", "container", "helm", "k8s", "iac"],
    "language": ["python", "typescript", "rust", "javascript"],
    "version-control": ["git", "github", "commits", "branches"],
    "testing": ["testing", "tdd", "pytest", "vitest", "test"],
    "quality": ["code-review", "refactoring", "linting", "analysis"],
    "ci-cd": ["ci-cd", "github-actions", "workflows", "automation"],
    "documentation": ["documentation", "docs", "readme", "blog", "writing"],
    "ai": ["agents", "langchain", "llm", "orchestration", "ai-agents"],
    "utilities": ["tools", "utilities", "analytics", "tracking"],
    "development": ["blueprint", "project", "api", "methodology"],
    "communication": ["communication", "chat", "formatting"],
    "integration": ["sync", "integration"],
    "ux": ["accessibility", "wcag", "aria", "ux"],
    "gamedev": ["bevy", "game-engine", "ecs", "gamedev"],
}


def get_repo_root() -> Path:
    """Get the repository root directory."""
    return Path(__file__).parent.parent


def discover_plugins(repo_root: Path) -> dict[str, dict]:
    """
    Discover all plugins by finding directories with .claude-plugin/plugin.json.
    Returns a dict mapping plugin name to plugin.json contents.
    """
    plugins = {}
    for plugin_json in repo_root.glob("*/.claude-plugin/plugin.json"):
        # Skip the root .claude-plugin directory
        plugin_dir = plugin_json.parent.parent
        if plugin_dir == repo_root:
            continue

        plugin_name = plugin_dir.name
        try:
            with open(plugin_json) as f:
                plugins[plugin_name] = json.load(f)
        except (json.JSONDecodeError, IOError) as e:
            print(f"Warning: Could not read {plugin_json}: {e}", file=sys.stderr)

    return plugins


def load_release_please_config(repo_root: Path) -> dict:
    """Load release-please-config.json."""
    config_path = repo_root / "release-please-config.json"
    with open(config_path) as f:
        return json.load(f)


def load_release_please_manifest(repo_root: Path) -> dict:
    """Load .release-please-manifest.json."""
    manifest_path = repo_root / ".release-please-manifest.json"
    with open(manifest_path) as f:
        return json.load(f)


def load_marketplace(repo_root: Path) -> dict:
    """Load .claude-plugin/marketplace.json."""
    marketplace_path = repo_root / ".claude-plugin" / "marketplace.json"
    with open(marketplace_path) as f:
        return json.load(f)


def save_json(path: Path, data: dict, sort_keys: bool = False) -> None:
    """Save JSON file with consistent formatting."""
    with open(path, "w") as f:
        json.dump(data, f, indent=2, sort_keys=sort_keys)
        f.write("\n")


def infer_category(keywords: list[str]) -> str:
    """Infer a marketplace category from plugin keywords."""
    keyword_set = set(k.lower() for k in keywords)
    for category, category_keywords in CATEGORY_KEYWORDS.items():
        if keyword_set & set(category_keywords):
            return category
    return "development"  # Default category


def create_release_please_package_config(plugin_name: str) -> dict:
    """Create a release-please package configuration for a plugin."""
    return {
        "component": plugin_name,
        "release-type": "simple",
        "extra-files": [
            {"type": "json", "path": ".claude-plugin/plugin.json", "jsonpath": "$.version"}
        ],
        "changelog-sections": DEFAULT_CHANGELOG_SECTIONS,
    }


def create_marketplace_entry(plugin_name: str, plugin_data: dict, version: str) -> dict:
    """Create a marketplace.json entry for a plugin."""
    keywords = plugin_data.get("keywords", [])
    return {
        "name": plugin_name,
        "source": f"./{plugin_name}",
        "description": plugin_data.get("description", f"{plugin_name} plugin"),
        "version": version,
        "keywords": keywords[:10],  # Limit to 10 keywords for readability
        "category": infer_category(keywords),
    }


def check_sync(repo_root: Path) -> tuple[list[str], dict]:
    """
    Check if all config files are in sync.
    Returns (list of issues, dict of fixes needed).
    """
    issues = []
    fixes = {
        "add_to_release_config": [],
        "remove_from_release_config": [],
        "add_to_manifest": [],
        "remove_from_manifest": [],
        "add_to_marketplace": [],
        "remove_from_marketplace": [],
        "version_mismatches": [],
    }

    # Load all data
    plugins = discover_plugins(repo_root)
    release_config = load_release_please_config(repo_root)
    manifest = load_release_please_manifest(repo_root)
    marketplace = load_marketplace(repo_root)

    plugin_names = set(plugins.keys())
    release_config_packages = set(release_config.get("packages", {}).keys())
    manifest_plugins = set(manifest.keys())
    marketplace_plugins = {p["name"] for p in marketplace.get("plugins", [])}

    # Check for plugins missing from release-please-config.json
    missing_from_config = plugin_names - release_config_packages
    for name in sorted(missing_from_config):
        issues.append(f"Plugin '{name}' missing from release-please-config.json")
        fixes["add_to_release_config"].append(name)

    # Check for orphaned entries in release-please-config.json
    orphaned_in_config = release_config_packages - plugin_names
    for name in sorted(orphaned_in_config):
        issues.append(f"Orphaned entry '{name}' in release-please-config.json (plugin directory not found)")
        fixes["remove_from_release_config"].append(name)

    # Check for plugins missing from .release-please-manifest.json
    missing_from_manifest = plugin_names - manifest_plugins
    for name in sorted(missing_from_manifest):
        issues.append(f"Plugin '{name}' missing from .release-please-manifest.json")
        fixes["add_to_manifest"].append(name)

    # Check for orphaned entries in .release-please-manifest.json
    orphaned_in_manifest = manifest_plugins - plugin_names
    for name in sorted(orphaned_in_manifest):
        issues.append(f"Orphaned entry '{name}' in .release-please-manifest.json (plugin directory not found)")
        fixes["remove_from_manifest"].append(name)

    # Check for plugins missing from marketplace.json
    missing_from_marketplace = plugin_names - marketplace_plugins
    for name in sorted(missing_from_marketplace):
        issues.append(f"Plugin '{name}' missing from .claude-plugin/marketplace.json")
        fixes["add_to_marketplace"].append(name)

    # Check for orphaned entries in marketplace.json
    orphaned_in_marketplace = marketplace_plugins - plugin_names
    for name in sorted(orphaned_in_marketplace):
        issues.append(f"Orphaned entry '{name}' in .claude-plugin/marketplace.json (plugin directory not found)")
        fixes["remove_from_marketplace"].append(name)

    # Check version sync between manifest and marketplace
    marketplace_versions = {p["name"]: p["version"] for p in marketplace.get("plugins", [])}
    for name in plugin_names & manifest_plugins & marketplace_plugins:
        manifest_version = manifest[name]
        marketplace_version = marketplace_versions.get(name)
        if manifest_version != marketplace_version:
            issues.append(
                f"Version mismatch for '{name}': manifest={manifest_version}, marketplace={marketplace_version}"
            )
            fixes["version_mismatches"].append((name, manifest_version))

    # Check for plugins missing from docs/PLUGIN-MAP.md (informational only)
    plugin_map_path = repo_root / "docs" / "PLUGIN-MAP.md"
    fixes["missing_from_plugin_map"] = []
    if plugin_map_path.exists():
        plugin_map_text = plugin_map_path.read_text()
        missing_from_map = [
            name for name in sorted(plugin_names) if name not in plugin_map_text
        ]
        for name in missing_from_map:
            issues.append(
                f"Plugin '{name}' missing from docs/PLUGIN-MAP.md (add manually to appropriate section)"
            )
            fixes["missing_from_plugin_map"].append(name)

    return issues, fixes


def apply_fixes(repo_root: Path, fixes: dict) -> None:
    """Apply fixes to sync all config files."""
    plugins = discover_plugins(repo_root)
    release_config = load_release_please_config(repo_root)
    manifest = load_release_please_manifest(repo_root)
    marketplace = load_marketplace(repo_root)

    modified_files = []

    # Fix release-please-config.json
    if fixes["add_to_release_config"] or fixes["remove_from_release_config"]:
        packages = release_config.get("packages", {})

        for name in fixes["add_to_release_config"]:
            packages[name] = create_release_please_package_config(name)
            print(f"  Added '{name}' to release-please-config.json")

        for name in fixes["remove_from_release_config"]:
            if name in packages:
                del packages[name]
                print(f"  Removed '{name}' from release-please-config.json")

        # Sort packages alphabetically
        release_config["packages"] = dict(sorted(packages.items()))
        save_json(repo_root / "release-please-config.json", release_config)
        modified_files.append("release-please-config.json")

    # Fix .release-please-manifest.json
    if fixes["add_to_manifest"] or fixes["remove_from_manifest"]:
        for name in fixes["add_to_manifest"]:
            # Get version from plugin.json, default to 1.0.0
            version = plugins[name].get("version", "1.0.0")
            manifest[name] = version
            print(f"  Added '{name}' (v{version}) to .release-please-manifest.json")

        for name in fixes["remove_from_manifest"]:
            if name in manifest:
                del manifest[name]
                print(f"  Removed '{name}' from .release-please-manifest.json")

        # Sort manifest alphabetically
        manifest = dict(sorted(manifest.items()))
        save_json(repo_root / ".release-please-manifest.json", manifest)
        modified_files.append(".release-please-manifest.json")

    # Fix marketplace.json
    marketplace_modified = False
    marketplace_plugins_list = marketplace.get("plugins", [])
    marketplace_by_name = {p["name"]: p for p in marketplace_plugins_list}

    for name in fixes["add_to_marketplace"]:
        version = manifest.get(name, plugins[name].get("version", "1.0.0"))
        entry = create_marketplace_entry(name, plugins[name], version)
        marketplace_by_name[name] = entry
        marketplace_modified = True
        print(f"  Added '{name}' to .claude-plugin/marketplace.json")

    for name in fixes["remove_from_marketplace"]:
        if name in marketplace_by_name:
            del marketplace_by_name[name]
            marketplace_modified = True
            print(f"  Removed '{name}' from .claude-plugin/marketplace.json")

    for name, version in fixes["version_mismatches"]:
        if name in marketplace_by_name:
            marketplace_by_name[name]["version"] = version
            marketplace_modified = True
            print(f"  Updated '{name}' version to {version} in .claude-plugin/marketplace.json")

    if marketplace_modified:
        # Sort plugins by name for consistent ordering
        marketplace["plugins"] = sorted(marketplace_by_name.values(), key=lambda p: p["name"])
        save_json(repo_root / ".claude-plugin" / "marketplace.json", marketplace)
        modified_files.append(".claude-plugin/marketplace.json")

    if modified_files:
        print(f"\nModified files: {', '.join(modified_files)}")
    else:
        print("\nNo changes needed.")


def main():
    parser = argparse.ArgumentParser(
        description="Sync plugin configuration files (release-please, marketplace)"
    )
    parser.add_argument(
        "--fix",
        action="store_true",
        help="Automatically fix issues (default: check only)",
    )
    parser.add_argument(
        "--quiet",
        "-q",
        action="store_true",
        help="Only output errors (for CI)",
    )
    args = parser.parse_args()

    repo_root = get_repo_root()

    if not args.quiet:
        print("Checking plugin configuration sync...")
        print(f"Repository root: {repo_root}\n")

    issues, fixes = check_sync(repo_root)

    if not issues:
        if not args.quiet:
            print("All plugin configurations are in sync!")
        return 0

    # Print issues
    print(f"Found {len(issues)} issue(s):\n")
    for issue in issues:
        print(f"  - {issue}")
    print()

    if args.fix:
        print("Applying fixes...\n")
        apply_fixes(repo_root, fixes)
        return 0
    else:
        print("Run with --fix to automatically resolve these issues.")
        return 1


if __name__ == "__main__":
    sys.exit(main())
