#!/usr/bin/env python3
"""Analyze exactly 1,000 visual-QA screenshots and build contact sheets.

Every captured frame appears once in one of ten 10x10 contact sheets. The gate
rejects missing/duplicate numbers, blank/near-solid output, invalid exposure, a
stuck renderer, missing scenario stages, or absent boss/victory/restart proof.
"""
from __future__ import annotations

import json
import re
import statistics
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFont, ImageStat

ROOT = Path(__file__).resolve().parents[1]
QA = ROOT / "artifacts" / "visual_qa"
FRAMES = QA / "frames"
SUMMARY = QA / "capture_summary.json"
CONTACTS = QA / "contact_sheets"
REPORT = QA / "analysis.json"
EXPECTED = 1000
EXPECTED_STAGES = {
    "TITLE_AND_SETTINGS", "INTRO_AND_LOCOMOTION", "COMBO_HEAVY_DODGE",
    "AIM_THROW_EMBED_RECALL", "WARRIOR_ROGUE", "MAGE_PROJECTILE",
    "HORDE", "ELITE_GAUNTLET", "BONE_JARL_BOSS", "VICTORY_RESULTS",
    "RESTARTED_TITLE",
}


def frame_number(path: Path) -> int:
    match = re.fullmatch(r"frame_(\d{4})\.jpg", path.name)
    return int(match.group(1)) if match else -1


def stats(path: Path, previous_thumb: Image.Image | None) -> tuple[dict, Image.Image]:
    with Image.open(path) as source:
        rgb = source.convert("RGB")
        gray = rgb.convert("L")
        stat = ImageStat.Stat(gray)
        histogram = gray.histogram()
        pixels = gray.width * gray.height
        thumb = gray.resize((32, 18), Image.Resampling.BILINEAR)
        diff = None
        if previous_thumb is not None:
            diff = ImageStat.Stat(ImageChops.difference(thumb, previous_thumb)).mean[0]
        return {
            "frame": frame_number(path),
            "mean_luma": round(stat.mean[0], 3),
            "contrast": round(stat.stddev[0], 3),
            "black_clip": round(sum(histogram[:6]) / pixels, 5),
            "white_clip": round(sum(histogram[250:]) / pixels, 5),
            "delta": None if diff is None else round(diff, 3),
            "width": rgb.width,
            "height": rgb.height,
        }, thumb.copy()


