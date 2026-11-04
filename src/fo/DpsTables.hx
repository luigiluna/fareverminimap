package fo;

import fo.logic.Build;
import fo.logic.CombatTracker;
import fo.logic.GameNames;

/**
 * The tables of the DPS meter, laid out like the C++ overlay's: skills
 * (icon, Hits, Casts, P/M/R, Total, Max, Crit%, DPS, %) and players
 * (arrow, class, name, Lv, weapons, DPS bar in the class color, Total, %).
 */
class DpsTables {
    public static inline var HEADER_BG = 0x2A1E48;
    public static inline var ROW_A = 0x0B0812;
    public static inline var ROW_B = 0x14101E;
    public static inline var SELF = 0xE8985C;
    public static inline var GROUP = 0x78DC8C;

    public static function fmt(v:Float):String {
        if (v >= 1e6) return (Math.round(v / 1e5) / 10) + "M";
        if (v >= 1e4) return (Math.round(v / 100) / 10) + "k";
        return Std.string(Math.round(v));
    }

    public static function one(v:Float):String {
        var r = Math.round(v * 10) / 10;
        var s = Std.string(r);
        return s.indexOf(".") < 0 ? s + ".0" : s;
    }

    public static function skillName(id:String):String {
        if (GameNames.hasSkill(id)) return GameNames.skill(id);
        var n = DpsCapture.skillNames.get(id);
        return n != null && n != "" && n != id ? n : GameNames.humanize(id, "");
    }

    public static function classColor(cls:String):Int {
        return switch (cls) {
            case "Warrior": 0xE68C59;
            case "Mage": 0x73B8FA;
            case "Priest": 0xFAE68C;
            case "Rogue": 0x8CE080;
            default: 0xBFBFBF;
        }
    }

    public static function rankColor(r:TargetRank):Int {
        return switch (r) {
            case Boss: 0xFFC444;
            case Miniboss: 0xFFA94D;
            case Elite: 0xC79EFF;
            default: Panel.TEXT;
        }
    }

    /** "Phys 57%  Magic 27%  Raw 16%" in the type colors; returns the x after it. */
    public static function typeSummary(p:Panel, x:Float, y:Float, ph:Float, mg:Float, rw:Float, total:Float):Float {
        if (total <= 0.001 || ph + mg + rw <= 0.001) {
            p.text(x, y, "Phys/Magic/Raw: n/a", Panel.DIM, 13);
            return x + 130;
        }
        p.text(x, y, "Phys " + Math.round(ph * 100 / total) + "%", Panel.PHYS, 13);
        p.text(x + 70, y, "Magic " + Math.round(mg * 100 / total) + "%", Panel.MAGIC, 13);
        p.text(x + 148, y, "Raw " + Math.round(rw * 100 / total) + "%", Panel.RAW, 13);
        return x + 210;
    }

    static function header(p:Panel, x:Float, y:Float, w:Float, cols:Array<{x:Float, t:String}>):Void {
        p.box(x, y, w, 20, HEADER_BG, 0.94);
        for (c in cols) p.text(c.x, y + 2, c.t, Panel.TEXT, 13);
    }

