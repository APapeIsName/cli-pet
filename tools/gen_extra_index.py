#!/usr/bin/env python3
"""extra-packs/*/ 를 읽어 extra-packs/index.json 을 만든다. 추가 팩을 넣거나 고친 뒤 실행."""
import json, glob, os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
out = []
for p in sorted(glob.glob(os.path.join(ROOT, "extra-packs", "*", "pack.json"))):
    d = json.load(open(p)); folder = os.path.dirname(p)
    files = sorted(f for f in os.listdir(folder) if not f.startswith("."))
    size = sum(os.path.getsize(os.path.join(folder, f)) for f in files)
    out.append({k: d.get(k) for k in ("id", "name", "category", "series", "seriesName", "credit", "license")} | {"files": files, "bytes": size})
json.dump(out, open(os.path.join(ROOT, "extra-packs", "index.json"), "w"), ensure_ascii=False, indent=2)
print(f"extra-packs/index.json: 추가 팩 {len(out)}개")
