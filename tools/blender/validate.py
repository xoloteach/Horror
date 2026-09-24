"""Independent GLB validation: parse binary glTF, count tris, check nodes/bones/materials."""
import json
import os
import struct
import sys

MODELS = os.path.expanduser("~/workspace/horror-game/assets/models")

EXPECTED_BONES = ["Hips", "Spine", "Chest", "Head",
                  "UpperArm.L", "ForeArm.L", "Hand.L",
                  "UpperArm.R", "ForeArm.R", "Hand.R",
                  "Thigh.L", "Shin.L", "Thigh.R", "Shin.R"]


def load_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, version, length = struct.unpack("<4sII", data[:12])
    assert magic == b"glTF", f"{path}: bad magic {magic}"
    assert version == 2, f"{path}: bad version {version}"
    off = 12
    json_doc = None
    while off < len(data):
        clen, ctype = struct.unpack("<II", data[off:off + 8])
        chunk = data[off + 8:off + 8 + clen]
        if ctype == 0x4E4F534A:  # JSON
            json_doc = json.loads(chunk.decode("utf-8"))
        off += 8 + clen
    assert json_doc is not None, f"{path}: no JSON chunk"
    return json_doc


def tri_count(doc):
    total = 0
    for mesh in doc.get("meshes", []):
        for prim in mesh["primitives"]:
            if "indices" in prim:
                acc = doc["accessors"][prim["indices"]]
                total += acc["count"] // 3
            else:
                # non-indexed: count POSITION
                for aname, aidx in prim["attributes"].items():
                    if aname == "POSITION":
                        total += doc["accessors"][aidx]["count"] // 3
    return total


def node_names(doc):
    return [n.get("name", "") for n in doc.get("nodes", [])]


def check(path, expect_nodes=(), expect_bones=False, expect_images=False):
    doc = load_glb(path)
    tris = tri_count(doc)
    names = node_names(doc)
    mats = [m.get("name", "") for m in doc.get("materials", [])]
    ok = True
    print(f"--- {os.path.basename(path)}: {os.path.getsize(path)} bytes, {tris} tris, "
          f"{len(doc.get('meshes', []))} meshes, {len(names)} nodes")
    for en in expect_nodes:
        found = en in names
        print(f"    node '{en}': {'OK' if found else 'MISSING'}")
        ok &= found
    if expect_bones:
        for b in EXPECTED_BONES:
            found = b in names
            if not found:
                print(f"    bone '{b}': MISSING")
                ok = False
        nskins = len(doc.get("skins", []))
        print(f"    all 14 bones present: OK; skins: {nskins}")
    if expect_images:
        nimgs = len(doc.get("images", []))
        print(f"    embedded images: {nimgs}")
        ok &= nimgs > 0
    print(f"    materials: {mats}")
    assert tris < 4500, "tri budget exceeded"
    assert ok, "validation failed"
    return tris


def main():
    results = {}
    results["slab.glb"] = check(f"{MODELS}/slab.glb", expect_images=True)
    results["wall.glb"] = check(f"{MODELS}/wall.glb", expect_images=True)
    results["pillar.glb"] = check(f"{MODELS}/pillar.glb", expect_images=True)
    results["axe.glb"] = check(f"{MODELS}/axe.glb", expect_nodes=("Socket_Emit",),
                               expect_images=True)
    results["player.glb"] = check(f"{MODELS}/player.glb", expect_bones=True)
    results["draugr.glb"] = check(f"{MODELS}/draugr.glb", expect_bones=True)
    print("\nALL VALIDATIONS PASSED")
    for k, v in results.items():
        print(f"  {k}: {v} tris")
    return 0


if __name__ == "__main__":
    sys.exit(main())
