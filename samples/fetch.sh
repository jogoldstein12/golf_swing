#!/bin/zsh
# Re-download the sample swing videos from Pexels (see README.md for the manifest).
set -e
cd "$(dirname "$0")"
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15"
typeset -A vids=(
  dtl_iron_a 6541682
  dtl_iron_b 6541842
  dtl_driver_c 34883764
  dtl_range_d 16632575
  faceon_iron_a 6541674
  faceon_driver_b 6541855
  faceon_driver_c 6541964
  faceon_iron_d 14980434
)
for name id in "${(@kv)vids}"; do
  [[ -f "$name.mp4" ]] && { echo "have $name.mp4"; continue }
  echo "fetching $name (pexels $id)"
  curl -sL -A "$UA" -o "$name.mp4" "https://www.pexels.com/download/video/$id/"
done
