package fo;

import fo.logic.MapMath;
import fo.logic.Pois;

/** Round minimap in the top-right corner, plus the large map on a key. */
class Minimap {
    var mini:MapView;
    var big:MapView;
    var tip:Tooltip;
    var legend:Legend;
    var compassG:Dynamic;
    var northLabel:Gfx.Label;
    var bigTitle:Gfx.Label;
    var mm = new MapMath();
    public var pois:Array<Poi> = [];

    // Smoothed hero state, like the overlay: position quick, heading calm.
    var sx = 0.0;
    var sy = 0.0;
    var sUp = 0.0;
    var sHeading = 0.0;
    var smoothInit = false;

    public var bigOpen = false;
    var panX = 0.0;
    var panY = 0.0;
    var dragging = false;
    var dragX = 0.0;
    var dragY = 0.0;

    var parent:Dynamic;
    var others:Array<{x:Float, y:Float, heading:Float, name:String, group:Bool}> = [];
    var othersAt = -1e9;

    /** Players the server sends to this client (near you), from the hero's layer. */
    function readOthers(hero:Dynamic, now:Float, groupUids:Array<Float>):Void {
        if (now - othersAt < 100) return;
        othersAt = now;
        others = [];
        var list = G.f(G.f(G.f(hero, "layer"), "players"), "array");
        var n = Std.int(Math.min(G.alen(list), 64));
        for (i in 0...n) {
            var pl = G.aget(list, i);
            var h = G.f(pl, "hero");
            if (h == null || h == hero || G.bool(G.f(h, "removed"))) continue;
            var name = G.str(G.f(h, "name"));
            if (name == null || name == "") name = G.str(G.f(pl, "name"));
            others.push({x: G.num(G.f(h, "posx")), y: G.num(G.f(h, "posy")), heading: G.num(G.f(h, "rotationZ")), name: name == null ? "?" : name,
                group: groupUids.indexOf(G.num(G.f(h, "__uid"))) >= 0});
        }
    }

    public function new(parent:Dynamic, dataDir:String) {
        this.parent = parent;
        try {
            pois = Pois.parse(sys.io.File.getContent(dataDir + "/pois_W1_Siagarta.json"));
            var n = 0;
            for (p in pois) if (p.kind == "soulstone") n++;
            Log.info('pois loaded: ${pois.length} (soulstone altars: $n)');
        } catch (e:Dynamic) Log.err("pois load failed: " + Std.string(e));
        try mm.loadCalibration(haxe.Json.parse(sys.io.File.getContent(dataDir + "/minimap_calibration.json"))) catch (e:Dynamic)
            Log.info("calibration: using built-in defaults (" + Std.string(e) + ")");
        MapTexture.load(dataDir + "/W1_Siagarta.preview.png");
        MapView.activityTile = MapTexture.loadTile(dataDir + "/activities.png");
        MapView.arrowTile = MapTexture.loadTile(dataDir + "/PlayerMapArrow.png");

        mini = new MapView(parent, true);
        compassG = Gfx.graphics(mini.root);
        northLabel = Gfx.text(mini.root, 0xFFFFFF);
        big = new MapView(parent, false);
        big.show(false);
        bigTitle = Gfx.text(big.root, 0xEDE9FE);
        legend = new Legend(big.root);
        tip = new Tooltip(parent);
    }

    public function dispose():Void {
        mini.dispose();
        big.dispose();
        tip.dispose();
    }

    var lastLevel:String = null;
    var noMap:Gfx.Label;

