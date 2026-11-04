package fo;

/**
 * A movable window drawn with the game's h2d objects, rebuilt in an immediate-mode
 * style: each refresh draws boxes and texts again, reusing the same h2d.Text
 * objects (a text is only sent to the game when it changed). Clicks are tested
 * against the regions of the last refresh.
 */
class Panel {
    public var root:Dynamic;
    var bg:Dynamic;
    var fg:Dynamic;
    var hit:Dynamic;
    var pool:Array<Gfx.Label> = [];
    var used = 0;
    var regions:Array<{x:Float, y:Float, w:Float, h:Float, fn:Void->Void}> = [];
    var tips:Array<{x:Float, y:Float, w:Float, h:Float, text:String}> = [];
    var nextTips:Array<{x:Float, y:Float, w:Float, h:Float, text:String}> = [];
    var nextRegions:Array<{x:Float, y:Float, w:Float, h:Float, fn:Void->Void}> = [];

    /** players_gear_atlas.png as a game tile; icons are 48 px cells, ICON_ATLAS_COLS per row. */
    public static var atlas:Dynamic;
    static var cells = new Map<Int, Dynamic>();
    var bitmaps:Array<{b:Dynamic, cell:Int, x:Float, y:Float, s:Float, vis:Bool, t:Dynamic}> = [];
    var usedBitmaps = 0;

    public static inline var PHYS = 0xE8985C;
    public static inline var MAGIC = 0x987CFF;
    public static inline var RAW = 0xCDCDCD;
    public static inline var UNKNOWN = 0x505050;
    public static inline var TEXT = 0xEDE9FE;
    public static inline var DIM = 0x8C849E;
    public static inline var ACCENT = 0xC79EFF;

    public var x = 0.0;
    public var y = 0.0;
    public var w = 300.0;
    public var h = 200.0;
    public var titleH = 26.0;

    /** Resize by the bottom-right grip; the owner reads reqW/reqH and lays out to fit. */
    public var resizable = false;
    /** Locked: no drag, no resize (clicks still work). */
    public var locked = false;
    public var reqW = -1.0;
    public var reqH = -1.0;
    public var resized = false;
    var resizing = false;
    var resizeDX = 0.0;
    var resizeDY = 0.0;
    var dragging = false;
    var dragDX = 0.0;
    var dragDY = 0.0;
    public var moved = false;

    public function new(parent:Dynamic) {
        root = Gfx.obj(parent);
        bg = Gfx.graphics(root);
        fg = Gfx.graphics(root);
        try hit = G.create("h2d.Interactive", [w, h, root, null]) catch (e:Dynamic) Log.once("interactive", "h2d.Interactive failed: " + Std.string(e), 1);
        Gfx.addChild(root, fg); // texts sit between bg and fg; fg on top
    }

    public function dispose():Void Gfx.remove(root);

    public function show(v:Bool):Void {
        visibleNow = v;
        Gfx.visible(root, v);
    }

    public function contains(mx:Float, my:Float):Bool return mx >= x && mx < x + w && my >= y && my < y + h;

    /** Drag by the title bar and run clicks. Returns true when the mouse is over the panel. */
    public function input(sw:Float, sh:Float):Bool {
        var over = contains(Input.mouseX, Input.mouseY);
        var onGrip = resizable && !locked && Input.mouseX >= x + w - 16 && Input.mouseX < x + w && Input.mouseY >= y + h - 16 && Input.mouseY < y + h;
        if (Input.leftPressed && onGrip) {
            resizing = true;
            resizeDX = x + w - Input.mouseX;
            resizeDY = y + h - Input.mouseY;
        } else if (Input.leftPressed && over) {
            var handled = false;
            for (r in regions)
                if (Input.mouseX >= x + r.x && Input.mouseX < x + r.x + r.w && Input.mouseY >= y + r.y && Input.mouseY < y + r.y + r.h) {
                    try r.fn() catch (e:Dynamic) Log.once("click", "click failed: " + Std.string(e), 3);
                    handled = true;
                    break;
                }
            if (!handled && !locked && Input.mouseY < y + titleH) {
                dragging = true;
                dragDX = Input.mouseX - x;
                dragDY = Input.mouseY - y;
            }
        }
        if (resizing) {
            if (!Input.leftDown) {
                resizing = false;
                resized = true;
            } else {
                reqW = Math.max(360, Math.min(sw - x, Input.mouseX + resizeDX - x));
                reqH = Math.max(160, Math.min(sh - y, Input.mouseY + resizeDY - y));
            }
        }
        if (dragging) {
            if (!Input.leftDown) {
                dragging = false;
                moved = true;
            } else {
                x = Math.max(0, Math.min(sw - 60, Input.mouseX - dragDX));
                y = Math.max(0, Math.min(sh - titleH, Input.mouseY - dragDY));
            }
        }
        Gfx.pos(root, x, y);
        return over || dragging || resizing;
    }

