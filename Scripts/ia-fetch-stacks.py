#!/usr/bin/env python3
#
# ia-fetch-stacks.py — pull HyperCard stacks from the Internet Archive's
# `hypercardstacks` collection (3,695 items) into the local parse corpus.
#
#   python3 Scripts/ia-fetch-stacks.py [count] [page]
#
# For each item: downloads its classic-HFS disk.img, extracts every STAK
# file's data fork (pure-Python `machfs`; pip3 install --user machfs), and
# writes the resource fork back via the com.apple.ResourceFork xattr so the
# importer's icon/sound reading works. Items already present under any
# "New Stacks*" folder are skipped, so batches are resumable; page through
# the collection with the second argument (200 ids per page).
# Output: "New Stacks IA Oct 15/<identifier>/<stack>". Then run the audit:
#   CONTRAPT_AUDIT=1 swift test --package-path HyperTalk --filter corpusParseAudit
#
import json, os, subprocess, urllib.request, urllib.parse, glob, sys
import machfs

root = "New Stacks IA Oct 15"
os.makedirs(root, exist_ok=True)

have = set(os.path.basename(p).lower() for p in glob.glob("New Stacks*/*"))

def api(url):
    with urllib.request.urlopen(url, timeout=30) as r:
        return json.load(r)

def extract_stacks(volume, outdir):
    found = []
    def walk(folder):
        for name, obj in folder.items():
            if isinstance(obj, machfs.Folder):
                walk(obj)
            elif getattr(obj, "type", b"") == b"STAK" and len(obj.data) > 512:
                safe = name.replace("/", ":")
                path = os.path.join(outdir, safe)
                open(path, "wb").write(obj.data)
                if obj.rsrc:
                    subprocess.run(["xattr", "-wx", "com.apple.ResourceFork",
                                    obj.rsrc.hex(), path], check=False)
                found.append(safe)
    walk(volume)
    return found

count = int(sys.argv[1]) if len(sys.argv) > 1 else 20
page = int(sys.argv[2]) if len(sys.argv) > 2 else 1
search = api("https://archive.org/advancedsearch.php?q=collection%3Ahypercardstacks"
             f"&fl=identifier&rows=200&page={page}&output=json&sort%5B%5D=identifier+asc")
ids = [d["identifier"] for d in search["response"]["docs"]]
fresh = [i for i in ids if i.lower() not in have][:count]
print(f"page {page}: {len(ids)} ids, taking {len(fresh)} new")

got = skipped = 0
for ident in fresh:
    try:
        meta = api(f"https://archive.org/metadata/{ident}")
        imgs = [f["name"] for f in meta.get("files", []) if f["name"].lower().endswith((".img", ".dsk"))]
        if not imgs:
            skipped += 1; continue
        outdir = os.path.join(root, ident)
        os.makedirs(outdir, exist_ok=True)
        stacks = []
        for img in imgs[:2]:
            url = f"https://archive.org/download/{ident}/{urllib.parse.quote(img)}"
            try:
                data = urllib.request.urlopen(url, timeout=120).read()
                v = machfs.Volume(); v.read(data)
                stacks += extract_stacks(v, outdir)
            except Exception:
                continue
        if stacks:
            got += 1
            print(f"  + {ident}: {', '.join(stacks[:4])}")
        else:
            if not os.listdir(outdir): os.rmdir(outdir)
            skipped += 1
    except Exception as e:
        print(f"  ! {ident}: {e}")
        skipped += 1

print(f"\ndone: {got} items with stacks, {skipped} without")
