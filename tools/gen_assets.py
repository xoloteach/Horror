#!/usr/bin/env python3
"""
MIDGARD FURY - procedural asset generation for Blender 5.2 headless.

Builds every mesh in the game from first principles and exports GLB:
  axe.glb            bearded Leviathan-style war axe, runic glyphs, leather wrap
  player.glb         stylized Nordic warrior, pivot hierarchy for procedural anim
  draugr.glb         hunched undead warrior, exposed ribs, pivot hierarchy
  pillar.glb         intact Nordic stone pillar
  pillar_broken.glb  shattered pillar with jagged crown
  slab.glb           cracked floor slab
  wall.glb           crenellated perimeter wall segment
  brazier.glb        fire brazier (doubles as a light anchor)

Characters use PARENTED PIVOT HIERARCHIES rather than skinned armatures: each
part's mesh origin sits exactly on its joint and is parented to the part above
it, so GDScript can drive limbs by writing plain Euler rotations. That keeps the
rig fully inspectable and avoids shipping skinning weights to WebGL.

Orientation: modelled Z-up with +Y forward. The glTF exporter maps
Blender(+X,+Y,+Z) -> glTF(+X,+Z,-Y), landing on Godot's Y-up / -Z-forward.

Usage: LIBGL_ALWAYS_SOFTWARE=1 blender -b -P tools/gen_assets.py -- <outdir>
"""
import os
import sys
import math
import bmesh
import bpy
from mathutils import Matrix, Vector

TRI_BUDGET = 4500
OUTDIR = "assets/models"
_log = []


# ------------------------------------------------------------------ utilities

def argv_outdir():
    if "--" in sys.argv:
        rest = sys.argv[sys.argv.index("--") + 1:]
        if rest:
            return rest[0]
    return OUTDIR


def new_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def mat(name, color, metallic=0.0, rough=0.7, emit=None, emit_str=0.0):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*color, 1.0)
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Roughness"].default_value = rough
    if emit is not None:
        for key in ("Emission Color", "Emission"):
            if key in b.inputs:
                b.inputs[key].default_value = (*emit, 1.0)
                break
        if "Emission Strength" in b.inputs:
            b.inputs["Emission Strength"].default_value = emit_str
    return m


def link(ob):
    bpy.context.collection.objects.link(ob)
    return ob


def mesh_obj(name, bm, material=None, parent=None, location=(0, 0, 0)):
    me = bpy.data.meshes.new(name)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    ob = link(bpy.data.objects.new(name, me))
    if material:
        me.materials.append(material)
    if parent is not None:
        ob.parent = parent
    ob.location = location
    return ob


def empty(name, parent=None, location=(0, 0, 0)):
    e = link(bpy.data.objects.new(name, None))
    e.empty_display_size = 0.04
    if parent is not None:
        e.parent = parent
    e.location = location
    return e


def cube(bm, center, size):
    m = Matrix.Translation(center) @ Matrix.Diagonal((*size, 1.0))
    bmesh.ops.create_cube(bm, size=1.0, matrix=m)


def cyl(bm, center, radius, depth, segments=12, radius2=None, rot=None):
    m = Matrix.Translation(center)
    if rot is not None:
        m = m @ rot
    kw = dict(cap_ends=True, cap_tris=False, segments=segments, depth=depth, matrix=m)
    r2 = radius if radius2 is None else radius2
    try:
        bmesh.ops.create_cone(bm, radius1=radius, radius2=r2, **kw)
    except TypeError:  # older/newer arg naming
        bmesh.ops.create_cone(bm, diameter1=radius, diameter2=r2, **kw)


