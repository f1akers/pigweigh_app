#!/usr/bin/env python3
"""
PigWeigh TFLite Preprocessing Diagnostic
==========================================
Loads the TFLite model, prints tensor metadata, then tests every common
preprocessing strategy and ranks them by logit spread.

A higher logit spread (max − mean) means the model is more decisive.
For 95% confidence with 95 classes you need a spread of ~7.5.

Usage
-----
    # Print model metadata only (no image needed):
    python debug_model.py

    # Full test with a pig photo (pull from device or use any pig image):
    python debug_model.py --image path/to/pig.jpg

    # adb pull from device (run separately first):
    #   adb pull /data/user/0/com.ajaparicio.pigweigh/cache/scaled_1000018364.jpg pig_test.jpg

Requirements
------------
    pip install numpy pillow tensorflow
    — or —
    pip install numpy pillow tflite-runtime
"""

import sys
import argparse
import numpy as np

# ── TFLite loader ────────────────────────────────────────────────────────────
try:
    import tensorflow as tf
    def _make_interpreter(model_path: str):
        interp = tf.lite.Interpreter(model_path=model_path)
        interp.allocate_tensors()
        return interp
    _backend = "TensorFlow"
except ImportError:
    try:
        import tflite_runtime.interpreter as tflite
        def _make_interpreter(model_path: str):
            interp = tflite.Interpreter(model_path=model_path)
            interp.allocate_tensors()
            return interp
        _backend = "tflite-runtime"
    except ImportError:
        sys.exit(
            "ERROR: Install tensorflow or tflite-runtime:\n"
            "  pip install tensorflow\n"
            "  — or —\n"
            "  pip install tflite-runtime\n"
        )

try:
    from PIL import Image
except ImportError:
    sys.exit("ERROR: Install Pillow: pip install pillow")

# ── Paths ────────────────────────────────────────────────────────────────────
MODEL_PATH  = "assets/models/pig_weight_estimation.tflite"
LABELS_PATH = "assets/labels/pig_weight_labels.txt"

# ── Helpers ──────────────────────────────────────────────────────────────────

def load_labels() -> list[str]:
    with open(LABELS_PATH) as f:
        return [line.strip() for line in f if line.strip()]


def softmax(logits: np.ndarray) -> np.ndarray:
    e = np.exp(logits - logits.max())
    return e / e.sum()


def run_inference(interp, input_data: np.ndarray) -> np.ndarray:
    in_det  = interp.get_input_details()[0]
    out_det = interp.get_output_details()[0]
    interp.set_tensor(in_det["index"], input_data)
    interp.invoke()
    return interp.get_tensor(out_det["index"])[0]


def print_section(title: str) -> None:
    print(f"\n{'═'*60}")
    print(f"  {title}")
    print('═'*60)


