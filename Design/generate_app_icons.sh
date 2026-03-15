#!/bin/sh

set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
SVG_SOURCE="$ROOT_DIR/Design/AIChat-AppIcon.svg"
PREVIEW_PNG="$ROOT_DIR/Design/AIChat-AppIcon-preview.png"
IOS_ICON_DIR="$ROOT_DIR/AIChat iOS App/Assets.xcassets/AppIcon.appiconset"
WATCH_ICON_DIR="$ROOT_DIR/AIChat Watch App/Assets.xcassets/AppIcon.appiconset"

if ! command -v magick >/dev/null 2>&1; then
  echo "error: ImageMagick 'magick' is required" >&2
  exit 1
fi

if ! command -v qlmanage >/dev/null 2>&1; then
  echo "error: Quick Look 'qlmanage' is required" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

perl -0pe 's/ rx="232"//g' "$SVG_SOURCE" > "$TMP_DIR/AIChat-AppIcon-store.svg"

qlmanage -t -s 1024 -o "$TMP_DIR" "$TMP_DIR/AIChat-AppIcon-store.svg" >/dev/null 2>&1
magick "$TMP_DIR/AIChat-AppIcon-store.svg.png" -alpha off "$TMP_DIR/master-1024.png"

qlmanage -t -s 512 -o "$TMP_DIR" "$SVG_SOURCE" >/dev/null 2>&1
cp "$TMP_DIR/AIChat-AppIcon.svg.png" "$PREVIEW_PNG"

mkdir -p "$IOS_ICON_DIR" "$WATCH_ICON_DIR"

while IFS=':' read -r name size; do
  magick "$TMP_DIR/master-1024.png" -resize "${size}x${size}" "$IOS_ICON_DIR/${name}.png"
done <<'EOF'
iphone-notification-20@2x:40
iphone-notification-20@3x:60
iphone-settings-29@2x:58
iphone-settings-29@3x:87
iphone-spotlight-40@2x:80
iphone-spotlight-40@3x:120
iphone-app-60@2x:120
iphone-app-60@3x:180
ipad-notification-20@1x:20
ipad-notification-20@2x:40
ipad-settings-29@1x:29
ipad-settings-29@2x:58
ipad-spotlight-40@1x:40
ipad-spotlight-40@2x:80
ipad-app-76@1x:76
ipad-app-76@2x:152
ipad-pro-app-83.5@2x:167
ios-marketing-1024:1024
EOF

cp "$TMP_DIR/master-1024.png" "$WATCH_ICON_DIR/AIChat-AppIcon-1024.png"

echo "Updated app icon assets and preview."
