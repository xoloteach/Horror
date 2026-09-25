#!/usr/bin/env python3
"""Build the curated runtime asset library from verified source archives.

Only files referenced by the production game are extracted. This keeps the Web
payload small and prevents duplicate FBX/OBJ/source formats from entering Godot's
import scan. PNG effects are downsampled to 256px and UI/icons are kept at their
native 1x/2x authored sizes.
"""
from __future__ import annotations

import json
import shutil
import zipfile
from pathlib import Path
from typing import Iterable

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT.parent / "asset-cache"
OUT = ROOT / "assets" / "production"
LOCK = ROOT / "assets" / "THIRD_PARTY.lock.json"
LICENSES = ROOT / "LICENSES"


def fresh_dir(path: Path) -> None:
    if path.exists():
        shutil.rmtree(path)
    path.mkdir(parents=True)


def choose_member(z: zipfile.ZipFile, basename: str, contains: str = "") -> str:
    hits = [n for n in z.namelist()
            if not n.endswith("/")
            and Path(n).name == basename
            and "__MACOSX" not in n
            and (not contains or contains in n)]
    if len(hits) != 1:
        raise RuntimeError(
            f"Expected one {basename!r} containing {contains!r}, got {hits}")
    return hits[0]


def extract_one(archive: str, basename: str, dest: Path,
                contains: str = "") -> Path:
    with zipfile.ZipFile(CACHE / archive) as z:
        member = choose_member(z, basename, contains)
        dest.parent.mkdir(parents=True, exist_ok=True)
        with z.open(member) as src, dest.open("wb") as dst:
            shutil.copyfileobj(src, dst)
    return dest


def extract_many(archive: str, basenames: Iterable[str], dest_dir: Path,
                 contains: str = "") -> None:
    for name in basenames:
        extract_one(archive, name, dest_dir / name, contains)


