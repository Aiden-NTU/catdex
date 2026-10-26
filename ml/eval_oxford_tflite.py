#!/usr/bin/env python3
"""Evaluate oxford_breed.tflite (+ SSD detect) on Oxford-IIIT cat images."""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np
from PIL import Image

try:
    from ai_edge_litert.interpreter import Interpreter
except ImportError:
    from tensorflow.lite.python.interpreter import Interpreter  # type: ignore

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tool"))
from scan_image import crop_box, run_detector  # noqa: E402

OXFORD_CATS = [
    "Abyssinian",
    "Bengal",
    "Birman",
    "Bombay",
    "British_Shorthair",
    "Egyptian_Mau",
    "Maine_Coon",
    "Persian",
    "Ragdoll",
    "Russian_Blue",
    "Siamese",
    "Sphynx",
]


def parse_breed(stem: str) -> str | None:
    m = re.match(r"^([A-Za-z]+(?:_[A-Za-z]+)*)_\d+$", stem)
    if not m:
        return None
    key = m.group(1)
    return key if key in OXFORD_CATS else None


def load_breed_model(path: Path, labels_path: Path):
    interp = Interpreter(model_path=str(path))
    interp.allocate_tensors()
    labels = json.loads(labels_path.read_text())
    # labels may be display names with spaces
    label_keys = [l.replace(" ", "_") if " " in l else l for l in labels]
    # Normalize to Oxford underscore keys when possible
    normalized = []
    for lab in labels:
        key = lab.replace(" ", "_")
        if key in OXFORD_CATS:
            normalized.append(key)
        else:
            # try match display
            hit = next((c for c in OXFORD_CATS if c.replace("_", " ") == lab), lab)
            normalized.append(hit)
    return interp, normalized


def classify(interp, labels, crop: Image.Image):
    inp = interp.get_input_details()[0]
    out = interp.get_output_details()[0]
    size = inp["shape"][1]
    arr = np.asarray(crop.convert("RGB").resize((size, size)), dtype=np.float32) / 255.0
    if inp["dtype"] == np.uint8:
        x = (arr * 255).astype(np.uint8)
    else:
        x = arr.astype(np.float32)
    interp.set_tensor(inp["index"], np.expand_dims(x, 0))
    interp.invoke()
    probs = interp.get_tensor(out["index"])[0].astype(np.float32)
    if out["dtype"] == np.uint8:
        scale, zero = out["quantization"]
        if scale:
            probs = (probs - zero) * scale
    i = int(np.argmax(probs))
    return labels[i], float(probs[i])


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--images", type=Path, default=ROOT / "ml/datasets/images")
    ap.add_argument(
        "--model",
        type=Path,
        default=ROOT / "assets/models/oxford_breed.tflite",
    )
    ap.add_argument(
        "--labels",
        type=Path,
        default=ROOT / "assets/models/oxford_breed_labels.json",
    )
    ap.add_argument("--per-breed", type=int, default=0)
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--out", type=Path, default=ROOT / "ml/eval_oxford_tflite.json")
    ap.add_argument("--skip-detect", action="store_true")
    args = ap.parse_args()

    if not args.model.is_file():
        print(f"Missing model {args.model}", file=sys.stderr)
        return 2

    interp, labels = load_breed_model(args.model, args.labels)
    print(f"Model {args.model.name} labels={labels}")

    samples = []
    for p in sorted(args.images.iterdir()):
        if p.suffix.lower() not in {".jpg", ".jpeg"}:
            continue
        b = parse_breed(p.stem)
        if b:
            samples.append((p, b))
    if args.per_breed:
        by = defaultdict(list)
        for p, b in samples:
            by[b].append((p, b))
        samples = []
        for items in by.values():
            samples.extend(items[: args.per_breed])
    if args.limit:
        samples = samples[: args.limit]

    print(f"Evaluating {len(samples)} images")
    detect_ok = breed_ok = top1 = 0
    per = defaultdict(lambda: {"n": 0, "ok": 0, "detect": 0})
    confusions = Counter()

    for i, (path, gt) in enumerate(samples, 1):
        per[gt]["n"] += 1
        img = Image.open(path).convert("RGB")
        if args.skip_detect:
            crop = img
            detect_ok += 1
            per[gt]["detect"] += 1
        else:
            det, _ = run_detector(img)
            if not det:
                confusions[(gt, "NO_DETECT")] += 1
                continue
            detect_ok += 1
            per[gt]["detect"] += 1
            crop = crop_box(img, det["box"])

        pred, conf = classify(interp, labels, crop)
        breed_ok += 1  # produced a breed
        if pred == gt:
            top1 += 1
            per[gt]["ok"] += 1
        else:
            confusions[(gt, pred)] += 1

        if i % 50 == 0:
            print(f"  [{i}/{len(samples)}] top1={top1/i:.2%} detect={detect_ok/i:.2%}")

    n = max(1, len(samples))
    summary = {
        "n": len(samples),
        "detect_rate": detect_ok / n,
        "breed_top1": top1 / n,
        "breed_top1_given_detect": top1 / max(1, detect_ok),
        "per_breed": {
            k: {
                **v,
                "acc": v["ok"] / max(1, v["n"]),
                "detect_rate": v["detect"] / max(1, v["n"]),
            }
            for k, v in sorted(per.items())
        },
        "top_confusions": [
            {"gt": a, "pred": b, "n": c} for (a, b), c in confusions.most_common(25)
        ],
    }
    args.out.write_text(json.dumps(summary, indent=2))
    print(json.dumps(summary, indent=2))
    print(f"Wrote {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
