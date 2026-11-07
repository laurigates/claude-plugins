#!/usr/bin/env python3
"""scan-context-leakage.py -- find names and defaults that only make sense in
one person's setup (code-quality-plugin:code-context-leakage, #3306).

Every hit is a CANDIDATE for the skill's classification step, not a verdict:
the scanner sees text, the skill decides whether a line is a default someone
else would trip over, a historical record, or a deliberate choice.

WHAT IT SCANS
  Tracked files (`git ls-files`), optionally narrowed with --include pathspecs
  (git's default pathspec mode, where `*` crosses `/`). Untracked files are out
  of scope; binary files (any NUL byte) are skipped. Changelogs, ADRs and
  lockfiles are excluded by default (historical records stay as written);
  --no-default-excludes turns that off and --exclude adds fnmatch globs.

CATEGORIES
  home-path          /Users/<name>, /home/<name>, C:\\Users\\<name>
  checkout-layout    ~/src/, $HOME/repos/ and similar personal layouts
  personal-channel   telegram, pushover, ntfy.sh, Slack/Discord webhook URLs
  dated-tag          a name carrying a date, e.g. manual-2026-10-23
  time-of-day        justfile/Makefile recipes and file names that say when
                     something ran (overnight, nightly, morning, ...)
  os-specific        BSD/macOS-only or GNU-only commands, macOS paths and fonts
  stale-repo-name    a self-reference (OCI source label, repository field)
                     naming a repository other than the git remote's
  identifier         each regex in the config's [identifiers] section
  old-name           each --name regex, matched against file contents and
                     tracked file paths: the rename gate (step 4 of the skill)

CONFIG (--config FILE, optional)
  [identifiers]  one Python regex per line (host names, site names, a handle).
  [allow]        path<TAB>matched text<TAB>reason -- an accepted line. Applies
                 to every category. An entry that matches nothing is ERROR
                 (stale_allowlist).
  Blank lines and lines starting with `#` are ignored.

OUTPUT  `=== CONTEXT LEAKAGE ===` block of KEY=VALUE lines, one
  `HIT=<category>|<path>:<line>|<match>|<line text>` per reported hit, and
  STATUS / REASON / ISSUE_COUNT per the structured-output convention.

EXIT  0 = OK or WARN (hits are a report), 1 = ERROR (stale allow entry,
  nothing scanned, or any hit under --strict), 2 = usage error.
"""

import argparse
import fnmatch
import os
import re
import subprocess
import sys

CATEGORIES = [
    "home-path",
    "checkout-layout",
    "personal-channel",
    "dated-tag",
    "time-of-day",
    "os-specific",
    "stale-repo-name",
    "identifier",
    "old-name",
]

DEFAULT_EXCLUDES = [
    "CHANGELOG*",
    "*/CHANGELOG*",
    "HISTORY*",
    "*/HISTORY*",
    "adr/*",
    "*/adr/*",
    "adrs/*",
    "*/adrs/*",
    "*/decisions/*",
    "decisions/*",
    "*.lock",
    "*.lockb",
    "package-lock.json",
    "*/package-lock.json",
    "pnpm-lock.yaml",
    "*/pnpm-lock.yaml",
    "go.sum",
    "*/go.sum",
]

# Generic stand-ins a document uses on purpose (/home/user, owner/repo) say
# nothing about one person's setup, so they are not hits.
PLACEHOLDER_NAMES = {
    "user",
    "username",
    "you",
    "me",
    "name",
    "example",
    "owner",
    "org",
    "your-org",
    "your-name",
    "your-user",
    "repo",
    "repository",
    "your-repo",
}
NOT_PLACEHOLDER = r"(?!(?i:%s)\b)" % "|".join(
    sorted(re.escape(n) for n in PLACEHOLDER_NAMES)
)

