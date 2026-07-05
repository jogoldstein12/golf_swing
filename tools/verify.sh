#!/bin/zsh
# Reproducible local verification for the app and SwingKit package.
set -euo pipefail

ROOT="${0:A:h:h}"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR
cd "$ROOT"

if [[ ! -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]]; then
  print -u2 "Full Xcode was not found at $DEVELOPER_DIR"
  print -u2 "Set DEVELOPER_DIR to your Xcode.app/Contents/Developer directory."
  exit 1
fi

"$ROOT/tools/bootstrap_xcodegen.sh"
"$ROOT/assets/fetch_fonts.sh"
"$ROOT/tools/bin/xcodegen/bin/xcodegen" generate --spec "$ROOT/project.yml"

derived_data="${SWINGTHROUGH_DERIVED_DATA:-$HOME/Library/Caches/swingthrough-dd}"
xcodebuild \
  -project "$ROOT/SwingThrough.xcodeproj" \
  -scheme SwingThrough \
  -destination "${SWINGTHROUGH_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro}" \
  -derivedDataPath "$derived_data" \
  build

(
  cd "$ROOT/SwingKit"
  swift test
)
