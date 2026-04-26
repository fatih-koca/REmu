# AltStore / JIT Enabler Olmadan Core Optimizasyonu

## Sorun
iOS, JIT (Just-In-Time) derlemesini varsayılan olarak yasaklar çünkü uygulamaların
kendi bellek alanına çalıştırılabilir kod yazması gerekir. Bu kısıtlama şu senaryolarda
geçerlidir:
- Sideloaded/Developer sertifikasıyla imzalanmış uygulamalar: `JIT KAPALIYDI`
- AltStore + JIT enabler: `MAP_JIT` flag açık, dynarec çalışır
- App Store: JIT tamamen yasak

## JIT Olmadan Neler Yapılabilir?

### 1. Interpreter Modu (Hep Çalışır, Yavaş)
Her core'un interpreter backend'i vardır. Sırf interpreter ile:
- PS1 → genellikle full speed (M1/M2 ile)
- N64 → %60-80 speed, bazı oyunlar oynamaz
- PS2/GameCube → çok yavaş

Mednafen PSX, mupen64plus, PPSSPP'nin interpreter modları vardır.
CoreBridge.mm'deki `libretro_environment()` içinde:
```c
case RETRO_ENVIRONMENT_GET_PERF_LEVEL:
    *(unsigned*)data = 4; // maximum → core kendi en iyi moduna geçer
    return true;
```

### 2. AOT (Ahead-of-Time) Derleme — iOS'ta Yasal ve Mümkün
`MAP_JIT` bayrağı olmadan sabit bellek bloklarına çalıştırılabilir kod yazmak
yasaktır. Ancak uygulama bundle'ı içindeki statik makine kodu tamamen serbesttir.

**Strateji: LLVM tabanlı "Ahead-of-Time Recompiler"**
- Oyun yüklendiğinde (ilk kez) ROM'un kod bölümlerini analiz et
- ARM64 makine koduna derle → `.aot` dosyası olarak Documents'e kaydet
- Sonraki açılışta `.aot` dosyasını `mmap(MAP_PRIVATE | PROT_READ | PROT_EXEC)` ile
  yükle — bu JIT DEĞİLDİR, statik dosya yükleme/mapping'dir ve App Store kurallarına uygundur.

Bu yöntemi kullanan gerçek proje: PPSSPP'nin "IR Interpreter" modu.

### 3. Metal Compute Shaders ile GPU-Yardımlı Emülasyon
PS2 / GameCube için gerçek iş yükü CPU değil GPU emülasyonudur.
Metal Compute ile:
```swift
// Texture cache, rasterizer, vertex transform → GPU'ya taşı
let commandBuffer = commandQueue.makeCommandBuffer()!
let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
computeEncoder.setComputePipelineState(gsEmulationPipeline)  // özel MTLComputePipelineState
computeEncoder.setBuffer(displayListBuffer, offset: 0, index: 0)
computeEncoder.dispatchThreadgroups(...)
```
Bu yaklaşım, hem JIT gerektirmez hem de M-series chip'in GPU'sunu tam kullanır.

### 4. ARM64 Native Assembly — En Yüksek Performans
JIT olmadan bile el yazısı ARM64 assembly kullanabilirsiniz:
- Xcode, `.s` / `.asm` dosyalarını doğrudan derler
- N64 MIPS → ARM64 çeviri tabloları (lookup table dynarec yerine static dispatch table)
- Her MIPS opcode için ARM64 fonksiyon pointer → switch tablosu yerine doğrudan dispatch

```c
// static_dispatch.h: MIPS opcode → ARM64 native handler
typedef void (*OpcodeHandler)(MIPSState* state, uint32_t instruction);
static const OpcodeHandler dispatch_table[64] = {
    handle_special, handle_regimm, handle_j, handle_jal, ...
};
// Bu tablo JIT değil, compile-time sabit → App Store uyumlu
```

### 5. Core-Spesifik Öneriler

| Core      | JIT Olmadan Öneri |
|-----------|-------------------|
| Mednafen PSX | Interpreter yeterli, M1+ full speed |
| PPSSPP    | IR Interpreter + Vulkan/Metal backend → %70-90 speed |
| mupen64plus | Interpreter + GlideN64 Metal port |
| PCSX2     | zaten interpreter ağırlıklı, ama yavaş |
| Dolphin   | JIT olmadan çok yavaş; GameCube için ideal değil |

### 6. Threading — Yanlış Anlaşılan Optimizasyon
JIT yoksa multithread daha kritik:
```swift
// CoreBridge: video ve audio'yu ayrı thread'de çalıştır
let coreQueue = DispatchQueue(label: "retronexus.core", qos: .userInteractive)
coreQueue.async { rn_core_run_frame() }
```
Metal rendering main thread'de, core ayrı thread'de → GPU ve CPU paralel çalışır.

### 7. Gerçek Çözüm: Developer Sertifikası + Entitlement
App Store dışı dağıtım (TestFlight/AltStore/sideload) için:
```xml
<!-- Entitlements.plist -->
<key>dynamic-codesigning</key>  <!-- iOS 14.4+ -->
<true/>
```
Bu entitlement ile `MAP_JIT` açılır, tüm dynarec backend'ler çalışır.
Apple Developer Program üyeliğiyle (ücretli) imzalanan uygulamalarda 7 gün (ücretsiz)
veya 1 yıl (ücretli) geçerlidir.

## Özet
JIT olmadan en iyi yol: **AOT + Metal Compute + ARM64 Assembly dispatch table**.
Full JIT için **developer sertifikası + `dynamic-codesigning` entitlement** şart.
