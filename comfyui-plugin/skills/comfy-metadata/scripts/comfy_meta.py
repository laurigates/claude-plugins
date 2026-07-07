#!/usr/bin/env python3
"""Read and analyze workflow metadata embedded in ComfyUI output files.

Library + CLI. Run with the project venv:

    .venv/bin/python .claude/skills/comfy-metadata/scripts/comfy_meta.py <cmd> ...

Subcommands:
    extract  <file>             dump prompt+workflow JSON (or one half via -k)
    summary  <file>             one-record summary of generation settings
    scan     <dir>              walk a tree, write one JSONL line per file
    diff     <file_a> <file_b>  unified diff of summarized settings

The summarizer recognizes the common loader / sampler / lora / latent /
text-encode node classes used in this install (core + WanVideoWrapper +
Qwen-Image-Edit + Flux + SDXL + HiDream). Unknown nodes are preserved
in the raw `prompt` half of `extract` but ignored by `summary`.
"""

from __future__ import annotations

import argparse
import dataclasses
import difflib
import io
import json
import os
import sys
from collections.abc import Iterable
from pathlib import Path
from typing import Any

# ---------------------------------------------------------------------------
# Raw extraction per file format
# ---------------------------------------------------------------------------

PNG_EXTS = {".png", ".apng"}
WEBP_EXTS = {".webp"}
PIL_EXTS = PNG_EXTS | WEBP_EXTS | {".jpg", ".jpeg", ".tiff", ".gif"}
VIDEO_EXTS = {".mp4", ".mov", ".webm", ".mkv", ".avi"}
AUDIO_EXTS = {".flac", ".ogg", ".mp3", ".wav", ".m4a", ".opus"}
LATENT_EXTS = {".latent"}


def _read_pil(path: Path) -> dict[str, str]:
    """Return raw key→string map from PIL Image.info (PNG tEXt / WebP EXIF / etc.)."""
    from PIL import Image  # lazy

    out: dict[str, str] = {}
    with Image.open(path) as img:
        # PNG tEXt / iTXt chunks land directly in Image.info as strings
        for k, v in img.info.items():
            if isinstance(v, str) and k in {"prompt", "workflow"}:
                out[k] = v
            elif isinstance(v, str) and v.startswith(("prompt:", "workflow:")):
                # belt + braces — shouldn't happen for PNG but harmless
                k2, _, val = v.partition(":")
                out[k2] = val

        # WebP: metadata lives in EXIF tags, encoded as "key:json"
        if "exif" in img.info or img.format == "WEBP":
            try:
                exif = img.getexif()
                for _, raw in exif.items():
                    if isinstance(raw, bytes):
                        try:
                            raw = raw.decode("utf-8", "ignore")
                        except Exception:
                            continue
                    if not isinstance(raw, str) or ":" not in raw:
                        continue
                    k2, _, val = raw.partition(":")
                    k2 = k2.strip()
                    if k2 in {"prompt", "workflow"} and val.lstrip().startswith(("{", "[")):
                        out.setdefault(k2, val)
            except Exception:
                pass
    return out


def _read_container(path: Path) -> dict[str, str]:
    """Return raw key→string map from a video/audio container.

    Handles both ComfyUI dialects:
        - native SaveVideo / SaveAudio: per-key tags (`prompt`, `workflow`, …)
        - kijai WanVideoWrapper / VHS: single `comment` (or uppercase `COMMENT`)
          holding a JSON object `{"prompt": <str>, "workflow": <str>}`
    """
    import av  # lazy

    out: dict[str, str] = {}
    with av.open(str(path)) as c:
        meta = dict(c.metadata)

    # Lowercase the keys we care about for the per-key path
    for k, v in meta.items():
        if k.lower() in {"prompt", "workflow"} and isinstance(v, str):
            out[k.lower()] = v

    if "prompt" not in out:
        # kijai / VHS dialect
        blob = meta.get("comment") or meta.get("COMMENT")
        if isinstance(blob, str) and blob.lstrip().startswith("{"):
            try:
                wrap = json.loads(blob)
                if isinstance(wrap, dict):
                    for k in ("prompt", "workflow"):
                        v = wrap.get(k)
                        if isinstance(v, str):
                            out[k] = v
                        elif v is not None:
                            out[k] = json.dumps(v)
            except json.JSONDecodeError:
                pass
    return out


