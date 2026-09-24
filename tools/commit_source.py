#!/usr/bin/env python3
"""Commit ~/workspace/horror-game source (minus build/ and .godot/) to main."""
import base64
import json
import os
import sys
import urllib.request
import urllib.error

sys.path.insert(0, "/opt/hatch/skills/skill-creator/bin")
from dynamic_credentials import add_surrogate_to_request

CREDENTIAL = "custom.github"
ALLOWED = ("api.github.com",)
API = "https://api.github.com"
OWNER, REPO, BRANCH = "xoloteach", "Horror", "main"
ROOT = os.path.expanduser("~/workspace/horror-game")
EXCLUDE = {"build", ".godot", "__pycache__"}


def req(method, path, data=None):
    body = json.dumps(data).encode() if data is not None else None
    r = urllib.request.Request(API + path, data=body, method=method)
    r.add_header("Accept", "application/vnd.github+json")
    if body is not None:
        r.add_header("Content-Type", "application/json")
    add_surrogate_to_request(r, CREDENTIAL, allowed_hosts=ALLOWED)
    try:
        with urllib.request.urlopen(r, timeout=120) as resp:
            raw = resp.read().decode()
            return resp.status, (json.loads(raw) if raw.strip() else {})
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            payload = json.loads(raw) if raw.strip() else {}
        except Exception:
            payload = {"raw": raw[:200]}
        return e.code, payload


def main():
    paths = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in EXCLUDE]
        for fn in filenames:
            if fn.endswith((".tmp", ".log")):
                continue
            full = os.path.join(dirpath, fn)
            rel = os.path.relpath(full, ROOT)
            paths.append((rel, full))
    paths.sort()
    print(f"Committing {len(paths)} files to {BRANCH}", flush=True)

    entries = []
    for rel, full in paths:
        with open(full, "rb") as fh:
            b64 = base64.b64encode(fh.read()).decode()
        st, blob = req("POST", f"/repos/{OWNER}/{REPO}/git/blobs",
                       {"content": b64, "encoding": "base64"})
        del b64
        if st != 201:
            print(f"BLOB FAILED {rel}: {st} {blob}")
            return 1
        entries.append({"path": rel, "mode": "100644", "type": "blob",
                        "sha": blob["sha"]})

    st, tree = req("POST", f"/repos/{OWNER}/{REPO}/git/trees",
                   {"tree": entries})
    if st != 201:
        print(f"TREE FAILED: {st} {tree}")
        return 1

    st, ref = req("GET", f"/repos/{OWNER}/{REPO}/git/ref/heads/{BRANCH}")
    parents = [ref["object"]["sha"]] if st == 200 else []
    st, commit = req("POST", f"/repos/{OWNER}/{REPO}/git/commits",
                     {"message": "HORROR: Godot 4 hack-and-slash source (axe throw/embed/Bezier recall, draugr AI, procedural Blender GLBs, synth SFX)",
                      "tree": tree["sha"], "parents": parents})
    if st != 201:
        print(f"COMMIT FAILED: {st} {commit}")
        return 1
    st, _ = req("PATCH", f"/repos/{OWNER}/{REPO}/git/refs/heads/{BRANCH}",
                {"sha": commit["sha"], "force": False})
    if st != 200:
        print(f"REF UPDATE FAILED: {st}")
        return 1
    print(f"main updated -> {commit['sha'][:8]}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
