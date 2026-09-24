"""wall.glb - ruined perimeter battle wall, 4m wide x 3m tall x 0.6m thick, base at y=0."""
import sys, os, random
sys.path.insert(0, os.path.expanduser("~/workspace/horror-game/tools/blender"))
from common import *

clean_scene()

stone = pbr_material("Stone", base_color=(0.55, 0.55, 0.58, 1.0),
                     metallic=0.0, roughness=0.95,
                     albedo_img="stone_albedo.png",
                     roughness_img="stone_roughness.png",
                     normal_img="stone_normal.png")

W, H, T = 4.0, 3.0, 0.6
courses, nblocks = 6, 4
ch = H / courses
bw = W / nblocks
blocks = []

for c in range(courses):
    off = -bw / 2 if c % 2 else 0.0  # staggered courses
    for i in range(nblocks + 1):
        x = -W / 2 + bw / 2 + i * bw + off
        if x < -W / 2 - bw / 2 + 0.01 or x > W / 2 + bw / 2 - 0.01:
            continue
        h = ch * random.uniform(0.72, 1.0) if c == courses - 1 else ch  # ruined top
        zc = c * ch + h / 2
        bpy.ops.mesh.primitive_cube_add(
            location=(x + random.uniform(-0.015, 0.015),
                      random.uniform(-0.010, 0.010), zc))
        b = bpy.context.view_layer.objects.active
        b.name = f"Block_{c}_{i}"
        b.scale = ((bw - 0.04) / 2, (T - 0.03) / 2, (h - 0.03) / 2)
        apply_transforms(b, rotation=False, scale=True)
        assign_material(b, stone)
        blocks.append(b)

# join into a single mesh
bpy.ops.object.select_all(action='DESELECT')
for b in blocks:
    b.select_set(True)
bpy.context.view_layer.objects.active = blocks[0]
bpy.ops.object.join()
wall = bpy.context.view_layer.objects.active
wall.name = "Wall"

finish_asset("wall.glb")
print("[done] wall.glb")
