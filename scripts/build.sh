#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo "Build this app on a Mac with macOS 13 or later." >&2
  exit 1
fi
if ! xcrun --find swift >/dev/null 2>&1; then
  echo "Install Apple Command Line Tools first: xcode-select --install" >&2
  exit 1
fi
swift build -c release
bin_dir="$(swift build -c release --show-bin-path)"
app="dist/fdm-3.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/fdm-3" "$app/Contents/MacOS/fdm-3"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>fdm-3</string>
<key>CFBundleIdentifier</key><string>app.metronom.desktop</string>
<key>CFBundleName</key><string>fdm-3</string>
<key>CFBundleDisplayName</key><string>fdm-3</string>
<key>CFBundleIconFile</key><string>AppIcon.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3.0</string>
<key>CFBundleVersion</key><string>4</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
/usr/bin/base64 -D < Assets/AppIcon.icns.base64 > "$app/Contents/Resources/AppIcon.icns"
/usr/bin/sips -g format "$app/Contents/Resources/AppIcon.icns" >/dev/null
codesign --force --deep --sign - "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" dist/fdm-3-0.3.0.zip
touch "$app"
echo "Built $PWD/$app"
echo "Run it: open dist/fdm-3.app"
