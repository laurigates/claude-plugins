# ComfyUI metadata format reference

Code anchors in a real install (upstream pulls move these line numbers;
re-grep when they drift). Everything below is verified against real
output files in a ComfyUI install's `output/` directory.

## The two JSON forms

Every save path writes **two** related JSON blobs:

| Key | Form | Shape |
|---|---|---|
| `prompt` | API form | flat dict `{node_id: {inputs, class_type, _meta}}` — what the backend actually executed |
| `workflow` | UI form | graph form with `nodes`, `links`, `groups`, `extra`, `last_node_id`, `last_link_id` — what the frontend renders |

The summarizer in `comfy_meta.py` reads the **API form** because it
flattens reroutes/links/etc. into resolved `inputs` values, which is
easier to walk than the UI graph. If you need to *re-import* a workflow
into the ComfyUI editor, use the UI form via `extract -k workflow`.

`extra_pnginfo` is the open extension slot: any custom node can stash
JSON-serializable data there. By convention the UI's workflow JSON lives
under `extra_pnginfo["workflow"]`, which is why the second tEXt chunk is
named `workflow`. Other plug-ins (e.g. for citation metadata, model
provenance) sometimes add their own keys — the toolkit preserves them
in `extract`'s raw output but ignores them in the summary.

## PNG — `tEXt` chunks

`nodes.py:1652–1658` (core `SaveImage`):

```python
metadata = PngInfo()
metadata.add_text("prompt", json.dumps(prompt))
for x in extra_pnginfo:
    metadata.add_text(x, json.dumps(extra_pnginfo[x]))
img.save(path, pnginfo=metadata, compress_level=...)
```

PIL exposes the chunks as plain strings in `Image.info`:

```python
img = PIL.Image.open(path)
prompt   = json.loads(img.info["prompt"])      # API form
workflow = json.loads(img.info["workflow"])    # UI form
```

The `--disable-metadata` server flag short-circuits this whole block
(see `_create_png_metadata` at `comfy_api/latest/_ui.py:85–95`).

## Animated PNG (APNG)

`comfy_api/latest/_ui.py:98–120`. Uses `PngInfo.add()` with a
zero-terminated key, so the resulting chunks are `iTXt` (international
text, UTF-8) rather than `tEXt`. PIL still surfaces them via
`Image.info[key]`; behaviour from a reader's perspective is identical.

## WebP — EXIF (the awkward one)

`comfy_api/latest/_ui.py:123–135`:

```python
exif = pil_image.getexif()
exif[0x0110] = "prompt:{}".format(json.dumps(prompt))      # Model
tag = 0x010F                                                # Make
for key, value in extra_pnginfo.items():
    exif[tag] = "{}:{}".format(key, json.dumps(value))
    tag -= 1                                                # 0x010E, 0x010D, ...
img.save(path, exif=exif, ...)
```

**Two consequences:**

1. The value is **not** pure JSON — it's `"<key>:<json>"` (literal colon
   separator). Strip the prefix before `json.loads`. The toolkit does
   `value.split(":", 1)[1]`.
2. `extra_pnginfo` keys are placed in **descending tag order** starting
   from `0x010F`, not by name. To find the `workflow` blob, walk every
   EXIF tag in `getexif()` and split on the first `:` to identify each
   one by its embedded key.

The toolkit handles both — see `comfy_meta._read_webp` for the
implementation.

Real example: a Flux-Kontext PNG re-saved as WebP through `SaveAnimatedWEBP`
yields `exif` bytes ~45 KB. Tag `0x0110` holds `prompt:{...}`; tag
`0x010F` holds `workflow:{...}`.

## MP4 / WebM — two distinct dialects

Native ComfyUI `SaveVideo` (`comfy_extras/nodes_video.py:85–112`):

```python
metadata = {}
metadata.update(cls.hidden.extra_pnginfo)       # workflow ends up here
metadata["prompt"] = cls.hidden.prompt
output_container.metadata[key] = json.dumps(value) if not str else value
```

→ Container metadata has **per-key tags**: `prompt`, `workflow`, plus
any extra. Each value is a JSON string. Read with:

```python
import av
c = av.open(path)
prompt   = json.loads(c.metadata["prompt"])
workflow = json.loads(c.metadata["workflow"])
```

**Kijai WanVideoWrapper** (and VideoHelperSuite, MMAudio) take a
different approach: one container tag named `comment` (MP4) or `COMMENT`
(Matroska/WebM) holds a single JSON object:

```json
{"prompt": "<json-string>", "workflow": "<json-string>"}
```

So the prompt JSON is **double-encoded** — once for the inner string,
once for the wrapping object. Reader:

```python
import av, json
c = av.open(path)
blob = c.metadata.get("comment") or c.metadata.get("COMMENT")
wrap = json.loads(blob)                  # outer
prompt   = json.loads(wrap["prompt"])    # inner
workflow = json.loads(wrap["workflow"])
```

Verified empirically:

| File | format | Metadata keys |
|---|---|---|
| `output/WanVideoWrapper_I2V_00001.mp4` (kijai) | `mov,mp4,m4a,3gp,3g2,mj2` | `major_brand, minor_version, compatible_brands, creation_time, encoder, comment` |
| `output/mmaudio_00001.webm` (kijai) | `matroska,webm` | `COMMENT, creation_time, ENCODER` |

The toolkit auto-detects which dialect is in play: per-key first, fall
back to the `comment`/`COMMENT` blob.

### MP4 metadata atom support

MP4 (`isom`/`moov`) only natively supports a fixed list of atom names
in its `udta` box, which is why kijai picked `comment` (one of the
universally-supported ones). FFmpeg writes per-key tags via free-form
`-metadata key=value` flags, which it stores as ITU-style `©XXX` atoms;
PyAV exposes those as plain lowercase keys. WebM/Matroska is more
permissive — any tag name works, conventionally uppercase.

