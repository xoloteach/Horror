#!/usr/bin/env python3
"""Fail-fast budget and provenance gate for production assets."""
from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).parent))
from inspect_glb import read_glb  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
PROD = ROOT / "assets" / "production"
LOCK = ROOT / "assets" / "THIRD_PARTY.lock.json"

MAX_RUNTIME_BYTES = 40 * 1024 * 1024
MAX_ACTOR_TRIS = 8000
MAX_ACTOR_TEXTURE_SIDE = 1024
MAX_VFX_SIDE = 256
MIN_ACTOR_ANIMS = 70
MIN_ENV_MODELS = 70


def actor_stats(path: Path) -> dict:
    g, _ = read_glb(str(path))
    tris = 0
    for mesh in g.get("meshes", []):
        for primitive in mesh.get("primitives", []):
            if "indices" in primitive:
                tris += g["accessors"][primitive["indices"]]["count"] // 3
    return {
        "tris": tris,
        "animations": len(g.get("animations", [])),
        "joints": max((len(s.get("joints", [])) for s in g.get("skins", [])), default=0),
        "materials": len(g.get("materials", [])),
        "bytes": path.stat().st_size,
    }


def fail(message: str, failures: list[str]) -> None:
    failures.append(message)
    print("FAIL", message)


def main() -> int:
    failures: list[str] = []
    files = [p for p in PROD.rglob("*") if p.is_file() and not p.name.endswith(".import")]
    runtime_bytes = sum(p.stat().st_size for p in files)
    print(f"Runtime source payload: {runtime_bytes / 1048576:.2f} MiB / {MAX_RUNTIME_BYTES / 1048576:.0f} MiB")
    if runtime_bytes > MAX_RUNTIME_BYTES:
        fail("production source payload exceeds 40 MiB", failures)

    forbidden = [p for p in files if p.suffix.lower() in {".zip", ".7z", ".fbx", ".obj", ".blend", ".psd"}]
    if forbidden:
        fail("source/archive formats leaked into runtime: " + ", ".join(map(str, forbidden)), failures)

    actors = sorted((PROD / "actors").glob("*.glb"))
    print("\nActors:")
    for actor in actors:
        s = actor_stats(actor)
        print(f"  {actor.name:24s} {s['tris']:5d} tris  {s['joints']:2d} bones  "
              f"{s['animations']:2d} clips  {s['materials']} mats  {s['bytes']/1048576:.2f} MiB")
        if s["tris"] > MAX_ACTOR_TRIS:
            fail(f"{actor.name} exceeds {MAX_ACTOR_TRIS} triangles", failures)
        if s["animations"] < MIN_ACTOR_ANIMS:
            fail(f"{actor.name} has only {s['animations']} animations", failures)
        if s["joints"] < 30:
            fail(f"{actor.name} is missing a production humanoid skeleton", failures)

    env_models = list((PROD / "environment").rglob("*.glb"))
    print(f"\nEnvironment modules: {len(env_models)} / minimum {MIN_ENV_MODELS}")
    if len(env_models) < MIN_ENV_MODELS:
        fail("insufficient environment module variety", failures)

    print("\nTexture dimensions:")
    for path in sorted(PROD.rglob("*.png")):
        with Image.open(path) as im:
            limit = MAX_VFX_SIDE if path.parent.name in {"vfx", "decals"} else MAX_ACTOR_TEXTURE_SIDE
            if max(im.size) > limit:
                fail(f"{path.relative_to(ROOT)} is {im.size}, limit {limit}", failures)
    print("  all VFX/decals <=256px; UI/shared atlases <=1024px")

    # Verify every external URI used by the accessory glTFs resolves.
    for gltf_path in (PROD / "weapons").glob("*.gltf"):
        gltf = json.loads(gltf_path.read_text())
        uris = [b.get("uri", "") for b in gltf.get("buffers", [])]
        uris += [i.get("uri", "") for i in gltf.get("images", [])]
        for uri in uris:
            if uri and not (gltf_path.parent / uri).exists():
                fail(f"unresolved URI {uri} in {gltf_path.name}", failures)

    lock = json.loads(LOCK.read_text())
    if len(lock.get("assets", [])) != 25:
        fail("provenance lock must contain all 25 verified source downloads", failures)
    if not (ROOT / "assets" / "THIRD_PARTY.md").exists():
        fail("human-readable third-party manifest missing", failures)
    for name in ("OFL-Cinzel.txt", "OFL-AlegreyaSans.txt", "OFL-NotoSansRunic.txt"):
        if not (ROOT / "LICENSES" / name).exists():
            fail(f"font license missing: {name}", failures)

    print(f"\n{'PASS' if not failures else 'FAILED'}: {len(files)} curated files, "
          f"{len(actors)} animated actors, {len(env_models)} environment modules")
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
