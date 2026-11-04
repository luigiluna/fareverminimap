package fo;

import fo.logic.Pois;

/**
 * Map options, opened from the minimap's menu button: what the minimap and
 * the large map show (one set of filters for both), other players, rotation,
 * and the minimap's lock / position. Same look as the DPS window.
 */
class MapOptions {
    var p:Panel;
    var dirty = true;
    public var isOpen(default, null) = false;

    static inline var W = 300.0;
    static inline var ROW = 22.0;

    public function new(parent:Dynamic, x:Float, y:Float) {
        p = new Panel(parent);
        p.x = x;
        p.y = y;
        p.show(false);
    }

    public function dispose() p.dispose();

    public function toggle():Void if (isOpen) close() else open();

    public function open():Void {
        isOpen = true;
        dirty = true;
        p.show(true);
    }

    public function close():Void {
        isOpen = false;
        p.show(false);
    }

    /** Redraw on the next update (a filter changed elsewhere, e.g. on the large map). */
    public function refresh() dirty = true;

    public function contains(mx:Float, my:Float) return isOpen && p.contains(mx, my);

    public function hoveredTip() return isOpen ? p.hoveredTip() : null;

    public var x(get, never):Float;
    inline function get_x() return p.x;
    public var y(get, never):Float;
    inline function get_y() return p.y;

    public function moved():Bool {
        var m = p.moved;
        p.moved = false;
        return m;
    }

    public function update(cfg:Dynamic, sw:Float, sh:Float):Void {
        if (!isOpen) return;
        if (p.input(sw, sh) && Input.leftPressed) dirty = true;
        if (!isOpen || !dirty) return; // a click on "x" closes inside p.input
        dirty = false;
        draw(cfg);
    }

    function check(cfg:Dynamic, x:Float, y:Float, label:String, on:Bool, fn:Void->Void, ?tip:String, ?swatch:Int):Void {
        p.box(x, y + 4, 13, 13, on ? 0x7C3AED : 0x1E1B2E, 1);
        p.frame(x, y + 4, 13, 13, 0xA78BFA);
        var tx = x + 20;
        if (swatch != null) {
            p.box(tx, y + 6, 9, 9, swatch, on ? 1 : 0.35);
            tx += 15;
        }
        p.text(tx, y + 2, label, on ? Panel.TEXT : Panel.DIM, 13);
        p.click(x - 2, y, 140, ROW, () -> {
            fn();
            dirty = true;
            OverlayMod.saveSoon();
        });
        if (tip != null) p.tip(x - 2, y, 140, ROW, tip);
    }

    static function kindOn(cfg:Dynamic, k:KindStyle):Bool {
        var v:Dynamic = Reflect.field(cfg.filters, k.kind);
        return v == null ? k.onByDefault : v == true;
    }

    function draw(cfg:Dynamic):Void {
        var kinds = Pois.KINDS;
        var half = Std.int((kinds.length + 1) / 2);
        var h = 26 + 24 + ROW * half + 30 + 24 + ROW * 2 + 30 + ROW * 2 + 10;
        p.begin(W, h);
        p.text(10, 4, "Map options", 0xFFFFFF, 15);
        p.button(W - 30, 4, 24, " x", false, close);

        var y = 32.0;
        p.text(10, y, "Shown on the minimap and the large map", DpsTables.HEAD, 13);
        p.button(W - 86, y - 1, 36, "All", false, () -> {
            for (k in kinds) Reflect.setField(cfg.filters, k.kind, true);
            dirty = true;
            OverlayMod.saveSoon();
        });
        p.button(W - 46, y - 1, 40, "None", false, () -> {
            for (k in kinds) Reflect.setField(cfg.filters, k.kind, false);
            dirty = true;
            OverlayMod.saveSoon();
        });
        y += 22;
        for (i in 0...kinds.length) {
            var k = kinds[i];
            var cx = i < half ? 12.0 : 12 + W / 2;
            var cy = y + ROW * (i < half ? i : i - half);
            var on = kindOn(cfg, k);
            check(cfg, cx, cy, k.label, on, () -> Reflect.setField(cfg.filters, k.kind, !on), null, k.color);
        }
        y += ROW * half + 8;

        p.box(10, y, W - 20, 1, 0x3B2A66);
        y += 8;
        p.text(10, y, "Players", DpsTables.HEAD, 13);
        y += 22;
        check(cfg, 12, y, "Other players", cfg.showPlayers, () -> cfg.showPlayers = !cfg.showPlayers, "Players near you, on both maps (group in green)");
        check(cfg, 12 + W / 2, y, "Their names", cfg.playerNames, () -> cfg.playerNames = !cfg.playerNames, "Names next to the arrows on the minimap");
        y += ROW + 8;

        p.box(10, y, W - 20, 1, 0x3B2A66);
        y += 8;
        p.text(10, y, "Minimap", DpsTables.HEAD, 13);
        y += 22;
        check(cfg, 12, y, "Rotate", cfg.rotateMinimap, () -> cfg.rotateMinimap = !cfg.rotateMinimap, "Off: north is always up");
        check(cfg, 12 + W / 2, y, "With the camera", cfg.followCamera, () -> cfg.followCamera = !cfg.followCamera,
            "When rotating: follow the camera (off: the character)");
        y += ROW;
        check(cfg, 12, y, "Lock", cfg.minimapLocked, () -> cfg.minimapLocked = !cfg.minimapLocked, "No moving or resizing the minimap");
        p.button(12 + W / 2, y + 2, 120, "Reset position", false, () -> {
            cfg.minimapX = -1;
            cfg.minimapY = -1;
            cfg.minimapSize = 220;
            dirty = true;
            OverlayMod.saveSoon();
        });
        p.tip(12 + W / 2, y + 2, 120, 18, "Back to the top-right corner, default size");
        p.end();
    }
}
