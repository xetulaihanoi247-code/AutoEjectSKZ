#!/bin/bash
# Build AutoEject.app (menu bar app) và (tuỳ chọn) cài vào /Applications.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/AutoEject.app"
rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Build universal (Apple Silicon + Intel)
for ARCH in arm64 x86_64; do
  swiftc -O -target "$ARCH-apple-macos13.0" AutoEject.swift -o "build/AutoEject-$ARCH" \
    -framework Cocoa -framework IOKit -framework ServiceManagement
done
lipo -create build/AutoEject-arm64 build/AutoEject-x86_64 -output "$APP/Contents/MacOS/AutoEject"
rm build/AutoEject-arm64 build/AutoEject-x86_64

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>AutoEject</string>
  <key>CFBundleIdentifier</key><string>local.tatrilinh.autoeject</string>
  <key>CFBundleExecutable</key><string>AutoEject</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
EOF

codesign --force --sign - "$APP"
echo "Đã build: $(pwd)/$APP"

if [[ "${1:-}" == "--zip" ]]; then
  ditto -c -k --keepParent "$APP" build/AutoEject.zip
  echo "Đã đóng gói: $(pwd)/build/AutoEject.zip"
fi

if [[ "${1:-}" == "--install" ]]; then
  pkill -x AutoEject 2>/dev/null || true
  rm -rf /Applications/AutoEject.app
  cp -R "$APP" /Applications/
  open /Applications/AutoEject.app
  LSR=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  "$LSR" -u "$PWD/$APP" 2>/dev/null || true
  rm -rf build   # tránh Spotlight hiện trùng 2 bản AutoEject
  echo "Đã cài vào /Applications và khởi chạy."
fi
