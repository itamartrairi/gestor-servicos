#!/usr/bin/env bash
# Gera as pastas android/ e ios/ (se ainda não existirem) e aplica as
# permissões necessárias. Rode uma vez na raiz do projeto:
#   bash tool/preparar_plataformas.sh
set -euo pipefail

cd "$(dirname "$0")/.."

if [ ! -d android ] || [ ! -d ios ] || [ ! -d web ]; then
  flutter create --platforms=android,ios,web --org br.com.gestorservicos --project-name gestor_servicos .
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

# Versão web (PWA): nome, cores e modo "app" ao adicionar à tela inicial.
if [ -f web/manifest.json ]; then
  python3 - <<'EOF2'
import json, re
m = json.load(open('web/manifest.json', encoding='utf-8'))
m.update({'name': 'Gestor de Serviços', 'short_name': 'Gestor', 'description': 'Agenda, vendas, DRE e fluxo de caixa',
          'background_color': '#FBF3F7', 'theme_color': '#B4457A', 'display': 'standalone', 'orientation': 'portrait'})
json.dump(m, open('web/manifest.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
h = open('web/index.html', encoding='utf-8').read()
h = re.sub(r'<title>.*?</title>', '<title>Gestor de Serviços</title>', h)
h = re.sub(r'(name="apple-mobile-web-app-title" content=")[^"]*', r'\1Gestor', h)
h = re.sub(r'(name="description" content=")[^"]*', r'\1Gestor de Serviços - agenda, vendas, DRE e fluxo de caixa', h)
if 'theme-color' not in h:
    h = h.replace('</head>', '  <meta name="theme-color" content="#B4457A">\n</head>')
open('web/index.html', 'w', encoding='utf-8').write(h)
EOF2
fi

# Ícone do app (Android, iPhone e web) a partir de assets/icon.
flutter pub get
dart run flutter_launcher_icons

echo "Plataformas prontas. Agora: flutter run"
