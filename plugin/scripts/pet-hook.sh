#!/bin/bash
# Claude Code 훅 입력(stdin JSON)을 CLIPet 앱에 넘긴다.
# 앱이 없으면 아무 일도 하지 않고 조용히 끝난다 (Claude Code를 방해하지 않도록 항상 exit 0).
input="$(cat)"

app=""
for candidate in "${CLI_PET_APP:-}" "$HOME/Applications/CLIPet.app" "/Applications/CLIPet.app"; do
  if [ -n "$candidate" ] && [ -x "$candidate/Contents/MacOS/cli-pet" ]; then
    app="$candidate"
    break
  fi
done
[ -z "$app" ] && exit 0

# 세션이 시작될 때 펫이 떠 있지 않으면 띄운다 (CLI_PET_NO_AUTOSTART=1 이면 끔)
case "$input" in
  *'"SessionStart"'*)
    if [ -z "${CLI_PET_NO_AUTOSTART:-}" ] && ! pgrep -qf "CLIPet.app/Contents/MacOS/cli-pet$"; then
      open -g "$app" >/dev/null 2>&1 || true
    fi
    ;;
esac

printf '%s' "$input" | "$app/Contents/MacOS/cli-pet" hook >/dev/null 2>&1 || true
exit 0
