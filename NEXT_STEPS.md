# 🎮 REmu — Senin Yapman Gerekenler

Hiç yazılımdan anlamasan bile yapabilirsin. Sırayla git, atlama.

---

## ADIM 1️⃣ — Xcode'u Kur (15 dk)

1. Mac'inde **App Store**'u aç
2. Arama çubuğuna **Xcode** yaz
3. **GET** → **INSTALL** (ücretsiz, ama ~10 GB, zamanın ve internetin olsun)
4. Kurulduktan sonra bir kere aç, "Agree" de, bitmesini bekle

---

## ADIM 2️⃣ — Otomatik Kurulumu Çalıştır (5 dk)

1. Mac'inde **Terminal** uygulamasını aç (Cmd+Space → "Terminal" yaz)
2. Şu komutu **kopyala-yapıştır**, Enter'a bas:

```bash
cd /Users/fatihkoca/REmu && ./bootstrap.sh
```

3. Şifren istenirse Mac'inin şifresini gir
4. Bitince "✅ KURULUM TAMAMLANDI" yazısını göreceksin

**Eğer hata alırsan:** Terminal çıktısını bana yapıştır, çözerim.

---

## ADIM 3️⃣ — Apple Developer Hesabı (10 dk, ücretsiz)

Uygulamayı iPhone'a kurmak için gerekli.

1. [appleid.apple.com](https://appleid.apple.com) adresine git
2. Apple ID'nle giriş yap (App Store'da kullandığın hesap)
3. Zaten hesabın var, ekstra bir şey yapmana gerek yok
4. **Team ID'ni bul:**
   - Xcode'u aç → menü çubuğu → **Xcode** → **Settings** → **Accounts** sekmesi
   - Sol altta **+** → **Apple ID** → hesabınla giriş yap
   - Sağ altta **Manage Certificates** olan alanın biraz üzerinde "Team" yazacak, oradaki 10 karakterlik kod senin Team ID'n (örnek: `ABCD123456`)

---

## ADIM 4️⃣ — Team ID'yi Projeye Yaz (2 dk)

1. Terminal'de şu dosyayı aç:

```bash
open -a TextEdit /Users/fatihkoca/REmu/project.yml
```

2. İçinde şu satırı bul:
```
DEVELOPMENT_TEAM: ""
```
3. Tırnakların içine Team ID'ni yaz:
```
DEVELOPMENT_TEAM: "ABCD123456"
```
4. Kaydet (Cmd+S), kapat
5. Terminal'e dön, şunu çalıştır:

```bash
cd /Users/fatihkoca/REmu && xcodegen generate
```

---

## ADIM 5️⃣ — Projeyi Xcode'da Aç (1 dk)

Terminal'de:

```bash
open /Users/fatihkoca/REmu/REmu.xcodeproj
```

Xcode açılacak. Sol tarafta dosya ağacı, üstte büyük bir ▶ oynat tuşu var.

**Henüz BASMA.** Önce core dosyalarını eklememiz lazım.

---

## ADIM 6️⃣ — Libretro Core Dosyalarını Al (20 dk)

Bu dosyalar emülatörün "motoru". Her konsol için ayrı bir motor var.

### Otomatik Deneme
Terminal'de:

```bash
cd /Users/fatihkoca/REmu && ./fetch-cores.sh
```

Çalışırsa harika. Çalışmazsa manuel:

### Manuel İndirme
1. Tarayıcıda aç: https://buildbot.libretro.com/nightly/apple/ios-arm64/latest/
2. Şu zip dosyalarını indir (her biri tıklayıp indir):
   - `mednafen_psx_libretro_ios.dylib.zip` (PS1)
   - `mupen64plus_next_libretro_ios.dylib.zip` (N64)
   - `ppsspp_libretro_ios.dylib.zip` (PSP)
   - `dolphin_libretro_ios.dylib.zip` (GameCube)
   - `pcsx2_libretro_ios.dylib.zip` (PS2)
3. Her zip'e çift tıkla (`.dylib` çıkar)
4. Tüm `.dylib` dosyalarını şu klasöre at:
   `/Users/fatihkoca/REmu/Resources/Cores/`

5. Terminal'de projeyi yeniden oluştur:
```bash
cd /Users/fatihkoca/REmu && xcodegen generate && open REmu.xcodeproj
```

---