    /**
     * Skill rows. Returns the height used. `scroll` rows are skipped; at most `maxRows` drawn.
     */
    public static function skills(p:Panel, x:Float, y:Float, w:Float, rows:Array<SkillRow>, total:Float, elapsed:Float, maxRows:Int,
            scroll:Int, rate = "DPS"):Float {
        var c = [x + 4, x + w * 0.34, x + w * 0.43, x + w * 0.52, x + w * 0.64, x + w * 0.74, x + w * 0.83, x + w * 0.90, x + w * 0.965];
        header(p, x, y, w, [
            {x: c[0], t: "Skill"}, {x: c[1], t: "Hits"}, {x: c[2], t: "Casts"}, {x: c[3], t: "P/M/R"}, {x: c[4], t: "Total"},
            {x: c[5], t: "Max"}, {x: c[6], t: "Crit%"}, {x: c[7], t: rate}, {x: c[8] - 6, t: "%"}
        ]);
        var rh = 24.0;
        var yy = y + 20;
        if (rows.length == 0) {
            p.text(x + 6, yy + 4, "no damage yet", Panel.DIM, 13);
            return 20 + rh;
        }
        var n = Std.int(Math.min(maxRows, rows.length - scroll));
        for (i in 0...n) {
            var r = rows[i + scroll];
            p.box(x, yy, w, rh, (i % 2 == 0) ? ROW_A : ROW_B, 0.7);
            var name = skillName(r.skill);
            var icon = DpsCapture.skillIcons.get(r.skill);
            var tx = c[0];
            if (icon != null) {
                p.tileIcon(c[0], yy + 1, 22, icon);
                tx += 27;
            }
            var maxChars = Std.int((c[1] - tx) / 7.2);
            p.text(tx, yy + 4, name.length > maxChars ? name.substr(0, maxChars - 1) + "." : name, Panel.TEXT, 13);
            p.tip(x, yy, c[1] - x, rh, name + "\n" + r.skill);
            p.text(c[1], yy + 4, Std.string(r.hitCount), Panel.TEXT, 13);
            p.text(c[2], yy + 4, r.castCount > 0 ? Std.string(r.castCount) : "-", r.castCount > 0 ? Panel.TEXT : Panel.DIM, 13);
            var known = r.physical + r.magic + r.raw;
            if (r.total > 0 && known > 0) {
                p.typeBar(c[3], yy + 8, c[4] - c[3] - 10, 8, r.total, r.physical, r.magic, r.raw);
                p.tip(c[3], yy, c[4] - c[3], rh, "Physical " + Math.round(r.physical * 100 / r.total) + "%  Magic " + Math.round(r.magic * 100 / r.total)
                    + "%  Raw " + Math.round(r.raw * 100 / r.total) + "%");
            } else p.text(c[3], yy + 4, "-", Panel.DIM, 13);
            p.text(c[4], yy + 4, Std.string(Math.round(r.total)), Panel.TEXT, 13);
            p.text(c[5], yy + 4, Std.string(Math.round(r.maxHit)), Panel.TEXT, 13);
            var crit = r.hitCount > 0 ? 100.0 * r.critCount / r.hitCount : 0;
            p.text(c[6], yy + 4, crit > 0 ? Math.round(crit) + "%" : "-", crit > 0 ? Panel.ACCENT : Panel.DIM, 13);
            p.text(c[7], yy + 4, elapsed > 0.001 ? one(r.total / elapsed) : "-", Panel.TEXT, 13);
            p.text(c[8] - 6, yy + 4, (total > 0.001 ? Math.round(r.total * 100 / total) : 0) + "%", Panel.TEXT, 13);
            yy += rh;
        }
        return 20 + n * rh;
    }

    public static function pct(a:Float, b:Float):String return b > 0 ? Math.round(a * 100 / b) + "%" : "-";

    public static function secs(v:Float):String {
        var s = Math.round(v * 10) / 10;
        if (s >= 60) {
            var m = Std.int(s / 60);
            var r = Std.int(s - m * 60);
            return m + ":" + (r < 10 ? "0" : "") + r;
        }
        return s + "s";
    }

