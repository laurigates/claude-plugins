#!/usr/bin/env python3
"""Generate a 21:9 banner BACKGROUND via the local ComfyUI Flux2 Klein API.

Background only — composite the crisp icon + wordmark on top afterwards with
registry_banner_compose.py. So the prompt aims for clean, dark, on-brand
abstract texture with negative space and NO text/symbols (diffusion can't be
trusted to spell, and the icon/wordmark are added sharply in the compose step).

Flux2 Klein topology mirrors tooling/.claude/rules/flux2-klein.md (distilled:
UNETLoader + CLIPLoader type=flux2 + Qwen3-8B encoder + Flux2 VAE +
EmptyFlux2LatentImage + FluxGuidance=4 + KSampler euler/simple 4 steps cfg=1 +
ConditioningZeroOut negative).

Run under the ComfyUI venv (stdlib only, but keeps things uniform):
  ComfyUI/.venv/bin/python tooling/scripts/registry_banner_bg.py \
    --accent "warm amber and orange" --seed 101 --out bg.png

See also: tooling/.claude/rules/comfy-registry-icons-banners.md
"""
import argparse, json, time, urllib.request, urllib.parse, sys

DEF_PROMPT = (
    "Abstract dark user-interface background wallpaper, deep charcoal near-black base, "
    "soft {accent} glow with gentle light streaks and faint bokeh, subtle geometric tech "
    "grid fading into shadow, smooth premium gradient, minimal and clean, generous empty "
    "negative space, cinematic soft studio lighting, high-end software branding backdrop. "
    "No text, no words, no letters, no logo, no symbols, no UI elements, no people."
)


def build_graph(text, seed, w, h, model):
    return {
        "unet": {"class_type": "UNETLoader", "inputs": {"unet_name": model, "weight_dtype": "default"}},
        "clip": {"class_type": "CLIPLoader", "inputs": {"clip_name": "qwen_3_8b_fp8mixed.safetensors", "type": "flux2"}},
        "vae":  {"class_type": "VAELoader", "inputs": {"vae_name": "Flux2/flux2-vae.safetensors"}},
        "pos":  {"class_type": "CLIPTextEncode", "inputs": {"clip": ["clip", 0], "text": text}},
        "zero": {"class_type": "ConditioningZeroOut", "inputs": {"conditioning": ["pos", 0]}},
        "guid": {"class_type": "FluxGuidance", "inputs": {"conditioning": ["pos", 0], "guidance": 4.0}},
        "lat":  {"class_type": "EmptyFlux2LatentImage", "inputs": {"width": w, "height": h, "batch_size": 1}},
        "ks":   {"class_type": "KSampler", "inputs": {"model": ["unet", 0], "positive": ["guid", 0],
                  "negative": ["zero", 0], "latent_image": ["lat", 0], "seed": seed, "steps": 4,
                  "cfg": 1.0, "sampler_name": "euler", "scheduler": "simple", "denoise": 1.0}},
        "dec":  {"class_type": "VAEDecode", "inputs": {"samples": ["ks", 0], "vae": ["vae", 0]}},
        "save": {"class_type": "SaveImage", "inputs": {"images": ["dec", 0], "filename_prefix": "registry_banner"}},
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out", required=True, help="output PNG path")
    ap.add_argument("--accent", default="cool blue and azure",
                    help='accent phrase, e.g. "warm amber and orange" / "cool blue and azure"')
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--width", type=int, default=1344, help="must be /16; 1344x576 = exact 21:9")
    ap.add_argument("--height", type=int, default=576)
    ap.add_argument("--prompt", default=None, help="override the default background prompt")
    ap.add_argument("--model", default="Flux2/flux-2-klein-9b-fp8.safetensors")
    ap.add_argument("--host", default="http://127.0.0.1:8188")
    a = ap.parse_args()

    text = a.prompt or DEF_PROMPT.format(accent=a.accent)
    graph = build_graph(text, a.seed, a.width, a.height, a.model)

    data = json.dumps({"prompt": graph}).encode()
    req = urllib.request.Request(f"{a.host}/prompt", data=data, headers={"Content-Type": "application/json"})
    pid = json.loads(urllib.request.urlopen(req, timeout=60).read())["prompt_id"]
    print(f"submitted {pid} ({a.width}x{a.height} seed={a.seed})", flush=True)

    t0 = time.time()
    while time.time() - t0 < 300:
        h = json.loads(urllib.request.urlopen(f"{a.host}/history/{pid}", timeout=30).read())
        if pid in h:
            img = h[pid]["outputs"]["save"]["images"][0]
            q = urllib.parse.urlencode({"filename": img["filename"], "subfolder": img.get("subfolder", ""), "type": img.get("type", "output")})
            open(a.out, "wb").write(urllib.request.urlopen(f"{a.host}/view?{q}", timeout=60).read())
            print(f"-> {a.out}")
            return
        time.sleep(2)
    sys.exit("timed out waiting for ComfyUI")


if __name__ == "__main__":
    main()
