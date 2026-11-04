package fo;

/**
 * Loads the map image from the mod folder through the game's own resource code
 * (hxd.fs.LocalEntry -> hxd.res.Image -> h2d.Tile), so the texture is the
 * engine's like any other.
 */
class MapTexture {
    public static var tile:Dynamic;
    public static var size = 0.0;
    static var tried = false;

    public static function load(path:String):Dynamic {
        if (tried) return tile;
        tried = true;
        tile = loadTile(path);
        size = tile == null ? 0 : G.num(G.f(tile, "width"));
        return tile;
    }

    /** Any PNG on disk as an h2d.Tile of the game; null on failure. */
    public static function loadTile(path:String):Dynamic {
        var tile:Dynamic = null;
        var t0 = haxe.Timer.stamp();
        try {
            if (!sys.FileSystem.exists(path)) {
                Log.err("map image missing: " + path);
                return null;
            }
            var abs = sys.FileSystem.fullPath(path);
            var name = haxe.io.Path.withoutDirectory(path);
            var fs:Dynamic = null;
            try fs = G.create("hxd.fs.LocalFileSystem", [haxe.io.Path.directory(abs), null, null]) catch (e:Dynamic) Log.info("LocalFileSystem: " + Std.string(e));
            var entry = G.create("hxd.fs.LocalEntry", [fs, name, name, abs]);
            var img = G.create("hxd.res.Image", [entry]);
            tile = G.call("hxd.res.Image", "toTile", img, []);
            Log.info('image loaded: $name ${G.num(G.f(tile, "width"))}x${G.num(G.f(tile, "height"))} in ${Math.round((haxe.Timer.stamp() - t0) * 1000)} ms');
        } catch (e:Dynamic) {
            Log.err("map image load failed: " + Std.string(e));
            tile = null;
        }
        return tile;
    }
}
