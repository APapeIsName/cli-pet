#!/usr/bin/env python3
"""packs/*/pack.json 을 읽어 CREDITS.md 를 만든다. 팩을 추가·수정한 뒤 실행: python3 tools/gen_credits.py"""
import json, glob, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LICENSE_URL = {
    "MIT": "https://opensource.org/license/mit",
    "CC BY 4.0": "https://creativecommons.org/licenses/by/4.0/",
    "CC BY 3.0": "https://creativecommons.org/licenses/by/3.0/",
    "CC0 1.0": "https://creativecommons.org/publicdomain/zero/1.0/",
    "BSD-3-Clause (New BSD)": "https://opensource.org/license/bsd-3-clause",
}
CATEGORY = {"animal": "동물", "dev": "개발", "game": "게임", "anime": "애니·만화·일러스트", "virtual": "보컬로이드·버추얼",
            "brand": "브랜드", "meme": "밈", "public": "공공 캐릭터", "etc": "기타"}

packs = [json.load(open(p)) for p in sorted(glob.glob(os.path.join(ROOT, "packs", "*", "pack.json")))]
extras = [json.load(open(p)) for p in sorted(glob.glob(os.path.join(ROOT, "extra-packs", "*", "pack.json")))]

def lic(name):
    url = LICENSE_URL.get(name)
    return f"[{name}]({url})" if url else name

out = ["# 크레딧", "",
       "CLIPet에 들어 있는 캐릭터 그림의 권리자, 라이선스, 출처예요. 이 파일은 `tools/gen_credits.py`로 만들어요.", "",
       "- **모든 캐릭터 팩은 비공식이에요.** 각 프로젝트·회사와 관련이 없고, 보증받지 않았어요. 캐릭터 이름과 로고는 각 권리자의 상표예요.",
       "- 팩 그림은 권리자가 공식으로 배포한 파일을 **자르고, 크기를 줄이고, PNG로 변환**한 것이에요. 새로 그린 부분은 없어요. 파일별 원본 주소와 바꾼 내용은 각 팩 폴더의 `LICENSE`에 있어요.",
       "- 앱 코드의 [MIT 라이선스](LICENSE)는 팩 그림에 적용되지 않아요.", "",
       "## 자체 캐릭터", "",
       "새싹, 둔갑이, 자체 동물 10종(고양이, 강아지, 햄스터, 토끼, 펭귄, 여우, 오리, 수달, 고슴도치, 거북이), 장난감 5종(왁뿌볼, 키캡 클리커, 쫀득볼, 만두 말랑이, 버터 말랑이)은 이 저장소의 코드(`main.swift`)로 그려요. 앱 코드와 같은 [MIT 라이선스](LICENSE)예요.", ""]

for cat, label in CATEGORY.items():
    in_cat = [p for p in packs if p.get("category") == cat]
    if not in_cat:
        continue
    out += [f"## {label}", ""]
    # 같은 시리즈·같은 표기면 한 줄로 묶는다
    groups = {}
    for p in in_cat:
        key = (p.get("seriesName") or p.get("series"), p.get("license"),
               p["credit"].split(" — ")[0] if p.get("series") == "cncf" else p["credit"])
        groups.setdefault(key, []).append(p)
    out += ["| 캐릭터 | 표기 | 라이선스 | 출처 |", "|---|---|---|---|"]
    for (series, license, _), ps in groups.items():
        names = ", ".join(f"[{p['name']}](packs/{p['id']}/LICENSE)" for p in ps)
        credit, src = ps[0]["credit"], ps[0].get("source", "").split(" (")[0].split(" , ")[0].split(" + ")[0]
        if ps[0].get("series") == "cncf":
            credit = "phippy.io — Phippy and Friends © The Linux Foundation (CNCF)"
            src = "https://github.com/cncf/artwork/tree/main/other/phippy-and-friends"
        out.append(f"| {names} | {credit} | {lic(license)} | {src} |")
    out.append("")

if extras:
    out += ["## 추가 팩", "", "앱에 기본으로 들어 있지 않고, 펫 메뉴의 **추가 팩 받기**나 `cli-pet pack get` 으로 받는 팩이에요.", "",
            "| 캐릭터 | 표기 | 라이선스 | 출처 |", "|---|---|---|---|"]
    names = ", ".join(f"[{p['name']}](extra-packs/{p['id']}/LICENSE)" for p in extras)
    out.append(f"| {names} | phippy.io — Phippy and Friends © The Linux Foundation (CNCF) | {lic(extras[0]['license'])} | https://github.com/cncf/artwork/tree/main/other/phippy-and-friends |")
    out.append("")
open(os.path.join(ROOT, "CREDITS.md"), "w").write("\n".join(out))
print(f"CREDITS.md: 기본 팩 {len(packs)}개, 추가 팩 {len(extras)}개")
