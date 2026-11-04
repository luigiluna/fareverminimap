package fo;

import fo.logic.MapMath;
import fo.logic.Pois;
import fo.logic.Pois.Poi;

/**
 * A view of the world map: the map image, markers by kind, the player arrow and a
 * frame. Round (minimap, may rotate) or rectangular (large map, north up).
 *
 * Layout in the game's scene:
 *   root (centre of the view)
 *     rotC (rotation)  -> mapG: the image, drawn as a tile-filled disc or rect
 *     markG            -> markers, upright
 *     meG              -> player arrow
 *     frameG           -> border
 */
class MapView {
    public var root:Dynamic;
    var rotC:Dynamic;
    var mapG:Dynamic;
    var markG:Dynamic;
    var meG:Dynamic;
    var frameG:Dynamic;
    var hit:Dynamic;
    var othersG:Dynamic;
    var iconG:Dynamic; // activities.png icons (one texture per Graphics)
    var meObj:Dynamic; // PlayerMapArrow.png, rotated
    public static var activityTile:Dynamic;
    public static var arrowTile:Dynamic;
    var otherLabels:Array<Gfx.Label> = [];
    var othersKey = "";

    public var round:Bool;
    public var radius = 100.0; // round
    public var w = 400.0; // rect
    public var h = 400.0;
    public var screenX = 0.0; // centre on screen
    public var screenY = 0.0;

    /** Last drawn state, so unchanged frames cost nothing. */
    var drawnKey = "";
    var markKey = "";
    var meKey = "";

    /** Markers drawn this frame, in screen coordinates, for hover tests. */
    public var shown:Array<{p:Poi, x:Float, y:Float}> = [];

    public function new(parent:Dynamic, round:Bool) {
        this.round = round;
        root = Gfx.obj(parent);
        rotC = Gfx.obj(root);
        mapG = Gfx.graphics(rotC);
        markG = Gfx.graphics(root);
        iconG = Gfx.graphics(root);
        othersG = Gfx.graphics(root);
        meG = Gfx.graphics(root);
        if (arrowTile != null) {
            meObj = Gfx.obj(root);
            var bmp = G.create("h2d.Bitmap", [arrowTile, meObj]);
            var aw = G.num(G.f(arrowTile, "width"), 21), ah = G.num(G.f(arrowTile, "height"), 21);
            Gfx.pos(bmp, -aw / 2, -ah / 2);
        }
        frameG = Gfx.graphics(root);
    }

    public function dispose():Void {
        Gfx.remove(root);
        root = null;
    }

    public function show(v:Bool):Void Gfx.visible(root, v);

    /** Game-side click blocker over the view (an h2d.Interactive); none for a round minimap without input. */
    public function block(on:Bool):Void {
        if (on && hit == null) {
            try {
                hit = G.create("h2d.Interactive", [w, h, root, null]);
                Gfx.pos(hit, -w / 2, -h / 2);
            } catch (e:Dynamic) Log.once("interactive", "h2d.Interactive failed: " + Std.string(e), 1);
        }
        if (hit != null) Gfx.visible(hit, on);
    }

    var roundHit:Dynamic;
    var roundHitR = -1.0;

    /** Click blocker over the round minimap, so drags and clicks on it do not reach the game. */
    public function blockRound(on:Bool):Void {
        if (on && roundHit == null) {
            try roundHit = G.create("h2d.Interactive", [2 * radius + 24, 2 * radius + 24, root, null]) catch (e:Dynamic)
                Log.once("interactive2", "h2d.Interactive failed: " + Std.string(e), 1);
        }
        if (roundHit == null) return;
        if (on && roundHitR != radius) {
            roundHitR = radius;
            G.set(roundHit, "width", 2 * radius + 24);
            G.set(roundHit, "height", 2 * radius + 24);
            G.set(roundHit, "isEllipse", true);
            Gfx.pos(roundHit, -radius - 12, -radius - 12);
        }
        Gfx.visible(roundHit, on);
    }