LINE_RULES = {
    "home-path": [
        re.compile(
            r"/Users/(?!(?:Shared|runner)\b)" + NOT_PLACEHOLDER + r"[A-Za-z][\w.-]*"
        ),
        re.compile(
            r"/home/(?!(?:runner|linuxbrew)\b)" + NOT_PLACEHOLDER + r"[a-z][\w.-]*"
        ),
        re.compile(r"[A-Za-z]:\\\\?Users\\\\?" + NOT_PLACEHOLDER + r"[A-Za-z][\w.-]*"),
    ],
    "checkout-layout": [
        re.compile(
            r"(?:~|\$HOME|\$\{HOME\})/(?:repos|src|code|projects|dev|git|work|workspace|Developer)/"
        ),
    ],
    "personal-channel": [
        re.compile(r"(?i)\btelegram\b"),
        re.compile(r"(?i)\bpushover\b"),
        re.compile(r"\bntfy\.sh\b"),
        re.compile(r"hooks\.slack\.com/services/"),
        re.compile(r"discord(?:app)?\.com/api/webhooks"),
    ],
    "dated-tag": [
        re.compile(r"\b[A-Za-z][\w.]*[-_]20\d\d-[01]\d-[0-3]\d\b"),
    ],
    "os-specific": [
        re.compile(r"\bstat -f\b"),
        re.compile(r"\bsed -i ''|\bsed -i \"\""),
        re.compile(r"\bdate -j\b|\bdate -v[+-]"),
        re.compile(r"\bdate -d\b|\bgrep -P\b"),
        re.compile(r"\b(?:pbcopy|pbpaste|osascript|launchctl)\b"),
        re.compile(
            r"/opt/homebrew/|/usr/local/Cellar/|/Applications/|/System/Library/|/Library/Fonts/"
        ),
        re.compile(r"\b(?:Menlo|Monaco|SF Mono|Helvetica Neue|Apple Color Emoji)\b"),
    ],
}

TIME_WORDS = r"(?:overnight|nightly|morning|evening|afternoon|midnight|weekend)"
TIME_IN_NAME = re.compile(r"(?i)(?<![A-Za-z])" + TIME_WORDS + r"(?![A-Za-z])")
RECIPE_FILES = re.compile(
    r"(?:^|/)(?:[Jj]ustfile|\.justfile|[^/]*\.just|[Mm]akefile|GNUmakefile|[^/]*\.mk)$"
)
RECIPE_DEF = re.compile(r"^@?([A-Za-z0-9_][\w-]*)[^:=\n]*:(?!=)")

SELF_REF_KEYS = re.compile(
    r"org\.opencontainers\.image\.(?:source|url)|\"?repository\"?\s*[:=]|\"?homepage\"?\s*[:=]"
)
REPO_URL = re.compile(
    r"(?:github|gitlab|codeberg)\.(?:com|org)[/:]([\w.-]+)/([\w.-]+?)(?:\.git)?(?=[\s\"'/#)>]|$)"
)


def usage_error(msg):
    print("scan-context-leakage.py: %s" % msg, file=sys.stderr)
    sys.exit(2)


def one_line(text):
    return " ".join(str(text).split())


def git(proj_dir, *args):
    return subprocess.run(["git", "-C", proj_dir] + list(args), capture_output=True)


def repo_name(proj_dir):
    proc = git(proj_dir, "remote", "get-url", "origin")
    if proc.returncode != 0:
        return ""
    m = REPO_URL.search(proc.stdout.decode("utf-8", "replace").strip() + " ")
    return ("%s/%s" % (m.group(1), m.group(2))) if m else ""


def read_config(path):
    patterns, allow, section = [], {}, None
    with open(path, encoding="utf-8") as fh:
        for lineno, raw in enumerate(fh, 1):
            line = raw.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            if line.strip() in ("[identifiers]", "[allow]"):
                section = line.strip()
                continue
            if section == "[identifiers]":
                try:
                    patterns.append(re.compile(line.strip()))
                except re.error as exc:
                    usage_error(
                        "%s:%d: invalid identifier regex %r: %s"
                        % (path, lineno, line.strip(), exc)
                    )
            elif section == "[allow]":
                parts = line.split("\t")
                if len(parts) < 3 or not parts[2].strip():
                    usage_error(
                        "%s:%d: allow entry needs path<TAB>matched text<TAB>reason"
                        % (path, lineno)
                    )
                allow[(parts[0].strip(), parts[1])] = parts[2].strip()
            else:
                usage_error(
                    "%s:%d: line outside [identifiers] / [allow]" % (path, lineno)
                )
    return patterns, allow


