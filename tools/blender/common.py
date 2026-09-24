"""Shared helpers for headless procedural asset generation (Blender 5.2 LTS).

Conventions:
- Blender units = meters. +Z up, +Y "front".
- glTF exporter (export_yup=True) maps Blender (x,y,z) -> glTF (x,z,-y),
  i.e. Blender +Y -> Godot -Z (Godot forward), Blender +Z -> Godot +Y (up).
"""
import bpy
import bmesh
import math
import os
import random
from mathutils import Matrix, Vector

TEXDIR = os.path.expanduser("~/workspace/horror-game/assets/textures")
OUTDIR = os.path.expanduser("~/workspace/horror-game/assets/models")
SEED = 20260925


def clean_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    random.seed(SEED)


def select_only(obj):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def apply_transforms(obj, location=False, rotation=True, scale=True):
    select_only(obj)
    bpy.ops.object.transform_apply(location=location, rotation=rotation, scale=scale)


# ---------------- materials ----------------

def load_image(filename, colorspace):
    path = os.path.join(TEXDIR, filename)
    if not os.path.isfile(path):
        print(f"  [warn] texture not found: {filename} (flat color fallback)")
        return None
    key = "packed::" + filename
    img = bpy.data.images.get(key)
    if img is None:
        img = bpy.data.images.load(path)
        img.name = key
        img.colorspace_settings.name = colorspace
        try:
            img.pack()
            print(f"  [info] packed texture: {filename}")
        except RuntimeError as e:
            print(f"  [warn] pack failed for {filename}: {e}")
    return img


def pbr_material(name, base_color=(0.8, 0.8, 0.8, 1.0), metallic=0.0, roughness=0.8,
                 albedo_img=None, roughness_img=None, normal_img=None,
                 emission_color=None, emission_strength=0.0, alpha_blend=False):
    if name in bpy.data.materials:
        return bpy.data.materials[name]
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = base_color
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission_color is not None:
        bsdf.inputs["Emission Color"].default_value = emission_color
        bsdf.inputs["Emission Strength"].default_value = emission_strength

    def tex_node(filename, colorspace, label):
        img = load_image(filename, colorspace)
        if img is None:
            return None
        t = nodes.new("ShaderNodeTexImage")
        t.image = img
        t.label = label
        return t

    if albedo_img:
        t = tex_node(albedo_img, "sRGB", "Albedo")
        if t:
            links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
            if alpha_blend:
                links.new(t.outputs["Alpha"], bsdf.inputs["Alpha"])
    if roughness_img:
        t = tex_node(roughness_img, "Non-Color", "Roughness")
        if t:
            links.new(t.outputs["Color"], bsdf.inputs["Roughness"])
    if normal_img:
        t = tex_node(normal_img, "Non-Color", "Normal")
        if t:
            nm = nodes.new("ShaderNodeNormalMap")
            links.new(t.outputs["Color"], nm.inputs["Color"])
            links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    if alpha_blend:
        mat.blend_method = 'BLEND'
    return mat


def assign_material(obj, mat):
    if mat is not None and mat.name not in obj.data.materials:
        obj.data.materials.append(mat)


# ---------------- mesh ops ----------------

def triangulate(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def ensure_uv(obj):
    select_only(obj)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.cube_project()
    bpy.ops.object.mode_set(mode='OBJECT')


def tri_count(obj):
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def jitter_verts(obj, dx=0.0, dy=0.0, dz=0.0, z_min=None):
    """Seeded random per-vertex jitter in LOCAL coords."""
    me = obj.data
    for v in me.vertices:
        if z_min is not None and v.co.z < z_min:
            continue
        v.co.x += random.uniform(-dx, dx)
        v.co.y += random.uniform(-dy, dy)
        v.co.z += random.uniform(-dz, dz)
    me.update()


# ---------------- armature ----------------

def make_armature(bone_defs, name="Armature"):
    """bone_defs: list of (name, head_xyz, tail_xyz, parent_name_or_None)."""
    bpy.ops.object.armature_add(enter_editmode=True, location=(0, 0, 0))
    arm = bpy.context.view_layer.objects.active
    arm.name = name
    eb = arm.data.edit_bones
    eb.remove(eb[0])
    created = {}
    for bname, head, tail, parent in bone_defs:
        b = eb.new(bname)
        b.head = head
        b.tail = tail
        created[bname] = b
    for bname, head, tail, parent in bone_defs:
        if parent:
            created[bname].parent = created[parent]
    bpy.ops.object.mode_set(mode='OBJECT')
    bpy.context.view_layer.update()
    return arm


def parent_to_bone(obj, arm, bone_name):
    """Rigid-bind part to bone, preserving the object's world transform."""
    bpy.context.view_layer.update()
    obj.parent = arm
    obj.parent_type = 'BONE'
    obj.parent_bone = bone_name
    pb = arm.pose.bones[bone_name]
    obj.matrix_parent_inverse = (arm.matrix_world @ pb.matrix).inverted()
    bpy.context.view_layer.update()


def limb(name, head, tail, radius, mat, vertices=8):
    """Cylinder stretched between two world points, orientation baked."""
    h = Vector(head)
    t = Vector(tail)
    d = t - h
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=d.length)
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    obj.location = (h + t) / 2
    obj.rotation_euler = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_euler()
    apply_transforms(obj, location=False, rotation=True, scale=False)
    assign_material(obj, mat)
    return obj


# ---------------- export ----------------

def export_glb(filename):
    assert hasattr(bpy.ops.export_scene, 'gltf'), "glTF exporter addon not enabled!"
    os.makedirs(OUTDIR, exist_ok=True)
    path = os.path.join(OUTDIR, filename)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format='GLB',
        export_yup=True,
        export_materials='EXPORT',
        export_cameras=False,
        export_lights=False,
    )
    print(f"  [export] {filename}: {os.path.getsize(path)} bytes -> {path}")
    return path


def finish_asset(filename, uv_skip=()):
    total = 0
    for obj in list(bpy.context.scene.objects):
        if obj.type != 'MESH':
            continue
        triangulate(obj)
        if obj.name not in uv_skip:
            ensure_uv(obj)
        n = tri_count(obj)
        total += n
        print(f"  [mesh] {obj.name}: {n} tris")
    export_glb(filename)
    print(f"[total] {filename}: {total} tris")
    if total >= 4500:
        raise RuntimeError(f"tri budget exceeded for {filename}: {total}")
    return total
