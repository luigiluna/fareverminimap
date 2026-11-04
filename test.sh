#!/bin/sh
# Logic tests, outside the game (Haxe eval interpreter).
set -e
cd "$(dirname "$0")"
TC=${HAXE_TC:-$(cd ../.. && pwd)/toolchain/haxe}
export HAXE_STD_PATH=$TC/std
"$TC/haxe" tests.hxml
