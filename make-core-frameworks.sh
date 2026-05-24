#!/bin/bash
# Wrap each libretro core .dylib (in Resources/Cores) into a proper iOS
# .framework bundle under CoreFrameworks/.
#
# WHY: Apple's App Store validation (error 90171) forbids standalone .dylib
# files anywhere in the app bundle — a dynamic library may only ship inside a
# valid bundle (a .framework). project.yml declares each generated framework as
# an embedded + code-signed dependency, so Xcode's normal "Embed Frameworks"
# phase places and signs it in REmu.app/Frameworks. At runtime CoreBridge's
# findCoreDylib() dlopen()s the framework's Mach-O by absolute path.
#
# Run this BEFORE `xcodegen generate` whenever the cores change:
#   ./fetch-cores.sh && ./make-core-frameworks.sh && xcodegen generate

set -euo pipefail
cd "$(dirname "$0")"

SRC_DIR="Resources/Cores"
OUT_DIR="CoreFrameworks"
INSTALL_NAME_TOOL="$(xcrun -f install_name_tool 2>/dev/null || echo install_name_tool)"

if [ ! -d "$SRC_DIR" ]; then
  echo "error: $SRC_DIR not found — run ./fetch-cores.sh first" >&2
  exit 1
fi

shopt -s nullglob
dylibs=("$SRC_DIR"/*.dylib)
if [ ${#dylibs[@]} -eq 0 ]; then
  echo "error: no .dylib files in $SRC_DIR" >&2
  exit 1
fi

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

for dylib in "${dylibs[@]}"; do
  base="$(basename "$dylib" .dylib)"            # e.g. snes9x_libretro_ios
  bundle_id_suffix="${base//_/-}"               # bundle IDs disallow underscores
  fw="$OUT_DIR/$base.framework"

  echo "📦 Wrapping $base → $fw"
  mkdir -p "$fw"
  cp -f "$dylib" "$fw/$base"

  # A framework binary's install name must be @rpath/Name.framework/Name.
  "$INSTALL_NAME_TOOL" -id "@rpath/$base.framework/$base" "$fw/$base"

  cat > "$fw/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$base</string>
    <key>CFBundleIdentifier</key>
    <string>com.fatihkoca.REmu2026.$bundle_id_suffix</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$base</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>iPhoneOS</string>
    </array>
    <key>MinimumOSVersion</key>
    <string>15.0</string>
</dict>
</plist>
PLIST
done

echo ""
echo "✅ Generated frameworks in $OUT_DIR:"
ls -1 "$OUT_DIR"