    public function update(cfg:Dynamic, app:Dynamic, hero:Dynamic, sw:Float, sh:Float, dt:Float, now:Float, groupUids:Array<Float>):Void {
        // The image and markers are W1 only: dungeons and other maps get an empty disc.
        var level:String = null;
        if (cfg.featMapLevel) {
            Log.stage("map level");
            level = G.str(G.f(G.f(app, "world"), "level"));
        }
        if (level != lastLevel) {
            lastLevel = level;
            Log.info("map level: " + level);
        }
        var onW1 = level == null || level.indexOf("W1_Siagarta") >= 0 || level.indexOf("Siagarta") >= 0;
        if (cfg.showPlayers) Log.stage("other players");
        if (cfg.showPlayers) try readOthers(hero, now, groupUids) catch (e:Dynamic) Log.once("others", "players read failed: " + Std.string(e), 2) else others = [];
        var hx = G.num(G.f(hero, "posx")), hy = G.num(G.f(hero, "posy"));
        var heading = G.num(G.f(hero, "rotationZ"));
        var cam = G.f(app, "camera");
        var yaw = cam != null ? G.num(G.f(cam, "curDirection"), heading) : heading;
        var up = cfg.followCamera ? yaw : heading;

        if (dt < 0) dt = 0;
        if (dt > 0.25) dt = 0.25;
        var jump = (hx - sx) * (hx - sx) + (hy - sy) * (hy - sy) > 500 * 500;
        if (!smoothInit || jump) {
            sx = hx;
            sy = hy;
            sUp = up;
            sHeading = heading;
            smoothInit = true;
        } else {
            var ap = 1 - Math.exp(-dt / 0.06), ah = 1 - Math.exp(-dt / 0.25);
            sx += (hx - sx) * ap;
            sy += (hy - sy) * ap;
            sUp = MapMath.lerpAngle(sUp, up, ah);
            sHeading = MapMath.lerpAngle(sHeading, heading, ah);
        }

        var filters:Dynamic = cfg.filters;
        var filter = (kind:String) -> {
            var v:Dynamic = Reflect.field(filters, kind);
            return v == null ? Pois.style(kind).onByDefault : v == true;
        };
        var none = (_:String) -> false;
        var me = {x: sx, y: sy, heading: sHeading};
        var tile = onW1 ? MapTexture.tile : null, tex = MapTexture.size;
        if (!onW1) filter = none;
        if (noMap == null) noMap = Gfx.text(mini.root, 0x9CA3AF);
        var hovered:{p:Poi, x:Float, y:Float} = null;

        // ---- minimap ----
        var showMini = cfg.showMinimap && !bigOpen;
        mini.show(showMini);
        if (!showMini) mini.blockRound(false);
        var hoveredText:String = null;
        if (showMini) {
            var size:Float = Math.max(120, Math.min(500, cfg.minimapSize));
            var r = size / 2;
            if (mini.radius != r) {
                mini.radius = r;
                mini.drawFrame(0x8B5CF6);
            }
            // Position: saved centre, or the top-right corner; kept on screen.
            var cxs:Float = cfg.minimapX, cys:Float = cfg.minimapY;
            if (cxs < 0 || cys < 0) {
                cxs = sw - r - 24;
                cys = r + 24 + 40;
            }
            mini.screenX = Math.max(r, Math.min(sw - r, cxs));
            mini.screenY = Math.max(r, Math.min(sh - r, cys));
            mini.blockRound(true);
            var range:Float = Math.max(40, cfg.minimapRangeM);
            var k = r / range;
            var rotation = cfg.rotateMinimap ? MapMath.rotationFor(sUp) : 0.0;
            mini.draw(tile, tex, mm, sx, sy, k, rotation, pois, filter, me, cfg.minimapAlpha, none);
            mini.drawOthers(others, sx, sy, k, rotation, cfg.playerNames);
            drawNorth(r, rotation);
            bezelButtons(cfg, r, range, sw, sh);
            noMap.show(!onW1).set("No map here").size(13).at(-34, r * 0.45);
            if (bezelTip != null) hoveredText = bezelTip;
            else if (Input.inside(mini.screenX - r, mini.screenY - r, 2 * r, 2 * r) && mini.contains(Input.mouseX, Input.mouseY)) {
                if (Input.wheel != 0) {
                    cfg.minimapRangeM = Math.max(40, Math.min(1500, range * (Input.wheel > 0 ? 0.8 : 1.25)));
                    OverlayMod.saveSoon();
                }
                hovered = nearest(mini.shown);
            }
        }

        // ---- large map ----
        big.show(bigOpen);
        if (bigOpen) {
            var bw = Math.round(Math.min(sw * 0.8, sh * 0.85 * 1.35)), bh = Math.round(sh * 0.85);
            if (big.w != bw || big.h != bh) {
                big.w = bw;
                big.h = bh;
                big.block(true);
                big.drawFrame(0x8B5CF6);
            }
            big.screenX = sw / 2;
            big.screenY = sh / 2;
            var k:Float = cfg.bigPxPerM;
            var left = big.screenX - bw / 2, top = big.screenY - bh / 2;
            var over = Input.inside(left, top, bw, bh);
            var onLegend = legend.contains(Input.mouseX - big.screenX, Input.mouseY - big.screenY);
            if (over && !onLegend) {
                if (Input.wheel != 0) {
                    // Zoom around the mouse: the world point under it stays put.
                    var wx = sx + panX + (Input.mouseX - big.screenX) / k, wy = sy + panY + (Input.mouseY - big.screenY) / k;
                    var nk = Math.max(0.05, Math.min(8, k * (Input.wheel > 0 ? 1.25 : 0.8)));
                    panX = wx - sx - (Input.mouseX - big.screenX) / nk;
                    panY = wy - sy - (Input.mouseY - big.screenY) / nk;
                    cfg.bigPxPerM = nk;
                    k = nk;
                    OverlayMod.saveSoon();
                }
                if (Input.doubleClick) {
                    panX = panY = 0;
                    dragging = false;
                } else if (Input.leftPressed) {
                    dragging = true;
                    dragX = Input.mouseX;
                    dragY = Input.mouseY;
                }
            }
            if (dragging) {
                if (!Input.leftDown) dragging = false else {
                    panX -= (Input.mouseX - dragX) / k;
                    panY -= (Input.mouseY - dragY) / k;
                    dragX = Input.mouseX;
                    dragY = Input.mouseY;
                }
            }
            big.draw(tile, tex, mm, sx + panX, sy + panY, k, 0, pois, filter, me, 1.0, none);
            big.drawOthers(others, sx + panX, sy + panY, k, 0, true);
            bigTitle.set("Map - drag to move, wheel to zoom, double-click to recentre, " + cfg.keyBigMap + " to close").size(14).at(-bw / 2 + 10, -bh / 2 + 8);
            if (legend.update(cfg, -bw / 2, -bh / 2 + 34, Input.mouseX - big.screenX, Input.mouseY - big.screenY, Input.leftPressed)) {
                OverlayMod.saveSoon();
                if (onFiltersChanged != null) onFiltersChanged();
            }
            if (over && !onLegend && !dragging) hovered = nearest(big.shown);
        }

        if (hoveredText != null) tip.show(hoveredText, Input.mouseX + 16, Input.mouseY + 12, sw, sh);
        else if (hovered != null) {
            var d = Math.sqrt((hovered.p.x - hx) * (hovered.p.x - hx) + (hovered.p.y - hy) * (hovered.p.y - hy));
            tip.show(Pois.tooltip(hovered.p, d), Input.mouseX + 16, Input.mouseY + 12, sw, sh);
        } else tip.hide();
    }

