package fo.logic;

typedef Poi = {
    var kind:String;
    var subkind:String;
    var name:String;
    var id:String;
    var zone:String;
    var x:Float;
    var y:Float;
    var z:Float;
}

enum abstract Shape(Int) to Int {
    var Circle = 0;
    var Square = 1;
    var Triangle = 2;
    var Diamond = 3;
    var Cross = 4;
    var Star = 5;
}

typedef KindStyle = {
    var kind:String;
    var label:String;
    var color:Int;
    var shape:Shape;
    var onByDefault:Bool;
}

/** Marker kinds of pois_W1_Siagarta.json, with the overlay's colors and shapes. */
class Pois {
    public static var KINDS:Array<KindStyle> = [
        {kind: "soulstone", label: "Soulstone altars", color: 0xFF46AA, shape: Star, onByDefault: true},
        {kind: "dungeon", label: "Dungeons", color: 0xC88CFF, shape: Square, onByDefault: true},
        {kind: "obelisk", label: "Obelisks", color: 0x78DCFF, shape: Diamond, onByDefault: true},
        {kind: "respawn", label: "Respawns", color: 0x78DC78, shape: Cross, onByDefault: true},
        {kind: "merchant", label: "Merchants", color: 0xFFC850, shape: Circle, onByDefault: true},
        {kind: "activity", label: "Activities", color: 0xFFDC64, shape: Triangle, onByDefault: true},
        {kind: "chest", label: "Chests", color: 0xFFC83C, shape: Square, onByDefault: true},
        {kind: "red_orb", label: "Red orbs", color: 0xFF3C3C, shape: Circle, onByDefault: true},
        {kind: "plant", label: "Plants", color: 0x5AC85A, shape: Diamond, onByDefault: false},
        {kind: "ore", label: "Ores", color: 0xB48C50, shape: Triangle, onByDefault: false},
    ];

    /** Cell (col,row) in activities.png (8x3 grid of 128 px), as the overlay picks it; null: draw a glyph. */
    public static function atlasCell(p:Poi):Null<{col:Int, row:Int}> {
        return switch (p.kind) {
            case "obelisk": {col: 4, row: 0};
            case "respawn": {col: 5, row: 0};
            case "dungeon": {col: 2, row: 0};
            case "merchant": {col: 7, row: 0};
            case "activity": switch (p.subkind) {
                    // Cells the overlay learned live from st.Activity first, then its table.
                    case "TimerCollectRun": {col: 0, row: 1};
                    case "FightStone": {col: 2, row: 1};
                    case "ChestOrb": {col: 1, row: 0};
                    case "WorldCamp": {col: 3, row: 0};
                    case "Ascension": {col: 1, row: 1};
                    case "WorldElite": {col: 0, row: 0};
                    case "MountRush": {col: 0, row: 1};
                    case "WorldPlant": {col: 7, row: 0};
                    default: null;
                };
            default: null;
        }
    }

    /** Activity colors by subkind (the overlay's table), for the shape fallback. */
    public static function activityColor(sub:String):Int {
        return switch (sub) {
            case "WorldElite": 0xFF5050;
            case "FightStone": 0xDC6464;
            case "ChestOrb": 0xFFDC64;
            case "WorldCamp": 0xC86432;
            case "WorldPlant": 0x50C850;
            case "Ascension": 0xDC78FF;
            case "MountRush": 0xB48C50;
            case "TimerCollectRun": 0xC8C850;
            default: 0xB4B4B4;
        }
    }

    public static function style(kind:String):KindStyle {
        for (k in KINDS) if (k.kind == kind) return k;
        return {kind: kind, label: kind, color: 0xB4B4B4, shape: Circle, onByDefault: false};
    }

    /** Parses the overlay's POI file (a JSON array). Bad entries are skipped. */
    public static function parse(text:String):Array<Poi> {
        var raw:Array<Dynamic> = haxe.Json.parse(text);
        var out:Array<Poi> = [];
        for (r in raw) {
            if (r == null || r.kind == null || r.x == null || r.y == null) continue;
            out.push({
                kind: Std.string(r.kind),
                subkind: r.subkind == null ? "" : Std.string(r.subkind),
                name: r.name == null ? "" : Std.string(r.name),
                id: r.id == null ? "" : Std.string(r.id),
                zone: r.zone == null ? "" : Std.string(r.zone),
                x: (r.x : Float),
                y: (r.y : Float),
                z: r.z == null ? 0.0 : (r.z : Float),
            });
        }
        return out;
    }

    /** Readable name: "Madrigold_Small" -> "Madrigold Small". */
    public static function pretty(s:String):String {
        if (s == null) return "";
        return StringTools.replace(s, "_", " ");
    }

    /** Tooltip text. Altars name their boss and the distance. */
    public static function tooltip(p:Poi, distM:Float):String {
        var d = Math.round(distM);
        if (p.kind == "soulstone") return p.name + " altar - " + d + " m\nUse the " + p.name + " Soulstone here";
        var label = style(p.kind).label;
        var n = pretty(p.name);
        if (n == "") n = label;
        return n + " - " + d + " m" + (n != label ? "\n" + label : "");
    }
}
