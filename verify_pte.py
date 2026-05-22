#!/usr/bin/env python3
"""
PigWeigh ExecuTorch Verification Script
========================================
Loads the exported .pte model, prints tensor metadata, runs inference
on a test image, and verifies the output format.

Usage
-----
    # Print model metadata only (no image needed):
    python verify_pte.py

    # Full test with a pig photo:
    python verify_pte.py --image path/to/pig.jpg

Requirements
------------
    pip install executorch numpy pillow
"""

import sys
import argparse
import math
import numpy as np

try:
    from PIL import Image
except ImportError:
    sys.exit("ERROR: Install Pillow: pip install pillow")

# ── Paths ──────────────────────────────────────────────────────────────────
MODEL_PATH = "assets/models/pig_weight_estimation.pte"
LABELS_PATH = "assets/labels/pig_weight_labels.txt"

# ── ExecuTorch loader ──────────────────────────────────────────────────────
try:
    import torch
    from executorch.extension.module import Module

    def load_model(path: str):
        return Module(path)

    def run_inference(module, input_tensor: torch.Tensor):
        return module.forward([input_tensor])

    _backend = "ExecuTorch (Module)"
except ImportError:
    sys.exit(
        "ERROR: ExecuTorch Python bindings not found.\n"
        "  pip install executorch\n"
        "  (You may need to build from source on some platforms.)"
    )

# ── Helpers ──────────────────────────────────────────────────────────────────


def load_labels() -> list[str]:
    with open(LABELS_PATH) as f:
        return [line.strip() for line in f if line.strip()]


def sigmoid(x: np.ndarray) -> np.ndarray:
    return 1.0 / (1.0 + np.exp(-x))


def softmax(logits: np.ndarray) -> np.ndarray:
    e = np.exp(logits - logits.max())
    return e / e.sum()


def print_section(title: str) -> None:
    print(f"\n{'═' * 60}")
    print(f"  {title}")
    print("═" * 60)


def letterbox_resize(pil_img: Image.Image, size: int, fill: int = 114) -> Image.Image:
    """Resize maintaining aspect ratio, pad remainder with fill value."""
    w, h = pil_img.size
    scale = size / max(w, h)
    new_w, new_h = int(w * scale), int(h * scale)
    resized = pil_img.resize((new_w, new_h), Image.BILINEAR)
    canvas = Image.new("RGB", (size, size), (fill, fill, fill))
    paste_x = (size - new_w) // 2
    paste_y = (size - new_h) // 2
    canvas.paste(resized, (paste_x, paste_y))
    return canvas


