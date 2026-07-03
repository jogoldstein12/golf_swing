#!/bin/zsh
# Fetch the app fonts. Kept out of git for license hygiene (Fontshare EULA).
set -e
cd "$(dirname "$0")/fonts"
if [[ ! -f satoshi/Satoshi_Complete/Fonts/OTF/Satoshi-Regular.otf ]]; then
  curl -sL -o satoshi.zip "https://api.fontshare.com/v2/fonts/download/satoshi"
  unzip -oq satoshi.zip -d satoshi && rm satoshi.zip
fi
for f in InstrumentSerif-Regular InstrumentSerif-Italic; do
  [[ -f "$f.ttf" ]] || curl -sL -o "$f.ttf" "https://github.com/google/fonts/raw/main/ofl/instrumentserif/$f.ttf"
done
echo "fonts ready"
