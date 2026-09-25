#!/usr/bin/env python3
"""Sequentially download the redistribution-safe production asset sources.

The cache lives outside the repository because archives contain duplicate FBX,
OBJ and source files that must not ship in the Web build. Every download is
hashed into ``assets/THIRD_PARTY.lock.json``; only selected runtime files are
copied into ``assets/production`` by the ingest script.

All downloads are deliberately sequential to keep peak memory and network load
predictable on the build VM.
"""
from __future__ import annotations

import hashlib
import json
import os
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT.parent / "asset-cache"
LOCK = ROOT / "assets" / "THIRD_PARTY.lock.json"

ASSETS = [
    {
        "id": "kaykit_adventurers_1_0",
        "url": "https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0/archive/672074b73ba276876a19e8816ecdc5241817ab47.zip",
        "page": "https://kaylousberg.itch.io/kaykit-adventurers",
        "file": "kaykit_adventurers.zip",
        "license": "CC0-1.0",
        "creator": "Kay Lousberg (KayKit)",
    },
    {
        "id": "kaykit_skeletons_1_0",
        "url": "https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Skeletons-1.0/archive/15b62b9bad122f72926c10fb14d622c73819fa54.zip",
        "page": "https://kaylousberg.itch.io/kaykit-skeletons",
        "file": "kaykit_skeletons.zip",
        "license": "CC0-1.0",
        "creator": "Kay Lousberg (KayKit)",
    },
    {
        "id": "kaykit_dungeon_remastered_1_0",
        "url": "https://github.com/KayKit-Game-Assets/KayKit-Dungeon-Remastered-1.0/archive/refs/heads/main.zip",
        "page": "https://kaylousberg.itch.io/kaykit-dungeon-pack",
        "file": "kaykit_dungeon.zip",
        "license": "CC0-1.0",
        "creator": "Kay Lousberg (KayKit)",
    },
    {
        "id": "kenney_castle_2_0",
        "url": "https://kenney.nl/media/pages/assets/castle-kit/a395102d20-1711543616/kenney_castle-kit.zip",
        "page": "https://kenney.nl/assets/castle-kit",
        "file": "kenney_castle.zip",
        "license": "CC0-1.0",
        "creator": "Kenney",
    },
    {
        "id": "kenney_graveyard_5_0",
        "url": "https://kenney.nl/media/pages/assets/graveyard-kit/ba8d4b4517-1760691807/kenney_graveyard-kit_5.0.zip",
        "page": "https://kenney.nl/assets/graveyard-kit",
        "file": "kenney_graveyard.zip",
        "license": "CC0-1.0",
        "creator": "Kenney",
    },
    {
        "id": "kenney_nature_1_0",
        "url": "https://kenney.nl/media/pages/assets/nature-kit/37ac38a37b-1677698939/kenney_nature-kit.zip",
        "page": "https://kenney.nl/assets/nature-kit",
        "file": "kenney_nature.zip",
        "license": "CC0-1.0",
        "creator": "Kenney",
    },
    {
        "id": "kenney_particle_pack",
        "url": "https://kenney.nl/media/pages/assets/particle-pack/f8fe0f8cb8-1677578741/kenney_particle-pack.zip",
        "page": "https://kenney.nl/assets/particle-pack",
        "file": "kenney_particles.zip",
        "license": "CC0-1.0",
        "creator": "Kenney",
    },
    {
        "id": "kenney_splat_pack",
        "url": "https://kenney.nl/media/pages/assets/splat-pack/1070534984-1677495350/kenney_splat-pack.zip",
        "page": "https://kenney.nl/assets/splat-pack",
        "file": "kenney_splats.zip",
        "license": "CC0-1.0",
        "creator": "Kenney",
    },
    {
        "id": "kenney_ui_adventure",
        "url": "https://kenney.nl/media/pages/assets/ui-pack-adventure/9a877376bc-1723597274/kenney_ui-pack-adventure.zip",
        "page": "https://kenney.nl/assets/ui-pack-adventure",
        "file": "kenney_ui_adventure.zip",
        "license": "CC0-1.0",
        "creator": "Kenney",
    },
    {
        "id": "kenney_fantasy_ui_borders",
        "url": "https://kenney.nl/media/pages/assets/fantasy-ui-borders/ab29cd0165-1701602367/kenney_fantasy-ui-borders.zip",
        "page": "https://kenney.nl/assets/fantasy-ui-borders",
        "file": "kenney_ui_borders.zip",
        "license": "CC0-1.0",
        "creator": "Kenney",
    },
    {
        "id": "kenney_game_icons",
        "url": "https://kenney.nl/media/pages/assets/game-icons/1ebf9c14af-1677661579/kenney_game-icons.zip",
        "page": "https://kenney.nl/assets/game-icons",
        "file": "kenney_icons.zip",
        "license": "CC0-1.0",
        "creator": "Kenney",
    },
    {
        "id": "kenney_rpg_audio",
        "url": "https://kenney.nl/media/pages/assets/rpg-audio/8e99002d76-1677590336/kenney_rpg-audio.zip",
        "page": "https://kenney.nl/assets/rpg-audio",
        "file": "kenney_rpg_audio.zip",
        "license": "CC0-1.0",
        "creator": "Kenney",
    },
    {
        "id": "kenney_impact_sounds",
        "url": "https://kenney.nl/media/pages/assets/impact-sounds/87b4ddecda-1677589768/kenney_impact-sounds.zip",
        "page": "https://kenney.nl/assets/impact-sounds",
        "file": "kenney_impacts.zip",
        "license": "CC0-1.0",
        "creator": "Kenney",
    },
    {
        "id": "rubberduck_80_rpg_sfx",
        "url": "https://opengameart.org/sites/default/files/80-CC0-RPG-SFX_0.zip",
        "page": "https://opengameart.org/content/80-cc0-rpg-sfx",
        "file": "rubberduck_rpg_sfx.zip",
        "license": "CC0-1.0",
        "creator": "rubberduck",
    },
    {
        "id": "artisticdude_swishes",
        "url": "https://opengameart.org/sites/default/files/swishes.zip",
        "page": "https://opengameart.org/content/swishes-sound-pack",
        "file": "swishes.zip",
        "license": "CC0-1.0",
        "creator": "artisticdude",
    },
    {
        "id": "cynic_battle_loop",
        "url": "https://opengameart.org/sites/default/files/cynicbattleloop.ogg",
        "page": "https://opengameart.org/content/cynic-battle-loop",
        "file": "cynicbattleloop.ogg",
        "license": "CC0-1.0",
        "creator": "Ferk / Alex Smith",
    },
    {
        "id": "viking_march",
        "url": "https://opengameart.org/sites/default/files/viking-march.ogg",
        "page": "https://opengameart.org/content/viking-march",
        "file": "viking-march.ogg",
        "license": "CC0-1.0",
        "creator": "nightm4re",
    },
    {
        "id": "winter_wind",
        "url": "https://opengameart.org/sites/default/files/winter-wind-short.mp3",
        "page": "https://opengameart.org/content/winter-wind",
        "file": "winter-wind-short.mp3",
        "license": "CC0-1.0",
        "creator": "qubodup",
    },
    {
        "id": "fire_crackle",
        "url": "https://opengameart.org/sites/default/files/fire-1.ogg",
        "page": "https://opengameart.org/content/fire-crackling",
        "file": "fire-1.ogg",
        "license": "CC0-1.0",
        "creator": "qubodup",
    },
    {
        "id": "google_font_cinzel",
        "url": "https://raw.githubusercontent.com/google/fonts/main/ofl/cinzel/Cinzel%5Bwght%5D.ttf",
        "page": "https://fonts.google.com/specimen/Cinzel",
        "file": "Cinzel-Variable.ttf",
        "license": "OFL-1.1",
        "creator": "Natanael Gama / Google Fonts",
    },
    {
        "id": "google_font_alegreya_sans",
        "url": "https://raw.githubusercontent.com/google/fonts/main/ofl/alegreyasans/AlegreyaSans-Regular.ttf",
        "page": "https://fonts.google.com/specimen/Alegreya+Sans",
        "file": "AlegreyaSans-Regular.ttf",
        "license": "OFL-1.1",
        "creator": "Huerta Tipografica / Google Fonts",
    },
    {
        "id": "google_font_noto_runic",
        "url": "https://raw.githubusercontent.com/google/fonts/main/ofl/notosansrunic/NotoSansRunic-Regular.ttf",
        "page": "https://fonts.google.com/noto/specimen/Noto+Sans+Runic",
        "file": "NotoSansRunic-Regular.ttf",
        "license": "OFL-1.1",
        "creator": "Google Fonts",
    },
    {
        "id": "google_font_cinzel_ofl",
        "url": "https://raw.githubusercontent.com/google/fonts/main/ofl/cinzel/OFL.txt",
        "page": "https://github.com/google/fonts/tree/main/ofl/cinzel",
        "file": "OFL-Cinzel.txt",
        "license": "OFL-1.1",
        "creator": "SIL",
    },
    {
        "id": "google_font_alegreya_ofl",
        "url": "https://raw.githubusercontent.com/google/fonts/main/ofl/alegreyasans/OFL.txt",
        "page": "https://github.com/google/fonts/tree/main/ofl/alegreyasans",
        "file": "OFL-AlegreyaSans.txt",
        "license": "OFL-1.1",
        "creator": "SIL",
    },
    {
        "id": "google_font_runic_ofl",
        "url": "https://raw.githubusercontent.com/google/fonts/main/ofl/notosansrunic/OFL.txt",
        "page": "https://github.com/google/fonts/tree/main/ofl/notosansrunic",
        "file": "OFL-NotoSansRunic.txt",
        "license": "OFL-1.1",
        "creator": "SIL",
    },
]


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def download(entry: dict) -> dict:
    CACHE.mkdir(parents=True, exist_ok=True)
    path = CACHE / entry["file"]
    if not path.exists() or path.stat().st_size == 0:
        print(f"GET  {entry['id']}")
        req = urllib.request.Request(entry["url"], headers={"User-Agent": "MidgardFury-AssetIngest/2.0"})
        tmp = path.with_suffix(path.suffix + ".part")
        with urllib.request.urlopen(req, timeout=180) as response, tmp.open("wb") as out:
            while True:
                chunk = response.read(1024 * 1024)
                if not chunk:
                    break
                out.write(chunk)
        tmp.replace(path)
    else:
        print(f"HAVE {entry['id']}")
    result = dict(entry)
    result["bytes"] = path.stat().st_size
    result["sha256"] = sha256(path)
    print(f"     {path.name}: {result['bytes'] / 1048576:.2f} MiB  {result['sha256'][:12]}")
    return result


def main() -> int:
    selected = set(sys.argv[1:])
    todo = [a for a in ASSETS if not selected or a["id"] in selected]
    unknown = selected - {a["id"] for a in ASSETS}
    if unknown:
        print("Unknown asset id(s):", ", ".join(sorted(unknown)), file=sys.stderr)
        return 2
    results = []
    for i, entry in enumerate(todo, 1):
        print(f"[{i:02d}/{len(todo):02d}]", end=" ")
        try:
            results.append(download(entry))
        except Exception as exc:
            print(f"ERROR {entry['id']}: {exc}", file=sys.stderr)
            return 1
        time.sleep(0.15)
    LOCK.parent.mkdir(parents=True, exist_ok=True)
    LOCK.write_text(json.dumps({"schema": 1, "assets": results}, indent=2) + "\n")
    print(f"\nWrote {LOCK.relative_to(ROOT)} with {len(results)} verified downloads")
    print(f"Cache total: {sum(a['bytes'] for a in results) / 1048576:.2f} MiB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
