#!/usr/bin/env python3
"""Deploy ~/workspace/horror-game/build/web/ to the gh-pages branch of
xoloteach/Horror via the GitHub git-database API.

Idempotent: creates the branch on first run, force-updates it on later runs.
Prints only SHAs and sizes, never file contents.
"""
import base64
import json
import os
import sys
import urllib.request
import urllib.error

sys.path.insert(0, "/opt/hatch/skills/skill-creator/bin")
from dynamic_credentials import add_surrogate_to_request, read_json_response

CREDENTIAL = "custom.github"
ALLOWED = ("api.github.com",)
API = "https://api.github.com"
OWNER, REPO, BRANCH = "xoloteach", "Horror", "gh-pages"
WEBDIR = os.path.expanduser("~/workspace/horror-game/build/web")


def req(method, path, data=None):
    body = json.dumps(data).encode() if data is not None else None
    r = urllib.request.Request(API + path, data=body, method=method)
    r.add_header("Accept", "application/vnd.github+json")
    if body is not None:
        r.add_header("Content-Type", "application/json")
    add_surrogate_to_request(r, CREDENTIAL, allowed_hosts=ALLOWED)
    try:
        with urllib.request.urlopen(r, timeout=120) as resp:
            return resp.status, read_json_response(resp)
    except urllib.error.HTTPError as e:
        try:
            payload = json.loads(e.read().decode())
        except Exception:
            payload = {"message": str(e)}
        return e.code, payload


def main():
    files = sorted(
        f for f in os.listdir(WEBDIR)
        if os.path.isfile(os.path.join(WEBDIR, f))
    )
    print(f"Deploying {len(files)} files from {WEBDIR}", flush=True)

    tree_entries = []
    for name in files:
        p = os.path.join(WEBDIR, name)
        size = os.path.getsize(p)
        with open(p, "rb") as fh:
            b64 = base64.b64encode(fh.read()).decode()
        mode = "100644"
        if name == ".nojekyll":
            mode = "100644"
        st, blob = req("POST", f"/repos/{OWNER}/{REPO}/git/blobs",
                       {"content": b64, "encoding": "base64"})
        if st != 201:
            print(f"BLOB FAILED for {name}: {st} {blob.get('message')}")
            return 1
        tree_entries.append({"path": name, "mode": mode, "type": "blob",
                             "sha": blob["sha"]})
        print(f"  blob {name} ({size} bytes) -> {blob['sha'][:8]}", flush=True)
        del b64

    st, tree = req("POST", f"/repos/{OWNER}/{REPO}/git/trees",
                   {"tree": tree_entries})
    if st != 201:
        print(f"TREE FAILED: {st} {tree.get('message')}")
        return 1
    print(f"tree -> {tree['sha'][:8]}", flush=True)

    st, commit = req("POST", f"/repos/{OWNER}/{REPO}/git/commits",
                     {"message": "Deploy HORROR web build",
                      "tree": tree["sha"]})
    if st != 201:
        print(f"COMMIT FAILED: {st} {commit.get('message')}")
        return 1
    print(f"commit -> {commit['sha'][:8]}", flush=True)

    st, ref = req("GET", f"/repos/{OWNER}/{REPO}/git/ref/heads/{BRANCH}")
    if st == 200:
        st2, _ = req("PATCH", f"/repos/{OWNER}/{REPO}/git/refs/heads/{BRANCH}",
                     {"sha": commit["sha"], "force": True})
        action = "updated"
    elif st == 404:
        st2, _ = req("POST", f"/repos/{OWNER}/{REPO}/git/refs",
                     {"ref": f"refs/heads/{BRANCH}", "sha": commit["sha"]})
        action = "created"
    else:
        print(f"REF CHECK FAILED: {st} {ref.get('message')}")
        return 1
    if st2 not in (200, 201):
        print(f"REF {action.upper()} FAILED: {st2}")
        return 1
    print(f"branch gh-pages {action}. LIVE: https://{OWNER}.github.io/{REPO}/",
          flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
