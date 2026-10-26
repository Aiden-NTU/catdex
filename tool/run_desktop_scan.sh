#!/usr/bin/env bash
# Run Catdex TFLite models on a still image (no Flutter GUI required).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMG="${1:-$ROOT/test_assets/cat.jpg}"
export MAMBA_ROOT_PREFIX="${MAMBA_ROOT_PREFIX:-$HOME/sdks/mamba}"
MM="${MICROMAMBA:-$HOME/sdks/micromamba/micromamba}"
exec "$MM" run -n catdex-ml python "$ROOT/tool/scan_image.py" "$IMG"
