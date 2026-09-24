"""player.glb - stylized Nordic warrior, ~1.8m, rigid-part construction.
Modeled facing Blender +Y -> exports facing Godot -Z (forward). Feet at y=0.
14-bone armature; every body-part mesh is rigid-parented to its bone.
"""
import sys, os, math
sys.path.insert(0, os.path.expanduser("~/workspace/horror-game/tools/blender"))
from common import *

clean_scene()

skin = pbr_material("Skin", base_color=(0.76, 0.57, 0.44, 1.0), roughness=0.7)
cloth = pbr_material("Cloth", base_color=(0.22, 0.26, 0.34, 1.0), roughness=0.95)
leather = pbr_material("Leather", base_color=(0.35, 0.23, 0.14, 1.0), roughness=0.9)
iron = pbr_material("Iron", base_color=(0.42, 0.44, 0.48, 1.0),
                    metallic=0.9, roughness=0.45)
beardm = pbr_material("Beard", base_color=(0.16, 0.11, 0.07, 1.0), roughness=0.95)

BONES = [
    ("Hips",       (0, 0, 0.98),      (0, 0, 1.12),       None),
    ("Spine",      (0, 0, 1.12),      (0, 0, 1.32),       "Hips"),
    ("Chest",      (0, 0, 1.32),      (0, 0, 1.50),       "Spine"),
    ("Head",       (0, 0, 1.50),      (0, 0.03, 1.74),    "Chest"),
    ("UpperArm.L", (0.20, 0, 1.46),   (0.36, -0.01, 1.28), "Chest"),
    ("ForeArm.L",  (0.36, -0.01, 1.28), (0.47, -0.02, 1.12), "UpperArm.L"),
    ("Hand.L",     (0.47, -0.02, 1.12), (0.53, -0.02, 1.04), "ForeArm.L"),
    ("UpperArm.R", (-0.20, 0, 1.46),  (-0.36, -0.01, 1.28), "Chest"),
    ("ForeArm.R",  (-0.36, -0.01, 1.28), (-0.47, -0.02, 1.12), "UpperArm.R"),
    ("Hand.R",     (-0.47, -0.02, 1.12), (-0.53, -0.02, 1.04), "ForeArm.R"),
    ("Thigh.L",    (0.10, 0, 0.98),   (0.11, 0.01, 0.52), "Hips"),
    ("Shin.L",     (0.11, 0.01, 0.52), (0.11, 0.02, 0.10), "Thigh.L"),
    ("Thigh.R",    (-0.10, 0, 0.98),  (-0.11, 0.01, 0.52), "Hips"),
    ("Shin.R",     (-0.11, 0.01, 0.52), (-0.11, 0.02, 0.10), "Thigh.R"),
]
arm = make_armature(BONES, name="PlayerArmature")


def box(name, bone, center, size, mat):
    bpy.ops.mesh.primitive_cube_add(location=center)
    o = bpy.context.view_layer.objects.active
    o.name = name
    o.scale = (size[0] / 2, size[1] / 2, size[2] / 2)
    apply_transforms(o, rotation=False, scale=True)
    assign_material(o, mat)
    parent_to_bone(o, arm, bone)
    return o


# ---- torso ----
box("Pelvis", "Hips", (0, 0, 1.02), (0.34, 0.22, 0.22), cloth)
bpy.ops.mesh.primitive_cone_add(vertices=10, radius1=0.28, radius2=0.20,
                                depth=0.34, location=(0, 0, 0.82))
skirt = bpy.context.view_layer.objects.active
skirt.name = "TunicSkirt"
assign_material(skirt, cloth)
parent_to_bone(skirt, arm, "Hips")
bpy.ops.mesh.primitive_torus_add(major_radius=0.185, minor_radius=0.028,
                                 major_segments=12, minor_segments=6,
                                 location=(0, 0, 1.06))
belt = bpy.context.view_layer.objects.active
belt.name = "Belt"
assign_material(belt, leather)
parent_to_bone(belt, arm, "Hips")
box("Abdomen", "Spine", (0, 0, 1.22), (0.30, 0.20, 0.22), cloth)
box("Chest", "Chest", (0, 0, 1.41), (0.38, 0.24, 0.22), cloth)
box("Pauldron.L", "UpperArm.L", (0.23, 0, 1.50), (0.17, 0.20, 0.10), iron)
box("Pauldron.R", "UpperArm.R", (-0.23, 0, 1.50), (0.17, 0.20, 0.10), iron)

# ---- head + beard ----
box("Head", "Head", (0, 0.01, 1.63), (0.20, 0.22, 0.24), skin)
bpy.ops.mesh.primitive_cone_add(vertices=8, radius1=0.085, radius2=0.0,
                                depth=0.30, location=(0, 0.10, 1.47))
beard = bpy.context.view_layer.objects.active
beard.name = "Beard"
beard.rotation_euler = (math.pi, 0, 0)  # apex down
apply_transforms(beard, rotation=True, scale=False)
assign_material(beard, beardm)
parent_to_bone(beard, arm, "Head")

# ---- arms ----
for s, m in (("L", 1), ("R", -1)):
    o = limb(f"UpperArmMesh.{s}", (m * 0.20, 0, 1.46), (m * 0.36, -0.01, 1.28),
             0.070, skin)
    parent_to_bone(o, arm, f"UpperArm.{s}")
    o = limb(f"ForeArmMesh.{s}", (m * 0.36, -0.01, 1.28), (m * 0.47, -0.02, 1.12),
             0.058, skin)
    parent_to_bone(o, arm, f"ForeArm.{s}")
    o = limb(f"Bracer.{s}", (m * 0.40, -0.015, 1.19), (m * 0.47, -0.02, 1.12),
             0.072, leather)
    parent_to_bone(o, arm, f"ForeArm.{s}")
    box(f"Hand.{s}", f"Hand.{s}", (m * 0.50, -0.02, 1.08), (0.09, 0.10, 0.15), skin)

# ---- legs ----
for s, m in (("L", 1), ("R", -1)):
    o = limb(f"ThighMesh.{s}", (m * 0.10, 0, 0.98), (m * 0.11, 0.01, 0.52),
             0.105, cloth)
    parent_to_bone(o, arm, f"Thigh.{s}")
    o = limb(f"ShinMesh.{s}", (m * 0.11, 0.01, 0.52), (m * 0.11, 0.02, 0.10),
             0.075, leather)
    parent_to_bone(o, arm, f"Shin.{s}")
    box(f"Foot.{s}", f"Shin.{s}", (m * 0.11, 0.10, 0.05), (0.11, 0.28, 0.10), leather)

finish_asset("player.glb")
print("[done] player.glb")
