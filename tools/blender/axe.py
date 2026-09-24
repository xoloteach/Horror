"""axe.glb - Leviathan-style bearded war axe, ~1.2m.
Built vertically in Blender (+Z up): glTF maps Blender +Z -> Godot +Y,
so the blade points +Y in Godot local space. Origin at grip center.
Empty "Socket_Emit" marks the blade edge for particle emission.
"""
import sys, os, math
import bmesh
sys.path.insert(0, os.path.expanduser("~/workspace/horror-game/tools/blender"))
from common import *

clean_scene()

iron = pbr_material("IronDark", base_color=(0.25, 0.26, 0.30, 1.0),
                    metallic=0.85, roughness=0.9,
                    albedo_img="iron_albedo.png",
                    roughness_img="iron_roughness.png")
leather = pbr_material("LeatherWrap", base_color=(0.32, 0.20, 0.12, 1.0),
                       metallic=0.0, roughness=0.9)
rune = pbr_material("RuneDecal", base_color=(1.0, 1.0, 1.0, 1.0),
                    metallic=0.0, roughness=0.5,
                    albedo_img="runes_alpha.png", alpha_blend=True)


def reg(obj, name, mat):
    obj.name = name
    assign_material(obj, mat)
    return obj


# ---- haft (handle), centered on origin = grip center ----
bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.028, depth=0.9,
                                    location=(0, 0, 0))
reg(bpy.context.view_layer.objects.active, "Handle", leather)

# ---- leather wrap rings ----
for i, z in enumerate([-0.30, -0.18, -0.06, 0.06, 0.18, 0.30]):
    bpy.ops.mesh.primitive_torus_add(major_radius=0.030, minor_radius=0.009,
                                     major_segments=12, minor_segments=6,
                                     location=(0, 0, z))
    reg(bpy.context.view_layer.objects.active, f"Wrap_{i}", leather)

# ---- pommel cap ----
bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=8, radius=0.045,
                                     location=(0, 0, -0.47))
pommel = bpy.context.view_layer.objects.active
pommel.scale = (1.0, 1.0, 0.7)
apply_transforms(pommel, rotation=False, scale=True)
reg(pommel, "Pommel", iron)

# ---- top spike ----
bpy.ops.mesh.primitive_cone_add(vertices=10, radius1=0.030, radius2=0.0,
                                depth=0.16, location=(0, 0, 0.53))
reg(bpy.context.view_layer.objects.active, "Spike", iron)

# ---- socket / eye wrapping the haft ----
bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.045, depth=0.07,
                                    location=(0.01, 0, 0.33))
sock = bpy.context.view_layer.objects.active
sock.rotation_euler = (math.pi / 2, 0, 0)
apply_transforms(sock, rotation=True, scale=False)
reg(sock, "Socket", iron)

# ---- bearded blade: extruded profile in XZ, thickness in Y ----
def build_blade():
    pts = [  # (x outward, z up) - classic bearded silhouette
        (0.00, 0.16), (0.08, 0.185), (0.17, 0.17), (0.24, 0.12),
        (0.285, 0.04), (0.295, -0.03), (0.27, -0.10), (0.22, -0.155),
        (0.15, -0.175), (0.09, -0.15), (0.05, -0.10), (0.02, -0.02),
        (0.00, 0.06),
    ]
    bm = bmesh.new()
    verts = [bm.verts.new((x, 0.0, z)) for x, z in pts]
    bm.verts.ensure_lookup_table()
    bm.faces.new(verts)
    bm.faces.ensure_lookup_table()
    ret = bmesh.ops.extrude_face_region(bm, geom=[bm.faces[0]])
    new_verts = [e for e in ret['geom'] if isinstance(e, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=(0.0, 0.03, 0.0), verts=new_verts)
    bmesh.ops.translate(bm, vec=(0.0, -0.015, 0.0), verts=bm.verts)  # center: +-0.015
    bmesh.ops.bevel(bm, geom=list(bm.edges), offset=0.004, segments=1, profile=0.7)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.translate(bm, vec=(0.0, 0.0, 0.325), verts=bm.verts)  # seat at socket
    me = bpy.data.meshes.new("BladeMesh")
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new("Blade", me)
    bpy.context.scene.collection.objects.link(obj)
    return obj

reg(build_blade(), "Blade", iron)

# ---- runic decals hugging both blade faces ----
for side, y, rotx in (("A", 0.021, -math.pi / 2), ("B", -0.021, math.pi / 2)):
    bpy.ops.mesh.primitive_plane_add(size=1.0, location=(0.13, y, 0.33))
    d = bpy.context.view_layer.objects.active
    d.rotation_euler = (rotx, 0, 0)
    d.scale = (0.08, 0.11, 1.0)
    apply_transforms(d, rotation=True, scale=True)
    reg(d, f"RuneDecal_{side}", rune)

# ---- particle emission socket at the cutting edge ----
bpy.ops.object.empty_add(type='PLAIN_AXES', location=(0.29, 0, 0.30))
se = bpy.context.view_layer.objects.active
se.name = "Socket_Emit"
se.empty_display_size = 0.05

finish_asset("axe.glb", uv_skip=("RuneDecal_A", "RuneDecal_B"))
print("[done] axe.glb")