    public var isResizing(get, never):Bool;
    inline function get_isResizing() return resizing;

    // ---- immediate drawing ----

    public function begin(width:Float, height:Float):Void {
        w = width;
        h = height;
        used = 0;
        usedBitmaps = 0;
        nextRegions = [];
        nextTips = [];
        Gfx.clear(bg);
        Gfx.clear(fg);
        if (hit != null) {
            G.set(hit, "width", w);
            G.set(hit, "height", h);
        }
        Gfx.line(bg, 1.5, 0x8B5CF6, 1);
        Gfx.fill(bg, 0x0F0B1A, 0.9);
        Gfx.rect(bg, 0, 0, w, h);
        Gfx.endFill(bg);
        Gfx.noLine(bg);
        Gfx.fill(bg, 0x2E1065, 0.95);
        Gfx.rect(bg, 0, 0, w, titleH);
        Gfx.endFill(bg);
    }

    public function end():Void {
        if (resizable) {
            // Grip: three short diagonal strokes in the corner.
            Gfx.line(fg, 1.5, 0xA78BFA, 0.9);
            for (k in 0...3) {
                var d = 4 + k * 4;
                Gfx.moveTo(fg, w - 3, h - 3 - d);
                Gfx.lineTo(fg, w - 3 - d, h - 3);
            }
            Gfx.noLine(fg);
        }
        for (i in used...pool.length) pool[i].show(false);
        for (i in usedBitmaps...bitmaps.length) if (bitmaps[i].vis) {
            bitmaps[i].vis = false;
            Gfx.visible(bitmaps[i].b, false);
        }
        regions = nextRegions;
        tips = nextTips;
    }

    public function text(tx:Float, ty:Float, s:String, color = 0xEDE9FE, size = 14.0, ?rightAlignW:Float):Float {
        var l:Gfx.Label;
        if (used < pool.length) l = pool[used] else {
            l = Gfx.text(root, color);
            if (l == null) return 0;
            pool.push(l);
        }
        used++;
        l.show(true).set(s).color(color).size(size);
        var tw = 0.0;
        if (rightAlignW != null) {
            tw = l.width();
            l.at(tx + rightAlignW - tw, ty);
        } else l.at(tx, ty);
        return tw;
    }

    public function box(bx:Float, by:Float, bw:Float, bh:Float, color:Int, a = 1.0, top = false):Void {
        if (bw <= 0 || bh <= 0) return;
        var g = top ? fg : bg;
        Gfx.fill(g, color, a);
        Gfx.rect(g, bx, by, bw, bh);
        Gfx.endFill(g);
    }

    public function frame(bx:Float, by:Float, bw:Float, bh:Float, color:Int):Void {
        Gfx.line(bg, 1, color, 1);
        Gfx.moveTo(bg, bx, by);
        Gfx.lineTo(bg, bx + bw, by);
        Gfx.lineTo(bg, bx + bw, by + bh);
        Gfx.lineTo(bg, bx, by + bh);
        Gfx.lineTo(bg, bx, by);
        Gfx.noLine(bg);
    }

    public function button(bx:Float, by:Float, bw:Float, label:String, active:Bool, fn:Void->Void):Void {
        var bh = 18.0;
        box(bx, by, bw, bh, active ? 0x7C3AED : 0x231B3A, 1);
        frame(bx, by, bw, bh, 0xA78BFA);
        text(bx + 6, by + 1, label, active ? 0xFFFFFF : 0xD6CCF5, 13);
        click(bx, by, bw, bh, fn);
    }

    static function cellTile(cell:Int):Dynamic {
        if (atlas == null || cell < 0) return null;
        var t = cells.get(cell);
        if (t == null) {
            var px = fo.data.GameTables.ICON_CELL_PX, cols = fo.data.GameTables.ICON_ATLAS_COLS;
            t = G.call("h2d.Tile", "sub", atlas, [(cell % cols) * px * 1.0, Std.int(cell / cols) * px * 1.0, px * 1.0, px * 1.0, null, null]);
            cells.set(cell, t);
        }
        return t;
    }

