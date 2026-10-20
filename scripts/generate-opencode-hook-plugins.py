#!/usr/bin/env python3
"""Generate OpenCode JS plugins from Claude Code plugin hook manifests.

Part of the OpenCode export pipeline (scripts/export-opencode.sh, issue #1605).
OpenCode has no Claude Code hook surface, so hooks have to be projected into its
plugin API. A converter was never an option: rulesync (retired in #2094) read
the consumer .claude/settings.json surface rather than plugin manifests, passed
${CLAUDE_PLUGIN_ROOT} through literally, and never copied the referenced scripts
(dyoshikawa/rulesync#1317). This generator projects them directly:

  <plugin>/hooks.json                        \\
  <plugin>/.claude-plugin/plugin.json#hooks  >  <out>/plugins/<plugin>-hooks.js
  <plugin>/hooks/*.sh  ->  <out>/hook-scripts/<plugin>/hooks/*.sh  (referenced scripts only)
  + each copied script's transitive helpers (PR #3046 review): the plugin's
    hooks/lib/ when a script mentions lib/, any <other>-plugin/hooks/lib/ it
    reaches across (both as generate-pi-hook-extension.py's copy_scripts), and
    sibling files in the same hooks/ dir it names (e.g. workflow-scale-guard.sh
    -> workflow-scale-estimate.py), followed transitively.

Discovery (issue #2724): every `*-plugin` directory is scanned for BOTH
declaration sites: a bare `<plugin>/hooks.json`, and the `hooks` value of
`.claude-plugin/plugin.json`. That value is either an inline object (events
directly beneath it) or a path / list of paths resolved against the plugin
dir; a `"./hooks.json"` pointer is de-duplicated against the bare file so it
is read once. All sources for one plugin merge into a single JS plugin.

Fidelity contract (what exports and how):
  - PreToolUse  command hooks -> "tool.execute.before": exit code 2 or JSON
    permissionDecision "deny" -> throw (OpenCode's blocking mechanism); JSON
    permissionDecision "ask" -> console.warn + allow (OpenCode cannot prompt
    from a hook).
  - PostToolUse command hooks -> "tool.execute.after": exit-2 stderr / JSON
    decision "block" reason / additionalContext appended to the model-visible
    tool output string.

Skipped, loudly (reported on stdout and in the generated JS header):
  - prompt / agent hooks — OpenCode has no model-evaluation hook (by design).
  - SessionStart / PreCompact / other events — no context-injection equivalent.
  - command strings not shaped `bash "${CLAUDE_PLUGIN_ROOT}/hooks/<script>.sh"`
    (the unquoted `bash ${CLAUDE_PLUGIN_ROOT}/hooks/<script>.sh` is still
    accepted for back-compat).
  - matcher alternatives naming a Claude Code tool OpenCode lacks (e.g.
    `SlashCommand`, `Workflow`): kept verbatim, so they never match; NOTE line.
  - malformed plugin.json / hooks.json (PARSE-ERROR) and hooks pointers that
    escape the plugin dir or name a missing file (POINTER-SKIP): reported per
    plugin, the export continues, and STATUS=WARN.

A missing script at runtime FAILS OPEN (console.error + allow) — deliberately
NOT the throw-ENOENT-on-every-matched-call failure mode a path-only projection
produces (what rulesync's output did, per the note above).

Usage: generate-opencode-hook-plugins.py <repo_root> <out_dir>
"""

import json
import re
import shutil
import sys
from pathlib import Path

EXPORTABLE_EVENTS = {"PreToolUse": "before", "PostToolUse": "after"}

# Claude Code tool name -> OpenCode built-in tool name.
CLAUDE_TO_OPENCODE_TOOL = {
    "Bash": "bash",
    "Write": "write",
    "Edit": "edit",
    "Read": "read",
    "Glob": "glob",
    "Grep": "grep",
    "LS": "list",
    "Task": "task",
    "Skill": "skill",
    "WebFetch": "webfetch",
    "TodoWrite": "todowrite",
}
OPENCODE_TOOLS = set(CLAUDE_TO_OPENCODE_TOOL.values())

# Accepts both `bash ${CLAUDE_PLUGIN_ROOT}/hooks/x.sh` and the quoted
# `bash "${CLAUDE_PLUGIN_ROOT}/hooks/x.sh"` (the form `claude plugin validate`
# requires since 2.1.281, so a plugin root containing a space is not
# word-split). The opening quote is captured and the closing one must match
# it; callers read the script name from the named group `script`.
COMMAND_RE = re.compile(
    r'^bash (?P<q>")?\$\{CLAUDE_PLUGIN_ROOT\}/hooks/(?P<script>[A-Za-z0-9._-]+\.sh)(?(q)"|)$'
)
MATCHER_WITH_ARG_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\((.*)\)$")

