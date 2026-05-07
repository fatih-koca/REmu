# REmu

iOS için çok sistemli retro konsol emülatörü. PS1, PS2, N64, GameCube, PSP destekler.

## Başlamak İçin

Yazılımdan anlamayan biriysen: **[NEXT_STEPS.md](NEXT_STEPS.md)** dosyasını oku, adım adım takip et.

Geliştiriciysen:
```bash
./bootstrap.sh         # Bağımlılıklar + Xcode projesi
./fetch-cores.sh       # Libretro core .dylib'leri
open REmu.xcodeproj
```

## Mimari
- **UI**: SwiftUI (landscape-locked)
- **Render**: Metal
- **Core**: Libretro cores via `dlopen` + Objective-C++ bridge
- **Audio**: AVAudioEngine + lock-free ring buffer
- **Input**: Dokunmatik gamepad + MFi/DualSense/Xbox (GameController framework)
- **State**: FileManager-based save states + BIOS klasörü
- **Built-in Games**: Glowchase (özgün, telifsiz yılan demo)

## Proje Ağacı
```
REmu/
├── Sources/
│   ├── App/           # @main entry, AppDelegate
│   ├── Views/         # SwiftUI (ContentView, Tutorial, Gamepad)
│   ├── Metal/         # MTKView + renderer
│   ├── Bridge/        # CoreBridge.mm + bridging header
│   ├── Managers/      # Audio, SaveState, GameController
│   ├── Models/        # ROM library, ConsoleSystem
│   └── BuiltInGames/  # Glowchase — native SwiftUI demo
├── Resources/
│   ├── Info.plist
│   ├── Entitlements
│   ├── LaunchScreen
│   └── Cores/         # .dylib'ler buraya (git'e commit edilmez)
├── project.yml        # XcodeGen spec
├── bootstrap.sh       # Otomatik kurulum
└── fetch-cores.sh     # Libretro indirici
```

## Lisans
[MIT](LICENSE) — uygulama kaynak kodu MIT altında. Opsiyonel Libretro
çekirdekleri kendi lisansları (GPL v2 / v3) altında dağıtılır, bu repo'ya
commit edilmez; `fetch-cores.sh` ile kendi sorumluluğunda indirilir.

## Yasal Uyarı
Bu uygulama ROM veya BIOS dosyası **içermez**. Sadece kendi sahip olduğun
oyunların kendin dump'ladığın dosyalarını kullanabilirsin. Piracy **desteklenmez**.