## ADIM 7️⃣ — iPhone'u Bağla ve Çalıştır (5 dk)

1. iPhone'unu **USB kablo** ile Mac'e bağla
2. iPhone'da "Bu bilgisayara güven" → **Güven**
3. Xcode penceresinin üstünde:
   - "REmu" yazan yerin sağında **cihaz seçici** var
   - Oraya tıkla, **iPhone'unun adını** seç
4. Üstteki büyük **▶ (Play)** tuşuna bas
5. İlk sefer uzun sürer (2-5 dk)

### İlk Açılışta Hata
iPhone'da "Untrusted Developer" yazısı çıkarsa:
- iPhone → **Ayarlar** → **Genel** → **VPN ve Cihaz Yönetimi**
- Apple ID'ni bul, **Trust** de
- Uygulamayı iPhone'dan elle aç

---

## ADIM 8️⃣ — ROM ve BIOS (YASAL YÖNTEM)

### ROM (Oyun Dosyası)
Satın aldığın **fiziksel** oyun diskini/kartuşunu dijitalleştirmen lazım.

- **PS1/PS2 CD/DVD**: Mac'te disk sürücüsü varsa ImgBurn benzeri bir yazılımla `.iso` dosyasına dönüştür
- **N64 kartuş**: "Retrode" veya "Sanni Cartridge Reader" cihazı ~$100. USB'ye takıp kartuşu okutuyorsun
- **GameCube disk**: Moddlu Wii ile CleanRip kullanılır
- **PSP UMD**: PSP'nde CFW varsa direkt dump atabilirsin

Elindeki dosyaları uygulamaya aktarma:
1. Uygulama açıkken iPhone'da **Files** uygulamasını aç
2. Klasörlerde **REmu** görünecek
3. ROM dosyanı **AirDrop** veya iCloud ile iPhone'a at
4. Uygulamada **+** tuşuna bas → dosyayı seç

### BIOS (Bazı Konsoller İçin Zorunlu)
- PS1 için: kendi PS1'inden `scph1001.bin` gibi bir dump gerekli
- PS2 için: kendi PS2'nden BIOS dump
- BIOS'u iPhone **Files** → **REmu** → **System** klasörüne at

**ÖNEMLİ:** Ne ROM'u ne de BIOS'u internetten indirme — yasadışı. Kendi cihazından dump et.

---

## ADIM 9️⃣ — Fiziksel Gamepad (Opsiyonel)

Şu gamepad'ler otomatik çalışır (Bluetooth ile eşleştir, uygulamaya gir):
- PS4 DualShock 4
- PS5 DualSense
- Xbox One/Series kumandaları
- Backbone, GameSir gibi MFi kumandaları

Eşleştirme: iPhone → **Ayarlar** → **Bluetooth** → gamepad'i pairing moduna al → listeden seç

---

## ADIM 🔟 — Eğer JIT İstiyorsan (İleri Seviye)

JIT = emülatörü 3-5 kat daha hızlı yapan teknoloji. Zorunlu değil, PS1 için gerekmez.

Aktif etmek için:
1. Terminal'de:
```bash
open -a TextEdit /Users/fatihkoca/REmu/Resources/REmu.entitlements
```
2. Yorum satırları olan `<!-- -->` işaretlerini şu 2 blokta kaldır:
   - `com.apple.security.cs.allow-jit`
   - `com.apple.developer.cs.dynamic-codesigning`
3. Kaydet
4. **AltStore** kur (https://altstore.io) — Apple Developer hesabın ücretsiz olduğu için 7 günde bir yenilemen gerekecek
5. Uygulamayı AltStore ile imzalayıp kur

---

## ❓ Soru / Sorun Çıkarsa

Terminal'de olan hata mesajlarını, Xcode'daki kırmızı hata satırlarını bana göster. Adım adım çözeriz.

## ✅ Kontrol Listesi

- [ ] Xcode kuruldu
- [ ] `./bootstrap.sh` çalıştı
- [ ] Team ID `project.yml`'ye yazıldı
- [ ] `xcodegen generate` yeniden çalıştırıldı
- [ ] Libretro core `.dylib`'leri `Resources/Cores/` içinde
- [ ] iPhone USB ile bağlı
- [ ] Xcode'da cihaz seçildi
- [ ] ▶ Play basıldı, uygulama açıldı
- [ ] ROM import edildi, oyun başladı