    var lastNorth = 1e9;
    var lastNorthR = 0.0;

    function drawNorth(r:Float, rotation:Float):Void {
        // North is world -y; on screen it sits at angle (-pi/2 + rotation).
        var a = -Math.PI / 2 + rotation;
        if (Math.abs(a - lastNorth) < 0.002 && r == lastNorthR) return;
        lastNorth = a;
        lastNorthR = r;
        var c = Math.cos(a), sn = Math.sin(a);
        Gfx.clear(compassG);
        // Red tick from the rim inwards (the overlay's kColNorth), and a small N.
        Gfx.line(compassG, 2.5, 0xFF5050, 0.9);
        Gfx.moveTo(compassG, c * r, sn * r);
        Gfx.lineTo(compassG, c * (r - 10), sn * (r - 10));
        Gfx.noLine(compassG);
        if (northLabel != null) northLabel.set("N").color(0xFF8080).size(12).at(c * (r - 20) - 4, sn * (r - 20) - 8);
    }

    var bezelG:Dynamic;
    var bezelKey = "";
    var plusL:Gfx.Label;
    var minusL:Gfx.Label;
    var bezelTip:String = null;
    var moving = false;
    var sizing = false;
    var grabDX = 0.0;
    var grabDY = 0.0;

    /** Opens / closes the map options (set by OverlayMod). */
    public var onOptions:Void->Void;
    /** A filter changed on the large map's legend. */
    public var onFiltersChanged:Void->Void;

    // Rim buttons, by angle (screen, y down): move top-left, options top-right,
    // size bottom-left, + and - bottom-right.
    static inline var A_MOVE = -0.75;
    static inline var A_OPT = -0.25;
    static inline var A_SIZE = 0.75;
    static inline var A_PLUS = 0.18;
    static inline var A_MINUS = 0.32;

