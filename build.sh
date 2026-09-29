#!/bin/bash
# CLIPet.app 을 만듭니다. 실행: ./build.sh && open CLIPet.app
set -euo pipefail
cd "$(dirname "$0")"
APP=CLIPet.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O main.swift -o "$APP/Contents/MacOS/cli-pet"
mkdir -p "$APP/Contents/Resources"
for d in packs packs-nc; do
  [ -d "$d" ] && cp -R "$d" "$APP/Contents/Resources/"
done
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>CLIPet</string>
  <key>CFBundleIdentifier</key><string>local.cli-pet</string>
  <key>CFBundleExecutable</key><string>cli-pet</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
echo "완료: $(pwd)/$APP"
