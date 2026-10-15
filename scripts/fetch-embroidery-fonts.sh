#!/bin/bash
# Downloads the bundled embroidery fonts, unmodified, from the Ink/Stitch font collection
# (https://github.com/inkstitch/embroidery-fonts) at a pinned commit, into Resources/EmbroideryFonts.
# Every font here is under the SIL Open Font License 1.1 or public domain; each folder keeps its own LICENSE.
# Fonts with non-commercial, share-alike, no-derivatives or GPL terms are deliberately left out.
# Run it again after changing the list; it replaces the folder's contents.
set -euo pipefail
cd "$(dirname "$0")/.."
COMMIT=c7e3a05c3d6f5c77b881c50f257851af9a8e9cb8   # inkstitch/embroidery-fonts main, 2026-08-28
FONTS="glacial_tiny small_font caffeine_tiny pacificlo_tiny amitaclo_small magnolia_small excalibur_small
venezia_small apex_simple_small_AGS medium_font caffeine_KOR pacificlo venezia barstitch_bold mam_script
roman_ags tt_directors initials_medium"
DEST=Resources/EmbroideryFonts
rm -rf "$DEST" && mkdir -p "$DEST"
# The repository's file list at that commit, then every file of each chosen font folder.
curl -sfL "https://api.github.com/repos/inkstitch/embroidery-fonts/git/trees/$COMMIT?recursive=1" -o "$DEST/.tree.json"
python3 - "$DEST" "$COMMIT" $FONTS <<'EOF'
import json, os, subprocess, sys
dest, commit, fonts = sys.argv[1], sys.argv[2], sys.argv[3:]
tree = json.load(open(os.path.join(dest, ".tree.json")))
for font in fonts:
    files = [x["path"] for x in tree["tree"] if x["type"] == "blob" and x["path"].startswith(f"src/{font}/")]
    if not files: sys.exit(f"Font folder {font} not found at {commit}")
    for path in files:
        out = os.path.join(dest, path[len("src/"):])
        os.makedirs(os.path.dirname(out), exist_ok=True)
        subprocess.run(["curl", "-sfL", f"https://raw.githubusercontent.com/inkstitch/embroidery-fonts/{commit}/{path}", "-o", out], check=True)
    print(f"{font}: {len(files)} files")
EOF
rm "$DEST/.tree.json"
printf 'Embroidery fonts from https://github.com/inkstitch/embroidery-fonts at commit %s, unmodified.\nEach folder holds its font'"'"'s LICENSE. Fetched by scripts/fetch-embroidery-fonts.sh.\n' "$COMMIT" > "$DEST/SOURCE.txt"
du -sh "$DEST"
