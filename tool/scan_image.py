#!/usr/bin/env python3
"""Desktop smoke-test: run Catdex TFLite models on a still image."""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

try:
    from ai_edge_litert.interpreter import Interpreter
except ImportError:
    from tensorflow.lite.python.interpreter import Interpreter  # type: ignore

ROOT = Path(__file__).resolve().parents[1]
MODELS = ROOT / "assets" / "models"
BREEDS = ROOT / "assets" / "data" / "breeds.json"


def letterbox_uint8(img: Image.Image, size: int) -> np.ndarray:
    img = img.convert("RGB")
    w, h = img.size
    scale = size / max(w, h)
    nw, nh = max(1, int(w * scale)), max(1, int(h * scale))
    resized = img.resize((nw, nh), Image.BILINEAR)
    canvas = Image.new("RGB", (size, size), (128, 128, 128))
    canvas.paste(resized, ((size - nw) // 2, (size - nh) // 2))
    return np.asarray(canvas, dtype=np.uint8)


def blur_score(img: Image.Image) -> float:
    gray = np.asarray(img.convert("L"), dtype=np.float64)
    if gray.shape[0] < 3 or gray.shape[1] < 3:
        return 0.0
    lap = (
        gray[1:-1, :-2]
        + gray[1:-1, 2:]
        + gray[:-2, 1:-1]
        + gray[2:, 1:-1]
        - 4 * gray[1:-1, 1:-1]
    )
    return float(lap.var())


def embed(crop: Image.Image) -> np.ndarray:
    """Match Dart IdentityEmbedder (8x8 opponent grid, L2-normalized)."""
    resized = crop.convert("RGB").resize((64, 64), Image.BILINEAR)
    arr = np.asarray(resized, dtype=np.float64)
    grid = 8
    cell = 64 // grid
    out = []
    for gy in range(grid):
        for gx in range(grid):
            patch = arr[gy * cell : (gy + 1) * cell, gx * cell : (gx + 1) * cell]
            mr, mg, mb = patch.mean(axis=(0, 1))
            out.append(((mr - mg) / 255.0))
            out.append(((mb - mg) / 255.0))
    v = np.asarray(out, dtype=np.float32)
    # edge energy modulation
    lum = arr.mean(axis=2)
    edge = (
        np.abs(lum[1:-1:2, 1:-1:2] - lum[1:-1:2, 2::2]).mean()
        + np.abs(lum[1:-1:2, 1:-1:2] - lum[2::2, 1:-1:2]).mean()
    ) / 255.0
    edge = float(np.clip(edge, 0, 1))
    v = v * (0.85 + 0.15 * edge)
    n = np.linalg.norm(v)
    if n > 1e-8:
        v = v / n
    return v


def run_detector(img: Image.Image):
    interp = Interpreter(model_path=str(MODELS / "detect.tflite"))
    interp.allocate_tensors()
    inp = interp.get_input_details()[0]
    out = interp.get_output_details()
    size = inp["shape"][1]
    data = letterbox_uint8(img, size)
    interp.set_tensor(inp["index"], np.expand_dims(data, 0))
    interp.invoke()

    locs = interp.get_tensor(out[0]["index"])[0]
    classes = interp.get_tensor(out[1]["index"])[0]
    scores = interp.get_tensor(out[2]["index"])[0]
    count = int(interp.get_tensor(out[3]["index"])[0])

    labels = (MODELS / "detect_labelmap.txt").read_text().strip().splitlines()
    candidates = []
    for i in range(min(count, len(scores))):
        score = float(scores[i])
        if score < 0.35:
            continue
        cls = int(classes[i])
        label = labels[cls] if 0 <= cls < len(labels) else "?"
        ymin, xmin, ymax, xmax = [float(x) for x in locs[i]]
        # Clamp; SSD sometimes slightly OOB
        xmin, ymin = max(0.0, xmin), max(0.0, ymin)
        xmax, ymax = min(1.0, xmax), min(1.0, ymax)
        area = max(0.0, xmax - xmin) * max(0.0, ymax - ymin)
        candidates.append(
            {
                "label": label,
                "score": score,
                "box": (xmin, ymin, xmax, ymax),
                "area": area,
                "is_cat": "cat" in label.lower(),
            }
        )

    # Prefer explicit cat labels; else keep high-scoring boxes for breed verify
    cats = [c for c in candidates if c["is_cat"]]
    if cats:
        return max(cats, key=lambda c: c["score"]), None
    if candidates:
        return max(candidates, key=lambda c: c["score"] * c["area"]), None
    return None, None


def crop_box(img: Image.Image, box, pad=0.05) -> Image.Image:
    w, h = img.size
    xmin, ymin, xmax, ymax = box
    l = max(0, int((xmin - pad) * w))
    t = max(0, int((ymin - pad) * h))
    r = min(w, int((xmax + pad) * w))
    b = min(h, int((ymax + pad) * h))
    return img.crop((l, t, r, b))


def run_breed(crop: Image.Image):
    interp = Interpreter(model_path=str(MODELS / "mobilenet_quant.tflite"))
    interp.allocate_tensors()
    inp = interp.get_input_details()[0]
    out = interp.get_output_details()[0]
    size = inp["shape"][1]
    # Direct resize works better than letterbox for this MobileNet checkpoint
    data = np.asarray(crop.convert("RGB").resize((size, size), Image.BILINEAR), dtype=np.uint8)
    interp.set_tensor(inp["index"], np.expand_dims(data, 0))
    interp.invoke()
    raw_u8 = interp.get_tensor(out["index"])[0]
    scale, zero = out["quantization"]
    # Output is already a quantized probability (no softmax)
    probs = (raw_u8.astype(np.float32) - zero) * (scale if scale else 1.0)

    labels = (MODELS / "imagenet_labels.txt").read_text().strip().splitlines()
    cat_hints = ("tabby", "tiger cat", "persian cat", "siamese cat", "egyptian cat")
    best_i, best_p = -1, 0.0
    for i, p in enumerate(probs):
        if i >= len(labels):
            break
        lab = labels[i].lower()
        is_cat = any(h in lab for h in cat_hints) or (
            "cat" in lab and "cattle" not in lab and "catamaran" not in lab
        )
        if is_cat and float(p) > best_p:
            best_p = float(p)
            best_i = i
    if best_i < 0:
        top = int(probs.argmax())
        return labels[top] if top < len(labels) else "Mixed", float(probs[top]), False
    return labels[best_i], best_p, True


def main(path: str) -> int:
    img_path = Path(path)
    img = Image.open(img_path).convert("RGB")
    print(f"image: {img_path} ({img.size[0]}x{img.size[1]})")
    print(f"blur(full): {blur_score(img):.1f}")

    det, _ = run_detector(img)
    if not det:
        print("RESULT: no cat detected")
        return 1

    print(
        f"detect: {det['label']} score={det['score']:.3f} "
        f"box={tuple(round(x, 3) for x in det['box'])}"
    )
    crop = crop_box(img, det["box"])
    print(f"crop: {crop.size[0]}x{crop.size[1]} blur={blur_score(crop):.1f}")

    breed, conf, is_feline = run_breed(crop)
    if not is_feline and not det.get("is_cat"):
        print(f"breed top-1 was non-feline ({breed}); rejecting box")
        print("RESULT: no cat detected")
        return 1
    if not is_feline:
        print("note: breed model unsure; keeping SSD cat box")
    breeds = json.loads(BREEDS.read_text())
    info = None
    for key, val in breeds.items():
        if key.lower() == breed.lower() or val["displayName"].lower() in breed.lower():
            info = (key, val)
            break
    if info is None:
        # map ImageNet names
        mapping = {
            "tabby": "Tabby",
            "tiger cat": "Tiger cat",
            "persian cat": "Persian cat",
            "siamese cat": "Siamese cat",
            "egyptian cat": "Egyptian cat",
        }
        key = mapping.get(breed.lower(), "Mixed")
        info = (key, breeds[key])

    key, stats = info
    emb = embed(crop)
    print(f"breed: {stats['displayName']} ({breed}) conf={conf:.3f}")
    print(
        f"stats: ATK {stats['attack']} DEF {stats['defense']} "
        f"SPD {stats['speed']} ability={stats['ability']}"
    )
    print(f"embedding: dim={len(emb)} L2={math.sqrt(float((emb * emb).sum())):.4f}")
    print("RESULT: OK — cat scan pipeline succeeded on desktop")
    return 0


if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else str(ROOT / "test_assets" / "cat.jpg")
    raise SystemExit(main(target))