    function bezelButtons(cfg:Dynamic, r:Float, range:Float, sw:Float, sh:Float):Void {
        if (bezelG == null) {
            bezelG = Gfx.graphics(mini.root);
            plusL = Gfx.text(mini.root, 0xC4B5FD);
            minusL = Gfx.text(mini.root, 0xC4B5FD);
        }
        inline function at(a:Float) return {x: Math.cos(Math.PI * a) * r, y: Math.sin(Math.PI * a) * r};
        var mv = at(A_MOVE), op = at(A_OPT), sz = at(A_SIZE), pl = at(A_PLUS), mn = at(A_MINUS);
        var locked:Bool = cfg.minimapLocked == true;
        var key = r + "|" + locked + "|" + moving + "|" + sizing;
        if (key != bezelKey) {
            bezelKey = key;
            var g = bezelG;
            Gfx.clear(g);
            for (pt in [mv, op, sz, pl, mn]) {
                var active = (pt == mv && moving) || (pt == sz && sizing);
                Gfx.line(g, 1.5, 0x8B5CF6, 0.94);
                Gfx.fill(g, active ? 0x7C3AED : 0x141020, 0.92);
                Gfx.circle(g, pt.x, pt.y, 9);
                Gfx.endFill(g);
            }
            var ic = locked ? 0x6B6480 : 0xC4B5FD;
            // Move: a cross with arrow tips.
            Gfx.line(g, 1.5, ic, 1);
            Gfx.moveTo(g, mv.x - 5, mv.y);
            Gfx.lineTo(g, mv.x + 5, mv.y);
            Gfx.moveTo(g, mv.x, mv.y - 5);
            Gfx.lineTo(g, mv.x, mv.y + 5);
            // Size: a diagonal with two corners.
            Gfx.moveTo(g, sz.x - 4, sz.y + 4);
            Gfx.lineTo(g, sz.x + 4, sz.y - 4);
            Gfx.moveTo(g, sz.x, sz.y - 4);
            Gfx.lineTo(g, sz.x + 4, sz.y - 4);
            Gfx.lineTo(g, sz.x + 4, sz.y);
            Gfx.moveTo(g, sz.x - 4, sz.y);
            Gfx.lineTo(g, sz.x - 4, sz.y + 4);
            Gfx.lineTo(g, sz.x, sz.y + 4);
            // Options: three lines.
            Gfx.line(g, 1.5, 0xC4B5FD, 1);
            for (d in [-3.5, 0.0, 3.5]) {
                Gfx.moveTo(g, op.x - 4.5, op.y + d);
                Gfx.lineTo(g, op.x + 4.5, op.y + d);
            }
            Gfx.noLine(g);
            plusL.set("+").size(15).at(pl.x - 4.5, pl.y - 10);
            minusL.set("-").size(15).at(mn.x - 3, mn.y - 10.5);
        }

        var mx = Input.mouseX - mini.screenX, my = Input.mouseY - mini.screenY;
        inline function on(pt:{x:Float, y:Float}) return (mx - pt.x) * (mx - pt.x) + (my - pt.y) * (my - pt.y) < 110;

        bezelTip = null;
        if (on(mv)) bezelTip = locked ? "Locked (Map options)" : "Drag to move the minimap";
        else if (on(sz)) bezelTip = locked ? "Locked (Map options)" : "Drag to resize the minimap";
        else if (on(op)) bezelTip = "Map options: what is shown, players, rotation, lock";
        else if (on(pl)) bezelTip = "Zoom in (or the mouse wheel)";
        else if (on(mn)) bezelTip = "Zoom out";

        if (Input.leftPressed) {
            if (on(pl)) {
                cfg.minimapRangeM = Math.max(40, range * 0.8);
                OverlayMod.saveSoon();
            } else if (on(mn)) {
                cfg.minimapRangeM = Math.min(1500, range * 1.25);
                OverlayMod.saveSoon();
            } else if (on(op)) {
                if (onOptions != null) onOptions();
            } else if (on(mv) && !locked) {
                moving = true;
                grabDX = Input.mouseX - mini.screenX;
                grabDY = Input.mouseY - mini.screenY;
            } else if (on(sz) && !locked) sizing = true;
        }
        if (moving) {
            if (!Input.leftDown) {
                moving = false;
                OverlayMod.saveSoon();
            } else {
                cfg.minimapX = Math.round(Math.max(r, Math.min(sw - r, Input.mouseX - grabDX)));
                cfg.minimapY = Math.round(Math.max(r, Math.min(sh - r, Input.mouseY - grabDY)));
            }
        }
        if (sizing) {
            if (!Input.leftDown) {
                sizing = false;
                OverlayMod.saveSoon();
            } else {
                // The rim follows the mouse: size = 2 x distance from the centre.
                var d = Math.sqrt(mx * mx + my * my);
                cfg.minimapSize = Std.int(Math.max(120, Math.min(Math.min(500, Math.min(sw, sh) - 40), d * 2)));
                if (cfg.minimapX < 0) {
                    // Pin the default spot so growing does not slide it.
                    cfg.minimapX = Math.round(mini.screenX);
                    cfg.minimapY = Math.round(mini.screenY);
                }
            }
        }
    }

