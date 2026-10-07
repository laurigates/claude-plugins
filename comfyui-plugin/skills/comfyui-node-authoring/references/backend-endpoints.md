# comfyui-node-authoring — Backend Endpoints

Reusing ComfyUI's core endpoints and helpers, and keeping a listing endpoint cheap. Entry point: [`../SKILL.md`](../SKILL.md).

## Reusing core endpoints

- `/api/view?filename=<name>&type=input|output|temp&subfolder=<sub>&preview=webp;75`
  returns a webp thumbnail; handles subfolder-escape checks. Works only for
  the three managed roots — arbitrary absolute paths must be served by your
  own endpoint.
- `folder_paths.annotated_filepath()` parses `name [input|output|temp]`.
- `PromptServer.instance.routes.get("/your_pack/something")` registers an
  HTTP endpoint. Call from JS via `fetch("/your_pack/...")`.

## Cheap metadata in listing endpoints

`PIL.Image.open(path)` is lazy — only the file header is decoded until pixel
data is accessed. So `.size`, `.mode`, and `.format` are nearly free and safe
to call inside an `os.scandir` listing loop, even for directories of 100+
images. Wrap in `try/except` so a single broken file doesn't kill the
listing, and do **not** call `im.load()` or access pixels in the listing
loop — that forces a full decode and turns the loop into a multi-second
operation.

```python
width: int | None = None
height: int | None = None
try:
    with Image.open(entry.path) as im:
        width, height = im.size
except Exception:
    pass
```