    /**
     * The fight's own damage over time: one bar per bucket, the average DPS as
     * a line, deaths as red ticks. Hover shows the DPS of a stretch.
     */
    public static function timeline(p:Panel, x:Float, y:Float, w:Float, h:Float, values:Array<Float>, bucketSec:Float, avgDps:Float,
            deaths:Array<fo.logic.Deaths.DeathRecap>):Void {
        p.box(x, y, w, h, 0x0B0812, 0.8);
        var n = values.length;
        if (n == 0) return;
        var top = 1.0;
        for (v in values) if (v > top) top = v;
        var avg = avgDps * bucketSec;
        if (avg > top) top = avg;
        var bw = w / n;
        for (i in 0...n) {
            var bh = (h - 4) * values[i] / top;
            p.box(x + i * bw, y + h - bh, Math.max(1, bw - (bw > 3 ? 1 : 0)), bh, 0x7C3AED, 0.9);
        }
        var ay = y + h - (h - 4) * avg / top;
        p.box(x, ay, w, 1, 0xFACC15, 0.8);
        p.text(x + 4, y + 2, "DPS over time", Panel.DIM, 11);
        p.text(x, y + 2, "avg " + fmt(avgDps), 0xFACC15, 11, w - 4);
        // Hover: about 40 stretches across the width.
        var group = Std.int(Math.max(1, Math.ceil(n / 40)));
        var i = 0;
        while (i < n) {
            var sum = 0.0, k = 0;
            while (k < group && i + k < n) sum += values[i + k++];
            var from = i * bucketSec, to = (i + k) * bucketSec;
            p.tip(x + i * bw, y, k * bw, h, fo.logic.Deaths.DeathTracker.clock(from) + " - " + fo.logic.Deaths.DeathTracker.clock(to) + "   DPS "
                + fmt(sum / (k * bucketSec)) + "\naverage " + fmt(avgDps));
            i += k;
        }
        var span = n * bucketSec;
        for (d in deaths) {
            if (d.atSec < 0) continue;
            var dx = x + w * Math.min(1, d.atSec / span);
            p.box(dx - 1, y, 2, h, 0xFF5050, 0.95);
            p.tip(dx - 4, y, 8, h, fo.logic.Deaths.DeathTracker.describe(d, skillName));
        }
    }

    public static inline var HEAD = 0xA78BFA;
    public static inline var CELL = 0xD6CCF5;

    /**
     * Skill rows in the first hlx window's look: a bar behind each row scaled
     * to the top skill, with a thin type bar under it. Adds the skill icon,
     * the Max column and tooltips. Returns the height used.
     */
    public static function skillsClassic(p:Panel, x:Float, y:Float, w:Float, rows:Array<SkillRow>, total:Float, elapsed:Float, maxRows:Int,
            scroll:Int, row = 22.0, rate = "DPS"):Float {
        var c = [x, x + w * 0.40, x + w * 0.52, x + w * 0.59, x + w * 0.68, x + w * 0.77, x + w * 0.85, x + w * 0.925];
        var heads = ["Skill", rate == "HPS" ? "Healed" : (rate == "SPS" ? "Absorbed" : "Damage"), "%", rate, "Max", "Hits", "Crit", "Casts"];
        for (i in 0...heads.length) p.text(c[i] + (i == 0 ? 2 : 0), y, heads[i], HEAD, 13);
        if (rows.length == 0) {
            p.text(x, y + row, "No damage yet. Hit something.", Panel.DIM, 13);
            return row * 2;
        }
        var top = rows[0].total > 0 ? rows[0].total : 1;
        var n = Std.int(Math.max(0, Math.min(maxRows, rows.length - scroll)));
        for (i in 0...n) {
            var r = rows[i + scroll];
            var ry = y + row * (i + 1);
            var bw = w * r.total / top;
            p.box(x, ry + 1, bw, row - 2, 0x2A2140, 0.9);
            p.typeBar(x, ry + row - 4, bw, 3, r.total, r.physical, r.magic, r.raw);
            var name = skillName(r.skill);
            var tx = x + 2;
            var icon = DpsCapture.skillIcons.get(r.skill);
            if (icon != null) {
                p.tileIcon(tx, ry + 1, row - 6, icon);
                tx += row - 2;
            }
            var maxChars = Std.int((c[1] - tx - 6) / 7.2);
            p.text(tx, ry + 1, name.length > maxChars ? name.substr(0, maxChars - 1) + "." : name, 0xFFFFFF, 13);
            p.tip(x, ry, c[1] - x, row, name + (name != r.skill ? "\n" + r.skill : ""));
            p.text(c[1], ry + 1, fmt(r.total), Panel.TEXT, 13);
            var known = r.physical + r.magic + r.raw;
            if (r.total > 0 && known > 0)
                p.tip(c[1], ry, c[2] - c[1], row, Math.round(r.total) + "\nPhysical " + pct(r.physical, r.total) + "  Magic " + pct(r.magic, r.total)
                    + "  Raw " + pct(r.raw, r.total));
            p.text(c[2], ry + 1, pct(r.total, total), CELL, 13);
            p.text(c[3], ry + 1, elapsed > 0.001 ? fmt(r.total / elapsed) : "-", CELL, 13);
            p.text(c[4], ry + 1, fmt(r.maxHit), CELL, 13);
            p.tip(c[4], ry, c[5] - c[4], row, "Biggest hit: " + Math.round(r.maxHit));
            p.text(c[5], ry + 1, Std.string(r.hitCount), CELL, 13);
            p.text(c[6], ry + 1, pct(r.critCount, r.hitCount), r.critCount > 0 ? Panel.ACCENT : CELL, 13);
            p.text(c[7], ry + 1, r.castCount > 0 ? Std.string(r.castCount) : "-", CELL, 13);
        }
        return row * (n + 1);
    }