# Transitive-dependency detection for copied hook scripts. LIB_REF_RE is a
# superset of generate-pi-hook-extension.py's `"/lib/" in text` test (it also
# catches `os.path.join(HERE, "lib", ...)` and a bare `lib/x` mention);
# CROSS_PLUGIN_LIB_RE is the pi generator's pattern verbatim. SIBLING_REF_RE
# collects candidate file names; only those that exist directly in the same
# plugin's hooks/ dir are copied.
LIB_REF_RE = re.compile(r"\blib/|[\"']lib[\"']")
CROSS_PLUGIN_LIB_RE = re.compile(r"([A-Za-z0-9_-]+-plugin)/hooks/lib/")
SIBLING_REF_RE = re.compile(r"[A-Za-z0-9_][A-Za-z0-9._-]*\.(?:sh|py|cjs|mjs|js)\b")


def glob_to_regex(pattern):
    """Translate a Claude Code matcher glob (docs/prds/**) to a JS regex source.

    `**` crosses path separators; `*` and `?` stay within one component.
    """
    out = []
    i = 0
    while i < len(pattern):
        if pattern[i : i + 2] == "**":
            out.append(".*")
            i += 2
        elif pattern[i] == "*":
            out.append("[^/]*")
            i += 1
        elif pattern[i] == "?":
            out.append("[^/]")
            i += 1
        else:
            out.append(re.escape(pattern[i]))
            i += 1
    return "^" + "".join(out) + "$"


def normalize_timeout(value):
    """hooks.json timeouts are seconds and pass through unchanged (floats are
    truncated to int). A missing, non-numeric, zero or negative value falls
    back to 60. Millisecond-looking values are kept out of the manifests by
    scripts/check-hook-timeout-units.sh (fails on any timeout >= 1000), so no
    unit conversion happens here (#3092)."""
    if not isinstance(value, (int, float)) or value <= 0:
        return 60
    return int(value)


def parse_matcher(matcher):
    """Return a list of {tool, path_re, skill_name} dicts (one per `|` alternative),
    or None when the matcher cannot be translated."""
    matcher = (matcher or "").strip()
    if matcher == "":
        return [{"tool": None, "path_re": None, "skill_name": None}]
    results = []
    # Only split alternation when no parenthesised argument is present.
    alternatives = matcher.split("|") if "(" not in matcher else [matcher]
    for alt in alternatives:
        alt = alt.strip()
        m = MATCHER_WITH_ARG_RE.match(alt)
        if m:
            tool_name, arg = m.group(1), m.group(2)
            opencode_tool = CLAUDE_TO_OPENCODE_TOOL.get(tool_name)
            if opencode_tool is None:
                return None
            if tool_name in ("Write", "Edit", "Read"):
                results.append(
                    {
                        "tool": opencode_tool,
                        "path_re": glob_to_regex(arg),
                        "skill_name": None,
                    }
                )
            elif tool_name == "Skill":
                results.append(
                    {"tool": opencode_tool, "path_re": None, "skill_name": arg}
                )
            else:
                return None
        else:
            # Bare tool name; MCP tool matchers (mcp__*) pass through verbatim.
            opencode_tool = CLAUDE_TO_OPENCODE_TOOL.get(alt, alt)
            results.append({"tool": opencode_tool, "path_re": None, "skill_name": None})
    return results


def js_export_name(plugin_name):
    return (
        "".join(p.capitalize() for p in re.split(r"[^A-Za-z0-9]+", plugin_name) if p)
        + "Hooks"
    )


