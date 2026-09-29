#!/bin/bash
# 더블클릭하면 CLIPet을 설치합니다.
set -euo pipefail
cd "$(dirname "$0")"
echo "🌱 CLIPet 설치를 시작할게요"
echo

if xcrun --find swiftc >/dev/null 2>&1; then
  ./build.sh
elif [ ! -d CLIPet.app ]; then
  echo "앱을 만들려면 Apple 개발 도구가 필요해요."
  echo "설치 창이 뜨면 '설치'를 누르고, 끝나면 이 파일을 다시 더블클릭해 주세요."
  xcode-select --install 2>/dev/null || true
  read -n 1 -s -r -p "아무 키나 누르면 닫혀요…"
  exit 1
fi

DEST="$HOME/Applications"
mkdir -p "$DEST"
pkill -f "CLIPet.app/Contents/MacOS/cli-pet" 2>/dev/null || true
sleep 0.3
rm -rf "$DEST/CLIPet.app"
cp -R CLIPet.app "$DEST/"
xattr -dr com.apple.quarantine "$DEST/CLIPet.app" 2>/dev/null || true
echo "✓ $DEST/CLIPet.app 에 설치"

echo
echo "Claude Code와 어떻게 연결할까요?"
echo "  1) 지금 바로 연결 (~/.claude/settings.json 에 훅 추가, 원본은 백업)"
echo "  2) 플러그인으로 연결 (Claude Code에서 /plugin 으로 직접 설치)"
echo "  3) 연결하지 않기"
read -r -p "번호 [1]: " choice
case "${choice:-1}" in
  2|3) "$DEST/CLIPet.app/Contents/MacOS/cli-pet" install --no-hooks ;;
  *)   "$DEST/CLIPet.app/Contents/MacOS/cli-pet" install ;;
esac
if [ "${choice:-1}" = "2" ]; then
  echo
  echo "Claude Code에서 아래 두 줄을 실행하세요:"
  echo "  /plugin marketplace add APapeIsName/cli-pet"
  echo "  /plugin install cli-pet@cli-pet"
fi
open "$DEST/CLIPet.app"

echo
echo "끝! 펫은 화면 오른쪽 아래에 있어요. 오른쪽 클릭하면 메뉴가 나와요."
echo "지우고 싶으면 uninstall.command 를 더블클릭하세요."
read -n 1 -s -r -p "아무 키나 누르면 닫혀요…"