    /**
     * Player rows (live or of a fight). `expanded` is the open player's uid.
     * Returns the height used.
     */
    public static function players(p:Panel, x:Float, y:Float, w:Float, rows:Array<PlayerRow>, inGroup:Float->Bool, expanded:Float,
            onToggle:Float->Void, onBuild:PlayerRow->Void, maxRows:Int, scroll:Int):Float {
        var c = [x + 4, x + w * 0.42, x + w * 0.56, x + w * 0.84, x + w * 0.94];
        header(p, x, y, w, [{x: c[0] + 14, t: "Player"}, {x: c[1], t: "Weapons"}, {x: c[2], t: "DPS"}, {x: c[3], t: "Total"}, {x: c[4], t: "%"}]);
        var total = 0.0, topDps = 0.0;
        for (r in rows) {
            total += r.total;
            if (r.dps > topDps) topDps = r.dps;
        }
        // Flatten: player row, then (when open) a build line and the skill lines.
        var lines:Array<{r:PlayerRow, kind:Int, s:PlayerSkillRow}> = [];
        for (r in rows) {
            lines.push({r: r, kind: 0, s: null});
            if (r.uid == expanded) {
                lines.push({r: r, kind: 1, s: null});
                for (s in r.skills) lines.push({r: r, kind: 2, s: s});
            }
        }
        var yy = y + 20;
        var n = Std.int(Math.min(maxRows, lines.length - scroll));
        for (i in 0...n) {
            var l = lines[i + scroll];
            var r = l.r;
            var grp = inGroup(r.uid) || r.inGroup;
            var ccol = classColor(r.className);
            switch (l.kind) {
                case 0:
                    var rh = 26.0;
                    p.box(x, yy, w, rh, (i % 2 == 0) ? ROW_A : ROW_B, 0.7);
                    p.arrow(c[0], yy + 9, r.uid == expanded);
                    var nx = c[0] + 13;
                    var cls = GameNames.classCell(r.className);
                    if (cls >= 0) {
                        p.icon(nx, yy + 3, 20, cls, 0x2A1E48);
                        nx += 24;
                    }
                    var name = r.name.length > 16 ? r.name.substr(0, 15) + "." : r.name;
                    p.text(nx, yy + 5, name, r.isSelf ? SELF : (grp ? GROUP : Panel.TEXT), 13);
                    if (r.level > 0) p.text(nx + name.length * 7.4 + 6, yy + 6, "Lv" + r.level, Panel.DIM, 12);
                    for (k in 0...r.weapons.length) {
                        var it = r.weapons[k];
                        var ix = c[1] + k * 25;
                        p.icon(ix, yy + 2, 22, it.icon, it.rarity.color());
                        p.tip(ix, yy, 24, rh, itemTip(it));
                    }
                    // DPS bar in the class color, scaled to the top player.
                    var bw = (c[3] - c[2] - 10) * (topDps > 0 ? r.dps / topDps : 0);
                    p.box(c[2], yy + 4, bw, rh - 8, ccol, 0.66);
                    p.text(c[2] + 4, yy + 5, Std.string(Math.round(r.dps)), 0xFFFFFF, 13);
                    p.text(c[3], yy + 5, fmt(r.total), Panel.TEXT, 13);
                    p.text(c[4], yy + 5, (total > 0.001 ? Math.round(r.total * 100 / total) : 0) + "%", Panel.DIM, 13);
                    p.tip(x, yy, c[1] - x, rh, playerTip(r, grp));
                    var uid = r.uid;
                    p.click(x, yy, c[1] - x, rh, () -> onToggle(uid));
                    p.click(c[2], yy, w - (c[2] - x), rh, () -> onToggle(uid));
                    yy += rh;
                case 1:
                    var rh = 22.0;
                    p.box(x, yy, w, rh, ROW_B, 0.7);
                    if (r.build != null) p.button(c[0] + 13, yy + 2, 52, "Build", false, () -> onBuild(r));
                    else p.text(c[0] + 13, yy + 4, "no build read", Panel.DIM, 12);
                    p.text(c[1], yy + 4, r.hitCount + " hits", Panel.DIM, 12);
                    p.typeBar(c[2], yy + 8, c[3] - c[2] - 10, 7, r.total, r.physical, r.magic, r.raw);
                    p.text(c[3], yy + 4, (r.hitCount > 0 ? Math.round(r.critCount * 100 / r.hitCount) : 0) + "% crit", Panel.DIM, 12);
                    yy += rh;
                case _:
                    var s = l.s;
                    var rh = 22.0;
                    p.box(x, yy, w, rh, ROW_A, 0.5);
                    var share = r.total > 0.001 ? s.total / r.total : 0;
                    var sx = c[0] + 13;
                    var icon = DpsCapture.skillIcons.get(s.skill);
                    if (icon != null) {
                        p.tileIcon(sx, yy + 2, 18, icon);
                        sx += 23;
                    }
                    var nm = skillName(s.skill);
                    var maxChars = Std.int((c[2] - sx - 6) / 6.8);
                    p.text(sx, yy + 4, nm.length > maxChars ? nm.substr(0, maxChars - 1) + "." : nm, Panel.DIM, 12);
                    p.tip(x, yy, c[2] - x, rh, nm + "\n" + s.hitCount + " hits  " + (s.hitCount > 0 ? Math.round(s.critCount * 100 / s.hitCount) : 0)
                        + "% crit");
                    p.box(c[2], yy + 4, (c[3] - c[2] - 10) * share, rh - 8, ccol, 0.35);
                    p.text(c[2] + 4, yy + 4, Std.string(Math.round(r.activeSec > 0.001 ? s.total / r.activeSec : 0)), Panel.DIM, 12);
                    p.text(c[3], yy + 4, fmt(s.total), Panel.DIM, 12);
                    p.text(c[4], yy + 4, Math.round(share * 100) + "%", Panel.DIM, 12);
                    yy += rh;
            }
        }
        if (rows.length == 0) {
            p.text(x + 6, yy + 4, "no player damage seen yet", Panel.DIM, 13);
            yy += 24;
        }
        return yy - y;
    }