JS_TEMPLATE = """// Generated by scripts/generate-opencode-hook-plugins.py — DO NOT EDIT.
// Source: {sources} (Claude Code plugin hooks -> OpenCode plugin).
// Layout: this file lives in <scope>/plugins/; its scripts live in
// <scope>/hook-scripts/{plugin}/hooks/, and CLAUDE_PLUGIN_ROOT is exported at
// that root so the scripts' own plugin-root references keep resolving.
//
// Semantics:
//   PreToolUse  -> tool.execute.before  (exit 2 / JSON deny -> throw = block;
//                                        JSON "ask" -> warn + allow: no prompt hook)
//   PostToolUse -> tool.execute.after   (block reason / additionalContext appended
//                                        to the model-visible tool output)
//   Missing or crashing scripts FAIL OPEN (console.error + allow).
{skip_report}
import {{ fileURLToPath }} from "node:url";

const PLUGIN_ROOT = fileURLToPath(new URL("../hook-scripts/{plugin}", import.meta.url));

const BEFORE = {before_json};

const AFTER = {after_json};

// OpenCode tool name -> Claude Code tool name (what the scripts expect on stdin).
const CLAUDE_TOOL_NAMES = {{
  bash: "Bash", write: "Write", edit: "Edit", read: "Read", glob: "Glob",
  grep: "Grep", list: "LS", task: "Task", skill: "Skill",
  webfetch: "WebFetch", todowrite: "TodoWrite",
}};

function claudeToolName(tool) {{
  return CLAUDE_TOOL_NAMES[tool] ?? tool.charAt(0).toUpperCase() + tool.slice(1);
}}

// OpenCode args are camelCase (filePath); Claude hook payloads are snake_case.
function toToolInput(args) {{
  const out = {{}};
  for (const [k, v] of Object.entries(args ?? {{}}))
    out[k.replace(/([A-Z])/g, "_$1").toLowerCase()] = v;
  return out;
}}

function matches(entry, tool, args, directory) {{
  if (entry.tool !== null && entry.tool !== tool) return false;
  if (entry.pathRe) {{
    let p = args?.filePath ?? args?.file_path ?? "";
    if (typeof p !== "string" || p === "") return false;
    if (directory && p.startsWith(directory + "/")) p = p.slice(directory.length + 1);
    if (!new RegExp(entry.pathRe).test(p)) return false;
  }}
  if (entry.skillName) {{
    const candidates = [args?.name, args?.skill, args?.skillName, args?.id];
    if (!candidates.includes(entry.skillName)) return false;
  }}
  return true;
}}

function parseDecision(stdout) {{
  const t = (stdout ?? "").trim();
  if (!t.startsWith("{{")) return {{}};
  try {{
    const j = JSON.parse(t);
    const hso = j.hookSpecificOutput ?? {{}};
    return {{
      deny: hso.permissionDecision === "deny" || j.decision === "block",
      ask: hso.permissionDecision === "ask",
      reason: hso.permissionDecisionReason ?? j.reason ?? "",
      context: hso.additionalContext ?? "",
    }};
  }} catch {{
    return {{}};
  }}
}}

async function runHook(entry, payload, directory) {{
  const script = PLUGIN_ROOT + "/hooks/" + entry.script;
  try {{
    const proc = Bun.spawn(["bash", script], {{
      cwd: directory,
      stdin: new TextEncoder().encode(JSON.stringify(payload)),
      stdout: "pipe",
      stderr: "pipe",
      env: {{
        ...process.env,
        CLAUDE_PLUGIN_ROOT: PLUGIN_ROOT,
        CLAUDE_PROJECT_DIR: directory ?? "",
      }},
    }});
    const killTimer = setTimeout(() => proc.kill(), (entry.timeout ?? 60) * 1000);
    const exitCode = await proc.exited;
    clearTimeout(killTimer);
    return {{
      exitCode,
      stdout: await new Response(proc.stdout).text(),
      stderr: await new Response(proc.stderr).text(),
    }};
  }} catch (err) {{
    // Fail open: a missing/broken hook script must never block tool calls.
    console.error(`[{plugin}-hooks] ${{entry.script}}: ${{err}}`);
    return null;
  }}
}}

export const {export_name} = async ({{ directory }}) => {{
  // tool.execute.after does not carry args; capture them per call in before.
  const argsByCall = new Map();
  return {{
    "tool.execute.before": async (input, output) => {{
      if (input.callID !== undefined) {{
        if (argsByCall.size > 1000)
          argsByCall.delete(argsByCall.keys().next().value);
        argsByCall.set(input.callID, output.args);
      }}
      for (const entry of BEFORE) {{
        if (!matches(entry, input.tool, output.args, directory)) continue;
        const res = await runHook(entry, {{
          hook_event_name: "PreToolUse",
          tool_name: claudeToolName(input.tool),
          tool_input: toToolInput(output.args),
          session_id: input.sessionID ?? "",
          cwd: directory ?? "",
          transcript_path: "",
        }}, directory);
        if (!res) continue;
        if (res.exitCode === 2)
          throw new Error(res.stderr.trim() || `Blocked by ${{entry.script}}`);
        if (res.exitCode !== 0) {{
          console.error(`[{plugin}-hooks] ${{entry.script}} exited ${{res.exitCode}}: ${{res.stderr.trim()}}`);
          continue;
        }}
        const d = parseDecision(res.stdout);
        if (d.deny) throw new Error(d.reason || `Blocked by ${{entry.script}}`);
        if (d.ask)
          console.warn(`[{plugin}-hooks] ${{entry.script}} requested confirmation (OpenCode cannot prompt; allowing): ${{d.reason}}`);
      }}
    }},
    "tool.execute.after": async (input, output) => {{
      const args = argsByCall.get(input.callID);
      argsByCall.delete(input.callID);
      for (const entry of AFTER) {{
        if (!matches(entry, input.tool, args, directory)) continue;
        const res = await runHook(entry, {{
          hook_event_name: "PostToolUse",
          tool_name: claudeToolName(input.tool),
          tool_input: toToolInput(args),
          tool_response: {{ output: typeof output.output === "string" ? output.output : "" }},
          session_id: input.sessionID ?? "",
          cwd: directory ?? "",
          transcript_path: "",
        }}, directory);
        if (!res) continue;
        const notes = [];
        if (res.exitCode === 2) {{
          if (res.stderr.trim()) notes.push(res.stderr.trim());
        }} else if (res.exitCode === 0) {{
          const d = parseDecision(res.stdout);
          if (d.deny && d.reason) notes.push(d.reason);
          if (d.context) notes.push(d.context);
        }} else {{
          console.error(`[{plugin}-hooks] ${{entry.script}} exited ${{res.exitCode}}: ${{res.stderr.trim()}}`);
        }}
        if (notes.length && typeof output.output === "string")
          output.output += `\\n\\n[${{entry.script}}] ` + notes.join("\\n");
      }}
    }},
  }};
}};
"""