    function nearest(list:Array<{p:Poi, x:Float, y:Float}>):{p:Poi, x:Float, y:Float} {
        var best = null, bd = 10.0 * 10.0;
        for (m in list) {
            var d = (m.x - Input.mouseX) * (m.x - Input.mouseX) + (m.y - Input.mouseY) * (m.y - Input.mouseY);
            if (d < bd) {
                bd = d;
                best = m;
            }
        }
        return best;
    }

    public function toggleBig():Void {
        bigOpen = !bigOpen;
        panX = panY = 0;
        dragging = false;
        if (!bigOpen) big.block(false) else big.block(true);
    }

    public function hideAll():Void {
        mini.show(false);
        big.show(false);
        tip.hide();
    }
}

/** Filter checkboxes on the large map; saved to the config. */
class Legend {
    var g:Dynamic;
    var labels:Array<Gfx.Label> = [];
    var x = 0.0;
    var y = 0.0;
    static inline var ROW = 22.0;
    static inline var W = 170.0;
    var key = "";

    public function new(parent:Dynamic) {
        g = Gfx.graphics(parent);
        for (k in Pois.KINDS) labels.push(Gfx.text(parent, 0xEDE9FE));
    }

    public function contains(lx:Float, ly:Float):Bool return lx >= x && lx < x + W && ly >= y && ly < y + ROW * Pois.KINDS.length + 8;

    /** Returns true when a filter changed. */
    public function update(cfg:Dynamic, x:Float, y:Float, mx:Float, my:Float, click:Bool):Bool {
        this.x = x + 8;
        this.y = y;
        var changed = false;
        var filters:Dynamic = cfg.filters;
        if (click && contains(mx, my)) {
            var i = Std.int((my - this.y - 4) / ROW);
            if (i >= 0 && i < Pois.KINDS.length) {
                var k = Pois.KINDS[i];
                var v:Dynamic = Reflect.field(filters, k.kind);
                var on = v == null ? k.onByDefault : v == true;
                Reflect.setField(filters, k.kind, !on);
                changed = true;
            }
        }
        var sb = new StringBuf();
        for (k in Pois.KINDS) {
            var v:Dynamic = Reflect.field(filters, k.kind);
            sb.add((v == null ? k.onByDefault : v == true) ? "1" : "0");
        }
        var nk = sb.toString() + this.x + "," + this.y;
        if (nk != key) {
            key = nk;
            Gfx.clear(g);
            Gfx.fill(g, 0x0F0B1A, 0.85);
            Gfx.rect(g, this.x, this.y, W, ROW * Pois.KINDS.length + 8);
            Gfx.endFill(g);
            for (i in 0...Pois.KINDS.length) {
                var k = Pois.KINDS[i];
                var on = nk.charAt(i) == "1";
                var ry = this.y + 4 + i * ROW;
                Gfx.line(g, 1, 0xA78BFA, 1);
                Gfx.fill(g, on ? 0x7C3AED : 0x1E1B2E, 1);
                Gfx.rect(g, this.x + 6, ry + 4, 13, 13);
                Gfx.endFill(g);
                Gfx.noLine(g);
                MapView.drawKind(g, k.kind, this.x + 32, ry + 10.5, 5, !on);
                labels[i].set(k.label).color(on ? 0xEDE9FE : 0x8C849E).size(14).at(this.x + 44, ry + 2);
            }
        }
        return changed;
    }
}

/** A small dark box with text, above everything else of the mod. */
class Tooltip {
    var g:Dynamic;
    var label:Gfx.Label;
    var root:Dynamic;
    var lastText = "";

    public function new(parent:Dynamic) {
        root = Gfx.obj(parent);
        g = Gfx.graphics(root);
        label = Gfx.text(root, 0xFFFFFF);
        Gfx.visible(root, false);
    }

    public function dispose() Gfx.remove(root);

    public function show(text:String, x:Float, y:Float, sw:Float, sh:Float):Void {
        Gfx.visible(root, true);
        if (label == null) return;
        if (text != lastText) {
            lastText = text;
            label.set(text).size(14).at(8, 5);
            var w = label.width() + 16;
            var lines = text.split("\n").length;
            Gfx.clear(g);
            Gfx.line(g, 1, 0xA78BFA, 1);
            Gfx.fill(g, 0x140F24, 0.94);
            Gfx.rect(g, 0, 0, w, lines * 17 + 10);
            Gfx.endFill(g);
            Gfx.noLine(g);
            tw = w;
            th = lines * 17 + 10;
        }
        Gfx.pos(root, Math.min(x, sw - tw - 4), Math.min(y, sh - th - 4));
    }

    var tw = 0.0;
    var th = 0.0;

    public function hide():Void Gfx.visible(root, false);
}
