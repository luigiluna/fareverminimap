#!/bin/sh
# Builds build/farever-overlay/ (the mod folder) with the local Haxe in ../toolchain (or $HAXE_TC).
set -e
cd "$(dirname "$0")"
TC=${HAXE_TC:-$(cd .. && pwd)/toolchain/haxe}
export HAXE_STD_PATH=$TC/std
rm -rf build/farever-overlay
mkdir -p build/farever-overlay/data
"$TC/haxe" compile.hxml 2>&1 | grep -v "This API should only be used from initialization macros" || true
test -s build/farever-overlay/farever-overlay.hl || { echo "BUILD FAILED"; exit 1; }
# A failed compile leaves no .hl: the check above stops here before anything is copied.
cp configFormats.json README.txt build/farever-overlay/ 2>/dev/null || cp configFormats.json build/farever-overlay/
cp data/pois_W1_Siagarta.json data/minimap_calibration.json data/W1_Siagarta.preview.png data/players_gear_atlas.png data/activities.png data/PlayerMapArrow.png build/farever-overlay/data/
python3 -c "import json;json.load(open('build/farever-overlay/configFormats.json'))"
echo "BUILD OK"; ls -l build/farever-overlay
