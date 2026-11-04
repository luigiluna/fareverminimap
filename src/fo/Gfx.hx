package fo;

/**
 * Thin wrappers over the game's own h2d objects. Every object here is created in
 * the game's module through G.create, so the game's renderer draws it like any of
 * its own UI. Calls are reflective, so callers keep them few per frame: redraw
 * graphics only when something moved, and set text only when it changed.
 */
class Gfx {
    // ---- objects ----

    public static function obj(parent:Dynamic):Dynamic return G.create("h2d.Object", [parent]);

    public static function graphics(parent:Dynamic):Dynamic return G.create("h2d.Graphics", [parent]);

    public static inline function pos(o:Dynamic, x:Float, y:Float):Void G.call("h2d.Object", "setPosition", o, [x, y]);

    public static inline function rot(o:Dynamic, r:Float):Void G.call("h2d.Object", "set_rotation", o, [r]);

    public static inline function scale(o:Dynamic, s:Float):Void G.call("h2d.Object", "setScale", o, [s]);

    public static inline function visible(o:Dynamic, v:Bool):Void G.call("h2d.Object", "set_visible", o, [v]);

    public static inline function alpha(o:Dynamic, a:Float):Void G.set(o, "alpha", a);

    public static function remove(o:Dynamic):Void {
        if (o != null) try G.call("h2d.Object", "remove", o, []) catch (_:Dynamic) {}
    }

    public static inline function addChild(parent:Dynamic, child:Dynamic):Void G.call("h2d.Object", "addChild", parent, [child]);

    // ---- h2d.Graphics ----

    public static inline function clear(g:Dynamic):Void G.call("h2d.Graphics", "clear", g, []);

    /** Solid fill. beginFill's own color/alpha are optional (ref) args, so they are set after it. */
    public static function fill(g:Dynamic, color:Int, a:Float = 1.0):Void {
        G.call("h2d.Graphics", "beginFill", g, [null, null]);
        G.call("h2d.Graphics", "setColor", g, [color & 0xFFFFFF, null]);
        if (a < 1.0) G.set(g, "curA", a);
    }

    public static inline function endFill(g:Dynamic):Void G.call("h2d.Graphics", "endFill", g, []);

    public static inline function rect(g:Dynamic, x:Float, y:Float, w:Float, h:Float):Void
        G.call("h2d.Graphics", "drawRect", g, [x, y, w, h]);

    public static inline function circle(g:Dynamic, x:Float, y:Float, r:Float):Void
        G.call("h2d.Graphics", "drawCircle", g, [x, y, r, null]);

    public static inline function moveTo(g:Dynamic, x:Float, y:Float):Void G.call("h2d.Graphics", "moveTo", g, [x, y]);

    public static inline function lineTo(g:Dynamic, x:Float, y:Float):Void G.call("h2d.Graphics", "lineTo", g, [x, y]);

    /** Outline: lineStyle's args are refs too, so set the fields it would set. */
    public static function line(g:Dynamic, size:Float, color:Int, a:Float = 1.0):Void {
        G.call("h2d.Graphics", "lineStyle", g, [null, null, null]);
        G.set(g, "lineSize", size);
        G.set(g, "lineR", ((color >> 16) & 0xFF) / 255.0);
        G.set(g, "lineG", ((color >> 8) & 0xFF) / 255.0);
        G.set(g, "lineB", (color & 0xFF) / 255.0);
        G.set(g, "lineA", a);
    }

    public static function noLine(g:Dynamic):Void {
        G.call("h2d.Graphics", "lineStyle", g, [null, null, null]);
        G.set(g, "lineSize", 0.0);
    }

    /** Closed polygon from flat [x0,y0,x1,y1...]. */
    public static function poly(g:Dynamic, pts:Array<Float>):Void {
        if (pts.length < 6) return;
        moveTo(g, pts[0], pts[1]);
        var i = 2;
        while (i < pts.length) {
            lineTo(g, pts[i], pts[i + 1]);
            i += 2;
        }
        lineTo(g, pts[0], pts[1]);
    }

