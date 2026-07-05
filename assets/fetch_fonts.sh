#!/bin/zsh
# Fetch and stage the app fonts. Kept out of git for license hygiene.
set -euo pipefail

FONT_DIR="${0:A:h}/fonts"
APP_DIR="$FONT_DIR/app"
SATOSHI_DIR="$FONT_DIR/satoshi/Satoshi_Complete/Fonts/OTF"
mkdir -p "$FONT_DIR" "$APP_DIR"

if [[ ! -f "$SATOSHI_DIR/Satoshi-Regular.otf" ]]; then
  archive="$FONT_DIR/satoshi.zip"
  curl -fL --retry 3 -o "$archive" "https://api.fontshare.com/v2/fonts/download/satoshi"
  rm -rf "$FONT_DIR/satoshi"
  unzip -oq "$archive" -d "$FONT_DIR/satoshi"
  rm -f "$archive"
fi

for name in InstrumentSerif-Regular InstrumentSerif-Italic; do
  source="$FONT_DIR/$name.ttf"
  if [[ ! -f "$source" ]]; then
    curl -fL --retry 3 -o "$source" \
      "https://github.com/google/fonts/raw/main/ofl/instrumentserif/$name.ttf"
  fi
  cp "$source" "$APP_DIR/$name.ttf"
done

for name in Satoshi-Regular Satoshi-Italic Satoshi-Medium Satoshi-MediumItalic Satoshi-Bold Satoshi-Black; do
  cp "$SATOSHI_DIR/$name.otf" "$APP_DIR/$name.otf"
done

expected=(
  InstrumentSerif-Regular.ttf InstrumentSerif-Italic.ttf
  Satoshi-Regular.otf Satoshi-Italic.otf Satoshi-Medium.otf
  Satoshi-MediumItalic.otf Satoshi-Bold.otf Satoshi-Black.otf
)
for file in $expected; do
  [[ -s "$APP_DIR/$file" ]] || { print -u2 "missing font: $file"; exit 1; }
done

echo "fonts ready in $APP_DIR"
