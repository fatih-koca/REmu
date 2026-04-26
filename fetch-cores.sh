#!/bin/bash
# Libretro core .dylib dosyalarını indirir
# NOT: libretro buildbot URL'leri zaman içinde değişebilir.
# Çalışmazsa manuel indir: https://buildbot.libretro.com/nightly/apple/ios-arm64/latest/

set -e

cd "$(dirname "$0")"
mkdir -p Resources/Cores
cd Resources/Cores

BASE="https://buildbot.libretro.com/nightly/apple/ios-arm64/latest"

CORES=(
    "mednafen_psx_libretro_ios.dylib.zip"
    "mupen64plus_next_libretro_ios.dylib.zip"
    "ppsspp_libretro_ios.dylib.zip"
    "dolphin_libretro_ios.dylib.zip"
    "pcsx2_libretro_ios.dylib.zip"
)

for core in "${CORES[@]}"; do
    echo "⬇️  $core"
    if curl -fsSL -o "$core" "$BASE/$core"; then
        unzip -o "$core" > /dev/null
        rm "$core"
        echo "   ✅ $core"
    else
        echo "   ⚠️  indirilemedi — manuel indirmen lazım"
    fi
done

echo ""
echo "📁 Core dosyaları: $(pwd)"
ls -lh *.dylib 2>/dev/null || echo "   (hiçbiri indirilemedi — manuel indir)"