    /** Fill with `tile`, drawn at (dx,dy) scaled by (sx,sy). */
    public static inline function tileFill(g:Dynamic, dx:Float, dy:Float, sx:Float, sy:Float, tile:Dynamic):Void
        G.call("h2d.Graphics", "beginTileFill", g, [dx, dy, sx, sy, tile]);

    // ---- text ----

    public static var font:Dynamic;
    public static var fontSize = 12.0;

    public static function text(parent:Dynamic, color = 0xFFFFFF):Label {
        if (font == null) return null;
        var t = G.create("h2d.Text", [font, parent]);
        var l = new Label(t);
        l.color(color);
        return l;
    }

    /** Fonts already used by the game's UI. Picks a readable one; logs what it saw. */
    public static function pickFont(root:Dynamic):Dynamic {
        var stack:Array<Dynamic> = [root];
        var seen = new Map<String, Dynamic>();
        var n = 0;
        while (stack.length > 0 && n < 20000) {
            var o = stack.pop();
            n++;
            if (G.isA(o, "h2d.Text")) {
                var f = G.f(o, "font");
                if (f != null) {
                    var key = G.str(G.f(f, "name")) + "/" + G.int(G.f(f, "size"));
                    if (!seen.exists(key)) seen.set(key, f);
                }
            }
            var kids = G.f(o, "children");
            for (i in 0...G.alen(kids)) stack.push(G.aget(kids, i));
        }
        var best:Dynamic = null, bestScore = -1e9;
        var names = [];
        for (k => f in seen) {
            names.push(k);
            var size = G.num(G.f(f, "size"), 12);
            var name = (G.str(G.f(f, "name")) : String);
            var score = -Math.abs(size - 15);
            if (name != null && name.toLowerCase().indexOf("pixel") >= 0) score -= 4;
            if (name != null && name.toLowerCase().indexOf("italic") >= 0) score -= 6;
            if (name != null && (name.toLowerCase().indexOf("bold") >= 0 || name.toLowerCase().indexOf("black") >= 0)) score -= 2;
            if (name != null && (name.toLowerCase().indexOf("icon") >= 0 || name.toLowerCase().indexOf("symbol") >= 0)) score -= 100;
            if (score > bestScore) {
                bestScore = score;
                best = f;
            }
        }
        if (names.length > 0) Log.once("fonts", "fonts seen: " + names.join(", "), 1);
        if (best != null) fontSize = G.num(G.f(best, "size"), 12);
        return best;
    }
}

/** One h2d.Text that only talks to the game when its content changes. */
class Label {
    public var t:Dynamic;
    var last:String = null;
    var lastColor = -1;
    var lastX = -1e9;
    var lastY = -1e9;
    var lastVis = true;
    var lastScale = 1.0;

    public function new(t:Dynamic) this.t = t;

    public function set(s:String):Label {
        if (s != last) {
            last = s;
            G.call("h2d.Text", "set_text", t, [s]);
        }
        return this;
    }

    public function color(c:Int):Label {
        if (c != lastColor) {
            lastColor = c;
            G.call("h2d.Text", "set_textColor", t, [c]);
        }
        return this;
    }

    public function at(x:Float, y:Float):Label {
        if (x != lastX || y != lastY) {
            lastX = x;
            lastY = y;
            Gfx.pos(t, x, y);
        }
        return this;
    }

    public function size(px:Float):Label {
        var s = px / Gfx.fontSize;
        if (s != lastScale) {
            lastScale = s;
            Gfx.scale(t, s);
        }
        return this;
    }

    public function show(v:Bool):Label {
        if (v != lastVis) {
            lastVis = v;
            Gfx.visible(t, v);
        }
        return this;
    }

    public function width():Float return G.num(G.call("h2d.Text", "get_textWidth", t, [])) * lastScale;
}