def taper_box(bm, origin, length, w0, w1, d0, d1, axis=Vector((0, 0, -1))):
    """Tapered box from `origin` extending `length` along `axis`.

    w = width (X), d = depth (Y); index 0 is the proximal end at the joint.
    Used for every limb and torso segment so parts read as organic, not blocky.
    """
    o = Vector(origin)
    e = o + axis.normalized() * length
    up = Vector((0, 0, 1))
    if abs(axis.normalized().dot(up)) > 0.95:
        side, fwd = Vector((1, 0, 0)), Vector((0, 1, 0))
    else:
        side = axis.cross(up).normalized()
        fwd = side.cross(axis.normalized()).normalized()

    def ring(c, w, d):
        return [c + side * (w / 2) + fwd * (d / 2),
                c - side * (w / 2) + fwd * (d / 2),
                c - side * (w / 2) - fwd * (d / 2),
                c + side * (w / 2) - fwd * (d / 2)]

    a = [bm.verts.new(p) for p in ring(o, w0, d0)]
    b = [bm.verts.new(p) for p in ring(e, w1, d1)]
    bm.faces.new(a[::-1])
    bm.faces.new(b)
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new([a[i], a[j], b[j], b[i]])


def bevel_all(bm, offset=0.006, segments=1):
    bmesh.ops.bevel(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces),
                    offset=offset, segments=segments, affect='EDGES',
                    profile=0.5, clamp_overlap=True)


def uv_unwrap(ob):
    try:
        bpy.ops.object.select_all(action='DESELECT')
        ob.select_set(True)
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.02)
        bpy.ops.object.mode_set(mode='OBJECT')
    except Exception as exc:
        print(f"  [uv] skipped {ob.name}: {exc}")
        if bpy.context.object and bpy.context.object.mode != 'OBJECT':
            bpy.ops.object.mode_set(mode='OBJECT')


def smooth_by_angle(ob, deg=42.0):
    try:
        bpy.ops.object.select_all(action='DESELECT')
        ob.select_set(True)
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(deg))
    except Exception:
        try:
            bpy.ops.object.shade_flat()
        except Exception:
            pass


def tri_count():
    total = 0
    for ob in bpy.context.scene.objects:
        if ob.type != 'MESH':
            continue
        total += sum(len(p.vertices) - 2 for p in ob.data.polygons)
    return total


def export(name, outdir, unwrap=True):
    os.makedirs(outdir, exist_ok=True)
    meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    if unwrap:
        for ob in meshes:
            uv_unwrap(ob)
    for ob in meshes:
        smooth_by_angle(ob)
    tris = tri_count()
    path = os.path.join(outdir, name + ".glb")
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format='GLB',
        use_selection=False,
        export_apply=True,
        export_yup=True,
        export_normals=True,
        export_texcoords=True,
        export_materials='EXPORT',
        export_cameras=False,
        export_lights=False,
    )
    kb = os.path.getsize(path) / 1024.0
    flag = "OVER BUDGET" if tris > TRI_BUDGET else "ok"
    node_count = len(bpy.context.scene.objects)
    line = (f"  {name+'.glb':20s} {tris:5d} tris  {node_count:3d} nodes  "
            f"{kb:7.1f}KB  {flag}")
    print(line)
    _log.append((name, tris, node_count, kb, flag))
    return tris


# ----------------------------------------------------------------- materials

def M():
    return {
        "iron": mat("Iron", (0.34, 0.36, 0.40), metallic=1.0, rough=0.42),
        "dark_iron": mat("DarkIron", (0.13, 0.14, 0.17), metallic=1.0, rough=0.55),
        "edge": mat("BladeEdge", (0.74, 0.78, 0.84), metallic=1.0, rough=0.18),
        "rune": mat("Rune", (0.55, 0.85, 1.0), metallic=0.0, rough=0.3,
                    emit=(0.45, 0.82, 1.0), emit_str=7.0),
        "leather": mat("Leather", (0.17, 0.10, 0.06), metallic=0.0, rough=0.86),
        "wood": mat("Wood", (0.25, 0.16, 0.09), metallic=0.0, rough=0.8),
        "skin": mat("Skin", (0.72, 0.52, 0.40), metallic=0.0, rough=0.72),
        "cloth": mat("Cloth", (0.32, 0.24, 0.18), metallic=0.0, rough=0.9),
        "hair": mat("Hair", (0.30, 0.20, 0.12), metallic=0.0, rough=0.85),
        "stone": mat("Stone", (0.44, 0.43, 0.41), metallic=0.0, rough=0.85),
        "rot_skin": mat("RotSkin", (0.42, 0.47, 0.42), metallic=0.0, rough=0.8),
        "bone": mat("Bone", (0.76, 0.73, 0.62), metallic=0.0, rough=0.7),
        "rag": mat("Rag", (0.20, 0.20, 0.17), metallic=0.0, rough=0.94),
        "rust": mat("Rust", (0.32, 0.18, 0.10), metallic=0.8, rough=0.8),
        "ember": mat("Ember", (1.0, 0.45, 0.12), metallic=0.0, rough=0.5,
                     emit=(1.0, 0.42, 0.10), emit_str=9.0),
    }