### Re-encoding gotcha

Container metadata survives stream-copy (`ffmpeg -c copy`) and `mv`/`cp`
but is dropped by re-encode unless you pass `-map_metadata 0`. If you
need to convert formats while preserving workflow data:

```sh
ffmpeg -i in.mp4 -c copy -map_metadata 0 out.mov
# Or, if a real re-encode is needed:
ffmpeg -i in.mp4 -map_metadata 0 -c:v libx264 -crf 18 out.mp4
```

## Audio (FLAC / OGG / MP3 / WAV)

`comfy_api/latest/_ui.py:261–319` (`AudioSaveHelper`). Same shape as
native SaveVideo — per-key container tags via PyAV, each value is
`json.dumps(...)`. Reader is identical to the per-key MP4 path.

## `.latent` files

`nodes.py:498–520` (core `SaveLatent`). Saves a safetensors with header
metadata:

```python
metadata = {}
metadata["prompt"] = json.dumps(prompt)
for x in extra_pnginfo:
    metadata[x] = json.dumps(extra_pnginfo[x])
# ... tae_latent_channels etc. for compatibility ...
safetensors.save_file({"latent": ...}, path, metadata=metadata)
```

Reader:

```python
from safetensors import safe_open
with safe_open(path, framework="pt") as f:
    meta = f.metadata() or {}
    prompt   = json.loads(meta["prompt"])
    workflow = json.loads(meta["workflow"])
```

Latents aren't currently saved on this install (no `*.latent` under
`output/`), but the code path is there and the toolkit covers it for
when a workflow does emit them.

## What goes into `extra_pnginfo`

The frontend sends two things:

- `extra_pnginfo["workflow"]` — the UI graph (set unconditionally for any
  prompt that came from the web UI)
- arbitrary custom-node additions — e.g. citation extensions write
  `extra_pnginfo["citations"]`; some packs write `extra_pnginfo["pysssss_prompts"]`
  or similar

Every key in `extra_pnginfo` becomes a separate top-level metadata entry
on every output format (PNG tEXt chunk, WebP EXIF tag, MP4 metadata key,
etc.), so a single output can have more than the canonical two JSON
blobs. The toolkit's `extract` returns them all under the raw key map;
`summary` ignores anything it doesn't understand.

## Compatibility quirks

### Animated PNG / iTXt vs tEXt

PIL's `PngInfo.add_text` writes `tEXt` (Latin-1) for the still path and
the manual `metadata.add(b"tEXt", b"key\x00...")` form, while the
animated path uses `PngInfo.add()` with a raw byte sequence which often
ends up as `iTXt`. Both surface identically through `Image.info[key]`,
so readers don't need to care. Writers that round-trip the metadata
should re-call `add_text` rather than copying chunk bytes.

### WebP EXIF tag exhaustion

`_create_webp_metadata` starts at `0x010F` and decrements per
`extra_pnginfo` key. There's no overflow guard — if a workflow stuffs
hundreds of keys into `extra_pnginfo`, tags eventually collide with
standard EXIF tags (orientation `0x0112`, x-resolution `0x011A`, …).
In practice `extra_pnginfo` only ever has `workflow` plus maybe one or
two pack-specific keys, so this hasn't bitten anyone yet. The toolkit
just walks every tag; collision with a numeric EXIF value would be
detected by the failing `value.split(":", 1)`.

### kijai vs native — which one will I see?

This install is dominated by **kijai** Wan workflows, so most MP4s here
have the single `comment` blob, not per-key tags. After 2026-03 ComfyUI
also has a native `SaveVideo` node (`comfy_extras/nodes_video.py`); if
you build a workflow with that instead of `WanVideoWrapper.save_video`,
you'll see per-key tags. The toolkit reads both transparently.

## Code anchors (verify against current `git HEAD`)

| What | File | Line(s) |
|---|---|---|
| Core `SaveImage` PNG write | `nodes.py` | 1652–1658 |
| Core `SaveLatent` | `nodes.py` | 498–520 |
| PNG metadata builder | `comfy_api/latest/_ui.py` | 85–95 |
| Animated PNG metadata builder | `comfy_api/latest/_ui.py` | 98–120 |
| WebP EXIF metadata builder | `comfy_api/latest/_ui.py` | 123–135 |
| Native `SaveVideo` video container write | `comfy_api/latest/_ui.py` | 317–319 |
| Native `SaveVideo` node | `comfy_extras/nodes_video.py` | 85–112 |
| Audio metadata builder | `comfy_api/latest/_ui.py` | 261–319 |
| `--disable-metadata` flag | `app/cmd_args.py` | search for `disable-metadata` |

When upstream renames `comfy_api/latest/_ui.py` or moves the helpers
(historically: this code used to live inline in `SaveImage`), update
this table.

## Sanity-check commands

```sh
# Confirm a PNG has the workflow tEXt chunk
.venv/bin/python -c "from PIL import Image; print(list(Image.open('foo.png').info))"

# Confirm an MP4 has container metadata
.venv/bin/python -c "import av; print(list(av.open('foo.mp4').metadata))"

# Strip JSON values to one line for quick eyeballing
.venv/bin/python -c "
import json, sys
from PIL import Image
i = Image.open(sys.argv[1])
for k in ('prompt','workflow'):
    if k in i.info:
        d = json.loads(i.info[k])
        print(f'{k}: {len(i.info[k]):,} chars, {len(d) if hasattr(d,\"__len__\") else \"?\"} top-level keys')
" foo.png
```