    public static function itemTip(it:BuildItem):String {
        var s = it.name + (it.level > 0 ? "  Lv" + it.level : "") + (it.upgrade > 0 ? " +" + it.upgrade : "");
        var r = it.rarity.name();
        if (r != "") s += "\n" + r + "  " + PlayerBuild.slotName(it.slot);
        if (it.infusion != "") s += "\nInfusion: " + it.infusion + (it.bonus != "" ? " (" + it.bonus + ")" : "");
        for (a in it.augments) s += "\n" + a;
        return s;
    }

    public static function playerTip(r:PlayerRow, grp:Bool):String {
        var s = r.name + (r.isSelf ? "  (you)" : (grp ? "  (in your group)" : ""));
        if (r.className != "") {
            s += "\n" + r.className + (r.level > 0 ? "  Lv" + r.level : "");
            for (w in r.weapons) s += "\n" + PlayerBuild.slotName(w.slot) + ": " + w.name + (w.upgrade > 0 ? " +" + w.upgrade : "");
            if (r.talentsRead) s += "\n" + r.talentPoints + " talent points";
        }
        var t = r.total > 0 ? r.total : 1;
        s += "\n" + r.hitCount + " hits  " + (r.hitCount > 0 ? Math.round(r.critCount * 100 / r.hitCount) : 0) + "% crit  max " + Math.round(r.maxHit);
        s += "\nPhys " + Math.round(r.physical * 100 / t) + "%  Magic " + Math.round(r.magic * 100 / t) + "%  Raw " + Math.round(r.raw * 100 / t) + "%";
        s += "\nClick for skills";
        return s;
    }
}
