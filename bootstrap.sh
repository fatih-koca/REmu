#!/bin/bash
# REmu sıfırdan kurulum scripti
# Kullanım: ./bootstrap.sh

set -e

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  REmu — Otomatik Kurulum"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 1. Xcode Command Line Tools
if ! xcode-select -p &> /dev/null; then
    echo "📦 Xcode Command Line Tools kuruluyor..."
    xcode-select --install
    echo "❗ Bir pencere açıldı. 'Install' tuşuna bas, bittikten sonra bu script'i TEKRAR çalıştır."
    exit 0
fi
echo "✅ Xcode Command Line Tools hazır"

# 2. Homebrew
if ! command -v brew &> /dev/null; then
    echo "📦 Homebrew kuruluyor (şifre isteyecek)..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Apple Silicon için PATH ekle
    if [[ $(uname -m) == "arm64" ]]; then
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
fi
echo "✅ Homebrew hazır"

# 3. XcodeGen
if ! command -v xcodegen &> /dev/null; then
    echo "📦 XcodeGen kuruluyor..."
    brew install xcodegen
fi
echo "✅ XcodeGen hazır"

# 4. Gerekli klasörleri oluştur
mkdir -p Resources/Cores
mkdir -p Resources/Assets.xcassets/AppIcon.appiconset
mkdir -p Resources/Assets.xcassets/AccentColor.colorset

# 5. Minimal asset catalog (uygulama ikonu için)
cat > Resources/Assets.xcassets/Contents.json <<'EOF'
{ "info": { "author": "xcode", "version": 1 } }
EOF

cat > Resources/Assets.xcassets/AppIcon.appiconset/Contents.json <<'EOF'
{
  "images": [
    { "idiom": "universal", "platform": "ios", "size": "1024x1024" }
  ],
  "info": { "author": "xcode", "version": 1 }
}
EOF

cat > Resources/Assets.xcassets/AccentColor.colorset/Contents.json <<'EOF'
{
  "colors": [
    {
      "idiom": "universal",
      "color": {
        "color-space": "srgb",
        "components": { "red": "0.0", "green": "0.478", "blue": "1.0", "alpha": "1.0" }
      }
    }
  ],
  "info": { "author": "xcode", "version": 1 }
}
EOF

echo "✅ Klasör yapısı hazır"

# 6. Xcode projesini üret
echo "🔨 Xcode projesi oluşturuluyor..."
xcodegen generate

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ KURULUM TAMAMLANDI"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Şimdi şunu çalıştır:"
echo ""
echo "    open REmu.xcodeproj"
echo ""
echo "Sonra NEXT_STEPS.md dosyasını oku — geri kalan adımlar orada."
echo ""
