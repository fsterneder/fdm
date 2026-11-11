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
app="dist/fdm.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/fdm" "$app/Contents/MacOS/fdm"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>fdm</string>
<key>CFBundleIdentifier</key><string>app.metronom.desktop</string>
<key>CFBundleName</key><string>fdm</string>
<key>CFBundleDisplayName</key><string>fdm</string>
<key>CFBundleIconFile</key><string>AppIcon.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.16.0</string>
<key>CFBundleVersion</key><string>29</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
icon_builder="$(mktemp -d)"
trap 'rm -rf "$icon_builder"' EXIT
xcrun swiftc -parse-as-library -framework AppKit Sources/Metronom/InstrumentIcon.swift scripts/make-icon.swift -o "$icon_builder/make-icon"
"$icon_builder/make-icon" "$app/Contents/Resources/AppIcon.icns"
/usr/bin/sips -g format "$app/Contents/Resources/AppIcon.icns" >/dev/null
codesign --force --deep --sign - "$app"
touch "$app"
# Register this freshly built bundle without resetting the user's icon caches.
registrar="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$registrar" ]]; then
  "$registrar" -f "$app" || echo "Launch Services will refresh the icon when the app is opened." >&2
fi
ditto -c -k --sequesterRsrc --keepParent "$app" dist/fdm-0.16.0.zip
echo "Built $PWD/$app"
echo "Run it: open dist/fdm.app"

