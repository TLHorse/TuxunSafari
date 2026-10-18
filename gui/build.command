#!/bin/zsh
set -euo pipefail
cd -- "${0:A:h}/.."
app="$PWD/dist/TuxunSafari.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$PWD/dist/module-cache"
xcrun swiftc -swift-version 5 -parse-as-library -O -target "$(uname -m)-apple-macosx13.0" \
  -module-cache-path "$PWD/dist/module-cache" gui/TuxunSafari.swift -o "$app/Contents/MacOS/TuxunSafari"
cp tuxun.py runner.js config.json "$app/Contents/Resources/"
iconset="$PWD/dist/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" gui/Assets/AppIcon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" gui/Assets/AppIcon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>TuxunSafari</string>
<key>CFBundleIdentifier</key><string>com.tlhorse.TuxunSafari</string>
<key>CFBundleName</key><string>TuxunSafari</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.1.1</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppleEventsUsageDescription</key><string>通过 Apple 事件读取 Safari 中的图寻对局并提交所选位置。</string>
</dict></plist>
PLIST
xattr -cr "$app"
codesign --force --sign - "$app"
print "已构建：$app"