    public inline function contains(mx:Float, my:Float):Bool {
        var dx = mx - screenX, dy = my - screenY;
        return round ? dx * dx + dy * dy <= radius * radius : Math.abs(dx) <= w / 2 && Math.abs(dy) <= h / 2;
    }

    /**
     * Draws the view centred on world (cx, cy) at `k` screen px per metre,
     * rotated so world heading `up` points up (null: north up).
     */
    public function draw(tile:Dynamic, tex:Float, mm:MapMath, cx:Float, cy:Float, k:Float, rotation:Float, pois:Array<Poi>,
            filter:String->Bool, hero:{x:Float, y:Float, heading:Float}, alpha:Float, done:String->Bool):Void {
        Gfx.pos(root, screenX, screenY);
        Gfx.rot(rotC, rotation);

        // Image: tile drawn so that texture pixel t lands at ((world(t) - c) * k).
        var key = Math.round(cx * 4) + "," + Math.round(cy * 4) + "," + Math.round(k * 1000) + "," + radius + "," + w + "," + h;
        if (key != drawnKey) {
            drawnKey = key;
            Gfx.clear(mapG);
            Gfx.fill(mapG, 0x14161E, 1.0);
            if (round) Gfx.circle(mapG, 0, 0, radius) else Gfx.rect(mapG, -w / 2, -h / 2, w, h);
            Gfx.endFill(mapG);
            if (tile != null && tex > 0) {
                var sx = MapMath.MOSAIC_PX * k / (tex * mm.scaleX);
                var sy = MapMath.MOSAIC_PX * k / (tex * mm.scaleY);
                var dx = (-mm.offsetX / mm.scaleX - cx) * k;
                var dy = (-mm.offsetY / mm.scaleY - cy) * k;
                Gfx.tileFill(mapG, dx, dy, sx, sy, tile);
                // A round view is a slightly bigger disc than the frame, so rotation never shows a seam.
                if (round) Gfx.circle(mapG, 0, 0, radius) else Gfx.rect(mapG, -w / 2, -h / 2, w, h);
                Gfx.endFill(mapG);
            }
            Gfx.alpha(mapG, alpha);
        }

        // Markers, upright, rotated around the centre by hand.
        var ca = Math.cos(rotation), sa = Math.sin(rotation);
        shown = [];
        var mk = new StringBuf();
        var lim = round ? radius - 4 : 0;
        var list:Array<{p:Poi, x:Float, y:Float}> = [];
        for (p in pois) {
            if (!filter(p.kind)) continue;
            var lx = (p.x - cx) * k, ly = (p.y - cy) * k;
            var rx = lx * ca - ly * sa, ry = lx * sa + ly * ca;
            if (round) {
                if (rx * rx + ry * ry > lim * lim) continue;
            } else if (Math.abs(rx) > w / 2 - 4 || Math.abs(ry) > h / 2 - 4) continue;
            list.push({p: p, x: rx, y: ry});
            mk.add(Math.round(rx));
            mk.add(",");
            mk.add(Math.round(ry));
            mk.add(done(p.id) ? "d" : "");
            mk.add(";");
        }
        var mkey = mk.toString();
        if (mkey != markKey) {
            markKey = mkey;
            Gfx.clear(markG);
            Gfx.clear(iconG);
            // Big markers last, so altars stay on top of plants.
            list.sort((a, b) -> rank(a.p.kind) - rank(b.p.kind));
            var sz = round ? 4.5 : 5.5;
            for (m in list) {
                var cell = activityTile != null ? Pois.atlasCell(m.p) : null;
                if (cell != null) {
                    // Icon from activities.png: the cell, scaled to the marker size.
                    var half = sz * 2.0, sc = half * 2 / 128.0;
                    Gfx.tileFill(iconG, m.x - half - cell.col * 128 * sc, m.y - half - cell.row * 128 * sc, sc, sc, activityTile);
                    Gfx.rect(iconG, m.x - half, m.y - half, half * 2, half * 2);
                    Gfx.endFill(iconG);
                } else drawMarker(markG, m.p, m.x, m.y, sz, done(m.p.id));
            }
        }
        for (m in list) shown.push({p: m.p, x: screenX + m.x, y: screenY + m.y});

        // Player arrow.
        if (hero != null) {
            var hx = (hero.x - cx) * k, hy = (hero.y - cy) * k;
            var px = hx * ca - hy * sa, py = hx * sa + hy * ca;
            var ang = hero.heading + rotation;
            var inside = round ? px * px + py * py <= radius * radius : Math.abs(px) <= w / 2 && Math.abs(py) <= h / 2;
            var mek = Math.round(px) + "," + Math.round(py) + "," + Math.round(ang * 50) + inside;
            if (mek != meKey && meObj != null) {
                meKey = mek;
                Gfx.visible(meObj, inside);
                Gfx.pos(meObj, px, py);
                Gfx.rot(meObj, ang + Math.PI / 2); // the image points up
            } else if (mek != meKey) {
                meKey = mek;
                Gfx.clear(meG);
                if (inside) {
                    var s = 9.0;
                    var c = Math.cos(ang), n = Math.sin(ang);
                    inline function pt(fx:Float, fy:Float) return [px + fx * c - fy * n, py + fx * n + fy * c];
                    var a = pt(s, 0), b = pt(-s * 0.7, s * 0.65), m = pt(-s * 0.35, 0), d = pt(-s * 0.7, -s * 0.65);
                    Gfx.line(meG, 1.5, 0x000000, 0.9);
                    Gfx.fill(meG, 0xFFFFFF, 1.0);
                    Gfx.poly(meG, a.concat(b).concat(m).concat(d));
                    Gfx.endFill(meG);
                    Gfx.noLine(meG);
                }
            }
        }
    }

