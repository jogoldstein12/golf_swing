#!/bin/zsh
# Install the repository-pinned XcodeGen into tools/bin when a fresh clone lacks it.
set -euo pipefail

ROOT="${0:A:h:h}"
VERSION="2.45.4"
INSTALL_DIR="$ROOT/tools/bin/xcodegen"
BINARY="$INSTALL_DIR/bin/xcodegen"

if [[ -x "$BINARY" ]] && [[ "$($BINARY --version)" == "Version: $VERSION" ]]; then
  echo "XcodeGen $VERSION already available"
  exit 0
fi

archive="${TMPDIR:-/tmp}/xcodegen-$VERSION.zip"
staging="${TMPDIR:-/tmp}/xcodegen-$VERSION"
rm -rf "$staging"
mkdir -p "$staging" "$ROOT/tools/bin"

curl -fL --retry 3 -o "$archive" \
  "https://github.com/yonaskolb/XcodeGen/releases/download/$VERSION/xcodegen.zip"
unzip -oq "$archive" -d "$staging"
rm -rf "$INSTALL_DIR"
mv "$staging" "$INSTALL_DIR"
rm -f "$archive"

[[ -x "$BINARY" ]] || { print -u2 "XcodeGen binary was not installed"; exit 1; }
[[ "$($BINARY --version)" == "Version: $VERSION" ]] || {
  print -u2 "Unexpected XcodeGen version: $($BINARY --version)"
  exit 1
}
echo "installed XcodeGen $VERSION"