def _load_hooks_json(path, label, problems):
    """Parse one JSON file; on failure record a PARSE-ERROR and return None."""
    try:
        return json.loads(path.read_text())
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as err:
        problems.append(f"PARSE-ERROR={label}: {err}")
        return None


def _hooks_of(doc):
    hooks = doc.get("hooks") if isinstance(doc, dict) else None
    return hooks if isinstance(hooks, dict) else {}


def discover_hook_sources(plugin_dir):
    """Return (sources, problems): sources is [(source_label, events_dict)] for
    every hook declaration site of one plugin (empty = declares no hooks);
    problems is a list of `PARSE-ERROR=...` / `POINTER-SKIP=...` report
    fragments, so one malformed manifest is reported rather than aborting the
    whole export.

    Reads `<plugin>/hooks.json` AND `<plugin>/.claude-plugin/plugin.json#hooks`
    (issue #2724: eight plugins declare hooks inline in plugin.json with no
    hooks.json, so a `*-plugin/hooks.json` glob never saw them). A plugin.json
    `hooks` that is a path (or list of paths) is resolved relative to the
    plugin dir and de-duplicated against hooks.json, so a `"./hooks.json"`
    pointer is read once. Mirrors generate-pi-hook-extension.py's discovery.
    """
    sources = []
    problems = []
    seen = set()
    plugin_root = plugin_dir.resolve()
    hooks_json = plugin_dir / "hooks.json"
    if hooks_json.is_file():
        seen.add(hooks_json.resolve())
        doc = _load_hooks_json(hooks_json, "hooks.json", problems)
        if doc is not None:
            sources.append(("hooks.json", _hooks_of(doc)))
    plugin_json = plugin_dir / ".claude-plugin" / "plugin.json"
    if not plugin_json.is_file():
        return sources, problems
    manifest = _load_hooks_json(plugin_json, ".claude-plugin/plugin.json", problems)
    if not isinstance(manifest, dict):
        return sources, problems
    declared = manifest.get("hooks")
    if isinstance(declared, dict):
        sources.append(("plugin.json", declared))
        return sources, problems
    refs = declared if isinstance(declared, list) else [declared]
    for ref in refs:
        if not isinstance(ref, str):
            continue
        target = (plugin_dir / ref).resolve()
        try:
            label = target.relative_to(plugin_root).as_posix()
        except ValueError:
            problems.append(f"POINTER-SKIP={ref} reason=escapes plugin dir")
            continue
        if target in seen:
            continue
        if not target.is_file():
            problems.append(f"POINTER-SKIP={ref} reason=file not found")
            continue
        seen.add(target)
        doc = _load_hooks_json(target, label, problems)
        if doc is not None:
            sources.append((label, _hooks_of(doc)))
    return sources, problems


