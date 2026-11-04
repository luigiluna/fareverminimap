package fo;

import hlx.runtime.ResolvedMember;

/**
 * Reflection helpers for objects that live in the game's own HashLink module.
 *
 * Game classes are never imported: a mod that imports `h2d.Graphics` compiles its own
 * private copy of that class, and the game's renderer never sees it. Everything goes
 * through HlxRuntime by type and member name instead.
 */
class G {
    static var members = new Map<String, ResolvedMember>();
    static var missing = new Map<String, Bool>();

    /** Field read; null on any failure. */
    public static function f(o:Dynamic, name:String):Dynamic {
        if (o == null) return null;
        try return Reflect.field(o, name) catch (_:Dynamic) return null;
    }

    public static function num(v:Dynamic, def:Float = 0):Float {
        if (v == null) return def;
        if (Std.isOfType(v, Float) || Std.isOfType(v, Int)) {
            var x:Float = v;
            return Math.isNaN(x) ? def : x;
        }
        var x = Std.parseFloat(Std.string(v));
        return Math.isNaN(x) ? def : x;
    }

    public static inline function int(v:Dynamic, def:Int = 0):Int return Std.int(num(v, def));

    public static function bool(v:Dynamic):Bool {
        if (v == null) return false;
        if (Std.isOfType(v, Bool)) return v;
        return num(v, 0) != 0;
    }

    /**
     * A game String as one of ours. Always copies: a String of the game's module
     * passes Std.isOfType(v, String) but is not our class, so it breaks Map keys,
     * == and JSON (it serializes as {bytes, length}).
     */
    public static function str(v:Dynamic):Null<String> {
        if (v == null) return null;
        var bytes:hl.Bytes = null;
        var len:Null<Int> = null;
        try {
            bytes = Reflect.field(v, "bytes");
            len = Reflect.field(v, "length");
        } catch (_:Dynamic) {}
        if (bytes == null || len == null || len < 0) return Std.string(v);
        if (len == 0) return "";
        // Copy, so the result does not share the game's buffer.
        var copy = new hl.Bytes((len + 1) << 1);
        copy.blit(0, bytes, 0, len << 1);
        copy.setUI16(len << 1, 0);
        return @:privateAccess String.__alloc__(copy, len);
    }

    public static function set(o:Dynamic, name:String, v:Dynamic):Void {
        if (o != null) Reflect.setField(o, name, v);
    }

    public static function member(type:String, name:String, isStatic = false):ResolvedMember {
        var key = type + (isStatic ? "::" : ".") + name;
        var m = members.get(key);
        if (m != null) return m;
        if (missing.exists(key)) return null;
        var t = HlxRuntime.resolveType(type);
        if (t != null) m = isStatic ? HlxRuntime.resolveStaticMember(t, name) : HlxRuntime.resolveMember(t, name);
        if (m == null) {
            missing.set(key, true);
            Log.err('member not found: $key');
            return null;
        }
        members.set(key, m);
        return m;
    }

    public static function has(type:String, name:String, isStatic = false):Bool return member(type, name, isStatic) != null;

    /** Calls `type.name` on `o` (non-virtual: the method of `type` itself). */
    public static function call(type:String, name:String, o:Dynamic, ?args:Array<Dynamic>):Dynamic {
        var m = member(type, name);
        if (m == null || o == null) return null;
        var all:Array<Dynamic> = [o];
        if (args != null) for (a in args) all.push(a);
        return HlxRuntime.callResolved(m, all);
    }

    public static function scall(type:String, name:String, ?args:Array<Dynamic>):Dynamic {
        var m = member(type, name, true);
        if (m == null) return null;
        return HlxRuntime.callResolved(m, args == null ? [] : args);
    }

    public static function stat(type:String, name:String):Dynamic {
        var t = HlxRuntime.resolveType(type);
        return t == null ? null : HlxRuntime.resolveStaticField(t, name);
    }

    public static function create(type:String, args:Array<Dynamic>):Dynamic {
        var t = HlxRuntime.resolveType(type);
        if (t == null) throw "type not found: " + type;
        return HlxRuntime.constructInstanceByName(t, args.length, args);
    }

    public static function typeName(o:Dynamic):String {
        if (o == null) return "null";
        try return hl.Type.getDynamic(o).getTypeName() catch (_:Dynamic) return "?";
    }

    /** True if `o`'s class or one of its parents is `name`. */
    public static function isA(o:Dynamic, name:String):Bool {
        if (o == null) return false;
        try {
            var t = hl.Type.getDynamic(o);
            while (t != null && t.kind == HObj) {
                if (t.getTypeName() == name) return true;
                t = t.getSuper();
            }
        } catch (_:Dynamic) {}
        return false;
    }

    /** Length of a game array (ArrayObj/ArrayDyn/ArrayBytes). */
    public static function alen(a:Dynamic):Int return a == null ? 0 : int(f(a, "length"));

    /** Element `i` of a game array, through the array's own reader. */
    public static function aget(a:Dynamic, i:Int):Dynamic {
        if (a == null) return null;
        return call(typeName(a), "getDyn", a, [i]);
    }
}