    /** Other players: a blue arrow with the name (green for the group). */
    public function drawOthers(list:Array<{x:Float, y:Float, heading:Float, name:String, group:Bool}>, cx:Float, cy:Float, k:Float,
            rotation:Float, names:Bool):Void {
        var ca = Math.cos(rotation), sa = Math.sin(rotation);
        var vis = [];
        for (o in list) {
            var lx = (o.x - cx) * k, ly = (o.y - cy) * k;
            var px = lx * ca - ly * sa, py = lx * sa + ly * ca;
            var inside = round ? px * px + py * py <= (radius - 6) * (radius - 6) : Math.abs(px) <= w / 2 - 6 && Math.abs(py) <= h / 2 - 6;
            if (inside) vis.push({px: px, py: py, a: o.heading + rotation, o: o});
        }
        var sb = new StringBuf();
        for (v in vis) {
            sb.add(Math.round(v.px));
            sb.add(",");
            sb.add(Math.round(v.py));
            sb.add(",");
            sb.add(Math.round(v.a * 20));
            sb.add(v.o.name);
            sb.add(";");
        }
        var key = sb.toString();
        if (key == othersKey) return;
        othersKey = key;
        Gfx.clear(othersG);
        var i = 0;
        for (v in vis) {
            var s = 6.5, c = Math.cos(v.a), n = Math.sin(v.a);
            inline function pt(fx:Float, fy:Float) return [v.px + fx * c - fy * n, v.py + fx * n + fy * c];
            Gfx.line(othersG, 1, 0x000000, 0.9);
            Gfx.fill(othersG, v.o.group ? 0x4ADE80 : 0x60A5FA, 1.0);
            Gfx.poly(othersG, pt(s, 0).concat(pt(-s * 0.7, s * 0.6)).concat(pt(-s * 0.7, -s * 0.6)));
            Gfx.endFill(othersG);
            Gfx.noLine(othersG);
            if (names && i < 40) {
                if (i >= otherLabels.length) {
                    var l = Gfx.text(root, 0xBFDBFE);
                    if (l == null) break;
                    otherLabels.push(l);
                }
                otherLabels[i].show(true).set(v.o.name).color(v.o.group ? 0x86EFAC : 0xBFDBFE).size(11).at(v.px + 7, v.py - 6);
                i++;
            }
        }
        for (j in i...otherLabels.length) otherLabels[j].show(false);
    }