    /** A cell of the gear atlas with a border (rarity color); an empty frame without the atlas. */
    public function icon(ix:Float, iy:Float, size:Float, cell:Int, border:Int):Void {
        box(ix - 1, iy - 1, size + 2, size + 2, border, 1);
        box(ix, iy, size, size, 0x15101F, 1);
        var t = cellTile(cell);
        if (t == null) return;
        var e = usedBitmaps < bitmaps.length ? bitmaps[usedBitmaps] : null;
        if (e == null) {
            var b = G.create("h2d.Bitmap", [t, root]);
            e = {b: b, cell: cell, x: -1, y: -1, s: -1, vis: true, t: t};
            bitmaps.push(e);
        }
        usedBitmaps++;
        if (e.cell != cell || e.t != t) {
            e.cell = cell;
            e.t = t;
            G.call("h2d.Bitmap", "set_tile", e.b, [t]);
        }
        if (!e.vis) {
            e.vis = true;
            Gfx.visible(e.b, true);
        }
        if (e.x != ix || e.y != iy) {
            e.x = ix;
            e.y = iy;
            Gfx.pos(e.b, ix, iy);
        }
        var sc = size / fo.data.GameTables.ICON_CELL_PX;
        if (e.s != sc) {
            e.s = sc;
            Gfx.scale(e.b, sc);
        }
    }

    /** Hover text for a region; the last one added wins where regions overlap. */
    public function tip(bx:Float, by:Float, bw:Float, bh:Float, text:String):Void nextTips.push({x: bx, y: by, w: bw, h: bh, text: text});

    /** Text of the hovered tip region, if the mouse is over this panel. */
    public function hoveredTip():String {
        if (!visibleNow || !contains(Input.mouseX, Input.mouseY)) return null;
        var i = tips.length - 1;
        while (i >= 0) {
            var t = tips[i];
            if (Input.mouseX >= x + t.x && Input.mouseX < x + t.x + t.w && Input.mouseY >= y + t.y && Input.mouseY < y + t.y + t.h) return t.text;
            i--;
        }
        return null;
    }

    public var visibleNow = true;

    /** Any game tile (e.g. a skill icon), scaled to `size`. */
    public function tileIcon(ix:Float, iy:Float, size:Float, t:Dynamic):Void {
        if (t == null) return;
        var e = usedBitmaps < bitmaps.length ? bitmaps[usedBitmaps] : null;
        if (e == null) {
            var b = G.create("h2d.Bitmap", [t, root]);
            e = {b: b, cell: -2, x: -1, y: -1, s: -1, vis: true, t: t};
            bitmaps.push(e);
        }
        usedBitmaps++;
        if (e.t != t) {
            e.t = t;
            e.cell = -2;
            G.call("h2d.Bitmap", "set_tile", e.b, [t]);
        }
        if (!e.vis) {
            e.vis = true;
            Gfx.visible(e.b, true);
        }
        if (e.x != ix || e.y != iy) {
            e.x = ix;
            e.y = iy;
            Gfx.pos(e.b, ix, iy);
        }
        var tw = G.num(G.f(t, "width"), size);
        var sc = tw > 0 ? size / tw : 1;
        if (e.s != sc) {
            e.s = sc;
            Gfx.scale(e.b, sc);
        }
    }

    /** Small triangle: open (pointing down) or closed (pointing right). */
    public function arrow(ax:Float, ay:Float, open:Bool, color = 0x8C849E):Void {
        Gfx.fill(bg, color, 1);
        if (open) Gfx.poly(bg, [ax, ay + 2, ax + 8, ay + 2, ax + 4, ay + 8]) else Gfx.poly(bg, [ax + 1, ay, ax + 7, ay + 4, ax + 1, ay + 8]);
        Gfx.endFill(bg);
    }

    public function poly(pts:Array<Float>, fill:Int, line:Int):Void {
        Gfx.line(bg, 1, line, 1);
        Gfx.fill(bg, fill, 1);
        Gfx.poly(bg, pts);
        Gfx.endFill(bg);
        Gfx.noLine(bg);
    }

    public function dot(cx:Float, cy:Float, r:Float, color:Int, filled:Bool):Void {
        if (filled) {
            Gfx.fill(bg, color, 1);
            Gfx.circle(bg, cx, cy, r);
            Gfx.endFill(bg);
        } else {
            Gfx.line(bg, 1.5, color, 1);
            Gfx.circle(bg, cx, cy, r);
            Gfx.noLine(bg);
        }
    }

    public function click(bx:Float, by:Float, bw:Float, bh:Float, fn:Void->Void):Void nextRegions.push({x: bx, y: by, w: bw, h: bh, fn: fn});

    /** A thin bar split by damage type: physical orange, magic blue, raw white, unknown grey. */
    public function typeBar(bx:Float, by:Float, bw:Float, bh:Float, total:Float, phys:Float, magic:Float, raw:Float):Void {
        box(bx, by, bw, bh, 0x2A2438, 1);
        if (total <= 0) return;
        var px = bx;
        for (part in [[phys, PHYS], [magic, MAGIC], [raw, RAW], [Math.max(0, total - phys - magic - raw), UNKNOWN]]) {
            var pw = bw * part[0] / total;
            box(px, by, pw, bh, Std.int(part[1]), 1);
            px += pw;
        }
    }
}
