#!/usr/bin/env python3
"""
Evaluate Catdex detection + breed recognition on Oxford-IIIT Pet (cats only).

Oxford cat breeds (12):
  Abyssinian, Bengal, Birman, Bombay, British_Shorthair, Egyptian_Mau,
  Maine_Coon, Persian, Ragdoll, Russian_Blue, Siamese, Sphynx

Maps onto Catdex / ImageNet-ish labels where possible; reports detect-rate,
breed top-1 / mapped accuracy, and confusion summary.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tool"))
from scan_image import (  # noqa: E402
    blur_score,
    crop_box,
    embed,
    run_breed,
    run_detector,
)

# Oxford folder/file prefix -> canonical breed key
OXFORD_CATS = {
    "Abyssinian": "Abyssinian",
    "Bengal": "Bengal",
    "Birman": "Birman",
    "Bombay": "Bombay",
    "British_Shorthair": "British Shorthair",
    "Egyptian_Mau": "Egyptian Mau",
    "Maine_Coon": "Maine Coon",
    "Persian": "Persian",
    "Ragdoll": "Ragdoll",
    "Russian_Blue": "Russian Blue",
    "Siamese": "Siamese",
    "Sphynx": "Sphynx",
}

# Predicted ImageNet / Catdex label -> Oxford-ish bucket (coarse POC mapping)
PRED_TO_OXFORD = {
    "egyptian cat": "Egyptian Mau",
    "egyptian mau": "Egyptian Mau",
    "persian cat": "Persian",
    "persian": "Persian",
    "siamese cat": "Siamese",
    "siamese": "Siamese",
    "tabby": "Mixed/Other",  # not an Oxford class
    "tiger cat": "Mixed/Other",
    "domestic shorthair": "Mixed/Other",
    "domestic longhair": "Mixed/Other",
    "mixed": "Mixed/Other",
    "mixed / unknown": "Mixed/Other",
}


def parse_oxford_name(stem: str) -> str | None:
    # e.g. Egyptian_Mau_1, British_Shorthair_12
    m = re.match(r"^([A-Za-z]+(?:_[A-Za-z]+)*)_\d+$", stem)
    if not m:
        return None
    key = m.group(1)
    return OXFORD_CATS.get(key)


def map_prediction(label: str) -> str:
    return PRED_TO_OXFORD.get(label.lower().strip(), label)


def list_cat_images(images_dir: Path, limit: int | None) -> list[tuple[Path, str]]:
    out: list[tuple[Path, str]] = []
    for p in sorted(images_dir.iterdir()):
        if p.suffix.lower() not in {".jpg", ".jpeg", ".png"}:
            continue
        breed = parse_oxford_name(p.stem)
        if breed is None:
            continue  # dog or unknown
        out.append((p, breed))
        if limit and len(out) >= limit:
            break
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--images",
        type=Path,
        default=ROOT / "ml" / "datasets" / "images",
    )
    ap.add_argument("--limit", type=int, default=0, help="0 = all cat images")
    ap.add_argument("--per-breed", type=int, default=0, help="cap samples per breed")
    ap.add_argument("--out", type=Path, default=ROOT / "ml" / "eval_results.json")
    args = ap.parse_args()

    if not args.images.is_dir():
        print(f"Missing images dir: {args.images}", file=sys.stderr)
        print("Extract Oxford images.tar.gz into ml/datasets/images/", file=sys.stderr)
        return 2

    samples = list_cat_images(args.images, None)
    if args.per_breed:
        by = defaultdict(list)
        for p, b in samples:
            by[b].append((p, b))
        samples = []
        for b, items in by.items():
            samples.extend(items[: args.per_breed])
    if args.limit:
        samples = samples[: args.limit]

    print(f"Evaluating {len(samples)} Oxford cat images from {args.images}")

    detect_ok = 0
    feline_ok = 0
    mapped_match = 0
    exactish = 0  # predicted name contains ground-truth tokens
    blur_fail = 0
    rows = []
    confusion = Counter()
    per_breed = defaultdict(lambda: {"n": 0, "detect": 0, "feline": 0, "mapped": 0})

    for i, (path, gt) in enumerate(samples, 1):
        rec = {"file": path.name, "gt": gt}
        try:
            img = Image.open(path).convert("RGB")
        except Exception as e:
            rec["error"] = f"open: {e}"
            rows.append(rec)
            continue

        bs = blur_score(img)
        rec["blur"] = bs
        det, _ = run_detector(img)
        pb = per_breed[gt]
        pb["n"] += 1

        if not det:
            rec["detect"] = False
            rows.append(rec)
            if i % 25 == 0:
                print(f"  [{i}/{len(samples)}] …")
            continue

        detect_ok += 1
        pb["detect"] += 1
        rec["detect"] = True
        rec["det_label"] = det["label"]
        rec["det_score"] = det["score"]

        crop = crop_box(img, det["box"])
        if blur_score(crop) < 40:
            blur_fail += 1
            rec["blur_reject"] = True

        breed, conf, is_feline = run_breed(crop)
        rec["pred"] = breed
        rec["conf"] = conf
        rec["feline"] = is_feline
        mapped = map_prediction(breed)
        rec["mapped"] = mapped

        if is_feline:
            feline_ok += 1
            pb["feline"] += 1

        # Exactish: shared distinctive token (egyptian/persian/siamese/…)
        gt_tok = gt.lower().replace(" ", "_")
        pred_l = breed.lower()
        if any(
            t in pred_l
            for t in gt_tok.split("_")
            if t not in {"cat", "mau", "blue", "shorthair", "coon"}
        ) or gt.lower().split()[0].lower() in pred_l:
            exactish += 1
            rec["exactish"] = True
        else:
            rec["exactish"] = False

        if mapped == gt or (mapped != "Mixed/Other" and mapped.lower() in gt.lower()):
            mapped_match += 1
            pb["mapped"] += 1
            rec["mapped_ok"] = True
        else:
            rec["mapped_ok"] = False
            confusion[(gt, mapped)] += 1

        emb = embed(crop)
        rec["emb_norm"] = float(np.linalg.norm(emb))
        rows.append(rec)
        if i % 25 == 0:
            print(f"  [{i}/{len(samples)}] detect={detect_ok/i:.2%} feline={feline_ok/i:.2%}")

    n = max(1, len(samples))
    summary = {
        "n": len(samples),
        "detect_rate": detect_ok / n,
        "feline_rate": feline_ok / n,
        "mapped_breed_rate": mapped_match / n,
        "exactish_rate": exactish / n,
        "blur_reject_count": blur_fail,
        "per_breed": {
            k: {
                **v,
                "detect_rate": v["detect"] / max(1, v["n"]),
                "feline_rate": v["feline"] / max(1, v["n"]),
                "mapped_rate": v["mapped"] / max(1, v["n"]),
            }
            for k, v in sorted(per_breed.items())
        },
        "top_confusions": [
            {"gt": a, "pred": b, "n": c} for (a, b), c in confusion.most_common(20)
        ],
    }

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps({"summary": summary, "rows": rows}, indent=2))
    print("\n=== SUMMARY ===")
    print(json.dumps(summary, indent=2))
    print(f"\nWrote {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
