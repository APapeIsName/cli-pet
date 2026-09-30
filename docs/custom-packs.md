# 커스텀 팩 만들기

펫 메뉴는 두 칸으로 나뉘어요.

| 칸 | 어디에 있나 | 누가 넣나 |
|---|---|---|
| **기본 팩** | 앱 안 (`CLIPet.app/Contents/Resources/packs`) | 앱에 들어 있음. 라이선스를 확인한 것만 |
| **커스텀 팩** | `~/.cli-pet/packs/<id>/` | 사용자가 직접. 앱은 배포하지 않음 |

펫 오른쪽 클릭 → 펫 바꾸기 → **커스텀 팩 폴더 열기…** 로 폴더를 바로 열 수 있어요.

## 1. 그림 준비

포즈마다 PNG 한 장씩, 파일 이름을 포즈 이름으로 지어요. 투명 배경이 좋아요.

| 등급 | 파일 이름 |
|---|---|
| 필수 | `normal.png` `happy.png` `focus.png` `surprised.png` `sleep.png` |
| 권장 | `blink.png` `dizzy.png` `think.png` `sad.png` |
| 선택 | `held.png` (들려 있을 때) `walk.png` |

- 최소한 `normal.png` 한 장만 있어도 돼요. 없는 포즈는 비슷한 포즈로 대신해요.
- 여러 장으로 움직이게 하려면 `happy-1.png`, `happy-2.png` … 처럼 번호를 붙여요. 움직이는 PNG(APNG) 한 장도 돼요.
- 모든 그림의 캔버스 크기를 같게 맞추면 포즈가 바뀔 때 튀지 않아요.

## 2. 팩 만들기

```bash
cli-pet pack new anime-myseries-mychar ~/Desktop/내그림폴더
```

- `~/.cli-pet/packs/anime-myseries-mychar/` 를 만들고, 포즈 이름에 맞는 그림을 복사해서 `pack.json`까지 써 줘요.
- id는 `분류-시리즈-캐릭터` 규칙을 권장해요. 분류는 `original` `animal` `dev` `game` `anime` `virtual` `brand` `meme` `public` `etc` 중 하나예요. 메뉴에서 이 분류대로 묶여요.
- Homebrew로 설치하지 않았다면 `cli-pet` 대신 `~/Applications/CLIPet.app/Contents/MacOS/cli-pet` 을 쓰세요.

## 3. 이름과 표기 채우기

`pack.json`을 열어서 고쳐요.

```json
{
  "id": "anime-myseries-mychar",
  "name": "내 캐릭터",
  "category": "anime",
  "series": "myseries",
  "seriesName": "내 시리즈",
  "credit": "그림: 나",
  "license": "개인 사용",
  "size": 80,
  "poses": { "normal": "normal.png", "happy": "happy.png" }
}
```

전체 키 설명은 [pack-format.md](pack-format.md)에 있어요. `"anchors"`로 눈·목 위치를 알려 주면 안경 같은 얼굴 아이템도 쓸 수 있어요. `"lines"`로 캐릭터만의 대사를 넣을 수 있어요 ([lines.md](lines.md)). `"group": 3`을 넣으면 메뉴에 "비상업"이 표시되고, `"zzz": true`를 넣으면 잘 때 zzz를 그려요.

## 4. 검사

```bash
cli-pet pack check anime-myseries-mychar
```

어떤 포즈가 있고 없는지, 파일이 제대로 읽히는지 알려줘요. 앱은 메뉴를 열 때마다 커스텀 팩을 다시 읽으니, 앱을 다시 켤 필요는 없어요.

## 추가 팩 받기

그림이 적은 팩 일부는 앱에 기본으로 넣지 않고 **추가 팩**으로 두었어요.

```bash
cli-pet pack get list          # 목록 (✓ 받은 것)
cli-pet pack get dev-cncf-tai  # 하나 받기 (all 이면 전부)
cli-pet pack remove dev-cncf-tai
```

펫 바꾸기 메뉴의 **추가 팩 받기**에서 눌러도 돼요. 받은 추가 팩은 기본 팩 목록에 나타나요.

## 권리 주의

- 커스텀 팩에 넣은 그림의 권리는 **넣은 사람이 확인**해야 해요.
- 유명 캐릭터 팬아트는 개인 컴퓨터에서 혼자 쓰는 정도로만 두고, **공유하거나 저장소에 올리지 마세요.** 이유는 [ip-research.md](ip-research.md)를 보세요.
- 공유해도 되는 그림인지 모르겠으면 [packs.csv](packs.csv)의 판정을 먼저 확인하세요.
