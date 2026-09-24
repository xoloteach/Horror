"""pillar.glb - ruined stone pillar, stacked drums + jagged broken top, ~3.4m, base at y=0."""
import sys, os
sys.path.insert(0, os.path.expanduser("~/workspace/horror-game/tools/blender"))
from common import *

clean_scene()

stone = pbr_material("Stone", base_color=(0.55, 0.55, 0.58, 1.0),
                     metallic=0.0, roughness=0.95,
                     albedo_img="stone_albedo.png",
                     roughness_img="stone_roughness.png",
                     normal_img="stone_normal.png")

parts = []

def reg(obj, name):
    obj.name = name
    assign_material(obj, stone)
    parts.append(obj)
    return obj

# base plinth
bpy.ops.mesh.primitive_cube_add(location=(0, 0, 0.175))
base = bpy.context.view_layer.objects.active
base.scale = (0.65, 0.65, 0.175)
apply_transforms(base, rotation=False, scale=True)
reg(base, "Base")

# stacked drums
for i, (r, zc) in enumerate([(0.48, 0.725), (0.46, 1.475), (0.44, 2.225)]):
    bpy.ops.mesh.primitive_cylinder_add(vertices=14, radius=r, depth=0.75,
                                        location=(0, 0, zc))
    reg(bpy.context.view_layer.objects.active, f"Drum{i+1}")

# capital
bpy.ops.mesh.primitive_cube_add(location=(0, 0, 2.74))
cap = bpy.context.view_layer.objects.active
cap.scale = (0.55, 0.55, 0.14)
apply_transforms(cap, rotation=False, scale=True)
reg(cap, "Capital")

# broken top drum with jagged displaced top ring (local coords: top at +0.25)
bpy.ops.mesh.primitive_cylinder_add(vertices=14, radius=0.44, depth=0.5,
                                    location=(0, 0, 3.13))
top = reg(bpy.context.view_layer.objects.active, "BrokenTop")
jitter_verts(top, dx=0.06, dy=0.06, dz=0.17, z_min=0.08)

# join into one mesh
bpy.ops.object.select_all(action='DESELECT')
for p in parts:
    p.select_set(True)
bpy.context.view_layer.objects.active = parts[0]
bpy.ops.object.join()
pillar = bpy.context.view_layer.objects.active
pillar.name = "Pillar"

finish_asset("pillar.glb")
print("[done] pillar.glb")
