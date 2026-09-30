# 팩 형식

팩 하나는 폴더 하나다. 두는 곳:

- `packs/<id>/` — 앱에 기본으로 들어가는 팩 (0군, 1군, 2군)
- `packs-nc/<id>/` — 비상업 조건 팩 (3군). 따로 떼어낼 수 있게 폴더를 나눈다
- `~/.cli-pet/packs/<id>/` — **커스텀 팩**. 사용자가 직접 넣는 팩 (앱에 포함하지 않음). 만드는 법은 [custom-packs.md](custom-packs.md)

```
packs/gopher/
  pack.json
  LICENSE          ← 권리자, 라이선스, 정확한 표기 문구, 출처 URL, 받은 날짜, 비공식 문구, 바꾼 점
  normal.png
  happy.png
  ...
```

## 분류와 이름 짓기

팩은 두 축으로 분류한다. **라이선스 축**(`group`, 0~3군)과 **내용 축**(`category` ▸ `series`)이다. 앱 메뉴는 기본 팩과 커스텀 팩을 나누고, 각각 내용 축으로 보여준다: `펫 바꾸기 ▸ (기본 팩 | 커스텀 팩) ▸ 분류 ▸ 시리즈 ▸ 펫`.

**id = `<category>-<series>-<캐릭터>`** (소문자, 하이픈). 폴더 이름도 같게 한다.

| category | 메뉴 이름 | 들어가는 것 | id 예 |
|---|---|---|---|
| `original` | 자체 캐릭터 | 0군 자체 캐릭터 | `original-sprout-sprout` → 줄여서 `original-sprout` |
| `animal` | 동물 | 실제 동물. 자체(`real`), 이모지(`fluent`, `noto`), 픽셀(`oneko`, `luizmelo`) | `animal-real-cat`, `animal-fluent-cat`, `animal-oneko-cat` |
| `dev` | 개발 | 언어·OS·도구 마스코트 | `dev-rust-ferris`, `dev-go-gopher`, `dev-linux-tux` |
| `game` | 게임 | 게임 캐릭터 | `game-lostark-mokoko`, `game-touhou-reimu`, `game-pokemon-pikachu` |
| `anime` | 애니·만화·일러스트 | 애니, 웹툰, 캐릭터 상품 | `anime-peppercarrot-pepper`, `anime-sanrio-kitty` |
| `virtual` | 보컬로이드·버추얼 | 보컬로이드, 보이스 캐릭터, VTuber | `virtual-crypton-miku`, `virtual-zunko-zundamon` |
| `brand` | 브랜드 | 회사·서비스 마스코트 | `brand-duolingo-duo` |
| `meme` | 밈 | 인터넷 밈 | `meme-nyancat-nyancat` |
| `public` | 공공 캐릭터 | 지자체·공공기관 캐릭터 | `public-seoul-haechi` |
| `etc` | 기타 | 어디에도 안 맞는 것 | |

- 시리즈 이름과 캐릭터 이름이 같으면 한 번만 쓴다 (`original-sprout`, `meme-nyancat`).
- `series`는 프로젝트나 작품 단위다: `rust`, `go`, `linux`, `java`, `zig`, `cncf`, `kotlin`, `android`, `deno`, `fluent`, `oneko`, `lostark`, `touhou`, `crypton`, `zunko`, `unity`, `pokemon` …
- 같은 시리즈에 팩이 둘 이상이면 메뉴에서 시리즈 폴더로 묶인다 (예: 동물 ▸ Fluent Emoji ▸ 고양이, 강아지…).
- 커스텀 팩도 같은 규칙을 권장한다. 분류가 없거나 모르는 값이면 `etc`로 들어간다.
- 코드로 그리는 0군 캐릭터(새싹, 실제 동물)는 `main.swift`의 `creatures` 목록에 있다. 폴더가 아니지만 id 규칙은 같다.

## pack.json

```json
{
  "id": "dev-go-gopher",
  "name": "Go Gopher",
  "group": 1,
  "category": "dev",
  "series": "go",
  "seriesName": "Go",
  "tags": ["vector"],
  "credit": "Go Gopher by Renée French",
  "license": "CC BY 4.0",
  "source": "https://go.dev/blog/gopher",
  "retrieved": "2026-09-29",
  "pixel": false,
  "size": 80,
  "fps": 6,
  "squash": true,
  "poses": {
    "normal": "normal.png",
    "happy": "happy.png",
    "focus": ["focus1.png", "focus2.png"]
  }
}
```

| 키 | 필수 | 뜻 |
|---|---|---|
| `id` | ○ | 폴더 이름과 같게 |
| `name` | ○ | 메뉴에 보이는 이름 |
| `group` | ○ | 0 자체, 1 열린 라이선스, 2 같은 조건 공유, 3 비상업 (메뉴에 "비상업" 표시) |
| `category` | ○ | 위 분류 표의 값 |
| `series` | ○ | 시리즈 id (소문자) |
| `seriesName` | | 메뉴에 보이는 시리즈 이름 (없으면 `series`) |
| `tags` | | 그림 스타일 등: `3d`, `flat`, `vector`, `pixel`, `hand-drawn`, `animated` |
| `credit` | ○ | 앱 메뉴에 그대로 표시되는 표기 문구 |
| `license` | ○ | 라이선스 이름 |
| `source`, `retrieved` | ○ | 그림을 받은 곳과 날짜 |
| `pixel` | | `true`면 확대할 때 픽셀이 뭉개지지 않게 그린다 (기본 `false`) |
| `size` | | 화면에 보이는 높이, pt 단위 (기본 80) |
| `fps` | | 프레임 배열의 재생 속도 (기본 6) |
| `squash` | | `false`면 찌그러짐·늘이기 모션을 끈다 (기본 `true`) |
| `lines` | | 이 팩만의 대사. 형식은 [lines.md](lines.md) |
| `walkFacing` | | `walk` 그림이 보는 방향 `"right"`(기본) 또는 `"left"`. 걷는 방향에 맞춰 그림을 뒤집을 때 쓴다 |
| `zzz` | | `true`면 `sleep` 포즈가 있어도 잘 때 zzz를 그린다 (기본: `sleep` 포즈가 없을 때만) |
| `fit` | | `"each"`면 포즈마다 따로 `size` 높이에 맞춘다. 원본 크기가 제각각인 팩용 (기본: 모든 포즈에 `normal` 기준 배율) |
| `poses` | ○ | 포즈 이름 → 파일 하나, 또는 프레임 배열. `normal`만 필수 |

포즈 이름: `normal` `happy` `focus` `surprised` `sleep` (필수 5) / `blink` `dizzy` `think` `sad` (권장) / `held` `walk` (선택). 없는 포즈는 `animation-spec.md`의 대체 규칙을 따른다.

## 그림 규칙

- PNG, 투명 배경. 움직이는 PNG(APNG)도 된다 (프레임을 자동으로 재생).
- 캐릭터 둘레의 빈 여백은 잘라내고, 긴 변은 512px 이하로 맞춘다.
- 한 팩 안의 그림들은 캐릭터 크기와 바닥 위치를 비슷하게 맞춘다 (포즈가 바뀔 때 튀지 않게).
- **권리자가 배포한 원본을 자르기, 크기 조정, 형식 변환하는 것까지만 한다.** 라이선스가 수정을 허용하더라도 새 그림을 지어내지 않는다. 바꾼 점은 LICENSE에 적는다.
