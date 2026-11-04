#!/bin/sh
# Installs build/farever-overlay into the game's hlx/mods. Only with the game closed and a good build.
set -e
cd "$(dirname "$0")"
GAME=${GAME:-$HOME/.local/share/Steam/steamapps/common/Farever}
if ps -eo args | grep -qE '^S:.*[F]arever\.exe'; then echo "Farever is running: close it first."; exit 1; fi
test -f "$GAME/libhl64.dll" -a -f "$GAME/hlx/loader/hlx-loader.hl" || { echo "hlx-core is not installed in $GAME"; exit 1; }
test -f "$GAME/hlx/mods/better-mod-settings/better-mod-settings.hl" || echo "warning: Better Mod Settings missing: the mod cannot be switched on in-game"
./build.sh >/dev/null
test -s build/farever-overlay/farever-overlay.hl || { echo "no build"; exit 1; }
rm -rf "$GAME/hlx/mods/farever-overlay"
cp -r build/farever-overlay "$GAME/hlx/mods/farever-overlay"
echo "installed to $GAME/hlx/mods/farever-overlay (settings: $GAME/hlx/config/farever-overlay/)"
