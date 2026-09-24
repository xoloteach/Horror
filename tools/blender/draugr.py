"""draugr.glb - gaunt undead enemy, ~1.9m, hunched.
Same 14 bone names/structure as player.glb so animation code is reusable.
Facing Blender +Y -> Godot -Z. Feet at y=0. Glowing eye sockets (EyeGlow).
"""
import sys, os, math, random
sys.path.insert(0, os.path.expanduser("~/workspace/horror-game/tools/blender"))
from common import *

clean_scene()

rotskin = pbr_material("RotSkin", base_color=(0.45, 0.50, 0.42, 1.0), roughness=0.85)
rags = pbr_material("Rags", base_color=(0.25, 0.20, 0.15, 1.0), roughness=0.95)
bonem = pbr_material("Bone", base_color=(0.75, 0.72, 0.62, 1.0), roughness=0.8)
rust = pbr_material("RustIron", base_color=(0.35, 0.28, 0.22, 1.0),
                    metallic=0.6, roughness=0.7)
eyeglow = pbr_material("EyeGlow", base_color=(0.0, 0.0, 0.0, 1.0),
                       emission_color=(0.4, 1.0, 0.7, 1.0), emission_strength=6.0)

BONES = [
    ("Hips",       (0, 0, 1.03),       (0, 0, 1.18),       None),
    ("Spine",      (0, 0.04, 1.18),    (0, 0.08, 1.39),    "Hips"),
    ("Chest",      (0, 0.08, 1.39),    (0, 0.14, 1.58),    "Spine"),
    ("Head",       (0, 0.14, 1.58),    (0, 0.20, 1.80),    "Chest"),
    ("UpperArm.L", (0.19, 0.06, 1.54), (0.33, 0.05, 1.36), "Chest"),
    ("ForeArm.L",  (0.33, 0.05, 1.36), (0.44, 0.04, 1.20), "UpperArm.L"),
    ("Hand.L",     (0.44, 0.04, 1.20), (0.50, 0.04, 1.12), "ForeArm.L"),
    ("UpperArm.R", (-0.19, 0.06, 1.54), (-0.33, 0.05, 1.36), "Chest"),
    ("ForeArm.R",  (-0.33, 0.05, 1.36), (-0.44, 0.04, 1.20), "UpperArm.R"),
    ("Hand.R",     (-0.44, 0.04, 1.20), (-0.50, 0.04, 1.12), "ForeArm.R"),
    ("Thigh.L",    (0.10, 0, 1.03),    (0.11, 0.01, 0.55), "Hips"),
    ("Shin.L",     (0.11, 0.01, 0.55),  (0.11, 0.02, 0.10), "Thigh.L"),
    ("Thigh.R",    (-0.10, 0, 1.03),   (-0.11, 0.01, 0.55), "Hips"),
    ("Shin.R",     (-0.11, 0.01, 0.55), (-0.11, 0.02, 0.10), "Thigh.R"),
]
arm = make_armature(BONES, name="DraugrArmature")


def box(name, bone, center, size, mat, rot=None):
    bpy.ops.mesh.primitive_cube_add(location=center)
    o = bpy.context.view_layer.objects.active
    o.name = name
    o.scale = (size[0] / 2, size[1] / 2, size[2] / 2)
    if rot:
        o.rotation_euler = rot
        apply_transforms(o, rotation=True, scale=True)
    else:
        apply_transforms(o, rotation=False, scale=True)
    assign_material(o, mat)
    parent_to_bone(o, arm, bone)
    return o


# ---- torso: gaunt, ribs exposed ----
box("Pelvis", "Hips", (0, 0.01, 1.07), (0.28, 0.19, 0.20), rags)
box("SpineLow", "Spine", (0, 0.06, 1.28), (0.20, 0.15, 0.22), rotskin)
box("Ribcage", "Chest", (0, 0.11, 1.48), (0.30, 0.20, 0.20), rotskin)
for i, (z, r) in enumerate([(1.54, 0.170), (1.47, 0.160), (1.40, 0.150)]):
    bpy.ops.mesh.primitive_torus_add(major_radius=r, minor_radius=0.018,
                                     major_segments=12, minor_segments=6,
                                     location=(0, 0.11, z))
    rib = bpy.context.view_layer.objects.active
    rib.name = f"Rib_{i}"
    assign_material(rib, bonem)
    parent_to_bone(rib, arm, "Chest")

# ---- tattered cloth strips hanging from the waist ----
for i in range(5):
    x = -0.16 + i * 0.08
    y = 0.10 if i % 2 == 0 else -0.08
    box(f"Tatter_{i}", "Hips", (x, y, 0.82), (0.09, 0.025, 0.34), rags,
        rot=(random.uniform(-0.12, 0.12), 0, random.uniform(-0.15, 0.15)))

# ---- skull + jaw + glowing eyes ----
box("Skull", "Head", (0, 0.155, 1.69), (0.19, 0.21, 0.23), bonem)
box("Jaw", "Head", (0, 0.20, 1.585), (0.14, 0.16, 0.08), bonem)
for s, m in (("L", 1), ("R", -1)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=8, ring_count=6, radius=0.028,
                                         location=(m * 0.055, 0.235, 1.71))
    eye = bpy.context.view_layer.objects.active
    eye.name = f"Eye.{s}"
    assign_material(eye, eyeglow)
    parent_to_bone(eye, arm, "Head")

# ---- arms (emaciated) ----
for s, m in (("L", 1), ("R", -1)):
    o = limb(f"UpperArmMesh.{s}", (m * 0.19, 0.06, 1.54), (m * 0.33, 0.05, 1.36),
             0.055, rotskin)
    parent_to_bone(o, arm, f"UpperArm.{s}")
    o = limb(f"ForeArmMesh.{s}", (m * 0.33, 0.05, 1.36), (m * 0.44, 0.04, 1.20),
             0.045, rotskin)
    parent_to_bone(o, arm, f"ForeArm.{s}")
    box(f"Claw.{s}", f"Hand.{s}", (m * 0.47, 0.04, 1.16), (0.08, 0.09, 0.14), bonem)

# ---- legs ----
for s, m in (("L", 1), ("R", -1)):
    o = limb(f"ThighMesh.{s}", (m * 0.10, 0, 1.03), (m * 0.11, 0.01, 0.55),
             0.085, rags)
    parent_to_bone(o, arm, f"Thigh.{s}")
    o = limb(f"ShinMesh.{s}", (m * 0.11, 0.01, 0.55), (m * 0.11, 0.02, 0.10),
             0.060, bonem)
    parent_to_bone(o, arm, f"Shin.{s}")
    box(f"Foot.{s}", f"Shin.{s}", (m * 0.11, 0.10, 0.05), (0.10, 0.26, 0.10), rags)

finish_asset("draugr.glb")
print("[done] draugr.glb")