def contact_sheet(paths: list[Path], destination: Path, heading: str) -> None:
    cell_w, cell_h = 128, 72
    header = 28
    canvas = Image.new("RGB", (cell_w * 10, header + cell_h * 10), "#080d18")
    draw = ImageDraw.Draw(canvas)
    draw.text((10, 7), heading, fill="#d7e7ff")
    for index, path in enumerate(paths):
        with Image.open(path) as source:
            image = source.convert("RGB").resize((cell_w, cell_h), Image.Resampling.LANCZOS)
        x = (index % 10) * cell_w
        y = header + (index // 10) * cell_h
        canvas.paste(image, (x, y))
        draw.rectangle((x, y, x + 34, y + 11), fill=(3, 6, 12))
        draw.text((x + 2, y), f"{frame_number(path):04d}", fill="#8fdcff")
    destination.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(destination, "JPEG", quality=86, optimize=True)


def overview(paths: list[Path], destination: Path) -> None:
    selected = [0, 10, 29, 42, 70, 115, 150, 205, 245, 285,
                325, 365, 410, 485, 590, 700, 850, 890, 945, 982]
    cell_w, cell_h = 256, 144
    canvas = Image.new("RGB", (cell_w * 5, 32 + cell_h * 4), "#080d18")
    draw = ImageDraw.Draw(canvas)
    draw.text((12, 8), "MIDGARD FURY — 1,000-FRAME VISUAL QA MILESTONES", fill="#d7e7ff")
    for index, number in enumerate(selected):
        with Image.open(paths[number]) as source:
            image = source.convert("RGB").resize((cell_w, cell_h), Image.Resampling.LANCZOS)
        x = (index % 5) * cell_w
        y = 32 + (index // 5) * cell_h
        canvas.paste(image, (x, y))
        draw.rectangle((x, y, x + 52, y + 16), fill=(3, 6, 12))
        draw.text((x + 3, y + 2), f"F{number:04d}", fill="#8fdcff")
    canvas.save(destination, "JPEG", quality=90, optimize=True)


def main() -> int:
    paths = sorted((p for p in FRAMES.glob("frame_*.jpg")), key=frame_number)
    failures: list[str] = []
    numbers = [frame_number(p) for p in paths]
    if len(paths) != EXPECTED:
        failures.append(f"expected {EXPECTED} screenshots, found {len(paths)}")
    if numbers != list(range(EXPECTED)):
        failures.append("frame numbers are missing, duplicated, or out of order")
    if failures:
        print("FAIL:", *failures, sep="\n  ")
        return 1

    rows = []
    previous = None
    frozen_run = 0
    max_frozen_run = 0
    for path in paths:
        row, previous = stats(path, previous)
        rows.append(row)
        if row["delta"] is not None and row["delta"] < 0.12:
            frozen_run += 1
            max_frozen_run = max(max_frozen_run, frozen_run)
        else:
            frozen_run = 0
        if row["contrast"] < 5.0:
            failures.append(f"frame {row['frame']} is near-solid (contrast {row['contrast']})")
        if row["mean_luma"] < 4.0 or row["mean_luma"] > 250.0:
            failures.append(f"frame {row['frame']} has invalid exposure ({row['mean_luma']})")
        if row["black_clip"] > 0.94 or row["white_clip"] > 0.75:
            failures.append(f"frame {row['frame']} is overwhelmingly clipped")
    if max_frozen_run > 35:
        failures.append(f"renderer appears frozen for {max_frozen_run} consecutive captures")

    capture = json.loads(SUMMARY.read_text()) if SUMMARY.exists() else {}
    stages = set(capture.get("stage_counts", {}))
    missing_stages = EXPECTED_STAGES - stages
    if missing_stages:
        failures.append("missing visual stages: " + ", ".join(sorted(missing_stages)))
    final = capture.get("final", {})
    for key in ("seen_boss", "seen_victory", "seen_restart"):
        if not final.get(key, False):
            failures.append(f"final telemetry did not prove {key}")

    CONTACTS.mkdir(parents=True, exist_ok=True)
    for sheet in range(10):
        block = paths[sheet * 100:(sheet + 1) * 100]
        contact_sheet(block, CONTACTS / f"contact_{sheet:02d}.jpg",
                      f"FRAMES {sheet*100:04d}–{sheet*100+99:04d}")
    overview(paths, QA / "milestones.jpg")

    report = {
        "passed": not failures,
        "frame_count": len(paths),
        "resolution": [rows[0]["width"], rows[0]["height"]],
        "mean_luma": round(statistics.mean(r["mean_luma"] for r in rows), 3),
        "min_luma": min(r["mean_luma"] for r in rows),
        "max_luma": max(r["mean_luma"] for r in rows),
        "mean_contrast": round(statistics.mean(r["contrast"] for r in rows), 3),
        "min_contrast": min(r["contrast"] for r in rows),
        "max_frozen_run": max_frozen_run,
        "stage_counts": capture.get("stage_counts", {}),
        "final": final,
        "failures": failures,
        "frames": rows,
    }
    REPORT.write_text(json.dumps(report, indent=2) + "\n")
    print(f"Captured:       {len(paths)} / {EXPECTED} screenshots")
    print(f"Resolution:     {rows[0]['width']}x{rows[0]['height']}")
    print(f"Luminance:      {report['min_luma']:.1f}–{report['max_luma']:.1f} (mean {report['mean_luma']:.1f})")
    print(f"Contrast mean:  {report['mean_contrast']:.1f}")
    print(f"Frozen run max: {max_frozen_run}")
    print(f"Stages:         {len(stages)} / {len(EXPECTED_STAGES)}")
    print(f"Contact sheets: 10 (every captured frame represented)")
    if failures:
        print("FAIL:")
        for failure in failures[:50]:
            print(" -", failure)
        return 1
    print("PASS: 1,000-frame visual gate")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
