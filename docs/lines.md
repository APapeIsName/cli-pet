# 상황별 대사 바꾸기

펫이 하는 말을 상황마다 바꿀 수 있어요.

## 바꾸는 법

- 펫 오른쪽 클릭 → **대사 바꾸기…** 를 누르면 텍스트 편집기에서 `~/.cli-pet/lines.json` 이 열려요.
- 터미널에서는 `cli-pet lines` 를 치면 파일을 만들고 위치와 상황 목록을 보여줘요.
- 파일이 없으면 기본 대사로 채워서 만들어요. **저장하면 바로 적용**돼요. 앱을 다시 켤 필요는 없어요.

```json
{
  "poke": ["히히", "간지러워!", "또 눌렀어?"],
  "done": "끝! 커피 한잔 해 ☕",
  "tool.run": ["$ {command}", "{command} 돌리는 중…"],
  "held": ["으앗, 내려줘!"],
  "think": []
}
```

- 여러 개를 적으면 그중 하나를 무작위로 골라요. 한 줄만 쓸 때는 `"문장"` 으로 써도 돼요.
- 빈 목록 `[]` 이면 그 상황에서는 말하지 않아요.
- 줄을 지우면 그 상황은 기본 대사로 돌아가요.
- `{file}` 처럼 중괄호로 쓴 칸은 그때의 값으로 바뀌어요.
- 파일에 문법 오류가 있으면 전부 기본 대사를 써요.

## 상황 목록

| 상황 | 언제 | 기본 대사 |
|---|---|---|
| `hello` | 앱을 켰을 때, Claude Code 세션이 시작될 때 | 안녕! 👋 |
| `think` | Claude Code에 프롬프트를 보냈을 때 | 음… 생각 중 |
| `tool.read` | 파일 읽기 — {file} | 📖 {file} |
| `tool.edit` | 파일 수정 — {file} | ✏️ {file} |
| `tool.run` | 명령 실행 — {command} | $ {command} |
| `tool.search` | 검색 — {pattern} | 🔍 {pattern} |
| `tool.web` | 웹 보기·검색 — {target} | 🌐 {target} |
| `tool.agent` | 도우미 에이전트 — {desc} | 🤖 {desc} |
| `tool.todo` | 할 일 목록 정리 | 📝 할 일 정리 중 |
| `tool.mcp` | MCP 도구 — {name} | 🔌 {name} |
| `tool.other` | 그 밖의 도구 — {name} | 🔧 {name} |
| `alert` | 권한 요청·입력 기다림 — {message}는 Claude Code가 보낸 문장 | {message} |
| `done` | Claude Code가 답을 끝냈을 때 | 다 했어! ✨ |
| `pipe.done` | cli-pet pipe 로 보던 명령이 끝났을 때 | 끝났어! ✨ |
| `poke` | 클릭했을 때 | 히히, 간지러워!, 왜~?, 놀아줘!, ♪, 헤헤, 뭐해? |
| `dizzy` | 빠르게 5번 클릭했을 때 | 어지러워~ 😵 |
| `wake` | 자고 있을 때 클릭했을 때 | 으음… 왜~ |
| `held` | 들어 올렸을 때 | (말하지 않음) |
| `land` | 내려놓았을 때 | (말하지 않음) |
| `switch` | 펫을 바꿨을 때 — {name} | 짠! {name} |

## 캐릭터마다 다른 말투 (팩 대사)

팩의 `pack.json`에 `lines`를 넣으면 그 팩을 고른 동안에만 쓰는 대사가 돼요. 형식은 위와 같아요.

```json
{
  "id": "game-myseries-mychar",
  "poses": { "normal": "normal.png" },
  "lines": {
    "poke": ["냥!", "냐앙~"],
    "done": "다 했다냥"
  }
}
```

## 대사를 고르는 순서

1. `~/.cli-pet/lines.json` (내가 바꾼 대사)
2. 지금 고른 팩의 `lines`
3. 기본 대사

내가 바꾼 대사가 가장 먼저예요. 팩마다 다른 말투를 쓰고 싶다면 `lines.json`에서는 그 상황을 지워 두세요.