def copy_hook_scripts(repo_root, plugin_dir, scripts, out_dir):
    """Copy the referenced scripts plus their transitive helpers.

    Returns (libs, helpers): the plugins whose hooks/lib/ was copied, and the
    sibling helper files pulled in by name. Mirrors the pi generator's
    copy_scripts lib handling so both exports ship the same dependency tree.
    """
    plugin = plugin_dir.name
    hooks_dir = plugin_dir / "hooks"
    dst_dir = out_dir / "hook-scripts" / plugin / "hooks"
    dst_dir.mkdir(parents=True, exist_ok=True)

    queue = sorted(scripts)
    copied = set(queue)
    helpers = []
    libs = set()
    while queue:
        name = queue.pop(0)
        src = hooks_dir / name
        shutil.copy2(src, dst_dir / name)
        text = src.read_text(errors="replace")
        if LIB_REF_RE.search(text) and (hooks_dir / "lib").is_dir():
            libs.add(plugin)
        libs.update(
            p
            for p in CROSS_PLUGIN_LIB_RE.findall(text)
            if (repo_root / p / "hooks" / "lib").is_dir()
        )
        # Sibling names are read from code lines only: hook headers routinely
        # cite their test twin or a peer hook in a `#` comment, which is not a
        # runtime dependency.
        code = "\n".join(
            line for line in text.splitlines() if not line.lstrip().startswith("#")
        )
        for ref in sorted(set(SIBLING_REF_RE.findall(code))):
            if ref not in copied and (hooks_dir / ref).is_file():
                copied.add(ref)
                helpers.append(ref)
                queue.append(ref)
    for lib_plugin in sorted(libs):
        shutil.copytree(
            repo_root / lib_plugin / "hooks" / "lib",
            out_dir / "hook-scripts" / lib_plugin / "hooks" / "lib",
            dirs_exist_ok=True,
        )
    return sorted(libs), sorted(helpers)


def source_path(plugin, label):
    """Repo-relative path of a hook source label, for the JS header."""
    if label == "plugin.json":
        return f"{plugin}/.claude-plugin/plugin.json"
    return f"{plugin}/{label}"


def process_plugin(repo_root, plugin_dir, sources, out_dir):
    """Returns (exported_count, skipped list of (event, matcher, kind, reason),
    notes list of (event, matcher, reason), copied script names, copied lib
    plugins, copied helper names)."""
    plugin = plugin_dir.name

    entries = {"before": [], "after": []}
    skipped = []
    notes = []
    scripts = set()

    events = [item for _, hooks in sources for item in hooks.items()]
    for event, groups in events:
        slot = EXPORTABLE_EVENTS.get(event)
        for group in groups:
            matcher = group.get("matcher", "")
            for hook in group.get("hooks", []):
                kind = hook.get("type", "command")
                if slot is None:
                    skipped.append(
                        (event, matcher, kind, "no OpenCode equivalent for this event")
                    )
                    continue
                if kind != "command":
                    skipped.append(
                        (event, matcher, kind, "OpenCode has no model-evaluation hook")
                    )
                    continue
                cmd = (hook.get("command") or "").strip()
                m = COMMAND_RE.match(cmd)
                if not m:
                    skipped.append(
                        (event, matcher, kind, f"unparseable command: {cmd}")
                    )
                    continue
                script = m.group("script")
                parsed = parse_matcher(matcher)
                if parsed is None:
                    skipped.append((event, matcher, kind, "untranslatable matcher"))
                    continue
                if not (plugin_dir / "hooks" / script).is_file():
                    skipped.append(
                        (
                            event,
                            matcher,
                            kind,
                            f"referenced script missing: hooks/{script}",
                        )
                    )
                    continue
                # A bare Claude Code tool name OpenCode lacks (SlashCommand,
                # Workflow) still passes through verbatim, as MCP names do, but
                # can never match: report it so the dead entry is visible.
                unmapped = [
                    a["tool"]
                    for a in parsed
                    if a["tool"] is not None
                    and a["tool"] not in OPENCODE_TOOLS
                    and not a["tool"].startswith("mcp__")
                ]
                if unmapped:
                    notes.append(
                        (
                            event,
                            matcher,
                            "no OpenCode tool named "
                            + "|".join(unmapped)
                            + " (entry kept, never matches)",
                        )
                    )
                timeout = normalize_timeout(hook.get("timeout", 60))
                for alt in parsed:
                    entries[slot].append(
                        {
                            "tool": alt["tool"],
                            "pathRe": alt["path_re"],
                            "skillName": alt["skill_name"],
                            "script": script,
                            "timeout": timeout,
                        }
                    )
                scripts.add(script)

    exported = len(entries["before"]) + len(entries["after"])
    if exported == 0:
        return 0, skipped, notes, [], [], []

    libs, helpers = copy_hook_scripts(repo_root, plugin_dir, scripts, out_dir)

    lines = ["//"]
    if libs or helpers:
        lines.append("// Helpers copied alongside the scripts:")
        lines.extend(f"//   - {p}/hooks/lib/" for p in libs)
        lines.extend(f"//   - hooks/{h}" for h in helpers)
    if notes:
        lines.append("// Notes:")
        for event, matcher, reason in notes:
            lines.append(f"//   - {event} [{matcher}]: {reason}")
    if skipped:
        lines.append("// Skipped (not exportable to OpenCode):")
        for event, matcher, kind, reason in skipped:
            shown = matcher or '""'
            lines.append(f"//   - {event} [{shown}] type={kind}: {reason}")
    skip_report = "\n".join(lines)

    js = JS_TEMPLATE.format(
        plugin=plugin,
        sources=", ".join(source_path(plugin, label) for label, _ in sources),
        export_name=js_export_name(plugin),
        skip_report=skip_report,
        before_json=json.dumps(entries["before"], indent=2),
        after_json=json.dumps(entries["after"], indent=2),
    )
    plugins_dst = out_dir / "plugins"
    plugins_dst.mkdir(parents=True, exist_ok=True)
    (plugins_dst / f"{plugin}-hooks.js").write_text(js)
    return exported, skipped, notes, sorted(scripts), libs, helpers


