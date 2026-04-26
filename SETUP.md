# REmu — Xcode Setup

## 1. Gereksinimler
- macOS 13+ / Xcode 15+
- Apple Developer Team ID (ücretsiz hesap yeterli — 7 gün provisioning)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) → `brew install xcodegen`

## 2. Projeyi Üret
```bash
cd /Users/fatihkoca/REmu
xcodegen generate
open REmu.xcodeproj
```

## 3. Team ID'yi Ayarla
`project.yml` → `DEVELOPMENT_TEAM` alanına Apple Developer Team ID'ni yaz,
sonra `xcodegen generate` komutunu tekrar çalıştır.

(Alternatif: Xcode'da Signing & Capabilities sekmesinden elle seç.)

## 4. Libretro Core'larını Ekle
Her core için precompiled iOS `.dylib` gerekli. Kaynaklar:
- [libretro/RetroArch iOS releases](https://buildbot.libretro.com/nightly/apple/ios-arm64/latest/)
- Kendin derlemek: `make platform=ios-arm64` libretro-super içinden

Dosyaları şuraya koy:
```
REmu/
└── Resources/
    └── Cores/
        ├── mednafen_psx_libretro_ios.dylib
        ├── mupen64plus_next_libretro_ios.dylib
        ├── ppsspp_libretro_ios.dylib
        ├── dolphin_libretro_ios.dylib
        └── pcsx2_libretro_ios.dylib
```

Sonra `project.yml` içine:
```yaml
    sources:
      - path: Sources
      - path: Resources
      - path: Resources/Cores   # ← ekle
```
ve `xcodegen generate` tekrar.

## 5. BIOS Dosyaları (Gerekliyse)
Kullanıcı uygulama yüklendikten sonra Files app → REmu → System
klasörüne kendi dump'larını kopyalar. Sen ürüne BIOS EKLEMEZSİN.

## 6. İlk Çalıştırma
1. Cihazı bağla (simulator'da Metal core'ları çalışmaz)
2. Xcode → Run
3. Uygulama açılır, ROM yoksa boş ekran görürsün
4. `+` ile ROM import et

## 7. JIT Açmak (Opsiyonel)
App Store dışı dağıtım için:
- `Resources/REmu.entitlements` içindeki iki JIT satırını yorumdan çıkar
- AltStore / Sideloadly ile imzala → JIT otomatik aktif olur

## 8. AdMob Entegrasyonu (Opsiyonel)
```bash
# Swift Package Manager:
# File → Add Package Dependencies
# https://github.com/googleads/swift-package-manager-google-mobile-ads
```
Sonra `AdBannerPlaceholder` yerine gerçek `GADBannerView` wrapper'ı yaz.

## Sorun Giderme
| Hata | Çözüm |
|---|---|
| `Undefined symbol: _retro_init` | `.dylib` dosyaları Bundle'da değil |
| `dlopen failed` | Code signing sorunu, embed-and-sign ayarı kontrol |
| Siyah ekran | Core yüklendi ama BIOS eksik veya ROM yanlış format |
| Ses yok | `AVAudioSession` izni veya background audio mode eksik |
| Crash on launch | Bridging header path yanlış, pbxproj'de düzelt |
