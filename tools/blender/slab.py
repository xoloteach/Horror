"""slab.glb - cracked stone slab, 2 x 0.3 x 2 m, bottom at y=0 (Godot)."""
import sys, os
sys.path.insert(0, os.path.expanduser("~/workspace/horror-game/tools/blender"))
from common import *

clean_scene()

stone = pbr_material("Stone", base_color=(0.55, 0.55, 0.58, 1.0),
                     metallic=0.0, roughness=0.95,
                     albedo_img="stone_albedo.png",
                     roughness_img="stone_roughness.png",
                     normal_img="stone_normal.png")

bpy.ops.mesh.primitive_cube_add(location=(0, 0, 0.15))
slab = bpy.context.view_layer.objects.active
slab.name = "Slab"
slab.scale = (1.0, 1.0, 0.15)  # 2 x 2 x 0.3 m
apply_transforms(slab, rotation=False, scale=True)

# chip the edges
select_only(slab)
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.bevel(offset=0.035, segments=2, profile=0.7)
bpy.ops.object.mode_set(mode='OBJECT')

# subtle top-surface unevenness (local z: top face at 0.15)
jitter_verts(slab, dx=0.008, dy=0.008, dz=0.012, z_min=0.13)

assign_material(slab, stone)
finish_asset("slab.glb")
print("[done] slab.glb")
