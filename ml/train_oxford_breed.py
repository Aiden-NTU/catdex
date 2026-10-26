#!/usr/bin/env python3
"""
Fine-tune a compact MobileNetV2 classifier on Oxford-IIIT Pet cat breeds (12 classes)
and export TFLite (float + int8) for Catdex.

Usage (micromamba env catdex-ml with tensorflow):
  micromamba run -n catdex-ml pip install tensorflow
  micromamba run -n catdex-ml python ml/train_oxford_breed.py
"""

from __future__ import annotations

import json
import re
from pathlib import Path

import numpy as np
import tensorflow as tf

ROOT = Path(__file__).resolve().parents[1]
IMAGES = ROOT / "ml" / "datasets" / "images"
OUT_DIR = ROOT / "ml" / "artifacts"
ASSETS = ROOT / "assets" / "models"

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

IMG_SIZE = 224
BATCH = 32
EPOCHS = 8
SEED = 42


def list_samples():
    xs, ys = [], []
    for p in sorted(IMAGES.iterdir()):
        if p.suffix.lower() not in {".jpg", ".jpeg"}:
            continue
        m = re.match(r"^([A-Za-z]+(?:_[A-Za-z]+)*)_\d+$", p.stem)
        if not m:
            continue
        breed = m.group(1)
        if breed not in OXFORD_CATS:
            continue
        xs.append(str(p))
        ys.append(OXFORD_CATS.index(breed))
    return xs, ys


def make_ds(paths, labels, training: bool):
    path_ds = tf.data.Dataset.from_tensor_slices((paths, labels))

    def _load(path, label):
        img = tf.io.read_file(path)
        img = tf.image.decode_jpeg(img, channels=3)
        img = tf.image.resize(img, [IMG_SIZE, IMG_SIZE])
        img = tf.cast(img, tf.float32) / 255.0
        if training:
            img = tf.image.random_flip_left_right(img)
            img = tf.image.random_brightness(img, 0.1)
        return img, label

    ds = path_ds.map(_load, num_parallel_calls=tf.data.AUTOTUNE)
    if training:
        ds = ds.shuffle(1000, seed=SEED)
    return ds.batch(BATCH).prefetch(tf.data.AUTOTUNE)


def build_model(num_classes: int) -> tf.keras.Model:
    base = tf.keras.applications.MobileNetV2(
        input_shape=(IMG_SIZE, IMG_SIZE, 3),
        include_top=False,
        weights="imagenet",
    )
    base.trainable = False
    inputs = tf.keras.Input((IMG_SIZE, IMG_SIZE, 3))
    # MobileNetV2 preprocess expects [-1,1]
    x = tf.keras.applications.mobilenet_v2.preprocess_input(inputs * 255.0)
    x = base(x, training=False)
    x = tf.keras.layers.GlobalAveragePooling2D()(x)
    x = tf.keras.layers.Dropout(0.2)(x)
    outputs = tf.keras.layers.Dense(num_classes, activation="softmax")(x)
    model = tf.keras.Model(inputs, outputs)
    model.compile(
        optimizer=tf.keras.optimizers.Adam(1e-3),
        loss="sparse_categorical_crossentropy",
        metrics=["accuracy"],
    )
    return model, base


def export_tflite(model: tf.keras.Model, paths_calibrate: list[str]):
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    # Float16 / dynamic-range for compact mobile
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    tflite_model = converter.convert()
    out_path = OUT_DIR / "oxford_breed_int8dyn.tflite"
    out_path.write_bytes(tflite_model)
    print(f"Wrote {out_path} ({out_path.stat().st_size / 1e6:.2f} MB)")

    labels_path = OUT_DIR / "oxford_breed_labels.json"
    labels_path.write_text(json.dumps(OXFORD_CATS, indent=2))
    # Also human display names
    display = [n.replace("_", " ") for n in OXFORD_CATS]
    (OUT_DIR / "oxford_breed_display.json").write_text(json.dumps(display, indent=2))

    # Copy into app assets for next iteration
    ASSETS.mkdir(parents=True, exist_ok=True)
    dest = ASSETS / "oxford_breed.tflite"
    dest.write_bytes(tflite_model)
    (ASSETS / "oxford_breed_labels.json").write_text(json.dumps(display, indent=2))
    print(f"Installed {dest}")


def main():
    paths, labels = list_samples()
    print(f"Oxford cat samples: {len(paths)}")
    rng = np.random.default_rng(SEED)
    idx = np.arange(len(paths))
    rng.shuffle(idx)
    cut = int(0.85 * len(idx))
    train_i, val_i = idx[:cut], idx[cut:]
    train_paths = [paths[i] for i in train_i]
    train_labels = [labels[i] for i in train_i]
    val_paths = [paths[i] for i in val_i]
    val_labels = [labels[i] for i in val_i]

    train_ds = make_ds(train_paths, train_labels, True)
    val_ds = make_ds(val_paths, val_labels, False)

    model, base = build_model(len(OXFORD_CATS))
    model.fit(train_ds, validation_data=val_ds, epochs=EPOCHS)

    # Light fine-tune last blocks
    base.trainable = True
    for layer in base.layers[:-30]:
        layer.trainable = False
    model.compile(
        optimizer=tf.keras.optimizers.Adam(1e-5),
        loss="sparse_categorical_crossentropy",
        metrics=["accuracy"],
    )
    model.fit(train_ds, validation_data=val_ds, epochs=5)

    loss, acc = model.evaluate(val_ds)
    print(f"Val accuracy: {acc:.3f}")
    (OUT_DIR / "train_metrics.json").write_text(
        json.dumps({"val_accuracy": float(acc), "val_loss": float(loss)}, indent=2)
    )
    export_tflite(model, val_paths[:100])


if __name__ == "__main__":
    main()
