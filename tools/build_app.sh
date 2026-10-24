#!/bin/bash
# Сборка Nativ Pro для macOS: swift build → пакет .build/app/PhotoEditor.app (иконка, Info.plist) → запуск.
#   ./tools/build_app.sh            собрать и запустить
#   ./tools/build_app.sh --no-run   только собрать
set -euo pipefail
cd "$(dirname "$0")/.."
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "Сборка… (первый раз — несколько минут)"
swift build -c release --product PhotoEditor
bin="$(swift build -c release --product PhotoEditor --show-bin-path)/PhotoEditor"

app=".build/app/PhotoEditor.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/PhotoEditor"
# Каталог ресурсов: акцентный цвет + иконка из tools/app/Logo/icon.svg (в репозитории только SVG).
cp -R tools/app/Assets.xcassets "$work/Assets.xcassets"
xcrun swift tools/app/render_icon.swift tools/app/Logo/icon.svg "$work/Assets.xcassets/AppIcon.appiconset" >/dev/null || echo "иконка не отрисована"
xcrun actool "$work/Assets.xcassets" --compile "$app/Contents/Resources" --platform macosx --minimum-deployment-target 26.0 \
  --app-icon AppIcon --output-partial-info-plist "$work/actool-partial.plist" >/dev/null || echo "actool: ресурсы не собраны"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>PhotoEditor</string>
  <key>CFBundleIdentifier</key><string>ru.ect.photoeditor</string>
  <key>CFBundleName</key><string>Nativ Pro</string>
  <key>CFBundleDisplayName</key><string>Nativ Pro</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.2</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleDevelopmentRegion</key><string>ru</string>
  <key>CFBundleLocalizations</key><array><string>ru</string><string>en</string></array>
  <key>CFBundleAllowMixedLocalizations</key><true/>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAccentColorName</key><string>AccentColor</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Nativ Pro Document</string>
      <key>CFBundleTypeRole</key><string>Editor</string>
      <key>LSHandlerRank</key><string>Owner</string>
      <key>LSItemContentTypes</key><array><string>ru.ect.photoeditor.document</string></array>
      <key>NSDocumentClass</key><string>EditorDocument</string>
    </dict>
    <dict>
      <key>CFBundleTypeName</key><string>Image</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>public.png</string><string>public.jpeg</string><string>public.heic</string>
        <string>public.tiff</string><string>com.compuserve.gif</string><string>org.webmproject.webp</string>
      </array>
      <key>NSDocumentClass</key><string>EditorDocument</string>
    </dict>
  </array>
  <key>UTExportedTypeDeclarations</key>
  <array>
    <dict>
      <key>UTTypeIdentifier</key><string>ru.ect.photoeditor.document</string>
      <key>UTTypeDescription</key><string>Nativ Pro Document</string>
      <key>UTTypeConformsTo</key><array><string>public.data</string><string>public.image</string></array>
      <key>UTTypeTagSpecification</key>
      <dict><key>public.filename-extension</key><array><string>pedoc</string></array></dict>
    </dict>
  </array>
</dict>
</plist>
PLIST
codesign --force --sign - "$app" >/dev/null 2>&1
echo "Готово: $(pwd)/$app"
[ "${1:-}" = "--no-run" ] && exit 0
pkill -x PhotoEditor 2>/dev/null || true
open "$app"
