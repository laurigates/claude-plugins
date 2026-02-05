#!/usr/bin/env python3
"""
Prune orphaned projects and cached data from ~/.claude.json

This script safely removes:
- Project entries for directories that no longer exist
- Cached data (changelog, feature flags, configs) that will be re-fetched
"""

import argparse
import json
import shutil
import sys
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Tuple


class ClaudeConfigPruner:
    """Manages pruning of Claude Code configuration file."""

    def __init__(self, config_path: Path, dry_run: bool = False, interactive: bool = False):
        self.config_path = config_path
        self.dry_run = dry_run
        self.interactive = interactive
        self.stats = {
            "original_size": 0,
            "new_size": 0,
            "orphaned_projects": 0,
            "cached_keys_removed": 0,
        }

    def load_config(self) -> Dict[str, Any]:
        """Load and parse the configuration file."""
        try:
            with open(self.config_path, "r") as f:
                return json.load(f)
        except FileNotFoundError:
            print(f"Error: Configuration file not found: {self.config_path}")
            sys.exit(1)
        except json.JSONDecodeError as e:
            print(f"Error: Invalid JSON in configuration file: {e}")
            sys.exit(1)

    def save_config(self, config: Dict[str, Any]) -> None:
        """Save configuration file with proper formatting."""
        with open(self.config_path, "w") as f:
            json.dump(config, f, indent=2)
            f.write("\n")  # Add trailing newline

    def create_backup(self) -> Path:
        """Create a timestamped backup of the configuration file."""
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        backup_path = self.config_path.with_suffix(f".json.backup.{timestamp}")
        shutil.copy2(self.config_path, backup_path)
        return backup_path

    def find_orphaned_projects(self, config: Dict[str, Any]) -> List[str]:
        """Find project paths that no longer exist on disk."""
        projects = config.get("projects", {})
        orphaned = []

        for project_path in projects.keys():
            if not Path(project_path).exists():
                orphaned.append(project_path)

        return orphaned

    def get_cached_keys(self, config: Dict[str, Any]) -> List[str]:
        """Get list of cached data keys that can be safely removed."""
        cache_prefixes = ["cached"]
        cached_keys = []

        for key in config.keys():
            if any(key.startswith(prefix) for prefix in cache_prefixes):
                cached_keys.append(key)

        return cached_keys

    def calculate_size(self, data: Dict[str, Any]) -> int:
        """Calculate approximate size of JSON data in bytes."""
        return len(json.dumps(data))

    def prune_config(self, config: Dict[str, Any]) -> Tuple[Dict[str, Any], Dict[str, Any]]:
        """
        Prune configuration by removing orphaned projects and cached data.

        Returns:
            Tuple of (pruned_config, removed_data)
        """
        pruned = config.copy()
        removed = {"projects": {}, "cached_keys": {}}

        # Remove orphaned projects
        orphaned_projects = self.find_orphaned_projects(config)
        if "projects" in pruned:
            for project_path in orphaned_projects:
                removed["projects"][project_path] = pruned["projects"].pop(project_path)

        self.stats["orphaned_projects"] = len(orphaned_projects)

        # Remove cached data
        cached_keys = self.get_cached_keys(config)
        for key in cached_keys:
            removed["cached_keys"][key] = pruned.pop(key)

        self.stats["cached_keys_removed"] = len(cached_keys)

        return pruned, removed

    def print_analysis(self, config: Dict[str, Any], orphaned: List[str], cached: List[str]) -> None:
        """Print detailed analysis of what will be pruned."""
        total_projects = len(config.get("projects", {}))
        remaining_projects = total_projects - len(orphaned)

        print("\n" + "=" * 70)
        print("Claude Config Analysis")
        print("=" * 70)
        print(f"\nConfiguration file: {self.config_path}")
        print(f"Current size: {self.config_path.stat().st_size / 1024:.1f} KB")

        print(f"\nProjects:")
        print(f"  Total: {total_projects}")
        print(f"  Orphaned (will be removed): {len(orphaned)}")
        print(f"  Remaining: {remaining_projects}")

        if orphaned and len(orphaned) <= 10:
            print(f"\n  Orphaned project paths:")
            for path in orphaned:
                print(f"    - {path}")
        elif orphaned:
            print(f"\n  Sample orphaned paths (showing first 10 of {len(orphaned)}):")
            for path in orphaned[:10]:
                print(f"    - {path}")

        print(f"\nCached data to remove:")
        if cached:
            for key in cached:
                size = len(json.dumps(config.get(key, "")))
                print(f"  - {key} ({size / 1024:.1f} KB)")
        else:
            print("  None found")

        if len(orphaned) > 0 or len(cached) > 0:
            pct = (len(orphaned) / total_projects * 100) if total_projects > 0 else 0
            print(f"\nEstimated space savings: ~{pct:.0f}% of projects + cached data")

        print("=" * 70 + "\n")

    def print_results(self, backup_path: Path) -> None:
        """Print summary of pruning results."""
        print("\n" + "=" * 70)
        print("Pruning Results")
        print("=" * 70)
        print(f"\nRemoved:")
        print(f"  - {self.stats['orphaned_projects']} orphaned project entries")
        print(f"  - {self.stats['cached_keys_removed']} cached data keys")

        if not self.dry_run:
            new_size = self.config_path.stat().st_size / 1024
            original_size = backup_path.stat().st_size / 1024
            saved = original_size - new_size
            pct = (saved / original_size * 100) if original_size > 0 else 0

            print(f"\nFile size:")
            print(f"  Original: {original_size:.1f} KB")
            print(f"  New: {new_size:.1f} KB")
            print(f"  Saved: {saved:.1f} KB ({pct:.1f}%)")
            print(f"\nBackup: {backup_path}")
        else:
            print("\nDRY RUN - No changes were made")

        print("=" * 70 + "\n")

    def run(self) -> None:
        """Execute the pruning process."""
        # Load configuration
        print(f"Loading configuration from {self.config_path}...")
        config = self.load_config()
        self.stats["original_size"] = self.calculate_size(config)

        # Analyze what will be pruned
        orphaned = self.find_orphaned_projects(config)
        cached = self.get_cached_keys(config)

        self.print_analysis(config, orphaned, cached)

        # Check if there's anything to prune
        if len(orphaned) == 0 and len(cached) == 0:
            print("✓ Configuration is already clean - nothing to prune!")
            return

        # Interactive confirmation
        if self.interactive and not self.dry_run:
            response = input("Proceed with pruning? [y/N]: ").strip().lower()
            if response not in ("y", "yes"):
                print("Aborted.")
                return

        # Create backup (even for dry-run, to show what would be backed up)
        backup_path = None
        if not self.dry_run:
            print("Creating backup...")
            backup_path = self.create_backup()

        # Prune configuration
        print("Pruning configuration..." if not self.dry_run else "Analyzing (dry-run)...")
        pruned_config, removed = self.prune_config(config)
        self.stats["new_size"] = self.calculate_size(pruned_config)

        # Save pruned configuration
        if not self.dry_run:
            self.save_config(pruned_config)

        # Print results
        self.print_results(backup_path or self.config_path)


