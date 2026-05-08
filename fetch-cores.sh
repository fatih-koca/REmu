#!/bin/bash
# Libretro core .dylib dosyalarını indirir.
# Liste, REmu'nun şu anda software-rendering ile sorunsuz çalıştırabildiği
# core'larla sınırlı. HW-render isteyen core'lar (mupen64plus_next, ppsspp,
# dolphin, pcsx2) frontend'de OpenGL ES context gerektirir; o desteği
# eklemeden buraya almak hata verir.

set -e

cd "$(dirname "$0")"
mkdir -p Resources/Cores
cd Resources/Cores

BASE="https://buildbot.libretro.com/nightly/apple/ios-arm64/latest"

CORES=(
    "snes9x_libretro_ios.dylib.zip"
    "mgba_libretro_ios.dylib.zip"
)

for core in "${CORES[@]}"; do
    echo "⬇️  $core"
    if curl -fsSL -o "$core" "$BASE/$core"; then
        unzip -o "$core" > /dev/null
        rm "$core"
        echo "   ✅ $core"
    else
        echo "   ⚠️  indirilemedi — manuel indir: $BASE/$core"
    fi
done

echo ""
echo "📁 Core dosyaları: $(pwd)"
ls -lh *.dylib 2>/dev/null || echo "   (hiçbiri indirilemedi — manuel indir)"