def _read_latent(path: Path) -> dict[str, str]:
    from safetensors import safe_open  # lazy

    out: dict[str, str] = {}
    with safe_open(str(path), framework="numpy") as f:
        meta = f.metadata() or {}
        for k in ("prompt", "workflow"):
            if k in meta:
                out[k] = meta[k]
    return out


def read_raw_metadata(path: str | os.PathLike[str]) -> dict[str, str]:
    """Read raw key→JSON-string map from a ComfyUI output file.

    Returns an empty dict if the file has no recognized embedded JSON.
    Raises FileNotFoundError if `path` doesn't exist.
    """
    p = Path(path)
    if not p.exists():
        raise FileNotFoundError(str(p))
    ext = p.suffix.lower()
    if ext in PIL_EXTS:
        return _read_pil(p)
    if ext in VIDEO_EXTS or ext in AUDIO_EXTS:
        return _read_container(p)
    if ext in LATENT_EXTS:
        return _read_latent(p)
    return {}


def extract(path: str | os.PathLike[str]) -> dict[str, Any]:
    """Return parsed `{"prompt": <api-dict>, "workflow": <ui-dict>}`.

    Keys that fail to parse as JSON are dropped silently. Missing keys are
    simply absent from the result. Use `read_raw_metadata` for the raw strings.
    """
    raw = read_raw_metadata(path)
    out: dict[str, Any] = {}
    for k, v in raw.items():
        try:
            out[k] = json.loads(v)
        except json.JSONDecodeError:
            continue
    return out


# ---------------------------------------------------------------------------
# Summarizer — walk the API-form prompt and pull out interesting fields
# ---------------------------------------------------------------------------


@dataclasses.dataclass
class SamplerCall:
    node_id: str
    class_type: str
    sampler: str | None = None
    scheduler: str | None = None
    steps: int | float | None = None
    cfg: float | None = None
    denoise: float | None = None
    seed: int | None = None
    start_step: int | None = None
    end_step: int | None = None
    add_noise: Any = None


@dataclasses.dataclass
class LoraEntry:
    name: str
    model_strength: float | None = None
    clip_strength: float | None = None


@dataclasses.dataclass
class Summary:
    models: list[str] = dataclasses.field(default_factory=list)
    text_encoders: list[str] = dataclasses.field(default_factory=list)
    vaes: list[str] = dataclasses.field(default_factory=list)
    samplers: list[SamplerCall] = dataclasses.field(default_factory=list)
    loras: list[LoraEntry] = dataclasses.field(default_factory=list)
    width: int | None = None
    height: int | None = None
    num_frames: int | None = None
    shift: float | None = None
    positive: list[str] = dataclasses.field(default_factory=list)
    negative: list[str] = dataclasses.field(default_factory=list)
    output_filenames: list[str] = dataclasses.field(default_factory=list)
    node_count: int = 0

    @property
    def sampler(self) -> str | None:
        return self.samplers[0].sampler if self.samplers else None

    @property
    def scheduler(self) -> str | None:
        return self.samplers[0].scheduler if self.samplers else None

    @property
    def steps(self) -> int | float | None:
        return self.samplers[0].steps if self.samplers else None

    @property
    def cfg(self) -> float | None:
        return self.samplers[0].cfg if self.samplers else None

    @property
    def seed(self) -> int | None:
        return self.samplers[0].seed if self.samplers else None

    def to_dict(self) -> dict[str, Any]:
        d = dataclasses.asdict(self)
        # Add convenience top-level fields the analyst usually wants
        d["sampler"] = self.sampler
        d["scheduler"] = self.scheduler
        d["steps"] = self.steps
        d["cfg"] = self.cfg
        d["seed"] = self.seed
        return d


# class_type → keys to pull out
_MODEL_LOADERS = {
    "UNETLoader": "unet_name",
    "CheckpointLoaderSimple": "ckpt_name",
    "CheckpointLoader": "ckpt_name",
    "WanVideoModelLoader": "model",
    "UnetLoaderGGUF": "unet_name",
    "DiffusersLoader": "model_path",
    "DiffusionModelLoader": "model_name",
}

