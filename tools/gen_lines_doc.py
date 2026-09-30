#!/usr/bin/env python3
"""main.swift 의 defaultLines 로 docs/lines.md 의 '상황 목록' 표를 다시 만든다. 대사를 추가·수정한 뒤 실행."""
import os, re
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src = open(os.path.join(ROOT, "main.swift")).read()
block = src[src.index("let defaultLines"):src.index("// 대사 찾는 순서")]
rows = re.findall(r'\("([a-z.]+)", \[(.*?)\], "(.*?)"\)', block)
table = "| 상황 | 언제 | 기본 대사 |\n|---|---|---|\n" + "\n".join(
    f"| `{k}` | {h} | {' / '.join(x.strip().strip(chr(34)) for x in v.split('\", ')) if v else '(말하지 않음)'} |" for k, v, h in rows)
p = os.path.join(ROOT, "docs", "lines.md")
doc = open(p).read()
start = doc.index("## 상황 목록")
end = doc.index("## ", start + 3)
doc = doc[:start] + "## 상황 목록\n\n" + table + "\n\n" + doc[end:]
open(p, "w").write(doc)
print(f"docs/lines.md: 상황 {len(rows)}개")
