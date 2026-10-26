"""Blender 4.x headless export for Catdex battle rigs.

Usage:
  blender --background cat_rig.blend --python blender_export_battle.py

The source .blend is deliberately optional: the shipped runtime uses Flame's
procedural rig until an approved artist-authored file enters the pipeline.
"""

from __future__ import annotations

import json
from pathlib import Path

import bpy

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "art" / "battle" / "generated"
ANIMATIONS = ("idle", "anticipation", "attack", "ability", "hit", "victory")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 512
    scene.render.resolution_y = 512
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.look = "AgX - Medium High Contrast"

    manifest = {"schema": 1, "frameSize": [512, 512], "animations": {}}
    for action_name in ANIMATIONS:
        action = bpy.data.actions.get(action_name)
        if action is None:
            continue
        scene.frame_start = int(action.frame_range[0])
        scene.frame_end = int(action.frame_range[1])
        scene.render.filepath = str(OUT / f"{action_name}_")
        bpy.ops.render.render(animation=True)
        manifest["animations"][action_name] = {
            "firstFrame": scene.frame_start,
            "lastFrame": scene.frame_end,
            "fps": scene.render.fps,
            "loop": action_name == "idle",
        }

    (OUT / "atlas-manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )


if __name__ == "__main__":
    main()
