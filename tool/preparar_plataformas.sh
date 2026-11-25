#!/usr/bin/env bash
# Gera as pastas android/ e ios/ (se ainda não existirem) e aplica as
# permissões necessárias. Rode uma vez na raiz do projeto:
#   bash tool/preparar_plataformas.sh
set -euo pipefail

cd "$(dirname "$0")/.."

if [ ! -d android ] || [ ! -d ios ]; then
  flutter create --platforms=android,ios --org br.com.gestorservicos --project-name gestor_servicos .
  # O template cria um teste de exemplo que não se aplica a este app.
  rm -f test/widget_test.dart
fi

# Nome exibido no aparelho.
if [ -f android/app/src/main/AndroidManifest.xml ]; then
  sed -i.bak 's/android:label="[^"]*"/android:label="Gestor de Serviços"/' android/app/src/main/AndroidManifest.xml
  rm -f android/app/src/main/AndroidManifest.xml.bak
fi

PLIST=ios/Runner/Info.plist
if [ -f "$PLIST" ] && ! grep -q NSPhotoLibraryUsageDescription "$PLIST"; then
  # Insere as chaves antes do último </dict>.
  python3 - "$PLIST" <<'EOF'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
extra = """	<key>NSPhotoLibraryUsageDescription</key>
	<string>Usado para escolher a logomarca do negócio.</string>
	<key>UIFileSharingEnabled</key>
	<true/>
	<key>LSSupportsOpeningDocumentsInPlace</key>
	<true/>
	<key>CFBundleDisplayName</key>
	<string>Gestor de Serviços</string>
"""
s = s.replace("<key>CFBundleDisplayName</key>\n\t<string>Gestor Servicos</string>\n", "")
i = s.rfind('</dict>')
s = s[:i] + extra + s[i:]
open(p, 'w', encoding='utf-8').write(s)
EOF
fi

# Ícone do app (Android e iPhone) a partir de assets/icon.
flutter pub get
dart run flutter_launcher_icons

echo "Plataformas prontas. Agora: flutter run"
