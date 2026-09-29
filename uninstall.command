#!/bin/bash
# 더블클릭하면 CLIPet을 깨끗이 지웁니다.
set -uo pipefail
APP="$HOME/Applications/CLIPet.app"
BIN="$APP/Contents/MacOS/cli-pet"
[ -x "$BIN" ] || BIN="$(dirname "$0")/CLIPet.app/Contents/MacOS/cli-pet"
echo "🌱 CLIPet을 지울게요"
echo
if [ -x "$BIN" ]; then
  "$BIN" uninstall
else
  echo "✗ 앱을 찾지 못해서 Claude Code 설정은 그대로예요. ~/.claude/settings.json 의 cli-pet 훅을 직접 지워 주세요."
fi
pkill -f "CLIPet.app/Contents/MacOS/cli-pet" 2>/dev/null || true
rm -rf "$APP" "$HOME/.cli-pet"
echo "✓ 앱과 저장된 위치 정보 삭제"
echo
read -n 1 -s -r -p "아무 키나 누르면 닫혀요…"