def copy_cache(name: str, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(CACHE / name, dest)


def downsample(src: Path, max_side: int = 256) -> None:
    with Image.open(src) as im:
        im.load()
        if max(im.size) <= max_side:
            return
        scale = max_side / max(im.size)
        size = (max(1, round(im.width * scale)), max(1, round(im.height * scale)))
        im = im.resize(size, Image.Resampling.LANCZOS)
        im.save(src, optimize=True)


def main() -> None:
    lock = json.loads(LOCK.read_text())
    by_file = {a["file"]: a for a in lock["assets"]}
    missing = [name for name in by_file if not (CACHE / name).exists()]
    if missing:
        raise SystemExit("Missing cache files; run acquire_assets.py: " + ", ".join(missing))

    fresh_dir(OUT)
    LICENSES.mkdir(exist_ok=True)

    # ---------------------------------------------------------------- actors
    actors = OUT / "actors"
    extract_many("kaykit_adventurers.zip", [
        "Barbarian.glb", "Knight.glb",
    ], actors)
    extract_many("kaykit_skeletons.zip", [
        "Skeleton_Warrior.glb", "Skeleton_Mage.glb",
        "Skeleton_Rogue.glb", "Skeleton_Minion.glb",
    ], actors)

    # --------------------------------------------------------------- weapons
    # KayKit accessories are external-buffer glTFs, so retain their original
    # basename triplets. The barbarian atlas is shared by both axe variants.
    weapons = OUT / "weapons"
    extract_many("kaykit_adventurers.zip", [
        "axe_1handed.gltf", "axe_1handed.bin",
        "axe_2handed.gltf", "axe_2handed.bin",
        "barbarian_texture.png", "shield_round_barbarian.gltf",
        "shield_round_barbarian.bin",
    ], weapons, "/Assets/gltf/")
    # shield shares the same atlas

    # Skeleton weapons share one external texture atlas.
    extract_many("kaykit_skeletons.zip", [
        "Skeleton_Axe.gltf", "Skeleton_Axe.bin",
        "Skeleton_Blade.gltf", "Skeleton_Blade.bin",
        "Skeleton_Staff.gltf", "Skeleton_Staff.bin",
        "skeleton_texture.png",
    ], weapons, "/Assets/gltf/")

    # ------------------------------------------------------------ environment
    dungeon = OUT / "environment" / "dungeon"
    extract_many("kaykit_dungeon.zip", [
        "floor_tile_large.gltf.glb", "floor_tile_large_rocks.gltf.glb",
        "floor_tile_small_broken_A.gltf.glb", "floor_tile_small_broken_B.gltf.glb",
        "floor_dirt_large_rocky.gltf.glb", "floor_dirt_small_weeds.gltf.glb",
        "wall.gltf.glb", "wall_broken.gltf.glb", "wall_cracked.gltf.glb",
        "wall_arched.gltf.glb", "wall_archedwindow_open.gltf.glb",
        "wall_doorway.glb", "wall_corner.gltf.glb", "wall_endcap.gltf.glb",
        "wall_half.gltf.glb", "wall_pillar.gltf.glb",
        "column.gltf.glb", "pillar_decorated.gltf.glb",
        "rubble_half.gltf.glb", "rubble_large.gltf.glb",
        "stairs_wide.gltf.glb", "torch_lit.gltf.glb", "torch_mounted.gltf.glb",
        "banner_patternC_red.gltf.glb", "banner_triple_red.gltf.glb",
        "barrel_large_decorated.gltf.glb", "barrel_small_stack.gltf.glb",
        "crates_stacked.gltf.glb", "table_long_broken.gltf.glb",
        "sword_shield_broken.gltf.glb", "chest.glb", "chest_gold.glb",
    ], dungeon)

    castle = OUT / "environment" / "castle"
    extract_many("kenney_castle.zip", [
        "gate.glb", "metal-gate.glb", "rocks-large.glb", "rocks-small.glb",
        "siege-ballista-demolished.glb", "siege-catapult-demolished.glb",
        "tower-base.glb", "tower-square-mid-windows.glb", "tower-top.glb",
        "wall.glb", "wall-half.glb", "wall-corner.glb", "wall-pillar.glb",
        "flag-banner-long.glb", "flag-pennant.glb",
    ], castle)
    extract_one("kenney_castle.zip", "colormap.png",
                castle / "Textures" / "colormap.png", "Models/GLB format/")

    graveyard = OUT / "environment" / "graveyard"
    extract_many("kenney_graveyard.zip", [
        "altar-stone.glb", "coffin-old.glb", "column-large.glb",
        "crypt-a.glb", "crypt-b.glb", "crypt-large.glb", "crypt-small.glb",
        "debris.glb", "fire-basket.glb", "gravestone-bevel.glb",
        "gravestone-broken.glb", "gravestone-debris.glb",
        "gravestone-decorative.glb", "gravestone-round.glb",
        "pillar-obelisk.glb", "pine-crooked.glb", "pine-fall.glb",
        "rocks-tall.glb", "stone-wall-damaged.glb", "trunk-long.glb",
    ], graveyard)
    extract_one("kenney_graveyard.zip", "colormap.png",
                graveyard / "Textures" / "colormap.png", "Models/GLB format/")

    nature = OUT / "environment" / "nature"
    extract_many("kenney_nature.zip", [
        "cliff_blockHalf_rock.glb", "cliff_blockSlope_rock.glb",
        "cliff_cornerLarge_rock.glb", "cliff_large_rock.glb",
        "rock_largeA.glb", "rock_largeB.glb", "rock_largeC.glb",
        "rock_largeD.glb", "rock_smallA.glb", "rock_smallB.glb",
        "rock_smallFlatA.glb", "rock_tallA.glb", "rock_tallC.glb",
        "stump_old.glb", "tree_pineTallA.glb", "tree_pineTallB.glb",
        "tree_pineTallC.glb", "tree_pineSmallA.glb",
    ], nature)

    # -------------------------------------------------------------------- VFX
    vfx = OUT / "vfx"
    particle_names = [
        "flame_02.png", "flame_05.png", "smoke_04.png", "smoke_07.png",
        "spark_02.png", "spark_05.png", "slash_02.png", "slash_04.png",
        "trace_03.png", "magic_03.png", "light_02.png", "dirt_02.png",
        "scorch_02.png", "circle_03.png",
    ]
    extract_many("kenney_particles.zip", particle_names, vfx,
                 "PNG (Transparent)/")
    for path in vfx.glob("*.png"):
        downsample(path, 256)

    decals = OUT / "decals"
    for i in (2, 7, 13, 21, 31):
        name = f"splat{i:02d}.png"
        extract_one("kenney_splats.zip", name, decals / name, "PNG/Default")
        downsample(decals / name, 256)

    # --------------------------------------------------------------------- UI
    ui = OUT / "ui"
    extract_many("kenney_ui_adventure.zip", [
        "panel_grey_bolts_dark.png", "panel_grey_dark.png",
        "panel_grey_blue.png", "panel_grey_red.png",
        "panel_border_grey_detail.png", "button_grey.png", "button_red.png",
        "banner_hanging.png", "progress_red.png", "progress_red_border.png",
        "progress_blue.png", "progress_blue_border.png",
        "progress_white.png", "progress_transparent.png",
        "checkbox_grey_checked.png", "checkbox_grey_empty.png",
    ], ui, "PNG/Double")
    extract_many("kenney_ui_borders.zip", [
        "panel-border-015.png", "panel-border-023.png", "panel-010.png",
        "panel-transparent-border-012.png", "divider-003.png", "divider-fade-004.png",
    ], ui, "PNG/Double")

    icons = ui / "icons"
    extract_many("kenney_icons.zip", [
        "gamepad.png", "mouse.png", "pause.png", "gear.png",
        "audioOn.png", "audioOff.png", "musicOn.png", "musicOff.png",
        "return.png", "cross.png", "checkmark.png", "home.png",
        "joystick.png", "buttonA.png", "buttonB.png", "buttonX.png", "buttonY.png",
    ], icons, "PNG/White/2x")

    fonts = OUT / "fonts"
    for name in ("Cinzel-Variable.ttf", "AlegreyaSans-Regular.ttf",
                 "NotoSansRunic-Regular.ttf"):
        copy_cache(name, fonts / name)
    for name in ("OFL-Cinzel.txt", "OFL-AlegreyaSans.txt", "OFL-NotoSansRunic.txt"):
        copy_cache(name, LICENSES / name)

    # ------------------------------------------------------------------ audio
    audio = OUT / "audio"
    extract_many("kenney_rpg_audio.zip", [
        "chop.ogg", "cloth1.ogg", "cloth2.ogg", "cloth3.ogg", "cloth4.ogg",
        "drawKnife1.ogg", "drawKnife2.ogg", "drawKnife3.ogg",
        "knifeSlice.ogg", "knifeSlice2.ogg", "metalClick.ogg", "metalLatch.ogg",
    ], audio / "foley")
    extract_many("kenney_impacts.zip", [
        *(f"footstep_snow_{i:03d}.ogg" for i in range(5)),
        *(f"footstep_concrete_{i:03d}.ogg" for i in range(5)),
        *(f"impactMetal_heavy_{i:03d}.ogg" for i in range(5)),
        *(f"impactMining_{i:03d}.ogg" for i in range(5)),
        *(f"impactWood_heavy_{i:03d}.ogg" for i in range(5)),
        *(f"impactPunch_heavy_{i:03d}.ogg" for i in range(5)),
        *(f"impactSoft_heavy_{i:03d}.ogg" for i in range(5)),
    ], audio / "impacts")
    extract_many("rubberduck_rpg_sfx.zip", [
        "blade_01.ogg", "blade_02.ogg", "blade_03.ogg",
        "creature_die_01.ogg", "creature_hurt_01.ogg", "creature_hurt_02.ogg",
        "creature_monster_01.ogg", "creature_monster_02.ogg",
        "creature_monster_03.ogg", "creature_monster_04.ogg",
        "creature_roar_01.ogg", "creature_roar_02.ogg", "creature_roar_03.ogg",
        "item_stone_01.ogg", "item_stone_02.ogg", "item_stone_03.ogg",
        "item_stone_04.ogg", "metal_01.ogg", "metal_02.ogg", "metal_03.ogg",
        "spell_01.ogg", "spell_02.ogg", "spell_fire_01.ogg", "spell_fire_02.ogg",
    ], audio / "creatures")
    extract_many("swishes.zip", [f"swish-{i}.wav" for i in range(1, 14)],
                 audio / "swishes", "swishes/")
    copy_cache("cynicbattleloop.ogg", audio / "music" / "battle.ogg")
    copy_cache("viking-march.ogg", audio / "music" / "title.ogg")
    copy_cache("winter-wind-short.mp3", audio / "ambience" / "winter_wind.mp3")
    copy_cache("fire-1.ogg", audio / "ambience" / "fire_crackle.ogg")

    # -------------------------------------------------------------- licenses
    extract_one("kaykit_adventurers.zip", "LICENSE.txt",
                LICENSES / "KayKit-Adventurers-CC0.txt")
    extract_one("kaykit_skeletons.zip", "LICENSE.txt",
                LICENSES / "KayKit-Skeletons-CC0.txt")
    extract_one("kaykit_dungeon.zip", "LICENSE.txt",
                LICENSES / "KayKit-Dungeon-CC0.txt")

    selected_ids = {
        "kaykit_adventurers_1_0", "kaykit_skeletons_1_0",
        "kaykit_dungeon_remastered_1_0", "kenney_castle_2_0",
        "kenney_graveyard_5_0", "kenney_nature_1_0",
        "kenney_particle_pack", "kenney_splat_pack", "kenney_ui_adventure",
        "kenney_fantasy_ui_borders", "kenney_game_icons", "kenney_rpg_audio",
        "kenney_impact_sounds", "rubberduck_80_rpg_sfx",
        "artisticdude_swishes", "cynic_battle_loop", "viking_march",
        "winter_wind", "fire_crackle", "google_font_cinzel",
        "google_font_alegreya_sans", "google_font_noto_runic",
    }
    selected = [a for a in lock["assets"] if a["id"] in selected_ids]
    lines = [
        "# Third-party production assets",
        "",
        "Every source archive is downloaded sequentially and SHA-256 verified by",
        "`tools/acquire_assets.py`. `tools/ingest_assets.py` extracts only the files",
        "used by the runtime. No NC, ND, marketplace-only, or unclear licenses are used.",
        "",
        "| Asset | Creator | License | Source | SHA-256 |",
        "|---|---|---|---|---|",
    ]
    for a in selected:
        lines.append(
            f"| {a['id']} | {a['creator']} | {a['license']} | "
            f"[official page]({a['page']}) | `{a['sha256']}` |")
    lines += [
        "", "CC0 items do not require attribution; credits are retained as provenance.",
        "The three font license texts are included in `LICENSES/`.",
    ]
    (ROOT / "assets" / "THIRD_PARTY.md").write_text("\n".join(lines) + "\n")

    files = [p for p in OUT.rglob("*") if p.is_file()]
    print(f"Ingested {len(files)} curated runtime files")
    for folder in sorted(p for p in OUT.iterdir() if p.is_dir()):
        total = sum(p.stat().st_size for p in folder.rglob("*") if p.is_file())
        count = sum(1 for p in folder.rglob("*") if p.is_file())
        print(f"  {folder.name:12s} {count:3d} files  {total / 1048576:6.2f} MiB")
    total = sum(p.stat().st_size for p in files)
    print(f"  TOTAL        {len(files):3d} files  {total / 1048576:6.2f} MiB")


if __name__ == "__main__":
    main()
