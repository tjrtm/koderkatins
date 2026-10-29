#!/bin/zsh
# Build Koderkatins.app into ./build.  Pass --install to copy it to ~/Applications.
# Every folder in ./pets (spritesheet.webp + pet.json) is bundled as a skin.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Koderkatins"
BUNDLE_ID="${BUNDLE_ID:-io.github.koderkatins}"
VERSION="${VERSION:-1.3.0}"
APP="build/$APP_NAME.app"
PETS="$APP/Contents/Resources/Pets"

command -v swiftc >/dev/null || { echo "swiftc not found: run  xcode-select --install"; exit 1; }
python3 -c "import PIL" 2>/dev/null || { echo "Pillow not found: run  python3 -m pip install --user pillow"; exit 1; }

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$PETS" build/AppIcon.iconset

echo "› compiling"
swiftc -O -swift-version 5 -o "$APP/Contents/MacOS/$APP_NAME" Sources/*.swift

echo "› skins + icon"
if [[ -d pets ]]; then
  for d in pets/*(N/); do
    [[ -f "$d/spritesheet.webp" || -f "$d/spritesheet.png" ]] || continue
    mkdir -p "$PETS/${d:t}"
    cp "$d"/spritesheet.* "$PETS/${d:t}/"
    [[ -f "$d/pet.json" ]] && cp "$d/pet.json" "$PETS/${d:t}/"
    echo "  + ${d:t}"
  done
fi
# App icon: first idle frame of the mascot when present
if [[ -f pets/koderkatis/spritesheet.webp ]]; then
  python3 - pets/koderkatis/spritesheet.webp build/icon.png <<'PY'
import sys
from PIL import Image
f = Image.open(sys.argv[1]).convert("RGBA").crop((0, 0, 192, 208))
f = f.crop(f.getbbox()); s = max(f.size)
c = Image.new("RGBA", (s, s)); c.paste(f, ((s - f.width) // 2, (s - f.height) // 2))
c.resize((1024, 1024), Image.LANCZOS).save(sys.argv[2])
PY
fi
for z in 16 32 128 256 512; do
  sips -z $z $z build/icon.png --out build/AppIcon.iconset/icon_${z}x${z}.png >/dev/null
  sips -z $((z*2)) $((z*2)) build/icon.png --out build/AppIcon.iconset/icon_${z}x${z}@2x.png >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
EOF

codesign --force --deep --sign - "$APP"
# no extended attributes / resource forks, so the zip has no "._" files
rm -f "build/$APP_NAME-$VERSION.zip"
(cd build && ditto -c -k --norsrc --noextattr --noacl --keepParent "$APP_NAME.app" "$APP_NAME-$VERSION.zip")
echo "✓ built $APP and build/$APP_NAME-$VERSION.zip"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x "$APP_NAME" 2>/dev/null || true
  mkdir -p ~/Applications
  rm -rf ~/Applications/"$APP_NAME.app"
  cp -R "$APP" ~/Applications/
  echo "✓ installed ~/Applications/$APP_NAME.app"
fi