def main():
    if len(sys.argv) != 3:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 2
    repo_root = Path(sys.argv[1]).resolve()
    out_dir = Path(sys.argv[2]).resolve()

    print("=== OPENCODE HOOK EXPORT ===")
    generated = total_exported = total_skipped = total_scripts = 0
    scanned = total_libs = total_helpers = parse_errors = pointer_skips = 0
    for plugin_dir in sorted(p for p in repo_root.glob("*-plugin") if p.is_dir()):
        sources, problems = discover_hook_sources(plugin_dir)
        for problem in problems:
            print(f"PLUGIN={plugin_dir.name} {problem}")
        parse_errors += sum(p.startswith("PARSE-ERROR=") for p in problems)
        pointer_skips += sum(p.startswith("POINTER-SKIP=") for p in problems)
        if not sources:
            continue
        scanned += 1
        exported, skipped, notes, scripts, libs, helpers = process_plugin(
            repo_root, plugin_dir, sources, out_dir
        )
        js_path = f"plugins/{plugin_dir.name}-hooks.js" if exported else "-"
        extra = ""
        if libs:
            extra += f" LIBS={','.join(libs)}"
        if helpers:
            extra += f" HELPERS={','.join(helpers)}"
        print(
            f"PLUGIN={plugin_dir.name} JS={js_path} "
            f"EXPORTED={exported} SKIPPED={len(skipped)} "
            f"SOURCE={','.join(label for label, _ in sources)}{extra}"
        )
        for event, matcher, reason in notes:
            print(f"  NOTE event={event} matcher={matcher} reason={reason}")
        for event, matcher, kind, reason in skipped:
            shown = matcher if matcher else '""'
            print(f"  SKIP event={event} matcher={shown} type={kind} reason={reason}")
        if exported:
            generated += 1
        total_exported += exported
        total_skipped += len(skipped)
        total_scripts += len(scripts)
        total_libs += len(libs)
        total_helpers += len(helpers)

    print(f"HOOK_PLUGINS_SCANNED={scanned}")
    print(f"HOOK_PLUGINS_GENERATED={generated}")
    print(f"EXPORTED_HOOKS={total_exported}")
    print(f"SKIPPED_HOOKS={total_skipped}")
    print(f"COPIED_SCRIPTS={total_scripts}")
    print(f"COPIED_HELPERS={total_helpers}")
    print(f"COPIED_LIB_DIRS={total_libs}")
    print(f"PARSE_ERRORS={parse_errors}")
    print(f"POINTER_SKIPS={pointer_skips}")
    print("STATUS=WARN" if parse_errors or pointer_skips else "STATUS=OK")
    print("=== END OPENCODE HOOK EXPORT ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())