    public function drawFrame(accent:Int):Void {
        Gfx.clear(frameG);
        Gfx.line(frameG, 3, accent, 1.0);
        if (round) {
            Gfx.circle(frameG, 0, 0, radius);
        } else {
            Gfx.moveTo(frameG, -w / 2, -h / 2);
            Gfx.lineTo(frameG, w / 2, -h / 2);
            Gfx.lineTo(frameG, w / 2, h / 2);
            Gfx.lineTo(frameG, -w / 2, h / 2);
            Gfx.lineTo(frameG, -w / 2, -h / 2);
        }
        Gfx.noLine(frameG);
        if (round) {
            // North tick is drawn by the owner (it moves with the rotation).
        }
        if (hit != null) {
            G.set(hit, "width", w);
            G.set(hit, "height", h);
            Gfx.pos(hit, -w / 2, -h / 2);
        }
    }

    /** Graphics for the frame's extras (north mark, buttons). */
    public var frame(get, never):Dynamic;
    inline function get_frame() return frameG;

    static function rank(kind:String):Int {
        return switch (kind) {
            case "plant", "ore": 0;
            case "red_orb", "chest": 1;
            case "activity", "merchant", "respawn", "obelisk": 2;
            case "dungeon": 3;
            case "soulstone": 4;
            default: 1;
        }
    }

    /** Legend swatch: the marker of a kind, without a POI. */
    public static function drawKind(g:Dynamic, kind:String, x:Float, y:Float, s:Float, dim:Bool):Void
        drawMarker(g, {kind: kind, subkind: "", name: "", id: "", zone: "", x: 0, y: 0, z: 0}, x, y, s, dim);

    /**
     * The overlay's markers: collectibles get a glyph over a dark disc with a gold ring;
     * the rest a shape in the kind's color (activities by subkind).
     */
    public static function drawMarker(g:Dynamic, p:Poi, x:Float, y:Float, s:Float, done:Bool):Void {
        var kind = p.kind;
        var st = Pois.style(kind);
        var a = done ? 0.35 : 1.0;
        var color = kind == "activity" ? Pois.activityColor(p.subkind) : st.color;
        switch (kind) {
            case "chest", "red_orb", "plant", "ore", "soulstone":
                var r = s * 1.35;
                Gfx.line(g, 1.2, 0xFFDC96, 0.9 * a);
                Gfx.fill(g, 0x120E08, 0.69 * a);
                Gfx.circle(g, x, y, r + 0.5);
                Gfx.endFill(g);
                Gfx.noLine(g);
                glyph(g, kind, x, y, s, color, a);
                return;
            default:
        }
        Gfx.line(g, 1.2, 0x000000, 0.85 * a);
        Gfx.fill(g, color, a);
        switch (st.shape) {
            case Circle:
                Gfx.circle(g, x, y, s * 0.8);
            case Square:
                Gfx.rect(g, x - s * 0.75, y - s * 0.75, s * 1.5, s * 1.5);
            case Triangle:
                Gfx.poly(g, [x, y - s, x + s * 0.9, y + s * 0.75, x - s * 0.9, y + s * 0.75]);
            case Diamond:
                Gfx.poly(g, [x, y - s, x + s * 0.8, y, x, y + s, x - s * 0.8, y]);
            case Cross:
                var t = s * 0.35;
                Gfx.poly(g, [x - t, y - s, x + t, y - s, x + t, y - t, x + s, y - t, x + s, y + t, x + t, y + t, x + t, y + s, x - t, y + s, x - t, y + t,
                    x - s, y + t, x - s, y - t, x - t, y - t]);
            case Star:
                var pts = [];
                for (i in 0...10) {
                    var r = i % 2 == 0 ? s * 1.15 : s * 0.5;
                    var ang = -Math.PI / 2 + i * Math.PI / 5;
                    pts.push(x + Math.cos(ang) * r);
                    pts.push(y + Math.sin(ang) * r);
                }
                Gfx.poly(g, pts);
        }
        Gfx.endFill(g);
        Gfx.noLine(g);
    }

