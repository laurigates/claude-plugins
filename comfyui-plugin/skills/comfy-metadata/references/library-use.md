# ComfyUI output metadata — Library Use (batch scripts)

Importing `comfy_meta` from Python for batch renaming, indexing, or classifying many outputs, including reading the UI-workflow half the summarizer does not surface. Entry point: [`../SKILL.md`](../SKILL.md) § Toolkit.

### Library use (batch scripts)

For ad-hoc batch work — renaming, indexing, clustering — calling the CLI
once per file is slow. Import `comfy_meta` directly instead. It has no
package wrapper, so add its dir to `sys.path` first:

```python
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(".claude/skills/comfy-metadata/scripts")))
import comfy_meta

for p in pathlib.Path("output").iterdir():
    if not p.is_file():
        continue
    ex = comfy_meta.extract(p)        # {"prompt": <api-dict>, "workflow": <ui-dict>}
    prompt = ex.get("prompt")
    if not isinstance(prompt, dict) or not prompt:
        continue                       # no embedded metadata
    summary = comfy_meta.summarize(prompt)
    print(p.name, summary.sampler, summary.scheduler, summary.seed)
```

`extract()` returns parsed JSON for both halves; `summarize()` walks the
API prompt and yields a `Summary` dataclass. Those two calls are enough
to build new filenames from `summary.samplers[0]` and the source file's
mtime; `scripts/comfy_meta.py` is the only script this skill ships.

### The UI workflow half is useful too

`summarize()` covers the API `prompt`, but `extract()["workflow"]` (the
UI form) carries data the summarizer doesn't surface — most usefully
**save-node widgets**. A workflow that wrote itself to a dedicated output
bucket (`<bucket>/<date>/…`) self-labels its outputs, so the prefix is a
free classification signal:

```python
BUCKET = "<bucket>/"          # whatever prefix your install sorts into

ex = comfy_meta.extract(p)
workflow = ex.get("workflow") or {}
for n in workflow.get("nodes", []) or []:
    wv = n.get("widgets_values")
    # SaveImage / SaveWEBM: list[0] is the filename_prefix
    if isinstance(wv, list) and wv and isinstance(wv[0], str) and wv[0].startswith(BUCKET):
        return BUCKET.rstrip("/")
    # VHS_VideoCombine: dict["filename_prefix"]
    if isinstance(wv, dict) and str(wv.get("filename_prefix", "")).startswith(BUCKET):
        return BUCKET.rstrip("/")
```

An NSFW classifier can combine this self-label signal
with API-prompt asset-name token matching (model / text-encoder / LoRA
names). The same approach works for any other categorisation the UI
workflow encodes that the API prompt strips out: node titles, custom
properties, group names, etc.
