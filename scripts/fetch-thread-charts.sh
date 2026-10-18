#!/bin/bash
# Downloads the bundled brand thread charts, unmodified, from Ink/Stitch's palettes folder
# (https://github.com/inkstitch/inkstitch/tree/main/palettes) at a pinned commit, into Resources/ThreadCharts.
# Ink/Stitch is licensed under the GNU GPL v3, like OpenHoop; the credit is in Resources/ThirdPartyNotices.txt.
# The colors are screen approximations of each brand's real spools. Only popular home-embroidery brands are chosen.
# Run it again after changing the list; it replaces only the Ink/Stitch charts (the machine palettes stay).
set -euo pipefail
cd "$(dirname "$0")/.."
COMMIT=9a5b98381e6db818acdb301edf7c7ccb7f2f0013   # inkstitch/inkstitch, last change to palettes/, 2025-10-29
CHARTS=(
  "Brother Embroidery" "Brother Country" "Madeira Polyneon" "Madeira Rayon" "Isacord Polyester"
  "Robison-Anton Polyester" "Robison-Anton Rayon" "Sulky Polyester" "Sulky Rayon" "Floriani Polyester"
  "Gunold Polyester" "Marathon Polyester" "Marathon Rayon" "Mettler Poly Sheen" "Hemingworth"
  "Fil-Tec Glide" "Simthread Polyester" "Simthread Polyester 63 Brother Colors" "Janome" "DMC" "Coats Alcazar"
)
DEST=Resources/ThreadCharts
rm -f "$DEST"/InkStitch\ *.gpl
for name in "${CHARTS[@]}"; do
  file="InkStitch $name.gpl"
  # %20 for each space in the file name, so curl gets a valid address.
  curl -sfL "https://raw.githubusercontent.com/inkstitch/inkstitch/$COMMIT/palettes/${file// /%20}" -o "$DEST/$file"
  echo "$name: $(grep -cE '^[[:space:]]*[0-9]+[[:space:]]+[0-9]+[[:space:]]+[0-9]+' "$DEST/$file") colors"
done