def main():
    parser = argparse.ArgumentParser(
        description="Prune orphaned projects and cached data from Claude Code configuration",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s --dry-run              # Preview what would be removed
  %(prog)s --interactive          # Confirm before making changes
  %(prog)s                        # Prune immediately (creates backup)

The script removes:
  - Project entries for directories that no longer exist
  - Cached data (changelog, feature flags, configs)

Your settings, MCP servers, and tips history are preserved.
        """,
    )

    parser.add_argument(
        "--config",
        type=Path,
        default=Path.home() / ".claude.json",
        help="Path to claude.json (default: ~/.claude.json)",
    )

    parser.add_argument(
        "-n", "--dry-run",
        action="store_true",
        help="Show what would be removed without making changes",
    )

    parser.add_argument(
        "-i", "--interactive",
        action="store_true",
        help="Prompt for confirmation before making changes",
    )

    parser.add_argument(
        "--version",
        action="version",
        version="%(prog)s 1.0.0",
    )

    args = parser.parse_args()

    # Validate config path exists
    if not args.config.exists():
        print(f"Error: Configuration file not found: {args.config}")
        sys.exit(1)

    # Run pruner
    pruner = ClaudeConfigPruner(
        config_path=args.config,
        dry_run=args.dry_run,
        interactive=args.interactive,
    )

    try:
        pruner.run()
    except KeyboardInterrupt:
        print("\n\nInterrupted by user.")
        sys.exit(130)
    except Exception as e:
        print(f"\nError: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
