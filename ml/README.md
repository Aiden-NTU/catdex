# Catdex ML notes

On-device models live in `assets/models/`:

| File | Role | Source |
|------|------|--------|
| `detect.tflite` | COCO SSD MobileNet (quant) — filter `cat` | TensorFlow Hosted Models |
| `mobilenet_quant.tflite` | ImageNet MobileNet — cat subclass → breed | TensorFlow Hosted Models |
| Identity | 128-d perceptual embedding in Dart | `lib/ml/identity_embedder.dart` |

## Replacing the identity embedder

Train a metric-learning / ReID backbone on multi-view cat photos, export TFLite
(int8, 224 input → 128-d L2 vector), and swap the body of `IdentityEmbedder`
while keeping `CatRepository.matchIdentity` thresholds.

## Fine-tuning breeds

Oxford-IIIT Pet (cat subset) + a Mixed bucket is a good starting set. Export
EfficientNet-Lite0 / MobileNetV3-small to TFLite and point `BreedClassifier`
at the new asset + label list.
