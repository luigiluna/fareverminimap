#!/bin/sh
# Removes the mod folder. Keeps hlx/config/farever-overlay (settings and fight history) unless --all.
set -e
GAME=${GAME:-$HOME/.local/share/Steam/steamapps/common/Farever}
if ps -eo args | grep -qE '^S:.*[F]arever\.exe'; then echo "Farever is running: close it first."; exit 1; fi
rm -rf "$GAME/hlx/mods/farever-overlay"
[ "$1" = "--all" ] && rm -rf "$GAME/hlx/config/farever-overlay"
echo "removed"
