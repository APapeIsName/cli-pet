# 남은 일 (2026-10-10 기준)

## 직접 해야 하는 일

| 할 일 | 이유 |
|---|---|
| Codex에서 `/hooks`를 열고 CLIPet 훅 신뢰하기 (안 쓸 거면 `cli-pet disconnect codex`) | 개발 Mac에 Codex가 연결돼 있지만 아직 신뢰하지 않아서, 평소에는 훅이 돌지 않아요 |
| Command Line Tools 업데이트 (시스템 설정 → 소프트웨어 업데이트) | 개발 Mac의 도구가 오래돼서 `brew install`이 빌드를 거부해요. 업데이트 후 실제 설치를 확인해야 해요 |
| 커밋 이메일 공개 여부 정하기 | 커밋에 개인 이메일이 공개돼 있어요. 숨기려면 GitHub noreply 주소로 바꿔야 해요 |
| 권리자 문의 메일 보내기 | `inquiry.md`의 틀과 `packs.csv`의 "문의" 목록 |

## 아직 확인하지 못한 것

- 실제 `brew install APapeIsName/tap/cli-pet` (위 도구 업데이트가 필요)
- 실제 `/plugin marketplace add` → `/plugin install` (개발 Mac의 Claude Code 설정을 바꾸기 때문에 하지 않았어요)
- Copilot CLI 실제 연결 (설치돼 있지 않음), Gemini CLI (개인 계정은 Google이 지원을 끝냄)
- 새 메뉴와 아이템을 실제 앱에서 눌러 보기 (그림으로 그려 보고, 메뉴 구조를 출력해서 확인함)
- Claude Code VS Code·JetBrains 확장, 데스크톱 앱에서 실제 연결 (공식 문서 기준으로만 확인)

## 다음 기능 후보

| 후보 | 메모 |
|---|---|
| 장난감 더 만들기 | 슬랑이, 두쫀쿠, 치즈, 과일, 통통 스티커 (`toy-candidates.md`) |
| 아이템 더 만들기 | 계절 아이템(산타 모자, 꽃다발), 사용자가 그림으로 만드는 아이템 |
| VS Code 확장 | AI가 아닌 빌드·테스트·터미널 이벤트에도 반응. Cursor 등 VS Code 계열에도 적용 |
| 다른 도구 연결 | Antigravity, Windsurf, Kiro, Xcode 에이전트 (`integrations.md`) |
| 실패 반응 | 명령이 실패하면 시무룩 (`sad` 포즈) |
| 답변 한 줄 보여주기 | 일이 끝나면 답변 첫 줄을 말풍선에 (기본은 꺼 둠) |
| 비상업 팩 저장소 | 즌다몬, Unity-chan을 따로 받는 저장소 |

## 저장소 밖에만 있는 것 (개발 Mac)

- `packs-nc/` (즌다몬, Unity-chan) — `.gitignore`로 제외
- `~/.cli-pet/packs/` 개인 커스텀 팩 (포켓몬 6종, 헬로키티·라이언·치이카와 시험용) — 배포하지 않음
