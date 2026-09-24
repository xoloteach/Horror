# MODELS.md — procedural asset manifest (Agent 2, Blender 5.2.2 LTS headless)

All assets generated 2026-09-25 by scripts in `~/workspace/horror-game/tools/blender/`
(`common.py` shared helpers + one script per asset, seeded RNG `20260925`).
Each script was run as `LIBGL_ALWAYS_SOFTWARE=1 blender -b -P <script>.py`
(one at a time, fresh Blender process per asset).

## Orientation convention

Blender: +Z up, +Y "front". The glTF exporter (`export_yup=True`, the default)
applies the basis change Blender `(x, y, z)` → glTF `(x, z, -y)`, verified
against the exporter's own `tree.py` in this Blender build. Consequences:

- A character modeled facing Blender **+Y** faces Godot **-Z** (Godot forward). ✓
- Something built pointing Blender **+Z** points Godot **+Y** (up). ✓
- +X stays +X.

All characters below were modeled facing Blender +Y (feet at Blender z=0),
so in Godot they face **-Z** with feet at **y=0**.

Stone/iron/rune PNGs from `../textures/` are **packed (embedded)** into the
GLBs that use them — no external file dependencies at import time.

## Files

| File | Tris | Size | Dimensions (Godot meters) | Origin |
|------|------|------|---------------------------|--------|
| `axe.glb` | 1,294 | 242 KB | ~1.2 m long (haft 0.9 m, blade ~0.36 m) | Grip center (haft midpoint) |
| `player.glb` | 594 | 62 KB | ~1.8 m tall | Feet center, y=0 |
| `draugr.glb` | 984 | 92 KB | ~1.9 m tall | Feet center, y=0 |
| `pillar.glb` | 232 | 746 KB | ~3.4 m tall, Ø ~0.96 m | Base center, y=0 |
| `slab.glb` | 108 | 740 KB | 2.0 × 0.3 × 2.0 m | Bottom center, y=0 |
| `wall.glb` | 324 | 753 KB | 4.0 × 3.0 × 0.6 m | Bottom center, y=0 |

(All well under the 4,500-tri budget. Texture PNGs dominate the stone file sizes.)

### axe.glb — Leviathan-style bearded war axe
- Built vertically in Blender (+Z up) → **blade points +Y in Godot local space**,
  haft along Godot Y. Origin at grip center (haft midpoint).
- Parts: `Handle` (leather haft), 6 `Wrap_*` torus grip rings, `Pommel` cap,
  `Spike` (top cone), `Socket` (eye cylinder), `Blade` (extruded bearded profile,
  0.03 m thick, slight forged bevel), 2 `RuneDecal_*` alpha-blend planes hugging
  the blade faces (runes strip texture).
- **Empty `Socket_Emit`** at local (0.29, 0, 0.30) — the cutting edge — for
  particle emission points.
- Materials: `IronDark` (packed iron albedo+roughness, metallic 0.85),
  `LeatherWrap`, `RuneDecal` (alpha BLEND, packed runes strip).

### player.glb — stylized Nordic warrior (~1.8 m)
- 23 rigid-part meshes (head+beard, torso boxes, tunic skirt cone, belt torus,
  limb cylinders, pauldrons, hands, feet), each rigid-parented to its bone
  (keep-transform bone parenting, no weight painting).
- Rest pose: relaxed A-pose, facing -Z (Godot forward), feet at y=0.
- Materials: `Skin`, `Cloth` (dark blue-grey tunic), `Leather`, `Iron`
  (pauldrons), `Beard`.

### draugr.glb — gaunt undead enemy (~1.9 m)
- Same 14 bone names/structure as player (animation code reusable).
- Emaciated proportions, hunched spine, exposed rib tori, 5 tattered cloth
  strips, skull + jaw boxes.
- **Eyes**: two small spheres with `EyeGlow` material (emission color
  (0.4, 1.0, 0.7), strength 6.0).
- Materials: `RotSkin` (sickly grey-green), `Rags`, `Bone`, `RustIron`, `EyeGlow`.

### Bone hierarchy (player.glb and draugr.glb — identical structure)
```
Hips
├── Spine
│   └── Chest
│       ├── Head
│       ├── UpperArm.L → ForeArm.L → Hand.L
│       └── UpperArm.R → ForeArm.R → Hand.R
├── Thigh.L → Shin.L
└── Thigh.R → Shin.R
```
Bone names: `Hips, Spine, Chest, Head, UpperArm.L, ForeArm.L, Hand.L,
UpperArm.R, ForeArm.R, Hand.R, Thigh.L, Shin.L, Thigh.R, Shin.R`
(14 bones, exported as a proper glTF skin with 14 joints; meshes are rigid
children of their joints — verified in the exported node tree.)

### pillar.glb — ruined stone pillar (~3.4 m)
- Base plinth, 3 stacked drums, capital, broken top drum with seeded-random
  jagged vertex displacement. Base at y=0.
- Material `Stone` (packed stone albedo + normal + roughness).

### slab.glb — cracked stone slab (2 × 0.3 × 2 m)
- Beveled/chipped edges (edit-mode bevel, 2 segments), subtle top-surface
  jitter. Bottom at y=0. Material `Stone` (packed textures).

### wall.glb — ruined perimeter wall (4 × 3 × 0.6 m)
- 6 staggered courses of blocks joined into one mesh; ruined uneven top
  course; slight per-block jitter. Bottom at y=0. Material `Stone`.

## Validation
`tools/blender/validate.py` independently parses each GLB (magic, JSON chunk),
counts triangles from index accessors, and asserts: `Socket_Emit` in axe.glb,
all 14 bones + skin in player/draugr.glb, embedded images in textured assets,
tri budget < 4500. All 6 files pass; Blender-reported tri counts match the
independent parse exactly.