_TEXT_ENCODER_LOADERS = {
    "CLIPLoader": "clip_name",
    "DualCLIPLoader": ("clip_name1", "clip_name2"),
    "TripleCLIPLoader": ("clip_name1", "clip_name2", "clip_name3"),
    "QuadrupleCLIPLoader": ("clip_name1", "clip_name2", "clip_name3", "clip_name4"),
    "LoadWanVideoT5TextEncoder": "model_name",
    "WanVideoT5TextEncode": None,  # encode-only, not a loader
    "TextEncoderLoaderHiDream": "text_encoder",
}

_VAE_LOADERS = {
    "VAELoader": "vae_name",
    "WanVideoVAELoader": "model_name",
}

_LORA_LOADERS = {
    "LoraLoader": ("lora_name", "strength_model", "strength_clip"),
    "LoraLoaderModelOnly": ("lora_name", "strength_model", None),
    "LoraLoaderAdvanced": ("lora_name", "strength_model", "strength_clip"),
    "WanVideoLoraSelect": ("lora", "strength", None),
    "LoRALoader|pysssss": ("lora_name", "strength_model", "strength_clip"),
}

_SAMPLERS = {
    "KSampler",
    "KSamplerAdvanced",
    "SamplerCustom",
    "SamplerCustomAdvanced",
    "WanVideoSampler",
    "WanVideoSamplerv2",
    "WanVideoSamplerV2",
    "Kontext_KSampler",
}

# Helper nodes that decompose what a single KSampler bundles together.
# When the workflow uses `SamplerCustomAdvanced`, the sampler/scheduler/
# steps/cfg/seed values live in these auxiliary nodes; harvest them all
# and stitch onto the SamplerCustomAdvanced call below.
_AUX_SAMPLER_FIELDS = {
    "KSamplerSelect": {"sampler": "sampler_name"},
    "BasicScheduler": {"scheduler": "scheduler", "steps": "steps", "denoise": "denoise"},
    "AlignYourStepsScheduler": {"scheduler": "scheduler", "steps": "steps", "denoise": "denoise"},
    "SDTurboScheduler": {"steps": "steps", "denoise": "denoise"},
    "BetaSamplingScheduler": {"steps": "steps", "denoise": "denoise"},
    "RandomNoise": {"seed": "noise_seed"},
    "CFGGuider": {"cfg": "cfg"},
    "BasicGuider": {},  # no cfg widget, just signals "CFG=1 (uncond skipped)"
    "DualCFGGuider": {"cfg": "cfg_conds"},
}

_LATENT_DIM_NODES = {
    "EmptyLatentImage",
    "EmptySD3LatentImage",
    "ModelSamplingSD3",
    "EmptyMochiLatentVideo",
    "EmptyLTXVLatentVideo",
    "EmptyHunyuanLatentVideo",
    "WanVideoEmptyEmbeds",
    "WanVideoImageToVideoEncode",
    "WanVideoImageToVideoEncodev2",
    "ImageScale",
    "ImageScaleBy",
    "FluxKontextImageScale",
}

_SHIFT_NODES = {"ModelSamplingAuraFlow", "ModelSamplingSD3", "ModelSamplingFlux"}

_TEXT_ENCODE_NODES = {
    "CLIPTextEncode",
    "CLIPTextEncodeFlux",
    "CLIPTextEncodeSDXL",
    "CLIPTextEncodeSD3",
    "TextEncodeQwenImageEdit",
    "TextEncodeQwenImageEditPlus",
    "WanVideoTextEncode",
    "WanVideoTextEncodeCached",
}


def _push_unique(lst: list[str], val: Any) -> None:
    if isinstance(val, str) and val and val not in lst:
        lst.append(val)


def _coalesce(*vals: Any) -> Any:
    for v in vals:
        if v is not None:
            return v
    return None