# ── Main ───────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description="PigWeigh ExecuTorch model verification"
    )
    parser.add_argument("--image", default=None, help="Path to a pig image for testing")
    args = parser.parse_args()

    print(f"\nBackend : {_backend}")
    print(f"Model   : {MODEL_PATH}")

    # ── Load model ──────────────────────────────────────────────────────────
    try:
        module = load_model(MODEL_PATH)
    except Exception as e:
        sys.exit(f"ERROR: Could not load model — {e}")

    print_section("MODEL LOADED SUCCESSFULLY")

    # Try to inspect input/output shapes via dummy inference
    print("\n  Probing tensor shapes with dummy input...")
    dummy = torch.zeros(1, 3, 640, 640)
    try:
        dummy_output = run_inference(module, dummy)
    except Exception as e:
        sys.exit(f"ERROR: Dummy inference failed — {e}")

    print(f"  Input  shape : {list(dummy.shape)}")
    if isinstance(dummy_output, (list, tuple)):
        for i, out in enumerate(dummy_output):
            print(f"  Output[{i}] shape : {list(out.shape)}")
            print(f"  Output[{i}] dtype  : {out.dtype}")
            print(f"  Output[{i}] stats  : min={out.min():.4f} max={out.max():.4f}")
            out_np = out.detach().cpu().numpy()
            print(f"  Output[{i}] sample : {out_np.flatten()[:10]}")
    else:
        print(f"  Output shape : {list(dummy_output.shape)}")
        print(f"  Output dtype  : {dummy_output.dtype}")

    # ── Load labels ───────────────────────────────────────────────────────
    try:
        labels = load_labels()
        print(f"\n  Labels: {len(labels)} classes  ({labels[0]} … {labels[-1]})")
    except FileNotFoundError:
        labels = []
        print(f"\n  Labels file not found.")

    # ── No image: stop here ────────────────────────────────────────────────
    if args.image is None:
        print_section("HOW TO RUN THE FULL TEST")
        print("  Provide a pig image:")
        print("    python verify_pte.py --image path/to/pig.jpg")
        print()
        print("  Expected input: NCHW float32 [0, 640, 640] (channels-first)")
        print("  Expected output: YOLOv8 raw detections [1, 38, 8400]")
        return

    # ── Load image ──────────────────────────────────────────────────────────
    print_section(f"IMAGE: {args.image}")
    try:
        img = Image.open(args.image).convert("RGB")
    except Exception as e:
        sys.exit(f"ERROR: Could not load image — {e}")

    img_lb = letterbox_resize(img, 640)
    arr = np.array(img_lb, dtype=np.float32)  # [H, W, 3] uint8 → float32 [0,255]

    print(f"  Original size : {img.size}")
    print(f"  Letterbox to  : 640x640")
    print(f"  Pixel [0,0]   : R={arr[0, 0, 0]:.1f}  G={arr[0, 0, 1]:.1f}  B={arr[0, 0, 2]:.1f}")
    print(f"  Tensor stats  : min={arr.min():.1f}  max={arr.max():.1f}  mean={arr.mean():.2f}")

    # Convert HWC → NCHW
    # arr is [H, W, 3]; we need [1, 3, H, W]
    nchw = np.transpose(arr, (2, 0, 1))[np.newaxis, ...]  # [1, 3, H, W]
    tensor = torch.from_numpy(nchw.copy())

    print(f"  Input tensor  : {list(tensor.shape)}  dtype={tensor.dtype}")

    # ── Run inference ───────────────────────────────────────────────────────
    print_section("INFERENCE")
    try:
        output = run_inference(module, tensor)
    except Exception as e:
        sys.exit(f"ERROR: Inference failed — {e}")

    if isinstance(output, (list, tuple)):
        out_tensor = output[0]
    else:
        out_tensor = output

    out_np = out_tensor.detach().cpu().numpy()
    print(f"  Output shape : {out_np.shape}")
    print(f"  Output stats : min={out_np.min():.4f} max={out_np.max():.4f} mean={out_np.mean():.4f}")

    # ── Parse YOLOv8 raw output ──────────────────────────────────────────────
    # Expected shape: [1, 38, 8400]  →  4 bbox + 34 classes (or similar)
    if out_np.ndim != 3 or out_np.shape[0] != 1:
        print(f"  ⚠  Unexpected output dimensions: {out_np.ndim}D shape {out_np.shape}")
        return

    num_channels = out_np.shape[1]
    num_anchors = out_np.shape[2]
    num_classes = num_channels - 4

    print(f"  Anchors      : {num_anchors}")
    print(f"  Channels     : {num_channels} (4 bbox + {num_classes} classes)")

    # Transpose to [1, 8400, 38] for per-anchor processing
    per_anchor = np.transpose(out_np, (0, 2, 1))[0]  # [8400, 38]

    conf_threshold = 0.25
    per_class_max = np.zeros(num_classes, dtype=np.float32)

    for a in range(num_anchors):
        anchor = per_anchor[a]
        # bbox = anchor[0:4]  # not needed for classification
        class_logits = anchor[4:]
        class_probs = sigmoid(class_logits)

        max_prob = float(class_probs.max())
        max_idx = int(class_probs.argmax())

        if max_prob > conf_threshold and max_idx < len(per_class_max):
            if max_prob > per_class_max[max_idx]:
                per_class_max[max_idx] = max_prob

    has_detections = per_class_max.max() > 0
    if not has_detections:
        print("  ⚠  No detections above threshold — returning uniform")
        probs = np.ones(num_classes) / num_classes
    else:
        probs = softmax(per_class_max)

    # ── Show top predictions ────────────────────────────────────────────────
    top3 = np.argsort(probs)[-3:][::-1]
    print("\n  Top predictions:")
    for rank, idx in enumerate(top3):
        lbl = labels[idx] if idx < len(labels) else f"idx_{idx}"
        print(f"    #{rank + 1}: {lbl} ({probs[idx] * 100:.2f}%)")

    # ── Recommendation ─────────────────────────────────────────────────────
    print_section("VERIFICATION SUMMARY")
    print(f"  ✓  Model loads successfully")
    print(f"  ✓  Input shape  : {list(tensor.shape)} (NCHW)")
    print(f"  ✓  Output shape  : {list(out_np.shape)} (raw YOLO)")
    print(f"  ✓  Top class    : {labels[top3[0]] if top3[0] < len(labels) else 'N/A'}")
    print()
    print("  If the top prediction matches your expected weight class,")
    print("  the ExecuTorch model is ready for Flutter integration.")


if __name__ == "__main__":
    main()
