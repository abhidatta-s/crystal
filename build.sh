#!/bin/bash
# Builds "build/Crystal.app" with plain swiftc. Needs only the Xcode
# command line tools (xcode-select --install). No Xcode project, no deps.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Crystal"
EXECUTABLE="Crystal"
BUNDLE_ID="com.abhidatta.crystal"
VERSION="0.1.0"
BUILD_NUMBER="1"
MIN_MACOS="14.0"
ARCH="${ARCH:-arm64}"          # ARCH=x86_64 ./build.sh for an Intel Mac
SWIFT_MODE="${SWIFT_MODE:-5}"  # SWIFT_MODE=6 ./build.sh for Swift 6 strict concurrency

APP="build/$APP_NAME.app"

if ! xcrun --find swiftc >/dev/null 2>&1; then
    echo "swiftc not found. Install the command line tools: xcode-select --install" >&2
    exit 1
fi
SDK="$(xcrun --sdk macosx --show-sdk-path)"

echo "==> Cleaning"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> Compiling ($ARCH, macOS $MIN_MACOS+)"
xcrun swiftc \
    -O \
    -parse-as-library \
    -swift-version "$SWIFT_MODE" \
    -target "$ARCH-apple-macos$MIN_MACOS" \
    -sdk "$SDK" \
    -module-name "$EXECUTABLE" \
    -o "$APP/Contents/MacOS/$EXECUTABLE" \
    Sources/Crystal/*.swift

echo "==> Building AppIcon.icns"
ICON_SRC="Resources/AppIcon-1024.png"
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

echo "==> Writing Info.plist"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MIN_MACOS</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <!-- Let users open plain http:// pages in the web view. -->
        <key>NSAllowsArbitraryLoadsInWebContent</key>
        <true/>
    </dict>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Ad-hoc signing"
codesign --force --deep -s - "$APP"
codesign --verify --strict "$APP"

echo "==> Done: $APP"
du -sh "$APP"
