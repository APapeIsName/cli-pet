# AI 도구·IDE 연결

CLIPet은 AI 코딩 도구의 **훅**(이벤트가 생길 때 명령을 실행하는 기능)으로 상태를 받아요. 연결 상태는 이렇게 봐요.

```bash
cli-pet connections           # 도구별 연결 상태
cli-pet connect codex         # 연결 (claude, codex, copilot, gemini, cursor, all)
cli-pet disconnect codex      # 연결 해제
```

펫 오른쪽 클릭(또는 메뉴 막대 아이콘) → **AI 도구 연결**에서도 켜고 끌 수 있어요. 연결할 때 원래 설정 파일은 `<파일>.cli-pet-backup`으로 백업하고, CLIPet이 넣은 항목만 고쳐요.

## 연결되는 도구

| 도구 | 연결 방법 | 설정 파일 | 확인 상태 |
|---|---|---|---|
| **Claude Code** (터미널) | `cli-pet connect claude` | `~/.claude/settings.json` | ✅ 직접 확인 |
| Claude Code VS Code·JetBrains 확장, 데스크톱 앱 | Claude Code를 연결하면 같이 적용 | 같은 파일 | 📄 공식 문서 기준 ("어디서 실행해도 같은 훅") |
| **Cursor** (IDE 에이전트) | Claude Code를 연결하면 같이 적용 | Cursor가 `~/.claude/settings.json` 훅을 기본으로 가져옴 | 📄 문서 기준 |
| **OpenAI Codex** (CLI, IDE 확장, 앱) | `cli-pet connect codex` 후 Codex에서 `/hooks`로 한 번 **신뢰** | `~/.codex/hooks.json` | ✅ CLI 0.157.1에서 확인 (세션 시작 → 생각 중 → 명령 실행 → 완료) |
| **GitHub Copilot CLI** | `cli-pet connect copilot` | `~/.copilot/hooks/cli-pet.json` (전용 파일) | 📄 문서 기준 |
| **Gemini CLI** | `cli-pet connect gemini` (훅이 꺼져 있으면 `/hooks enable-all`) | `~/.gemini/settings.json` | 📄 문서 기준. 개인 계정은 Google이 Gemini CLI 지원을 끝내서 확인하지 못했어요 (기업 계정용) |

- ✅ 직접 확인: 실제로 연결해서 펫이 반응하는 것까지 봤어요.
- 📄 문서 기준: 공식 문서에 있는 훅 형식과 예시 데이터로 CLIPet이 올바르게 읽는 것까지 확인했어요. 그 도구를 실제로 돌려서 확인하지는 않았어요. 안 되면 [이슈](https://github.com/APapeIsName/cli-pet/issues)로 알려 주세요.
- **Cursor를 따로 연결하지 않는 이유:** Cursor가 Claude Code 훅을 이미 가져오기 때문에, 따로 넣으면 같은 알림이 두 번 가요. 다만 가져온 훅에는 알림(권한 요청) 이벤트가 없어서, Cursor에서는 "나 좀 봐줘" 상태가 나오지 않아요.
- **Codex:** 최근 데스크톱 앱 업데이트 뒤 훅이 실행되지 않는다는 보고가 있어요 ([openai/codex#21639](https://github.com/openai/codex/issues/21639)).

## 설정 몇 줄로 되는 도구

`cli-pet status <idle|think|working|done|alert> [글]` 과 `cli-pet say <글>` 로 어떤 도구든 펫을 움직일 수 있어요. 아래는 공식 문서를 보고 만든 예시예요. 직접 확인하지는 않았어요.

### Aider

응답이 끝날 때만 알림을 줘요.

```bash
aider --notifications --notifications-command "cli-pet status done"
```

### Neovim (CodeCompanion)

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = { "CodeCompanionRequestStarted", "CodeCompanionRequestFinished" },
  callback = function(ev)
    local state = ev.match == "CodeCompanionRequestStarted" and "think" or "done"
    vim.system({ "cli-pet", "status", state })
  end,
})
```

### OpenCode

`~/.config/opencode/plugins/cli-pet.js`:

```js
export const CliPet = async ({ $ }) => ({
  "tool.execute.before": async (input) => { await $`cli-pet status working ${input.tool}`.nothrow() },
  "permission.asked": async () => { await $`cli-pet status alert 허락이 필요해요`.nothrow() },
  "session.idle": async () => { await $`cli-pet status done`.nothrow() },
})
```

> Homebrew로 설치하지 않았다면 `cli-pet` 대신 `~/Applications/CLIPet.app/Contents/MacOS/cli-pet` 을 쓰세요.

## 아직 안 되는 것 (다음 버전 후보)

| 도구 | 이유 |
|---|---|
| VS Code 자체 이벤트 (빌드, 테스트, 터미널 명령, 디버그) | 작은 VS Code 확장이 필요해요. 만들면 Cursor, Windsurf, Kiro, Antigravity에도 같이 적용돼요 |
| Google Antigravity | 훅은 있지만 이벤트 이름을 보내지 않아서, 이벤트마다 따로 설정해야 해요 (`cli-pet hook --event`) |
| Windsurf(Devin Desktop), Kiro, Cline | 훅 형식이 다르거나 문서가 아직 바뀌는 중이에요 |
| Xcode의 Claude·Codex 에이전트 | 훅 지원이 공식 문서에 없어요. 실험이 필요해요 |
| JetBrains Junie | CLI에서만 훅이 돌고, IDE 안에서는 아직 안 돌아요 |
| Zed·Warp 자체 에이전트, Jules, Visual Studio | 훅이 없거나, 클라우드 전용이거나, Windows 전용이에요 |

## 안 될 때

```bash
cli-pet debug on     # 훅으로 받은 입력을 ~/.cli-pet/hooks.log 에 남기기
# … 도구에서 한 번 써 보기 …
cli-pet debug log    # 기록 보기
cli-pet debug off
```

기록이 비어 있으면 그 도구가 훅을 실행하지 않은 거예요 (연결, 신뢰, 도구 버전 확인). 기록은 있는데 펫이 반응하지 않으면 [이슈](https://github.com/APapeIsName/cli-pet/issues)에 기록 한 줄을 붙여 알려 주세요.

## 직접 연결하기 (고급)

어떤 도구든 훅이 JSON을 표준 입력으로 넘겨준다면 이렇게 연결할 수 있어요.

```bash
cli-pet hook [--event <이벤트>] [--json]
```

- 이벤트 이름은 대소문자와 표기 차이를 알아서 맞춰요. 예: `PreToolUse`, `preToolUse`, `BeforeTool` → 작업 중. `UserPromptSubmit`, `beforeSubmitPrompt`, `BeforeAgent` → 생각 중. `Stop`, `agentStop`, `AfterAgent` → 완료. `Notification`, `PermissionRequest` → 날 봐줘.
- 입력에 이벤트 이름이 없으면 `--event`로 알려 주세요.
- 표준 출력이 JSON이어야 하는 도구라면 `--json`을 붙이면 `{}`를 출력해요.
- 이 명령은 항상 성공(exit 0)으로 끝나서 도구의 작업을 막지 않아요.