# ---------------------------------------------------------------------- AXE

# Bearded axe silhouette in the YZ plane: +Y toward the cutting edge, +Z up.
# The "beard" is the hook that drops below the haft line behind the edge.
AXE_PROFILE = [
    (0.000, 0.105), (0.052, 0.140), (0.150, 0.158), (0.252, 0.142),
    (0.320, 0.098), (0.352, 0.040), (0.356, -0.028), (0.332, -0.098),
    (0.268, -0.152), (0.186, -0.172), (0.108, -0.150), (0.052, -0.098),
    (0.000, -0.062),
]

RUNES = [
    [((0, -0.5), (0, 0.5)), ((0, 0.34), (0.40, 0.12)), ((0, 0.04), (0.40, -0.18))],
    [((-0.22, -0.5), (-0.22, 0.5)), ((-0.22, 0.5), (0.22, 0.14)),
     ((0.22, 0.14), (0.22, -0.5))],
    [((0, -0.5), (0, 0.5)), ((0, 0.30), (0.34, 0.0)), ((0.34, 0.0), (0, -0.30))],
    [((0, -0.5), (0, 0.5)), ((0, 0.5), (0.34, 0.18)), ((0, 0.14), (0.34, -0.16))],
    [((0, -0.5), (0, 0.5)), ((0, 0.5), (0.34, 0.20)), ((0.34, 0.20), (0, 0.02)),
     ((0, 0.02), (0.32, -0.5))],
    [((0, 0.5), (0.30, 0.0)), ((0.30, 0.0), (0, -0.5))],
    [((-0.22, -0.5), (-0.22, 0.5)), ((0.22, -0.5), (0.22, 0.5)),
     ((-0.22, 0.10), (0.22, -0.10))],
    [((0, -0.5), (0, 0.5))],
]


def axe_thickness(y):
    """Half-thickness of the head at distance y from the socket.

    Thick at the socket, knife-thin at the cutting edge -- this is what stops
    the axe from reading as a flat cardboard cutout in silhouette.
    """
    ymin = min(p[0] for p in AXE_PROFILE)
    ymax = max(p[0] for p in AXE_PROFILE)
    k = (y - ymin) / (ymax - ymin)
    k = k * k * (3 - 2 * k)  # smoothstep
    return 0.019 * (1.0 - 0.86 * k)