# ── Main ─────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description="PigWeigh TFLite preprocessing diagnostic")
    parser.add_argument("--image", default=None, help="Path to a pig image for testing")
    args = parser.parse_args()

    print(f"\nBackend : {_backend}")
    print(f"Model   : {MODEL_PATH}")

    # ── Load model ────────────────────────────────────────────────────────────
    try:
        interp = _make_interpreter(MODEL_PATH)
    except Exception as e:
        sys.exit(f"ERROR: Could not load model — {e}")

    in_det  = interp.get_input_details()[0]
    out_det = interp.get_output_details()[0]

    _, H, W, C   = in_det["shape"]
    in_dtype     = in_det["dtype"]
    in_scale, in_zp  = in_det["quantization"]
    out_scale, out_zp = out_det["quantization"]

    print_section("MODEL TENSOR DETAILS")
    print(f"  Input  shape : {in_det['shape']}   dtype: {in_dtype.__name__}")
    print(f"  Input  quant : scale={in_scale:.6f}  zero_point={in_zp}")
    print(f"  Output shape : {out_det['shape']}   dtype: {out_det['dtype'].__name__}")
    print(f"  Output quant : scale={out_scale:.6f}  zero_point={out_zp}")
    print()

    # ── Interpret quantization ────────────────────────────────────────────────
    if in_dtype == np.uint8:
        print("  ⚠  Input tensor is UINT8.")
        print("     Flutter must pass Uint8List with values in [0, 255].")
        print("     Do NOT use float32 input.")
    elif in_dtype == np.int8:
        print("  ⚠  Input tensor is INT8.")
        print(f"     Expected float range ≈ [{(-128 - in_zp) * in_scale:.3f}, "
              f"{(127 - in_zp) * in_scale:.3f}]")
    else:
        print(f"  ✓  Input tensor is float32.")
        if in_scale != 0.0:
            # Quantization params set → model has no internal preprocessing
            print(f"     Quantization scale suggests input range ≈ "
                  f"[{(0   - in_zp) * in_scale:.3f}, "
                  f"{(255 - in_zp) * in_scale:.3f}]")
        else:
            print("     No quantization params (scale=0) — preprocessing may be baked in,")
            print("     or the model expects raw [0, 255] float32.")

    # ── Load labels ───────────────────────────────────────────────────────────
    try:
        labels = load_labels()
        print(f"\n  Labels: {len(labels)} classes  ({labels[0]} … {labels[-1]})")
    except FileNotFoundError:
        labels = [str(i) for i in range(out_det["shape"][1])]
        print(f"\n  Labels file not found — using numeric indices.")

    # ── No image: stop here ────────────────────────────────────────────────────
    if args.image is None:
        print_section("HOW TO RUN THE FULL TEST")
        print("  Provide a pig image:")
        print("    python debug_model.py --image path/to/pig.jpg")
        print()
        print("  Pull test image from Android device:")
        print("    adb pull /data/user/0/com.ajaparicio.pigweigh/cache/scaled_1000018364.jpg pig_test.jpg")
        print("    python debug_model.py --image pig_test.jpg")
        return

    # ── Load image ────────────────────────────────────────────────────────────
    print_section(f"IMAGE: {args.image}")
    try:
        img = Image.open(args.image).convert("RGB")
    except Exception as e:
        sys.exit(f"ERROR: Could not load image — {e}")

    img_resized = img.resize((W, H), Image.BILINEAR)
    base = np.array(img_resized, dtype=np.float32)          # [H,W,3] float32 [0,255]
    print(f"  Original size : {img.size}")
    print(f"  Resized to    : {img_resized.size}")
    print(f"  Pixel [0,0]   : R={base[0,0,0]:.1f}  G={base[0,0,1]:.1f}  B={base[0,0,2]:.1f}")
    print(f"  Tensor stats  : min={base.min():.1f}  max={base.max():.1f}  mean={base.mean():.2f}")

    # ImageNet channel means and stds (RGB)
    IN_MEAN = np.array([123.68, 116.779, 103.939], dtype=np.float32)
    IN_STD  = np.array([ 58.393,  57.12,   57.375], dtype=np.float32)

    # ── Resize strategies ──────────────────────────────────────────────────
    # base was already stretch-resized above (the naive approach).
    # Now produce alternate spatial layouts from the ORIGINAL image.

    orig_w, orig_h = img.size  # PIL: (width, height)

    def center_crop_resize(pil_img, size: int) -> np.ndarray:
        """Crop the largest centre square, then resize to size×size."""
        w, h = pil_img.size
        s = min(w, h)
        left = (w - s) // 2
        top  = (h - s) // 2
        cropped = pil_img.crop((left, top, left + s, top + s))
        resized  = cropped.resize((size, size), Image.BILINEAR)
        return np.array(resized, dtype=np.float32)

    def letterbox_resize(pil_img, size: int, fill: int = 128) -> np.ndarray:
        """Resize maintaining aspect ratio, pad remainder with fill value."""
        w, h = pil_img.size
        scale = size / max(w, h)
        new_w, new_h = int(w * scale), int(h * scale)
        resized = pil_img.resize((new_w, new_h), Image.BILINEAR)
        canvas = Image.new("RGB", (size, size), (fill, fill, fill))
        paste_x = (size - new_w) // 2
        paste_y = (size - new_h) // 2
        canvas.paste(resized, (paste_x, paste_y))
        return np.array(canvas, dtype=np.float32)

    def short_side_resize_center_crop(pil_img, size: int) -> np.ndarray:
        """Resize so the SHORT side = size, then center-crop to size×size.
        This is the standard Keras/TF ImageNet preprocessing pipeline."""
        w, h = pil_img.size
        if w < h:
            new_w, new_h = size, int(h * size / w)
        else:
            new_w, new_h = int(w * size / h), size
        resized = pil_img.resize((new_w, new_h), Image.BILINEAR)
        left = (new_w - size) // 2
        top  = (new_h - size) // 2
        cropped = resized.crop((left, top, left + size, top + size))
        return np.array(cropped, dtype=np.float32)

    base_cc  = center_crop_resize(img, W)           # centre-crop square
    base_lb  = letterbox_resize(img, W)              # letterbox (grey pad)
    base_ss  = short_side_resize_center_crop(img, W) # short-side → centre crop
    base_bgr = base[:, :, ::-1].copy()               # swap R↔B channels

    print(f"  Resize strategies prepared:")
    print(f"    stretch     : {img.size} → {W}x{H} (base)")
    print(f"    center-crop : {orig_w}x{orig_h} → {W}x{H} via {min(orig_w,orig_h)}px square")
    print(f"    letterbox   : {orig_w}x{orig_h} → {W}x{H} with grey pad")
    print(f"    short-side  : {orig_w}x{orig_h} → {W}x{H} (Keras ImageNet style)")

    # Each resize strategy × each normalization
    def variants(arr: np.ndarray, label: str) -> list[tuple[str, np.ndarray]]:
        return [
            (f"{label} | raw [0,255]",          arr.copy()),
            (f"{label} | ÷127.5−1  [-1,1]",     arr / 127.5 - 1.0),
            (f"{label} | ÷255      [0,1]",       arr / 255.0),
            (f"{label} | ImageNet mean-std",     (arr - IN_MEAN) / IN_STD),
        ]

    strategies: list[tuple[str, np.ndarray]] = (
        variants(base,     "stretch    ")
        + variants(base_cc,  "center-crop")
        + variants(base_lb,  "letterbox  ")
        + variants(base_ss,  "short-side ")
        + variants(base_bgr, "stretch BGR")   # channel-swap sanity check
    )

    print_section("PREPROCESSING COMPARISON")
    best_spread   = -999.0
    best_name     = ""
    best_label    = ""
    best_conf     = 0.0
    results       = []

    for name, norm in strategies:
        batch = norm[np.newaxis].astype(in_dtype)          # [1,H,W,3]
        try:
            raw = run_inference(interp, batch)
        except Exception as e:
            print(f"\n  [{name}]\n    ERROR: {e}")
            continue

        # Detect whether output is already probabilities
        already_prob = abs(raw.sum() - 1.0) < 0.01
        probs = raw if already_prob else softmax(raw)

        spread   = float(raw.max() - raw.mean())
        top_idx  = int(np.argmax(probs))
        top_lbl  = labels[top_idx] if top_idx < len(labels) else f"idx_{top_idx}"
        top_conf = float(probs[top_idx]) * 100.0

        # Top-3
        top3 = np.argsort(probs)[-3:][::-1]

        results.append((spread, name, top_lbl, top_conf, raw, probs, top3))

        if spread > best_spread:
            best_spread = spread
            best_name   = name
            best_label  = top_lbl
            best_conf   = top_conf

    # Print sorted by spread descending
    results.sort(key=lambda r: r[0], reverse=True)
    for rank, (spread, name, top_lbl, top_conf, raw, probs, top3) in enumerate(results):
        marker = " ◀ BEST" if rank == 0 else ""
        print(f"\n  [{rank+1}] {name}{marker}")
        print(f"       raw  : max={raw.max():.4f}  min={raw.min():.4f}  "
              f"sum={raw.sum():.4f}  mean={raw.mean():.4f}")
        print(f"       spread (max−mean) : {spread:.4f}  "
              f"{'▓'*min(int(spread*4), 40)}")
        print(f"       → {top_lbl} @ {top_conf:.1f}%")
        for i, idx in enumerate(top3):
            lbl = labels[idx] if idx < len(labels) else f"idx_{idx}"
            print(f"         #{i+1}: {lbl} ({probs[idx]*100:.2f}%)")

    # ── Recommendation ────────────────────────────────────────────────────────
    print_section("RECOMMENDATION")
    print(f"  Best preprocessing : {best_name}")
    print(f"  Best prediction    : {best_label} @ {best_conf:.1f}%")
    print(f"  Logit spread       : {best_spread:.4f}")
    print()

    if best_spread < 2.0:
        print("  ⚠  WARNING: Even the best strategy gives spread < 2.0.")
        print("     This usually means one of:")
        print("     (a) The model input tensor dtype is wrong (uint8 vs float32).")
        print("     (b) The model expects a different input size than what we resized to.")
        print("     (c) The model has a preprocessing layer that processes the input differently.")
        print(f"\n     Input dtype used: {in_dtype.__name__}  (model expects: {in_det['dtype'].__name__})")
    elif best_spread >= 5.0:
        print(f"  ✓  Spread ≥ 5.0 — use '{best_name}'")
    else:
        print(f"  △  Spread {best_spread:.2f} is mediocre (need ~7.5 for 95% confidence).")
        print("     Try a different resize/crop strategy (center crop vs stretch).")

    print()
    print("  → Update _preprocessImage in weight_estimation_service.dart accordingly.")


if __name__ == "__main__":
    main()
