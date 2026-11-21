# Farever Overlay

A minimap, a big map and a DPS meter for Farever, drawn by the game itself.

Farever is written in Haxe. So instead of bolting an overlay onto the game from the outside,
this mod is written in Haxe too and runs inside the game itself.

<!-- TODO screenshot: round minimap in the top-right corner, in W1 Siagarta, with a few markers and the player arrow -->
<p align="center"><i>[ screenshot: minimap in the corner of the screen ]</i></p>

## What it does

**Minimap**
- Round minimap in the top-right corner. It rotates with the camera, with your character, or not at all.
- Markers for W1 Siagarta: the 8 Soulstone altars, dungeons, obelisks, respawn points, merchants, activities, chests and red orbs. Plants and ores too, off by default.
- Other players nearby, with their names if you want them.
- Size, position, lock and filters live in an options panel behind the minimap's menu button.

**Big map** (F6)
- Drag to pan, mouse wheel to zoom, double-click to recentre.
- Filters by marker type in the legend. They are saved.

**DPS meter** (F10 show/hide, F9 reset, F12 pause)
- DMG tab: damage per skill with the game's own skill icons, hits, crits, casts, max hit, and a Physical / Magic / Raw split.
- HEAL and SHIELD tabs: the same thing for your heals and absorbs.
- PLAYERS tab: everyone the server sends to your client, with class, level, their 3 weapons and a DPS bar. Filter by ALL or GROUP. The Build button opens their gear, infusions, gems and talents.
- HISTORY tab: past fights, a star to keep the good ones, and a detail window per fight with a DPS graph, the players in it and a death recap. A Records view keeps your best boss DPS per boss and your average DPS per weapon, solo and group apart.
- Optional "boss reset": the first hit on a boss starts a new fight.
- The window can be moved, resized and minimized.

<!-- TODO screenshot: DPS meter window, DMG tab, mid-fight -->
<p align="center"><i>[ screenshot: DPS meter during a fight ]</i></p>

<!-- TODO screenshot: big map (F6) with the legend filters open -->
<p align="center"><i>[ screenshot: big map with the legend ]</i></p>

## Install (players)

The full guide, in Portuguese, is in [LEIA-ME.txt](LEIA-ME.txt). The short version:

1. Install [hlx-core](https://github.com/hlx-framework/hlx-core) 0.0.11 in the game folder (`libhl64.dll` and `hlx\loader`).
2. Install the Better Mod Settings mod. Without it you cannot switch this one on.
3. Close the game. Copy the `hlx` folder from the release zip into the Farever folder. You should end up with `hlx\mods\farever-overlay\farever-overlay.hl`.
4. Start the game. The mod starts **off**. Turn it on in Esc > Mod Settings > Farever Overlay > "Enable Farever Overlay".

To uninstall, close the game and delete `hlx\mods\farever-overlay`. Your settings and fight history live in `hlx\config\farever-overlay`. Delete that too if you want a clean slate.

Things you should know:
- I have only tested it on Linux, through Proton. Not on Windows.
- The map only exists for W1 Siagarta. In dungeons you get "No map here".
- PLAYERS only shows what reaches your client. Players far away do not show up.
- Item, talent and skill names come from a table generated from the game data, in English.
- A game update can break it. Class and field names change.
- It can live next to the old C++ overlay, but run one at a time. Both put a minimap in the same corner and both listen to F6/F8/F9/F10. The old overlay's fight history is read once and imported.

## Building from source

You need Haxe 4.3.7. The scripts look for it in `../toolchain/haxe` (a folder next to this repo). Point `HAXE_TC` somewhere else if yours lives elsewhere.

```sh
./test.sh       # logic tests, outside the game (Haxe eval interpreter)
./build.sh      # builds build/farever-overlay/
./install.sh    # builds and copies it into the game. Game must be closed.
./uninstall.sh  # removes the mod. --all also removes settings and history.
```

`install.sh` and `uninstall.sh` assume the Steam path on Linux (`~/.local/share/Steam/steamapps/common/Farever`). Set `GAME` to change it. Both refuse to run while the game is open.

The map images (`data/W1_Siagarta.preview.png`, `data/players_gear_atlas.png`, `data/activities.png`, `data/PlayerMapArrow.png`) come from the game files, so they are not in this repo. Copy them from your own install into `data/` before running `build.sh`.

## How it works

[hlx](https://github.com/hlx-framework/hlx-core) is a modding framework for HashLink games, and Farever is one. hlx loads mods compiled to HashLink bytecode and lets them hook game functions.

This mod hooks a handful of them:
- `GameApp.update`: once per frame, to read the hero, the camera and nearby players, and to draw.
- `ent.Unit.rpcReceiveDamage__impl`: every damage event, for the meter.
- `ent.Unit.onDeath` and `ent.Hero.playDeath`: deaths, for the recap.
- `GameApp.dispose`: save the history on the way out.

The update and damage hooks are postfixes: they run after the game and only watch. The dispose hook runs just before shutdown to save the history, and lets the game carry on. Nothing changes damage, input or packets. Game objects are read by reflection, so the mod never imports game classes.

Everything is drawn with Heaps `h2d`, the same 2D engine the game uses for its own UI. No DirectX, no D3D12 hooks, no `dinput8.dll` injection. The panels block clicks on themselves like any game window. The mouse wheel and the keyboard still reach the game.

## Project layout

```
src/fo/              game side: hooks, windows, drawing
src/fo/logic/        pure logic: combat, history, records, map math. Covered by tests/
src/fo/data/         GameTables.hx, generated by tools/gen_tables.py
tests/               logic tests and fixtures
data/                marker list and map calibration for W1 Siagarta
vendor/hlx-runtime/  hlx runtime 0.0.11 (MIT)
configFormats.json   the options shown in Better Mod Settings
LEIA-ME.txt          player guide, in Portuguese
```

## Credits

- [hlx](https://github.com/hlx-framework/hlx-core) by hlx-framework. It makes this whole approach possible. The runtime in `vendor/` is theirs, under MIT.
- The C++ overlay this grew out of: [farever-minimap](https://github.com/ramisotti13-eng/farever-minimap) by ramisotti13-eng. The W1 Siagarta marker list and the map calibration come from there, and so does the original minimap. Most of that project is their work. I added the DPS meter, the players tab, the fight history and the name tables to it, then rewrote all of it here as an hlx mod.

## Disclaimer

This is an unofficial fan mod. It is not made or endorsed by Shiro Games. Modding may go against the game's terms of service, and that risk is yours. The mod only reads game state and never touches damage, input or network traffic, but I can't promise anything about how the developers see it.

## License

MIT. See [LICENSE](LICENSE).
