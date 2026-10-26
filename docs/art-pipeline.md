# Battle art pipeline

The checked-in arena and card-frame source images are generated visuals licensed
for this project. Keep their original files and do not train or derive unrelated
assets from them. The battle sound effects are locally synthesized by
`tools/assets/generate_battle_sfx.py` and contain no recorded samples.

## Runtime

Battles embed a Flame game only inside the arena route. The current fighter is a
reusable procedural 2.5D rig, so no unreviewed binary animation file is shipped.
The rig supports idle, anticipation/dash, impact flash, damage text, particles,
and camera shake. Flutter owns controls, semantics, timers, and navigation.

The animation boundary is Rive-ready: fighter state is expressed as named
actions (`idle`, `anticipation`, `attack`, `ability`, `hit`, `victory`) rather
than frame indices. An approved `.riv` can replace the renderer by mapping these
names to a state machine. Do not add a placeholder or renamed fake `.riv`.

## Blender and atlas export

1. Author actions with the exact names in `battle-atlas-spec.json`.
2. Use one armature, apply transforms, and keep the ground pivot at `(0.5, .82)`.
3. Export transparent PNG frames:

   `blender --background cat_rig.blend --python tools/assets/blender_export_battle.py`

4. Pack frames according to `tools/assets/battle-atlas-spec.json`.
5. Review silhouette readability at 25% scale and test reduced-motion mode.

Blender is not required for the procedural fallback and is intentionally not a
build dependency.
