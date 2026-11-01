#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR"

echo "=========================================================="
echo "  Building AutoApply Pro (Universal Native macOS App)    "
echo "=========================================================="

echo "==> Compiling Swift Package in Release configuration..."
swift build -c release

BIN_PATH=$(find .build -path "*/Release/AutoApplyMac" -type f -perm +111 | head -n 1)

if [ -z "$BIN_PATH" ]; then
    echo "Error: Release binary not found!"
    exit 1
fi

# Dynamic destination directory (defaults to user's Desktop)
APP_DIR="${APP_OUTPUT_DIR:-$HOME/Desktop/AutoApply.app}"
echo "==> Creating Self-Contained App Bundle at: $APP_DIR"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Helpers"
mkdir -p "$APP_DIR/Contents/Resources"

# 1. Install Main Executable
cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/AutoApply"
chmod +x "$APP_DIR/Contents/MacOS/AutoApply"

# 2. Bundle Lightpanda helper inside app bundle for zero-dependency portability
LIGHTPANDA_FOUND=""
if [ -f "$HOME/.local/bin/lightpanda" ]; then
    LIGHTPANDA_FOUND="$HOME/.local/bin/lightpanda"
elif command -v lightpanda >/dev/null 2>&1; then
    LIGHTPANDA_FOUND=$(command -v lightpanda)
elif [ -f "/opt/homebrew/bin/lightpanda" ]; then
    LIGHTPANDA_FOUND="/opt/homebrew/bin/lightpanda"
elif [ -f "/usr/local/bin/lightpanda" ]; then
    LIGHTPANDA_FOUND="/usr/local/bin/lightpanda"
fi

if [ -n "$LIGHTPANDA_FOUND" ]; then
    echo "==> Bundling Lightpanda helper from: $LIGHTPANDA_FOUND"
    cp "$LIGHTPANDA_FOUND" "$APP_DIR/Contents/Helpers/lightpanda"
    chmod +x "$APP_DIR/Contents/Helpers/lightpanda"
else
    echo "==> Note: lightpanda binary not found in standard paths; background scraping will search user PATH."
fi

# 3. Install Native macOS App Icon
if [ -f "$DIR/Resources/AppIcon.icns" ]; then
    echo "==> Installing Native AppIcon.icns..."
    cp "$DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

# 4. Generate Standard Native macOS Info.plist
cat << 'EOF' > "$APP_DIR/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>AutoApply</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.autoapply.AutoApplyMac</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>AutoApply Pro</string>
    <key>CFBundleDisplayName</key>
    <string>AutoApply Pro</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0.0</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
    <key>NSDesktopFolderUsageDescription</key>
    <string>AutoApply Pro accesses your resumes and exports application receipts.</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>AutoApply Pro saves candidate profiles and resume records.</string>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>AutoApply Pro downloads application confirmation receipts.</string>
</dict>
</plist>
EOF

# 5. PkgInfo file
echo "APPL????" > "$APP_DIR/Contents/PkgInfo"

echo "==> Build and Packaging Complete!"
echo "Bundle location: $APP_DIR"
ls -la "$APP_DIR/Contents/MacOS"
ls -la "$APP_DIR/Contents/Resources"
if [ -d "$APP_DIR/Contents/Helpers" ]; then
    ls -la "$APP_DIR/Contents/Helpers"
fi