def scan_line(rel, line, rules, cats, current_repo, is_recipe_file):
    """Yield (category, matched text) for one line."""
    for cat, rxs in rules.items():
        if cat not in cats:
            continue
        for rx in rxs:
            for m in rx.finditer(line):
                yield cat, m.group(0)
    if "time-of-day" in cats and is_recipe_file:
        m = RECIPE_DEF.match(line)
        if m and not line.startswith((" ", "\t")):
            t = TIME_IN_NAME.search(m.group(1))
            if t:
                yield "time-of-day", t.group(0)
    if "stale-repo-name" in cats and current_repo and SELF_REF_KEYS.search(line):
        for m in REPO_URL.finditer(line):
            named = "%s/%s" % (m.group(1), m.group(2))
            if (
                m.group(1).lower() in PLACEHOLDER_NAMES
                or m.group(2).lower() in PLACEHOLDER_NAMES
            ):
                continue
            if named.lower() != current_repo.lower():
                yield "stale-repo-name", named


def main():
    ap = argparse.ArgumentParser(
        description="Find context-dependent names and personal-environment leakage."
    )
    ap.add_argument("--project-dir", default=".")
    ap.add_argument("--config")
    ap.add_argument(
        "--include", action="append", default=[], help="git pathspec (repeatable)"
    )
    ap.add_argument(
        "--exclude", action="append", default=[], help="fnmatch glob (repeatable)"
    )
    ap.add_argument("--no-default-excludes", action="store_true")
    ap.add_argument(
        "--name",
        action="append",
        default=[],
        help="old name regex for the rename gate (repeatable)",
    )
    ap.add_argument("--only", help="comma-separated categories")
    ap.add_argument("--strict", action="store_true", help="any reported hit is ERROR")
    ap.add_argument(
        "--max-hits",
        type=int,
        default=200,
        help="HIT= lines printed (counts are always complete)",
    )
    args = ap.parse_args()

    proj_dir = os.path.abspath(args.project_dir)
    if git(proj_dir, "rev-parse", "--is-inside-work-tree").returncode != 0:
        usage_error("not a git work tree: %s" % proj_dir)

    cats = set(CATEGORIES)
    if args.only:
        cats = {c.strip() for c in args.only.split(",") if c.strip()}
        unknown = sorted(cats - set(CATEGORIES))
        if unknown:
            usage_error(
                "unknown category %s (known: %s)"
                % (", ".join(unknown), ", ".join(CATEGORIES))
            )

    patterns, allow = ([], {})
    if args.config:
        if not os.path.isfile(args.config):
            usage_error("config not found: %s" % args.config)
        patterns, allow = read_config(args.config)
    rules = dict(LINE_RULES)
    rules["identifier"] = patterns
    try:
        rules["old-name"] = [re.compile(n) for n in args.name]
    except re.error as exc:
        usage_error("invalid --name regex: %s" % exc)

    current_repo = repo_name(proj_dir)
    excludes = ([] if args.no_default_excludes else DEFAULT_EXCLUDES) + args.exclude

    proc = git(proj_dir, "ls-files", "-z", "--", *args.include)
    if proc.returncode != 0:
        usage_error(
            "git ls-files failed: %s" % proc.stderr.decode("utf-8", "replace").strip()
        )
    files = sorted(p for p in proc.stdout.decode("utf-8", "replace").split("\0") if p)

    hits = {}  # (path, match) -> [(cat, line_no, text)]
    scanned, excluded, binary = set(), 0, 0
    for rel in files:
        if any(fnmatch.fnmatch(rel, g) for g in excludes):
            excluded += 1
            continue
        full = os.path.join(proj_dir, rel)
        if not os.path.isfile(full):
            continue
        if "old-name" in cats:
            # A file left under its old name (a missed `git mv`) survives a
            # content-only gate, so the rename gate matches the path too.
            for rx in rules["old-name"]:
                m = rx.search(rel)
                if m:
                    hits.setdefault((rel, m.group(0)), []).append(
                        ("old-name", 0, "(file path)")
                    )
        with open(full, "rb") as fh:
            data = fh.read()
        if b"\0" in data:
            binary += 1
            continue
        scanned.add(rel)
        if "time-of-day" in cats:
            t = TIME_IN_NAME.search(os.path.basename(rel))
            if t:
                hits.setdefault((rel, t.group(0)), []).append(
                    ("time-of-day", 0, "(file name)")
                )
        recipe_file = bool(RECIPE_FILES.search(rel))
        for idx, line in enumerate(data.decode("utf-8", "replace").split("\n"), 1):
            for cat, match in scan_line(
                rel, line, rules, cats, current_repo, recipe_file
            ):
                hits.setdefault((rel, match), []).append((cat, idx, one_line(line)))

    counts = {c: 0 for c in CATEGORIES if c in cats}
    rows, allowed_hits = [], 0
    for key in sorted(hits):
        for cat, line_no, text in hits[key]:
            counts[cat] += 1
            if key in allow:
                allowed_hits += 1
                continue
            rows.append((cat, key[0], line_no, key[1], text))
    reported = len(rows)

    errors, warns = [], []
    for key in sorted(allow):
        if key not in hits:
            errors.append(
                (
                    "stale_allowlist",
                    "allow entry %s %r matches nothing; delete it" % key,
                )
            )
    if not scanned:
        errors.append(
            (
                "nothing_scanned",
                "no tracked files left to scan in %s; check --include/--exclude"
                % proj_dir,
            )
        )
    for cat, path, line_no, match, _ in rows:
        msg = "%s:%d [%s] %r" % (path, line_no, cat, match)
        (errors if args.strict else warns).append(("hit", msg))

    if errors:
        item_status = "ERROR"
    elif warns:
        item_status = "WARN"
    else:
        item_status = "OK"
    issues = [("ERROR",) + e for e in errors] + [("WARN",) + w for w in warns]

    print("=== CONTEXT LEAKAGE ===")
    print("REPO_NAME=%s" % current_repo)
    print("FILES_SCANNED=%d" % len(scanned))
    print("FILES_EXCLUDED=%d" % excluded)
    print("FILES_SKIPPED_BINARY=%d" % binary)
    print("CATEGORIES=%s" % ",".join(c for c in CATEGORIES if c in cats))
    for cat, n in counts.items():
        print("CATEGORY_%s=%d" % (cat.upper().replace("-", "_"), n))
    print("HITS_TOTAL=%d" % sum(counts.values()))
    print("ALLOWED_HITS=%d" % allowed_hits)
    print("REPORTED_HITS=%d" % reported)
    for cat, path, line_no, match, text in rows[: args.max_hits]:
        print("HIT=%s|%s:%d|%s|%s" % (cat, path, line_no, match, text[:160]))
    if reported > args.max_hits:
        print("HITS_TRUNCATED=%d" % (reported - args.max_hits))
    print("STATUS=%s" % item_status)
    if issues:
        first = next(i for i in issues if i[0] == item_status)
        reason = one_line("%s: %s" % (first[1], first[2]))[:180]
        if len(issues) > 1:
            reason += " (+%d more)" % (len(issues) - 1)
        print("REASON=%s" % reason)
    print("ISSUE_COUNT=%d" % len(issues))
    if issues:
        print("ISSUES:")
        for sev, itype, msg in issues:
            print("  - SEVERITY=%s TYPE=%s MSG=%s" % (sev, itype, one_line(msg)))
    print("=== END CONTEXT LEAKAGE ===")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
