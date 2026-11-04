package fo;

import fo.logic.Build;
import fo.logic.GameNames;

/**
 * A player's gear and talents, laid out like the C++ overlay's Build window:
 * class (in its color) and level, then a table of the gear slots (36 px icon
 * with the rarity border, Slot, Item, Infusion, Gems / enchants), then the
 * talents, one line per branch.
 */
class BuildWindow {
    var p:Panel;
    public var build:PlayerBuild = null;
    public var subtitle = "";
    public var saved = false;
    var dirty = true;

    static inline var W = 640.0;
    static inline var ICON = 36.0;

    public function new(parent:Dynamic, x:Float, y:Float) {
        p = new Panel(parent);
        p.x = x;
        p.y = y;
        p.show(false);
    }

    public function dispose() p.dispose();

    public function open(b:PlayerBuild, sub:String):Void {
        build = b;
        subtitle = sub;
        saved = sub.indexOf("fight") >= 0;
        dirty = true;
        p.show(true);
    }

    public function close():Void {
        build = null;
        p.show(false);
    }

    public var isOpen(get, never):Bool;
    inline function get_isOpen() return build != null;

    public function contains(mx:Float, my:Float) return build != null && p.contains(mx, my);

    public function hoveredTip() return build == null ? null : p.hoveredTip();

    public function update(sw:Float, sh:Float):Void {
        if (build == null) return;
        if (p.input(sw, sh) && Input.leftPressed) dirty = true;
        // A click on "x" closes the window inside p.input: nothing left to draw.
        if (build == null || !dirty) return;
        dirty = false;
        draw();
    }

    static function rowHeight(it:BuildItem):Float return Math.max(ICON + 4, it.augments.length * 17 + 8);

    /** Talent lines: one per branch, "Name" or "Name xN". */
    static function talentLines(b:PlayerBuild):Array<String> {
        var out = [];
        var i = 0;
        while (i < b.talents.length) {
            var branch = b.talents[i].branch;
            var parts = [];
            while (i < b.talents.length && b.talents[i].branch == branch) {
                var t = b.talents[i];
                parts.push(t.rank > 1 ? t.name + " x" + t.rank : t.name);
                i++;
            }
            // Wrap at about 90 characters, like the overlay's TextWrapped.
            var line = "";
            for (part in parts) {
                var next = line == "" ? part : line + ",  " + part;
                if (next.length > 90 && line != "") {
                    out.push(line + ",");
                    line = part;
                } else line = next;
            }
            if (line != "") out.push(line);
        }
        return out;
    }

    function draw():Void {
        var b = build;
        var gearH = 0.0;
        for (g in b.gear) gearH += rowHeight(g);
        var lines = b.talentsRead ? talentLines(b) : [];
        var h = 26 + 24 + 20 + Math.max(24, gearH) + 10 + 20 + Math.max(1, lines.length) * 17 + 12;
        p.begin(W, h);

        // Title: the player's name, like the overlay's window title.
        p.text(8, 4, b.name, 0xFFFFFF, 14);
        p.button(W - 26, 4, 20, "x", false, close);

        var y = 30.0;
        var cls = GameNames.classCell(b.className);
        var tx = 8.0;
        if (cls >= 0) {
            p.icon(8, y - 1, 18, cls, 0x2A1E48);
            tx += 24;
        }
        p.text(tx, y, b.className != "" ? b.className : "?", DpsTables.classColor(b.className), 13);
        if (b.level > 0) p.text(tx + b.className.length * 8 + 8, y, "Lv" + b.level, Panel.TEXT, 13);
        p.text(tx + b.className.length * 8 + 60, y, saved ? "as worn in that fight" : subtitle, Panel.DIM, 12);
        y += 24;

        // Gear table.
        var x = 6.0, w = W - 12;
        var c = [x + 4, x + 4 + ICON + 8, x + w * 0.24, x + w * 0.56, x + w * 0.76];
        p.box(x, y, w, 20, DpsTables.HEADER_BG, 0.94);
        p.text(c[1], y + 2, "Slot", Panel.TEXT, 13);
        p.text(c[2], y + 2, "Item", Panel.TEXT, 13);
        p.text(c[3], y + 2, "Infusion", Panel.TEXT, 13);
        p.text(c[4], y + 2, "Gems / enchants", Panel.TEXT, 13);
        y += 20;
        if (b.gear.length == 0) {
            p.text(c[1], y + 4, "no gear read", Panel.DIM, 13);
            y += 24;
        }
        for (i in 0...b.gear.length) {
            var g = b.gear[i];
            var rh = rowHeight(g);
            p.box(x, y, w, rh, (i % 2 == 0) ? DpsTables.ROW_A : DpsTables.ROW_B, 0.7);
            var mid = y + rh / 2 - 8;
            p.icon(c[0], y + (rh - ICON) / 2, ICON, g.icon, g.rarity.color());
            p.tip(c[0], y, ICON + 4, rh, DpsTables.itemTip(g));
            p.text(c[1], mid, PlayerBuild.slotName(g.slot), Panel.DIM, 13);
            var name = g.name + (g.level > 0 ? " Lv" + g.level : "") + (g.upgrade > 0 ? " +" + g.upgrade : "");
            var maxItem = Std.int((c[3] - c[2] - 8) / 7.2);
            p.text(c[2], mid, name.length > maxItem ? name.substr(0, maxItem - 1) + "." : name, g.rarity.color(), 13);
            p.tip(c[2], y, c[3] - c[2], rh, DpsTables.itemTip(g));
            if (g.infusion != "") {
                var maxInf = Std.int((c[4] - c[3] - 6) / 7.0);
                p.text(c[3], mid, g.infusion.length > maxInf ? g.infusion.substr(0, maxInf - 1) + "." : g.infusion, Panel.TEXT, 13);
                if (g.bonus != "") p.tip(c[3], y, c[4] - c[3], rh, "+ " + g.bonus);
            }
            var ay = y + (rh - g.augments.length * 17) / 2;
            var maxAug = Std.int((x + w - c[4] - 4) / 6.8);
            for (a in g.augments) {
                p.text(c[4], ay, a.length > maxAug ? a.substr(0, maxAug - 1) + "." : a, Panel.TEXT, 12);
                ay += 17;
            }
            y += rh;
        }

        // Talents, by branch.
        y += 10;
        if (!b.talentsRead) {
            p.text(8, y, "Talents: not available", Panel.DIM, 13);
        } else {
            p.text(8, y, "Talents", Panel.TEXT, 13);
            var spent = b.talentPoints + b.unlistedPoints();
            var info = spent + (b.talentTotal > 0 ? " of " + b.talentTotal : "") + " points";
            if (b.talentFree > 0) info += "  (" + b.talentFree + " unspent)";
            p.text(64, y, info, Panel.DIM, 13);
            if (b.unlistedPoints() > 0)
                p.tip(64, y, 220, 18, b.unlistedPoints() + " point(s) are in talents missing from the name table:\nthey count here but are not listed below.");
            else if (b.talentTotal > 0)
                p.tip(64, y, 220, 18, "The total is what the level allows.");
            y += 20;
            for (l in lines) {
                p.text(8, y, l, Panel.TEXT, 12);
                y += 17;
            }
        }
        p.end();
    }
}
