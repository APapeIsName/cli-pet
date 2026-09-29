#!/bin/bash
# CLIPet 한 줄 설치:
#   curl -fsSL https://raw.githubusercontent.com/APapeIsName/cli-pet/main/install.sh | bash
# 연결 방식을 미리 정하려면: ... | CLI_PET_CONNECT=2 bash   (1 바로 연결, 2 플러그인, 3 연결 안 함)
set -euo pipefail

if [ "$(uname)" != "Darwin" ]; then
  echo "CLIPet은 macOS 전용이에요."
  exit 1
fi

if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "앱을 만들려면 Apple 개발 도구가 필요해요."
  echo "설치 창이 뜨면 '설치'를 누르고, 끝나면 이 명령을 다시 실행해 주세요."
  xcode-select --install 2>/dev/null || true
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "🌱 CLIPet 받는 중…"
git clone --quiet --depth 1 --branch "${CLI_PET_REF:-main}" https://github.com/APapeIsName/cli-pet.git "$tmp/cli-pet"
bash "$tmp/cli-pet/install.command"
