#!/usr/bin/env python3
"""
Generic Image Generator using Google Nano Banana Pro (Gemini 3 Pro Image).

This is a reusable module for image generation that can be used in any context.
Domain-specific logic (like D&D character lookup) should be handled by the caller.

Usage as module:
    from nano_banana_pro import generate_image, create_client

    client = create_client()
    result = generate_image(
        client=client,
        prompt="A beautiful sunset over mountains",
        output_path=Path("output.png"),
        enhance_prompt=lambda p: f"Photorealistic: {p}",  # Optional callback
    )

Usage as script:
    python nano_banana_pro.py "A beautiful sunset" --aspect 16:9 --resolution 2K
    python nano_banana_pro.py "Portrait photo" --reference image.png --aspect 3:4

Environment:
    GOOGLE_API_KEY or GEMINI_API_KEY must be set

Model:
    Nano Banana Pro (gemini-3-pro-image-preview)
"""

from __future__ import annotations

import argparse
import os
import sys
from collections.abc import Callable
from datetime import datetime
from io import BytesIO
from pathlib import Path

try:
    from google import genai
    from google.genai import types
except ImportError:
    print("Error: google-genai library not installed.")
    print("Install with: pip install google-genai")
    sys.exit(1)

try:
    from PIL import Image
except ImportError:
    print("Error: Pillow library not installed.")
    print("Install with: pip install Pillow")
    sys.exit(1)


# Supported aspect ratios and resolutions
ASPECT_RATIOS = ["1:1", "2:3", "3:2", "3:4", "4:3", "4:5", "5:4", "9:16", "16:9", "21:9"]
RESOLUTIONS = ["1K", "2K", "4K"]
DEFAULT_ASPECT = "16:9"
DEFAULT_RESOLUTION = "2K"
MAX_REFERENCE_IMAGES = 5


def get_api_key() -> str:
    """Get API key from environment variables.

    Returns:
        The API key string.

    Raises:
        SystemExit: If no API key is found in environment.
    """
    key = os.environ.get("GOOGLE_API_KEY") or os.environ.get("GEMINI_API_KEY")
    if not key:
        print("Error: GOOGLE_API_KEY or GEMINI_API_KEY environment variable not set.")
        print("Get your API key from: https://aistudio.google.com/apikey")
        sys.exit(1)
    return key


def create_client(api_key: str | None = None) -> genai.Client:
    """Create a Google GenAI client.

    Args:
        api_key: Optional API key. If not provided, reads from environment.

    Returns:
        Configured genai.Client instance.
    """
    key = api_key or get_api_key()
    return genai.Client(api_key=key)


def load_reference_images(image_paths: list[Path]) -> list[Image.Image]:
    """Load reference images from paths.

    Args:
        image_paths: List of paths to image files.

    Returns:
        List of PIL Image objects.
    """
    images = []
    for path in image_paths:
        if not path.exists():
            print(f"Warning: Reference image not found: {path}")
            continue
        try:
            img = Image.open(path)
            images.append(img)
            print(f"Loaded reference image: {path.name}")
        except Exception as e:
            print(f"Warning: Could not load reference image {path}: {e}")
    return images


def generate_output_path(
    output_dir: Path,
    prefix: str = "image",
) -> Path:
    """Generate a timestamped output path.

    Args:
        output_dir: Directory to save images.
        prefix: Filename prefix.

    Returns:
        Path with timestamp-based filename.
    """
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    return output_dir / f"{prefix}_{timestamp}.png"


