#!/usr/bin/env python3
"""Inspect exported GLB files: node hierarchy, bounds, materials.

Validates that the Blender pivot hierarchies and socket empties actually
survived the glTF round-trip, and that assets are at believable world scale.

Usage: python3 tools/inspect_glb.py assets/models [--tree name]
"""
import json
import os
import struct
import sys


def read_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, version, _ = struct.unpack("<III", data[:12])
    assert magic == 0x46546C67, f"{path}: not a GLB"
    off = 12
    gltf = None
    bin_chunk = None
    while off < len(data):
        clen, ctype = struct.unpack("<II", data[off:off + 8])
        chunk = data[off + 8: off + 8 + clen]
        if ctype == 0x4E4F534A:
            gltf = json.loads(chunk.decode("utf-8"))
        elif ctype == 0x004E4942:
            bin_chunk = chunk
        off += 8 + clen + ((4 - clen % 4) % 4 if clen % 4 else 0)
    return gltf, bin_chunk


def _mat_of(n):
    """4x4 (row-major list of lists) for a glTF node's local transform."""
    import math
    if "matrix" in n:
        m = n["matrix"]  # column-major
        return [[m[0], m[4], m[8], m[12]],
                [m[1], m[5], m[9], m[13]],
                [m[2], m[6], m[10], m[14]],
                [m[3], m[7], m[11], m[15]]]
    t = n.get("translation", [0, 0, 0])
    r = n.get("rotation", [0, 0, 0, 1])  # xyzw
    s = n.get("scale", [1, 1, 1])
    x, y, z, w = r
    rm = [
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ]
    out = [[rm[i][j] * s[j] for j in range(3)] + [t[i]] for i in range(3)]
    out.append([0, 0, 0, 1])
    return out


def _mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)]
            for i in range(4)]


def _xf(m, p):
    return [sum(m[i][j] * p[j] for j in range(3)) + m[i][3] for i in range(3)]


def bounds(g):
    """True world-space bounds, accumulating node transforms down the scene tree."""
    lo = [1e9] * 3
    hi = [-1e9] * 3
    ident = [[1 if i == j else 0 for j in range(4)] for i in range(4)]

    def rec(idx, parent):
        nonlocal lo, hi
        n = g["nodes"][idx]
        world = _mul(parent, _mat_of(n))
        if "mesh" in n:
            for p in g["meshes"][n["mesh"]].get("primitives", []):
                acc = g["accessors"][p["attributes"]["POSITION"]]
                if "min" not in acc:
                    continue
                mn, mx = acc["min"], acc["max"]
                # transform all 8 corners of the local AABB
                for cx in (mn[0], mx[0]):
                    for cy in (mn[1], mx[1]):
                        for cz in (mn[2], mx[2]):
                            w = _xf(world, [cx, cy, cz])
                            lo = [min(a, b) for a, b in zip(lo, w)]
                            hi = [max(a, b) for a, b in zip(hi, w)]
        for c in n.get("children", []):
            rec(c, world)

    for r in g["scenes"][g.get("scene", 0)]["nodes"]:
        rec(r, ident)
    return lo, hi


def walk(g, idx, depth, out, prefix=""):
    n = g["nodes"][idx]
    name = n.get("name", f"<{idx}>")
    kind = "mesh" if "mesh" in n else "node"
    t = n.get("translation")
    tt = f" t=({t[0]:+.3f},{t[1]:+.3f},{t[2]:+.3f})" if t else ""
    out.append(f"{'  ' * depth}{name} [{kind}]{tt}")
    for c in n.get("children", []):
        walk(g, c, depth + 1, out)


def main():
    d = sys.argv[1] if len(sys.argv) > 1 else "assets/models"
    tree_for = None
    if "--tree" in sys.argv:
        tree_for = sys.argv[sys.argv.index("--tree") + 1]

    files = sorted(f for f in os.listdir(d) if f.endswith(".glb"))
    print(f"{'file':20s} {'nodes':>5s} {'meshes':>6s} {'mats':>4s} "
          f"{'sizeX':>6s} {'sizeY':>6s} {'sizeZ':>6s}")
    for fn in files:
        g, _ = read_glb(os.path.join(d, fn))
        lo, hi = bounds(g)
        sx, sy, sz = (hi[i] - lo[i] for i in range(3))
        print(f"{fn:20s} {len(g.get('nodes',[])):5d} {len(g.get('meshes',[])):6d} "
              f"{len(g.get('materials',[])):4d} {sx:6.2f} {sy:6.2f} {sz:6.2f}")

    if tree_for:
        path = os.path.join(d, tree_for if tree_for.endswith(".glb")
                            else tree_for + ".glb")
        g, _ = read_glb(path)
        print(f"\n--- hierarchy: {os.path.basename(path)} ---")
        roots = g["scenes"][g.get("scene", 0)]["nodes"]
        out = []
        for r in roots:
            walk(g, r, 0, out)
        print("\n".join(out))
        print(f"\nmaterials: {[m.get('name') for m in g.get('materials', [])]}")


if __name__ == "__main__":
    main()
