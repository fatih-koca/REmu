#!/bin/bash
# Libretro core .dylib dosyalarını indirir.
# Liste, REmu'nun software-rendering ile sorunsuz çalıştırabildiği
# core'larla sınırlı. HW-render isteyen core'lar (mupen64plus_next, ppsspp,
# dolphin, pcsx2) frontend'de OpenGL ES context gerektirir; o desteği
# eklemeden buraya almak hata verir.
#
# Desteklenen sistemler ve core eşlemesi:
#   snes9x          → SNES
#   mgba            → Game Boy + Game Boy Color + GBA (üç sistem, tek core)
#   fceumm          → NES
#   genesis_plus_gx → Sega Genesis + Master System + Game Gear (üç sistem)
#   mednafen_pce_fast → PC Engine / TurboGrafx-16 (kartuş oyunları BIOS istemez)
#   stella          → Atari 2600
#   mednafen_ngp    → Neo Geo Pocket / Color
#   mednafen_wswan  → WonderSwan / Color
#   mednafen_psx    → PlayStation 1 (DENEYSEL: kendi BIOS dosyanı ister,
#                     JIT olmadığı için hız oyuna/cihaza göre değişir)

set -e

cd "$(dirname "$0")"
mkdir -p Resources/Cores
cd Resources/Cores

BASE="https://buildbot.libretro.com/nightly/apple/ios-arm64/latest"

CORES=(
    "snes9x_libretro_ios.dylib.zip"
    "mgba_libretro_ios.dylib.zip"
    "fceumm_libretro_ios.dylib.zip"
    "genesis_plus_gx_libretro_ios.dylib.zip"
    "mednafen_pce_fast_libretro_ios.dylib.zip"
    "stella_libretro_ios.dylib.zip"
    "mednafen_ngp_libretro_ios.dylib.zip"
    "mednafen_wswan_libretro_ios.dylib.zip"
    "mednafen_psx_libretro_ios.dylib.zip"
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