    /** Glyphs ported from the overlay's pois.cpp (chest, orb, plant, ore, soulstone gem). */
    static function glyph(g:Dynamic, kind:String, x:Float, y:Float, s:Float, fill:Int, a:Float):Void {
        Gfx.line(g, 1.0, 0x000000, 0.8 * a);
        switch (kind) {
            case "chest":
                var w = s * 1.1, up = s * 0.55, dn = s * 0.40;
                Gfx.fill(g, fill, a);
                Gfx.rect(g, x - w, y - up, w * 2, up + dn);
                Gfx.endFill(g);
                Gfx.noLine(g);
                Gfx.fill(g, 0x28200C, a);
                Gfx.rect(g, x - w, y - up * 0.1 - 0.5, w * 2, 1);
                Gfx.rect(g, x - 1.6, y - 1.6, 3.2, 3.4);
                Gfx.endFill(g);
            case "red_orb":
                Gfx.fill(g, fill, a);
                Gfx.circle(g, x, y, s);
                Gfx.endFill(g);
                Gfx.noLine(g);
                Gfx.fill(g, 0xFFDCDC, 0.78 * a);
                Gfx.circle(g, x - s * 0.35, y - s * 0.35, s * 0.30);
                Gfx.endFill(g);
            case "plant":
                Gfx.noLine(g);
                Gfx.fill(g, fill, a);
                Gfx.poly(g, [x, y + s * 0.25, x - s * 0.9, y - s * 0.1, x - s * 1.1, y + s * 0.4, x - s * 0.35, y + s * 0.55]);
                Gfx.poly(g, [x, y + s * 0.25, x + s * 0.9, y - s * 0.1, x + s * 1.1, y + s * 0.4, x + s * 0.35, y + s * 0.55]);
                Gfx.poly(g, [x, y - s, x - s * 0.45, y + s * 0.1, x + s * 0.45, y + s * 0.1]);
                Gfx.rect(g, x - 0.75, y + s * 0.55, 1.5, s * 0.45);
                Gfx.endFill(g);
            case "ore":
                Gfx.fill(g, fill, a);
                for (d in [[-0.45, 0.25, 0.55], [0.45, 0.25, 0.50], [0.0, -0.30, 0.60]]) {
                    var cx = x + s * d[0], cy = y + s * d[1], r = s * d[2];
                    Gfx.poly(g, [cx, cy - r, cx + r, cy, cx, cy + r, cx - r, cy]);
                }
                Gfx.endFill(g);
            case "soulstone":
                Gfx.fill(g, fill, a);
                Gfx.poly(g, [x, y - s * 1.05, x + s * 0.62, y - s * 0.15, x, y + s * 0.75, x - s * 0.62, y - s * 0.15]);
                Gfx.endFill(g);
                Gfx.noLine(g);
                Gfx.fill(g, 0xFFD2F0, 0.82 * a);
                Gfx.poly(g, [x, y - s * 1.05, x - s * 0.62, y - s * 0.15, x, y - s * 0.15]);
                Gfx.rect(g, x - s * 0.8, y + s * 0.95 - 1, s * 1.6, 2);
                Gfx.endFill(g);
            default:
        }
        Gfx.noLine(g);
    }
}