def _scalar_or_none(v: Any) -> Any:
    """Reject ComfyUI link-form values like ['66', 1] — those are node refs.

    ComfyUI stores either a literal widget value (int/float/str) or a
    2-list `[upstream_node_id, output_slot]`. The summarizer only cares
    about literals; the linked-value case means the dim is computed
    upstream and isn't recoverable without graph traversal.
    """
    if isinstance(v, list):
        return None
    return v


def summarize(api_prompt: dict[str, Any]) -> Summary:
    """Walk the API-form prompt and pull out generation settings.

    `api_prompt` is the dict from `extract(...)["prompt"]` — i.e. the
    flat `{node_id: {inputs, class_type, _meta}}` shape that the ComfyUI
    backend executes.
    """
    s = Summary()
    if not isinstance(api_prompt, dict):
        return s
    s.node_count = len(api_prompt)

    # Index node titles for prompting-vs-not classification
    title_for: dict[str, str] = {}
    for nid, node in api_prompt.items():
        if isinstance(node, dict):
            title_for[nid] = (node.get("_meta", {}) or {}).get("title", "") or ""

    # First pass: harvest auxiliary sampler fields keyed by node_id. The
    # SamplerCustomAdvanced chain spreads sampler/scheduler/cfg/seed across
    # separate helper nodes, so collect them up front and merge below.
    aux_fields: dict[str, Any] = {}
    has_basic_guider = False
    for nid, node in api_prompt.items():
        if not isinstance(node, dict):
            continue
        cls = node.get("class_type")
        if cls in _AUX_SAMPLER_FIELDS:
            inputs = node.get("inputs", {}) or {}
            for out_key, in_key in _AUX_SAMPLER_FIELDS[cls].items():
                v = _scalar_or_none(inputs.get(in_key))
                if v is not None and out_key not in aux_fields:
                    aux_fields[out_key] = v
            if cls == "BasicGuider":
                has_basic_guider = True

    for nid, node in api_prompt.items():
        if not isinstance(node, dict):
            continue
        cls = node.get("class_type")
        inputs = node.get("inputs", {}) or {}
        if not isinstance(inputs, dict):
            continue

        if cls in _MODEL_LOADERS:
            _push_unique(s.models, inputs.get(_MODEL_LOADERS[cls]))

        if cls in _TEXT_ENCODER_LOADERS:
            keys = _TEXT_ENCODER_LOADERS[cls]
            if isinstance(keys, tuple):
                for k in keys:
                    _push_unique(s.text_encoders, inputs.get(k))
            elif isinstance(keys, str):
                _push_unique(s.text_encoders, inputs.get(keys))

        if cls in _VAE_LOADERS:
            _push_unique(s.vaes, inputs.get(_VAE_LOADERS[cls]))

        if cls in _LORA_LOADERS:
            name_key, m_key, c_key = _LORA_LOADERS[cls]
            name = inputs.get(name_key)
            if name:
                s.loras.append(
                    LoraEntry(
                        name=name,
                        model_strength=inputs.get(m_key) if m_key else None,
                        clip_strength=inputs.get(c_key) if c_key else None,
                    )
                )

        if cls in _SAMPLERS:
            g = lambda k: _scalar_or_none(inputs.get(k))  # noqa: E731
            # For SamplerCustomAdvanced the widget fields are all None on
            # the sampler node itself; merge in the harvested aux_fields.
            use_aux = cls == "SamplerCustomAdvanced"
            cfg_default = 1.0 if (use_aux and has_basic_guider and "cfg" not in aux_fields) else None
            s.samplers.append(
                SamplerCall(
                    node_id=nid,
                    class_type=cls,
                    sampler=g("sampler_name") or g("sampler") or (aux_fields.get("sampler") if use_aux else None),
                    scheduler=g("scheduler") or (aux_fields.get("scheduler") if use_aux else None),
                    steps=g("steps") or (aux_fields.get("steps") if use_aux else None),
                    cfg=g("cfg") if g("cfg") is not None else (aux_fields.get("cfg", cfg_default) if use_aux else None),
                    denoise=g("denoise") if g("denoise") is not None else (aux_fields.get("denoise") if use_aux else None),
                    seed=g("seed") or g("noise_seed") or (aux_fields.get("seed") if use_aux else None),
                    start_step=g("start_step") or g("start_at_step"),
                    end_step=g("end_step") or g("end_at_step"),
                    add_noise=g("add_noise"),
                )
            )

        if cls in _LATENT_DIM_NODES:
            s.width = _coalesce(_scalar_or_none(inputs.get("width")), s.width)
            s.height = _coalesce(_scalar_or_none(inputs.get("height")), s.height)
            s.num_frames = _coalesce(
                _scalar_or_none(inputs.get("num_frames")),
                _scalar_or_none(inputs.get("length")),
                _scalar_or_none(inputs.get("frames")),
                s.num_frames,
            )

        if cls in _SHIFT_NODES and "shift" in inputs:
            s.shift = _coalesce(_scalar_or_none(inputs.get("shift")), s.shift)

        if cls in _TEXT_ENCODE_NODES:
            title = title_for.get(nid, "").lower()
            for key in ("text", "positive_prompt", "negative_prompt", "prompt"):
                val = inputs.get(key)
                if isinstance(val, str) and val.strip():
                    if (
                        "negative" in title
                        or "negative" in key
                        or (key == "prompt" and "neg" in title)
                    ):
                        if val not in s.negative:
                            s.negative.append(val)
                    else:
                        if val not in s.positive:
                            s.positive.append(val)

        if cls in {"SaveImage", "SaveVideo", "SaveAudio", "SaveAnimatedWEBP", "SaveAnimatedPNG", "imageSaveSimple", "VHS_VideoCombine"}:
            fp = inputs.get("filename_prefix")
            if isinstance(fp, str):
                s.output_filenames.append(fp)

    return s


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def _cmd_extract(args: argparse.Namespace) -> int:
    try:
        data = extract(args.file)
    except FileNotFoundError:
        print(f"error: {args.file}: not found", file=sys.stderr)
        return 2
    if args.key:
        if args.key not in data:
            print(f"error: {args.file}: no '{args.key}' metadata", file=sys.stderr)
            return 1
        out = data[args.key]
    else:
        out = data
    json.dump(out, sys.stdout, indent=2 if args.pretty else None, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


def _cmd_summary(args: argparse.Namespace) -> int:
    try:
        data = extract(args.file)
    except FileNotFoundError:
        print(f"error: {args.file}: not found", file=sys.stderr)
        return 2
    if "prompt" not in data:
        print(f"error: {args.file}: no embedded prompt", file=sys.stderr)
        return 1
    s = summarize(data["prompt"]).to_dict()
    s["path"] = str(args.file)
    if args.pretty:
        _pretty_print_summary(s)
    else:
        json.dump(s, sys.stdout, indent=2, ensure_ascii=False, default=str)
        sys.stdout.write("\n")
    return 0


def _pretty_print_summary(s: dict[str, Any]) -> None:
    def line(label: str, value: Any) -> None:
        if value is None or value == [] or value == "":
            return
        print(f"  {label:14} {value}")

    print(s.get("path", ""))
    line("model", ", ".join(s["models"]) if s["models"] else None)
    line("text_encoders", ", ".join(s["text_encoders"]) if s["text_encoders"] else None)
    line("vae", ", ".join(s["vaes"]) if s["vaes"] else None)
    line("dims", f"{s['width']}x{s['height']}" if s["width"] and s["height"] else None)
    line("num_frames", s["num_frames"])
    line("shift", s["shift"])
    for i, sc in enumerate(s["samplers"]):
        prefix = "sampler" if i == 0 else f"sampler[{i}]"
        # Render "sampler/scheduler" but drop None halves cleanly
        algo = "/".join(x for x in (sc.get("sampler"), sc.get("scheduler")) if x) or "?"
        parts = [f"steps={sc['steps']}", f"cfg={sc['cfg']}"]
        if sc.get("denoise") is not None:
            parts.append(f"denoise={sc['denoise']}")
        parts.append(f"seed={sc['seed']}")
        line(prefix, f"{algo} {' '.join(parts)}")
    for lo in s["loras"]:
        ms = lo["model_strength"]
        cs = lo["clip_strength"]
        strs = f"m={ms}" + (f" c={cs}" if cs is not None else "")
        line("lora", f"{lo['name']} ({strs})")
    for i, p in enumerate(s["positive"]):
        line(f"pos[{i}]", (p[:120] + "...") if len(p) > 123 else p)
    for i, n in enumerate(s["negative"]):
        line(f"neg[{i}]", (n[:120] + "...") if len(n) > 123 else n)


def _iter_files(root: Path, recursive: bool) -> Iterable[Path]:
    if root.is_file():
        yield root
        return
    pattern = "**/*" if recursive else "*"
    for p in root.glob(pattern):
        if p.is_file() and p.suffix.lower() in (
            PIL_EXTS | VIDEO_EXTS | AUDIO_EXTS | LATENT_EXTS
        ):
            yield p


def _cmd_scan(args: argparse.Namespace) -> int:
    root = Path(args.dir)
    if not root.exists():
        print(f"error: {root}: not found", file=sys.stderr)
        return 2

    out_stream: Any
    if args.out and args.out != "-":
        out_stream = open(args.out, "w", encoding="utf-8")  # noqa: SIM115
    else:
        out_stream = sys.stdout

    n_ok = n_err = 0
    try:
        for p in sorted(_iter_files(root, recursive=not args.no_recursive)):
            rec: dict[str, Any] = {"path": str(p)}
            try:
                stat = p.stat()
                rec["size"] = stat.st_size
                rec["mtime"] = stat.st_mtime
                data = extract(p)
                if "prompt" not in data:
                    rec["error"] = "no metadata"
                    n_err += 1
                else:
                    rec["summary"] = summarize(data["prompt"]).to_dict()
                    n_ok += 1
            except Exception as e:
                rec["error"] = f"{type(e).__name__}: {e}"
                n_err += 1
            out_stream.write(json.dumps(rec, ensure_ascii=False, default=str) + "\n")
    finally:
        if out_stream is not sys.stdout:
            out_stream.close()

    if args.verbose:
        print(f"scan: {n_ok} indexed, {n_err} skipped/error", file=sys.stderr)
    return 0


def _cmd_diff(args: argparse.Namespace) -> int:
    def lines_for(path: str) -> list[str]:
        data = extract(path)
        if "prompt" not in data:
            return [f"# {path}: no embedded prompt"]
        s = summarize(data["prompt"]).to_dict()
        s["path"] = path
        import contextlib

        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            _pretty_print_summary(s)
        return buf.getvalue().splitlines(keepends=True)

    a_lines = lines_for(args.file_a)
    b_lines = lines_for(args.file_b)
    sys.stdout.writelines(
        difflib.unified_diff(
            a_lines, b_lines, fromfile=args.file_a, tofile=args.file_b, n=2
        )
    )
    return 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        prog="comfy_meta",
        description="Read ComfyUI workflow metadata embedded in output files.",
    )
    sub = ap.add_subparsers(dest="cmd", required=True)

    ex = sub.add_parser("extract", help="dump embedded prompt+workflow JSON")
    ex.add_argument("file")
    ex.add_argument(
        "-k",
        "--key",
        choices=("prompt", "workflow"),
        help="dump only one half (default: both)",
    )
    ex.add_argument("-p", "--pretty", action="store_true", help="indent the JSON")
    ex.set_defaults(func=_cmd_extract)

    su = sub.add_parser("summary", help="one-record summary of settings")
    su.add_argument("file")
    su.add_argument(
        "-p", "--pretty", action="store_true", help="human-readable instead of JSON"
    )
    su.set_defaults(func=_cmd_summary)

    sc = sub.add_parser("scan", help="walk a directory and emit JSONL")
    sc.add_argument("dir")
    sc.add_argument("-o", "--out", help="output file ('-' for stdout, default stdout)")
    sc.add_argument(
        "--no-recursive", action="store_true", help="only the top-level directory"
    )
    sc.add_argument("-v", "--verbose", action="store_true", help="print summary to stderr")
    sc.set_defaults(func=_cmd_scan)

    df = sub.add_parser("diff", help="diff summarized settings of two files")
    df.add_argument("file_a")
    df.add_argument("file_b")
    df.set_defaults(func=_cmd_diff)

    args = ap.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