def build_axe(outdir):
    new_scene()
    m = M()
    root = empty("AxeRoot")

    # ---- head: profile face, extruded and tapered toward the edge
    bm = bmesh.new()
    verts = [bm.verts.new((0.0, y, z)) for (y, z) in AXE_PROFILE]
    face = bm.faces.new(verts)
    res = bmesh.ops.extrude_face_region(bm, geom=[face])
    new_v = [g for g in res["geom"] if isinstance(g, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, verts=new_v, vec=(1.0, 0, 0))
    for v in bm.verts:
        t = axe_thickness(v.co.y)
        v.co.x = t if v.co.x > 0.5 else -t
    bevel_all(bm, offset=0.005, segments=1)
    head = mesh_obj("AxeHead", bm, m["iron"], parent=root, location=(0, 0, 0.30))

    # ---- cutting edge highlight: a thin wedge laid over the bit
    bm = bmesh.new()
    edge_pts = AXE_PROFILE[4:8]
    for i in range(len(edge_pts) - 1):
        (y0, z0), (y1, z1) = edge_pts[i], edge_pts[i + 1]
        t0, t1 = axe_thickness(y0) * 1.05, axe_thickness(y1) * 1.05
        a = bm.verts.new((-t0, y0, z0))
        b = bm.verts.new((t0, y0, z0))
        c = bm.verts.new((t1, y1, z1))
        d = bm.verts.new((-t1, y1, z1))
        bm.faces.new([a, b, c, d])
    mesh_obj("AxeEdge", bm, m["edge"], parent=root, location=(0, 0, 0.30))

    # ---- runic glyphs, inlaid on both cheeks of the blade
    bm = bmesh.new()
    glyph_w = 0.030
    stroke = 0.0075
    for i, glyph in enumerate(RUNES):
        gy = 0.085 + (i % 4) * 0.062
        gz = 0.055 if i < 4 else -0.045
        surf = axe_thickness(gy) + 0.0022
        for sx in (surf, -surf):
            for (u0, v0), (u1, v1) in glyph:
                p0 = Vector((gy + u0 * glyph_w, gz + v0 * glyph_w))
                p1 = Vector((gy + u1 * glyph_w, gz + v1 * glyph_w))
                d = (p1 - p0)
                if d.length < 1e-6:
                    continue
                n = Vector((-d.y, d.x)).normalized() * (stroke / 2)
                q = [p0 + n, p1 + n, p1 - n, p0 - n]
                if sx < 0:
                    q = q[::-1]
                bm.faces.new([bm.verts.new((sx, p.x, p.y)) for p in q])
    mesh_obj("AxeRunes", bm, m["rune"], parent=root, location=(0, 0, 0.30))

    # ---- haft
    bm = bmesh.new()
    cyl(bm, (0, 0.012, -0.02), 0.0185, 0.62, segments=12, radius2=0.0155)
    haft = mesh_obj("AxeHaft", bm, m["wood"], parent=root)

    # ---- leather grip wrap: stacked rings, tightest at the choke
    bm = bmesh.new()
    for i in range(7):
        z = -0.28 + i * 0.047
        r = 0.0225 - i * 0.0008
        cyl(bm, (0, 0.012, z), r, 0.032, segments=12)
    mesh_obj("AxeGrip", bm, m["leather"], parent=root)

    # ---- socket collar where head meets haft, and the pommel
    bm = bmesh.new()
    cyl(bm, (0, 0.012, 0.255), 0.027, 0.055, segments=12)
    cyl(bm, (0, 0.012, 0.215), 0.023, 0.022, segments=12)
    mesh_obj("AxeCollar", bm, m["dark_iron"], parent=root)

    bm = bmesh.new()
    cyl(bm, (0, 0.012, -0.325), 0.026, 0.038, segments=12, radius2=0.020)
    mesh_obj("AxePommel", bm, m["dark_iron"], parent=root)

    # ---- attachment / FX anchors consumed by GDScript
    empty("GripPoint", root, (0, 0.012, -0.10))
    empty("SocketPoint", root, (0, 0.10, 0.36))    # particle emission socket
    empty("EdgePoint", root, (0, 0.355, 0.30))     # tip of the bit
    empty("EmbedPoint", root, (0, 0.30, 0.30))     # where it bites geometry

    return export("axe", outdir)


# ------------------------------------------------------------------ CHARACTERS

def part(name, parent, joint_local, length, w0, w1, d0, d1, material,
         axis=(0, 0, -1), bevel=0.008):
    """One rigid limb segment: origin ON the joint, geometry hanging off it."""
    bm = bmesh.new()
    taper_box(bm, (0, 0, 0), length, w0, w1, d0, d1, Vector(axis))
    if bevel:
        bevel_all(bm, offset=bevel, segments=1)
    return mesh_obj(name, bm, material, parent=parent, location=joint_local)


def build_player(outdir):
    new_scene()
    m = M()
    root = empty("PlayerRoot")
    hips = empty("Hips", root, (0, 0, 0.94))

    # torso
    bm = bmesh.new()
    taper_box(bm, (0, 0, 0), 0.20, 0.30, 0.34, 0.20, 0.21, Vector((0, 0, 1)))
    bevel_all(bm, 0.012)
    pelvis = mesh_obj("Pelvis", bm, m["cloth"], parent=hips)

    chest = empty("ChestPivot", hips, (0, 0, 0.20))
    bm = bmesh.new()
    taper_box(bm, (0, 0, 0), 0.30, 0.36, 0.44, 0.22, 0.24, Vector((0, 0, 1)))
    bevel_all(bm, 0.014)
    mesh_obj("Chest", bm, m["skin"], parent=chest)

    # leather chest strap + belt read as armour without extra silhouette cost
    bm = bmesh.new()
    cube(bm, (0.0, 0.0, 0.14), (0.40, 0.26, 0.055))
    cube(bm, (0.07, -0.10, 0.16), (0.09, 0.09, 0.30))
    bevel_all(bm, 0.008)
    mesh_obj("Harness", bm, m["leather"], parent=chest)

    bm = bmesh.new()
    cube(bm, (0, 0, 0.015), (0.33, 0.23, 0.05))
    bevel_all(bm, 0.008)
    mesh_obj("Belt", bm, m["leather"], parent=hips)

    # head + nordic beard
    neck = empty("NeckPivot", chest, (0, 0, 0.30))
    bm = bmesh.new()
    cube(bm, (0, 0, 0.035), (0.10, 0.10, 0.07))
    mesh_obj("Neck", bm, m["skin"], parent=neck)

    head_p = empty("HeadPivot", neck, (0, 0, 0.07))
    bm = bmesh.new()
    taper_box(bm, (0, 0, 0.0), 0.21, 0.19, 0.16, 0.20, 0.17, Vector((0, 0, 1)))
    bevel_all(bm, 0.022, segments=2)
    mesh_obj("Head", bm, m["skin"], parent=head_p)

    bm = bmesh.new()
    taper_box(bm, (0, 0.055, 0.085), 0.13, 0.17, 0.11, 0.11, 0.08,
              Vector((0, 0.25, -1)))
    bevel_all(bm, 0.012)
    mesh_obj("Beard", bm, m["hair"], parent=head_p)

    bm = bmesh.new()
    cube(bm, (0, -0.02, 0.175), (0.20, 0.20, 0.07))
    bevel_all(bm, 0.015)
    mesh_obj("Hair", bm, m["hair"], parent=head_p)

    # arms
    for s, tag in ((1, "R"), (-1, "L")):
        sh = empty(f"Shoulder_{tag}", chest, (0.20 * s, 0, 0.255))
        bm = bmesh.new()
        cube(bm, (0.03 * s, 0, -0.01), (0.14, 0.19, 0.12))
        bevel_all(bm, 0.016)
        mesh_obj(f"Pauldron_{tag}", bm, m["dark_iron"], parent=sh)

        ua = part(f"UpperArm_{tag}", sh, (0.035 * s, 0, -0.03), 0.28,
                  0.105, 0.088, 0.115, 0.095, m["skin"])
        fa = part(f"Forearm_{tag}", ua, (0, 0, -0.28), 0.26,
                  0.088, 0.070, 0.095, 0.075, m["skin"])
        bm = bmesh.new()
        cube(bm, (0, 0, -0.07), (0.10, 0.105, 0.11))
        bevel_all(bm, 0.012)
        mesh_obj(f"Bracer_{tag}", bm, m["leather"], parent=fa)
        hand = part(f"Hand_{tag}", fa, (0, 0, -0.26), 0.11,
                    0.070, 0.060, 0.090, 0.070, m["skin"], bevel=0.010)
        empty(f"WeaponSocket_{tag}", hand, (0, 0, -0.055))

    # legs
    for s, tag in ((1, "R"), (-1, "L")):
        th = part(f"Thigh_{tag}", hips, (0.105 * s, 0, -0.045), 0.44,
                  0.145, 0.115, 0.155, 0.125, m["cloth"])
        sh_ = part(f"Shin_{tag}", th, (0, 0, -0.44), 0.42,
                   0.115, 0.085, 0.125, 0.090, m["cloth"])
        bm = bmesh.new()
        cube(bm, (0, 0, -0.10), (0.125, 0.135, 0.16))
        bevel_all(bm, 0.012)
        mesh_obj(f"Greave_{tag}", bm, m["leather"], parent=sh_)
        bm = bmesh.new()
        cube(bm, (0, 0.035, -0.035), (0.115, 0.235, 0.07))
        bevel_all(bm, 0.014)
        mesh_obj(f"Foot_{tag}", bm, m["leather"], parent=sh_, location=(0, 0, -0.42))

    empty("CameraTarget", chest, (0, 0, 0.26))
    return export("player", outdir)


def build_draugr(outdir):
    new_scene()
    m = M()
    root = empty("DraugrRoot")
    hips = empty("Hips", root, (0, 0, 0.86))

    bm = bmesh.new()
    taper_box(bm, (0, 0, 0), 0.18, 0.25, 0.28, 0.17, 0.18, Vector((0, 0, 1)))
    bevel_all(bm, 0.010)
    mesh_obj("Pelvis", bm, m["rag"], parent=hips)

    # hunched spine: the chest pivot is pitched forward so it reads as undead
    chest = empty("ChestPivot", hips, (0, 0.035, 0.18))
    chest.rotation_euler = (math.radians(17.0), 0, 0)
    bm = bmesh.new()
    taper_box(bm, (0, 0, 0), 0.30, 0.30, 0.37, 0.19, 0.21, Vector((0, 0, 1)))
    bevel_all(bm, 0.012)
    mesh_obj("Chest", bm, m["rot_skin"], parent=chest)

    # exposed ribcage
    bm = bmesh.new()
    for i in range(4):
        z = 0.06 + i * 0.062
        w = 0.30 - i * 0.022
        cube(bm, (0, -0.085, z), (w, 0.045, 0.028))
    cube(bm, (0, -0.105, 0.16), (0.045, 0.030, 0.26))
    bevel_all(bm, 0.005)
    mesh_obj("Ribs", bm, m["bone"], parent=chest)

    bm = bmesh.new()
    cube(bm, (0.0, 0.02, 0.13), (0.34, 0.24, 0.07))
    cube(bm, (0.0, 0.02, 0.24), (0.30, 0.22, 0.05))
    bevel_all(bm, 0.008)
    mesh_obj("Rags", bm, m["rag"], parent=chest)

    neck = empty("NeckPivot", chest, (0, 0.012, 0.30))
    neck.rotation_euler = (math.radians(-13.0), 0, 0)
    bm = bmesh.new()
    cube(bm, (0, 0, 0.03), (0.075, 0.075, 0.06))
    mesh_obj("Neck", bm, m["bone"], parent=neck)

    head_p = empty("HeadPivot", neck, (0, 0, 0.06))
    bm = bmesh.new()
    taper_box(bm, (0, 0, 0), 0.19, 0.165, 0.145, 0.185, 0.155, Vector((0, 0, 1)))
    bevel_all(bm, 0.018, segments=2)
    mesh_obj("Head", bm, m["rot_skin"], parent=head_p)
    # sunken eye sockets + jaw
    bm = bmesh.new()
    for sx in (0.042, -0.042):
        cube(bm, (sx, 0.072, 0.115), (0.040, 0.030, 0.030))
    cube(bm, (0, 0.055, 0.032), (0.105, 0.075, 0.045))
    bevel_all(bm, 0.004)
    mesh_obj("Face", bm, m["dark_iron"], parent=head_p)

    # gaunt arms, longer than human proportion
    for s, tag in ((1, "R"), (-1, "L")):
        sh = empty(f"Shoulder_{tag}", chest, (0.175 * s, 0, 0.245))
        bm = bmesh.new()
        cube(bm, (0.02 * s, 0, -0.01), (0.10, 0.13, 0.10))
        # shoulder spike
        taper_box(bm, (0.03 * s, -0.02, 0.02), 0.11, 0.05, 0.012, 0.05, 0.012,
                  Vector((0.35 * s, -0.2, 1)))
        bevel_all(bm, 0.008)
        mesh_obj(f"Pauldron_{tag}", bm, m["rust"], parent=sh)

        ua = part(f"UpperArm_{tag}", sh, (0.03 * s, 0, -0.03), 0.30,
                  0.080, 0.062, 0.085, 0.066, m["rot_skin"])
        fa = part(f"Forearm_{tag}", ua, (0, 0, -0.30), 0.29,
                  0.062, 0.048, 0.066, 0.052, m["rot_skin"])
        hand = part(f"Hand_{tag}", fa, (0, 0, -0.29), 0.12,
                    0.052, 0.042, 0.070, 0.050, m["bone"], bevel=0.007)
        # claws
        bm = bmesh.new()
        for k in (-1, 0, 1):
            taper_box(bm, (k * 0.020, 0.012, -0.10), 0.065, 0.016, 0.004,
                      0.016, 0.004, Vector((k * 0.15, 0.25, -1)))
        bevel_all(bm, 0.003)
        mesh_obj(f"Claws_{tag}", bm, m["bone"], parent=hand)
        empty(f"WeaponSocket_{tag}", hand, (0, 0, -0.06))

    for s, tag in ((1, "R"), (-1, "L")):
        th = part(f"Thigh_{tag}", hips, (0.095 * s, 0, -0.04), 0.40,
                  0.115, 0.090, 0.125, 0.100, m["rag"])
        sh_ = part(f"Shin_{tag}", th, (0, 0, -0.40), 0.40,
                   0.090, 0.062, 0.100, 0.070, m["rot_skin"])
        bm = bmesh.new()
        cube(bm, (0, 0.030, -0.030), (0.100, 0.205, 0.060))
        bevel_all(bm, 0.010)
        mesh_obj(f"Foot_{tag}", bm, m["bone"], parent=sh_, location=(0, 0, -0.40))

    empty("HitTarget", chest, (0, 0, 0.16))
    return export("draugr", outdir)


# ---------------------------------------------------------------------- ARENA

def build_pillar(outdir, broken=False):
    new_scene()
    m = M()
    h = 1.75 if broken else 3.30
    bm = bmesh.new()
    cyl(bm, (0, 0, 0.10), 0.46, 0.20, segments=12)          # plinth
    cyl(bm, (0, 0, 0.26), 0.38, 0.14, segments=12)
    cyl(bm, (0, 0, 0.26 + h / 2), 0.30, h, segments=12, radius2=0.265)
    if not broken:
        cyl(bm, (0, 0, 0.26 + h + 0.08), 0.40, 0.18, segments=12, radius2=0.34)
        cube(bm, (0, 0, 0.26 + h + 0.22), (0.86, 0.86, 0.14))
    # shallow flutes carved around the shaft
    for i in range(12):
        a = i * math.tau / 12
        cube(bm, (math.cos(a) * 0.295, math.sin(a) * 0.295, 0.26 + h / 2),
             (0.055, 0.055, h * 0.88))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = mesh_obj("Pillar", bm, m["stone"])

    if broken:
        # jagged crown: push the top ring of verts to uneven heights
        import random
        random.seed(7)
        top = 0.26 + h
        for v in ob.data.vertices:
            if v.co.z > top - 0.35:
                v.co.z -= random.uniform(0.0, 0.42)
                v.co.x += random.uniform(-0.05, 0.05)
                v.co.y += random.uniform(-0.05, 0.05)
    return export("pillar_broken" if broken else "pillar", outdir)


def build_slab(outdir):
    new_scene()
    m = M()
    import random
    random.seed(21)
    bm = bmesh.new()
    cube(bm, (0, 0, -0.06), (3.0, 3.0, 0.12))
    # cracked surface: irregular tiles with small height jitter
    for gx in range(3):
        for gy in range(3):
            x = (gx - 1) * 0.98
            y = (gy - 1) * 0.98
            bm2 = bm
            cube(bm2, (x + random.uniform(-0.03, 0.03),
                       y + random.uniform(-0.03, 0.03),
                       random.uniform(-0.012, 0.012)),
                 (0.92 + random.uniform(-0.05, 0.05),
                  0.92 + random.uniform(-0.05, 0.05), 0.09))
    bevel_all(bm, 0.010)
    mesh_obj("Slab", bm, m["stone"])
    return export("slab", outdir)


def build_wall(outdir):
    new_scene()
    m = M()
    bm = bmesh.new()
    cube(bm, (0, 0, 1.05), (4.0, 0.55, 2.10))
    cube(bm, (0, 0, 0.10), (4.3, 0.75, 0.20))
    for i in range(5):
        cube(bm, (-1.6 + i * 0.80, 0, 2.28), (0.52, 0.60, 0.40))
    # block courses scored into the face
    for row in range(4):
        z = 0.35 + row * 0.44
        off = 0.0 if row % 2 == 0 else 0.33
        for i in range(6):
            cube(bm, (-1.75 + off + i * 0.66, 0.275, z), (0.60, 0.05, 0.38))
    bevel_all(bm, 0.012)
    mesh_obj("Wall", bm, m["stone"])
    return export("wall", outdir)


def build_brazier(outdir):
    new_scene()
    m = M()
    root = empty("BrazierRoot")
    bm = bmesh.new()
    cyl(bm, (0, 0, 0.62), 0.34, 0.20, segments=12, radius2=0.22)
    cyl(bm, (0, 0, 0.74), 0.30, 0.05, segments=12)
    for i in range(3):
        a = i * math.tau / 3
        taper_box(bm, (math.cos(a) * 0.19, math.sin(a) * 0.19, 0.56), 0.56,
                  0.07, 0.10, 0.07, 0.10,
                  Vector((math.cos(a) * 0.45, math.sin(a) * 0.45, -1)))
    cyl(bm, (0, 0, 0.05), 0.40, 0.10, segments=12)
    bevel_all(bm, 0.008)
    mesh_obj("Brazier", bm, m["dark_iron"], parent=root)

    bm = bmesh.new()
    cyl(bm, (0, 0, 0.70), 0.24, 0.12, segments=10, radius2=0.14)
    mesh_obj("Coals", bm, m["ember"], parent=root)
    empty("FirePoint", root, (0, 0, 0.80))
    return export("brazier", outdir)


# ------------------------------------------------------------------------ main

def main():
    outdir = argv_outdir()
    print(f"\n=== MIDGARD FURY asset build -> {outdir} ===")
    build_axe(outdir)
    build_player(outdir)
    build_draugr(outdir)
    build_pillar(outdir, broken=False)
    build_pillar(outdir, broken=True)
    build_slab(outdir)
    build_wall(outdir)
    build_brazier(outdir)

    print("\n--- polygon report ---")
    total = 0
    over = []
    for name, tris, nodes, kb, flag in _log:
        total += tris
        if flag != "ok":
            over.append(name)
        print(f"  {name:16s} {tris:5d} tris  {nodes:3d} nodes  {kb:7.1f}KB")
    print(f"  {'TOTAL':16s} {total:5d} tris")
    if over:
        print(f"!! OVER {TRI_BUDGET} TRI BUDGET: {', '.join(over)}")
    else:
        print(f"All assets within {TRI_BUDGET} tri budget.")


if __name__ == "__main__":
    main()