def generate_image(
    client: genai.Client,
    prompt: str,
    output_path: Path,
    enhance_prompt: Callable[[str], str] | None = None,
    aspect_ratio: str = DEFAULT_ASPECT,
    resolution: str = DEFAULT_RESOLUTION,
    reference_images: list[Path] | None = None,
) -> Path | None:
    """Generate image using Nano Banana Pro (Gemini 3 Pro Image).

    Args:
        client: Google GenAI client.
        prompt: Image description.
        output_path: Where to save the generated image.
        enhance_prompt: Optional callback to enhance/modify the prompt before generation.
                       Receives the original prompt and should return the enhanced version.
        aspect_ratio: Image aspect ratio (1:1, 2:3, 3:2, 3:4, 4:3, 4:5, 5:4, 9:16, 16:9, 21:9).
        resolution: Image resolution (1K, 2K, 4K).
        reference_images: Optional list of reference image paths.

    Returns:
        Path to saved image, or None on failure.

    Example:
        # Basic usage
        result = generate_image(client, "A sunset", output_path)

        # With prompt enhancement callback
        def fantasy_enhance(p: str) -> str:
            return f"Fantasy illustration: {p}. Epic, dramatic lighting."

        result = generate_image(
            client,
            "A wizard casting a spell",
            output_path,
            enhance_prompt=fantasy_enhance,
        )
    """
    # Validate aspect ratio
    if aspect_ratio not in ASPECT_RATIOS:
        print(f"Warning: Invalid aspect ratio '{aspect_ratio}', using {DEFAULT_ASPECT}")
        aspect_ratio = DEFAULT_ASPECT

    # Validate resolution
    if resolution not in RESOLUTIONS:
        print(f"Warning: Invalid resolution '{resolution}', using {DEFAULT_RESOLUTION}")
        resolution = DEFAULT_RESOLUTION

    # Apply prompt enhancement if callback provided
    final_prompt = enhance_prompt(prompt) if enhance_prompt else prompt

    # Build contents with prompt and optional reference images
    contents: list = [final_prompt]

    if reference_images:
        loaded_images = load_reference_images(reference_images[:MAX_REFERENCE_IMAGES])
        if loaded_images:
            print(f"Using {len(loaded_images)} reference image(s)")
            contents.extend(loaded_images)

    try:
        config = types.GenerateContentConfig(
            response_modalities=["TEXT", "IMAGE"],
            image_config=types.ImageConfig(
                aspect_ratio=aspect_ratio,
                image_size=resolution,
            ),
        )

        response = client.models.generate_content(
            model="gemini-3-pro-image-preview",
            contents=contents,
            config=config,
        )

        # Extract and save image from response
        for part in response.candidates[0].content.parts:
            if part.inline_data:
                image = Image.open(BytesIO(part.inline_data.data))
                output_path.parent.mkdir(parents=True, exist_ok=True)
                image.save(output_path)
                print(f"Image saved to: {output_path}")
                return output_path
            elif hasattr(part, "text") and part.text:
                print(f"Model response: {part.text}")

        print("No image was generated in the response.")
        return None

    except Exception as e:
        print(f"Error generating image: {e}")
        return None


def main() -> None:
    """CLI entry point for generic image generation."""
    parser = argparse.ArgumentParser(
        description="Generate images using Google Nano Banana Pro (Gemini 3 Pro Image)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s "A beautiful mountain landscape at sunset"
  %(prog)s --prompt "Portrait of a person" --aspect 3:4 --resolution 4K
  %(prog)s "Product photo" --reference existing_product.png
  %(prog)s "Cinematic scene" --aspect 21:9 --output scene.png
        """,
    )

    parser.add_argument(
        "prompt_positional",
        nargs="?",
        help="Image description (can also use --prompt)",
    )
    parser.add_argument(
        "--prompt",
        "-p",
        help="Image description",
    )
    parser.add_argument(
        "--output",
        "-o",
        type=Path,
        help="Output file path (default: auto-generated with timestamp)",
    )
    parser.add_argument(
        "--aspect",
        "-a",
        choices=ASPECT_RATIOS,
        default=DEFAULT_ASPECT,
        help=f"Aspect ratio (default: {DEFAULT_ASPECT})",
    )
    parser.add_argument(
        "--resolution",
        "-r",
        choices=RESOLUTIONS,
        default=DEFAULT_RESOLUTION,
        help=f"Image resolution (default: {DEFAULT_RESOLUTION})",
    )
    parser.add_argument(
        "--reference",
        type=Path,
        action="append",
        help=f"Reference image path (repeatable, max {MAX_REFERENCE_IMAGES})",
    )

    args = parser.parse_args()

    # Get prompt from either positional or named argument
    prompt = args.prompt_positional or args.prompt
    if not prompt:
        parser.error("A prompt is required. Use positional argument or --prompt")

    # Determine output path
    if args.output:
        output_path = args.output
        if not output_path.suffix:
            output_path = output_path.with_suffix(".png")
    else:
        # Default to current directory with generated subdirectory
        output_dir = Path.cwd() / "generated"
        output_dir.mkdir(parents=True, exist_ok=True)
        output_path = generate_output_path(output_dir)

    # Collect reference images
    reference_images = args.reference or []
    if len(reference_images) > MAX_REFERENCE_IMAGES:
        print(f"Warning: Using only first {MAX_REFERENCE_IMAGES} reference images")
        reference_images = reference_images[:MAX_REFERENCE_IMAGES]

    # Initialize client
    client = create_client()

    print("Generating image with Nano Banana Pro (Gemini 3 Pro Image)...")
    print(f"Prompt: {prompt}")
    print(f"Aspect ratio: {args.aspect}")
    print(f"Resolution: {args.resolution}")

    # Generate image (no enhancement callback in generic mode)
    result = generate_image(
        client,
        prompt,
        output_path,
        aspect_ratio=args.aspect,
        resolution=args.resolution,
        reference_images=reference_images if reference_images else None,
    )

    if result:
        print(f"\nSuccess! Image saved to: {result}")


if __name__ == "__main__":
    main()
