# CLIPet 🌱

터미널 위에 떠 있는 작은 데스크톱 펫 (macOS).

클릭하면 폴짝 뛰고, 드래그하면 대롱대롱 매달리고, 가만히 두면 잠들어요.
Claude Code를 연결하면 지금 무슨 일을 하는지 말풍선으로 알려줘요. 생각 중, 파일 읽기·수정, 명령 실행, 권한 요청, 완료.

![자체 캐릭터들](docs/previews/group0-creatures.png)

## 설치

**필요한 것:** macOS, Apple 개발 도구(Xcode Command Line Tools). 설치할 때 컴퓨터에서 직접 빌드해요.

### Homebrew (추천)

```bash
brew install APapeIsName/tap/cli-pet
cli-pet install      # Claude Code 연결 + 로그인할 때 자동 실행 (원본 설정은 백업)
cli-pet start        # 펫 띄우기
```

- 플러그인으로 연결하려면 `cli-pet install --no-hooks` 로 설치한 뒤 아래 [플러그인](#claude-code-플러그인)을 보세요.
- 업데이트: `brew upgrade cli-pet`
- 지우기: `cli-pet uninstall` 후 `brew uninstall cli-pet`

### curl 한 줄

Homebrew가 없다면:

```bash
curl -fsSL https://raw.githubusercontent.com/APapeIsName/cli-pet/main/install.sh | bash
```

앱을 빌드해서 `~/Applications/CLIPet.app`에 넣고, Claude Code와 어떻게 연결할지 물어봐요.

1. **바로 연결**: `~/.claude/settings.json`에 훅을 추가해요. 원본은 `settings.json.cli-pet-backup`으로 백업해요.
2. **플러그인으로 연결**: 설정 파일은 건드리지 않아요.
3. **연결하지 않기**

물어보지 않게 하려면 `... | CLI_PET_CONNECT=2 bash` 처럼 번호를 미리 줄 수 있어요.

- 지우기: `~/Applications/CLIPet.app/Contents/MacOS/cli-pet uninstall` 후 `rm -rf ~/Applications/CLIPet.app ~/.cli-pet`

### 직접 받아서 설치

```bash
git clone https://github.com/APapeIsName/cli-pet.git
cd cli-pet
./install.command      # Finder에서 더블클릭해도 돼요. 지우기는 uninstall.command
```

> ZIP으로 받았다면, 처음 한 번은 `install.command`를 **오른쪽 클릭 → 열기**로 실행해야 해요 (서명되지 않은 스크립트라서).

### Claude Code 플러그인

앱을 설치한 뒤 Claude Code에서:

```
/plugin marketplace add APapeIsName/cli-pet
/plugin install cli-pet@cli-pet
```

- 새로 여는 Claude Code 세션부터 적용돼요.
- 세션이 시작될 때 펫이 떠 있지 않으면 자동으로 띄워요. 끄려면 환경 변수 `CLI_PET_NO_AUTOSTART=1`을 설정하세요.
- 앱이 없으면 플러그인은 아무 일도 하지 않아요.
- **바로 연결**(`cli-pet install`, 설치 스크립트의 1번)과 플러그인은 하나만 쓰세요. 둘 다 쓰면 같은 알림이 두 번 가요.

플러그인은 Claude Code에서 `/plugin uninstall cli-pet@cli-pet`으로 지워요.

## 쓰는 법

| 하는 일 | 펫 반응 |
|---|---|
| 클릭 | 폴짝 뛰며 한마디 |
| 빠르게 5번 클릭 | 어지러워해요 |
| 드래그 | 대롱대롱, 놓으면 착지 |
| 90초 동안 가만히 | 잠들어요 |
| 오른쪽 클릭 | 메뉴: 펫 바꾸기, 대사 바꾸기, 크기, 숨기기, 구석으로 보내기, Claude Code 연결, 로그인 시 자동 실행, 종료 |

터미널에서도 부를 수 있어요 (Homebrew로 설치했다면 `cli-pet`, 아니면 `~/Applications/CLIPet.app/Contents/MacOS/cli-pet`):

```bash
cli-pet start                 # 펫 띄우기
cli-pet show / cli-pet hide   # 펫 보이기 / 숨기기
cli-pet menubar on|off        # 메뉴 막대 아이콘 켜기 / 끄기
cli-pet size 크게             # 작게 · 보통 · 크게 · 아주크게, 또는 0.5~2.5 배율
cli-pet say "안녕"            # 펫이 말하게 하기
npm test | cli-pet pipe       # 명령 출력을 펫이 말풍선으로 보여주기 (출력은 그대로 터미널에도 나옴)
```

## 펫 고르기

오른쪽 클릭 → **펫 바꾸기 ▸ 분류 ▸ 시리즈 ▸ 펫**

| 분류 | 들어 있는 펫 |
|---|---|
| 자체 캐릭터 | 새싹 |
| 동물 | 자체 동물 10종 (고양이, 강아지, 햄스터, 토끼, 펭귄, 여우, 오리, 수달, 고슴도치, 거북이), Fluent Emoji 동물 8종, oneko 고양이 |
| 개발 | Ferris (Rust), Go Gopher, Tux (Linux), Duke (Java), Kodee (Kotlin), Android 로봇, Zig 마스코트 3종, Phippy와 친구들 (CNCF) 12종 |

자체 캐릭터와 동물은 코드로 그려서 모든 표정이 있어요. 다른 팩은 권리자가 공식으로 배포한 그림을 그대로 쓰기 때문에, 그림이 없는 표정은 비슷한 표정으로 대신해요.

### 메뉴 막대 아이콘

메뉴 막대의 🌱 아이콘을 누르면 펫 메뉴가 열려요. 맨 위의 **펫 보이기 / 숨기기**로 펫을 켜고 끌 수 있어요. 아이콘이 필요 없으면 메뉴에서 **메뉴 막대에 아이콘 보이기**를 끄거나 `cli-pet menubar off` 를 치세요.

### 크기와 숨기기

- 오른쪽 클릭 → **크기**에서 작게·보통·크게·아주 크게를 고를 수 있어요. 말풍선도 같이 커져요.
- **숨기기** 또는 **30분 동안 숨기기**로 잠깐 치워 둘 수 있어요. 다시 부르려면 메뉴 막대 아이콘을 누르거나, CLIPet을 다시 열거나(Finder, Spotlight), `cli-pet show` 를 치세요.

### 대사 바꾸기

펫 오른쪽 클릭 → **대사 바꾸기…** (또는 `cli-pet lines`)로 클릭했을 때, 작업이 끝났을 때 같은 상황마다 할 말을 바꿀 수 있어요. 저장하면 바로 적용돼요. 자세한 방법은 [docs/lines.md](docs/lines.md)를 보세요.

### 기본 팩과 커스텀 팩

메뉴는 **기본 팩**(앱에 들어 있는 것)과 **커스텀 팩**(직접 넣은 것)으로 나뉘어 있어요.

### 커스텀 팩 만들기

포즈 이름으로 된 PNG(`normal.png`, `happy.png` …)를 한 폴더에 모은 다음:

```bash
cli-pet pack new anime-myseries-mychar ~/Desktop/내그림폴더   # 팩 만들기
cli-pet pack check anime-myseries-mychar                      # 검사
```

펫 오른쪽 클릭 → 펫 바꾸기 → 커스텀 팩에 나타나요. 자세한 방법은 [docs/custom-packs.md](docs/custom-packs.md)를 보세요. 넣은 그림의 권리는 넣은 사람이 확인해야 하고, 유명 캐릭터 팬아트는 공유하지 마세요.

## 문서

- [docs/lines.md](docs/lines.md) — 상황별 대사 바꾸기
- [docs/custom-packs.md](docs/custom-packs.md) — 커스텀 팩 만들기
- [docs/pack-format.md](docs/pack-format.md) — 팩 형식, 분류와 이름 짓는 규칙
- [docs/animation-spec.md](docs/animation-spec.md) — 상태, 포즈, 트리거 분류
- [docs/ip-research.md](docs/ip-research.md) — 캐릭터 IP 사용 가능 여부 조사
- [docs/packs.csv](docs/packs.csv) — 전체 캐릭터 목록 (엑셀·구글 시트용)
- [docs/inquiry.md](docs/inquiry.md) — 권리자 문의 가이드

## 크레딧

캐릭터 그림마다 권리자, 라이선스, 출처를 **[CREDITS.md](CREDITS.md)** 에 정리해 뒀어요. 앱에서는 펫 오른쪽 클릭 → 펫 바꾸기 → **크레딧 보기…** 로 볼 수 있고, 지금 고른 팩의 표기는 메뉴의 "그림:" 줄에 나와요.

| 캐릭터 | 권리자 | 라이선스 |
|---|---|---|
| 새싹, 자체 동물 10종 | CLIPet (이 저장소) | MIT |
| Fluent Emoji 동물 8종 | Microsoft | MIT |
| oneko 고양이 | Masayuki Koba, Tatsuya Kato | 퍼블릭 도메인 |
| Ferris | Karen Rustad Tölva | CC0 |
| Go Gopher | Renée French | CC BY 4.0 |
| Tux | Larry Ewing, The GIMP (SVG: Garrett LeSage) | CC0 |
| Duke | Sun Microsystems / Oracle | BSD-3-Clause |
| Kodee | JetBrains s.r.o. | CC BY 4.0 |
| Android 로봇 | Google | CC BY 3.0 |
| Zig 마스코트 3종 | Zig 프로젝트 | CC BY 4.0 |
| Phippy와 친구들 12종 | The Linux Foundation (CNCF), phippy.io | CC BY 4.0 |

## 라이선스

앱 코드, 스크립트, 플러그인, 문서는 [MIT 라이선스](LICENSE)예요.

- **`packs/` 안의 그림에는 앱 코드 라이선스가 적용되지 않아요.** 각 팩 폴더의 `LICENSE`에 권리자, 라이선스, 표기 문구, 출처가 있어요.
- 모든 캐릭터 팩은 **비공식**이에요. 각 프로젝트·회사와 관련이 없고, 보증받지 않았어요. 이름과 로고는 각 권리자의 상표예요.
- 자체 캐릭터(새싹, 자체 동물 10종)는 이 저장소의 코드로 그려져요.
