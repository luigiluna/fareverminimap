package fo;

import fo.logic.Build;
import fo.logic.CombatTracker;
import fo.logic.Deaths;
import fo.logic.Records;

/** One past fight, like the C++ overlay's fight detail window: targets, weapons, DMG / PLAYERS tables. */
class FightWindow {
    var p:Panel;
    var meter:Meter;
    public var fight:FightLogEntry = null;
    /** 0 DMG, 1 PLAYERS, 2 DEATHS. */
    var view = 0;
    var expanded = -1.0;
    var dirty = true;
    var scroll = 0;
    public var onBuild:PlayerBuild->String->Void;
    public var onClose:Void->Void;

    static inline var W = 640.0;

    public function new(parent:Dynamic, meter:Meter, x:Float, y:Float) {
        this.meter = meter;
        p = new Panel(parent);
        p.x = x;
        p.y = y;
        p.show(false);
    }

    public function dispose() p.dispose();

    public function open(f:FightLogEntry):Void {
        if (f == null) {
            close();
            return;
        }
        fight = f;
        scroll = 0;
        expanded = -1;
        view = 0;
        dirty = true;
        p.show(true);
    }

    public function close():Void {
        fight = null;
        p.show(false);
        if (onClose != null) onClose();
    }

    public var isOpen(get, never):Bool;
    inline function get_isOpen() return fight != null;

    public function contains(mx:Float, my:Float) return fight != null && p.contains(mx, my);

    public function hoveredTip() return fight == null ? null : p.hoveredTip();

    public function update(sw:Float, sh:Float):Void {
        if (fight == null) return;
        var over = p.input(sw, sh);
        if (over && Input.wheel != 0) {
            scroll = Std.int(Math.max(0, scroll - Input.wheel * 2));
            dirty = true;
        }
        if (over && Input.leftPressed) dirty = true;
        // A click on "x" closes the window inside p.input: nothing left to draw.
        if (fight == null || !dirty) return;
        dirty = false;
        draw();
    }

    static inline var GRAPH_H = 56.0;

    function setView(v:Int) {
        view = v;
        scroll = 0;
        dirty = true;
    }

    function deathLines(f:FightLogEntry):Int {
        var n = 0;
        for (d in f.deaths) n += 1 + d.hits.length;
        return n;
    }

    function draw():Void {
        var f = fight;
        if (f == null) return;
        if (view == 2 && f.deaths.length == 0) view = 0;
        var graph = f.timeline.length > 1;
        var rowsH = switch (view) {
            case 1: 20 + 26 * Math.min(10, Math.max(1, f.players.length)) + 60;
            case 2: 18 * Math.min(14, deathLines(f)) + 8;
            default: 22 * (Math.min(10, Math.max(1, f.rows.length)) + 1);
        }
        var h = 26 + 20 * 5 + (graph ? GRAPH_H + 10 : 0) + 26 + rowsH + 12;
        p.begin(W, h);
        var title = "Fight #" + f.id + "  " + CombatTracker.targetLabel(f);
        p.text(8, 4, title.length > 62 ? title.substr(0, 61) + "." : title, 0xFFFFFF, 14);
        if (f.newRecord) {
            p.text(W - 120, 5, "NEW RECORD", 0xFACC15, 13);
            p.tip(W - 120, 4, 86, 18, "Best boss DPS on " + bossName(f) + " (" + (f.group ? "group" : "solo") + ") when it was set");
        }
        p.button(W - 26, 4, 20, "x", false, close);
        var y = 30.0;
        var d = Date.fromTime(f.endedUnixMs);
        p.text(8, y, (f.endedUnixMs > 0 ? DateTools.format(d, "%H:%M:%S") + "   " : "") + DpsTables.secs(f.durationSec) + "   total "
            + DpsTables.fmt(f.totalDamage), Panel.TEXT, 13);
        p.text(230, y - 2, "DPS " + DpsTables.fmt(f.dps), 0xFFFFFF, 16);
        p.text(340, y, f.hitCount + " hits   " + f.castCount + " casts", Panel.DIM, 13);
        var sup = (f.totalHeal > 0 ? "HPS " + DpsTables.fmt(f.hps) + "  " : "") + (f.totalShield > 0 ? "SPS " + DpsTables.fmt(f.sps) : "");
        if (sup != "") p.text(8, y, sup, 0x86EFAC, 13, W - 16);
        y += 20;
        DpsTables.typeSummary(p, 8, y, f.totalPhysical, f.totalMagic, f.totalRaw, f.totalDamage);
        p.text(8, y, f.group ? "Group fight" : "Solo fight", Panel.DIM, 12, W - 16);
        p.tip(W - 100, y, 92, 18, "Group: in a party with someone, or other players did at least 10% of the damage.\nRecords are kept apart for solo and group.");
        y += 20;
        // Boss vs adds, and the record for this boss in the same mode.
        var boss = Records.bossOf(f);
        if (boss != null) {
            var bd = Records.bossDamage(f), sec = Math.max(0.001, f.durationSec);
            p.text(8, y, "Boss " + DpsTables.fmt(bd / sec) + " DPS", 0xFACC15, 13);
            p.text(110, y, "Adds " + DpsTables.fmt((f.totalDamage - bd) / sec) + " DPS", Panel.TEXT, 13);
            p.tip(8, y, 200, 18, "DPS on " + boss.name + " and other bosses / minibosses, and on everything else.");
            var pb = meter.records.best(boss.name, f.group);
            if (pb != null) {
                var mine = bd / sec;
                var diff = pb.dps > 0 ? Math.round((mine - pb.dps) * 100 / pb.dps) : 0;
                var txt = f.newRecord ? "record (" + (f.group ? "group" : "solo") + ")" : "PB " + DpsTables.fmt(pb.dps) + " (" + (diff >= 0 ? "+" : "") + diff + "%)";
                p.text(230, y, txt, f.newRecord || diff >= 0 ? 0x86EFAC : 0xFCA5A5, 13);
                p.tip(230, y, 160, 18, recordTip(pb, f.group));
            }
        } else p.text(8, y, "No boss in this fight", Panel.DIM, 12);
        y += 20;
        var ts = [for (t in f.targets) t.name + " " + DpsTables.fmt(t.total) + (t.kills > 0 ? " (" + t.kills + " kill" + (t.kills > 1 ? "s" : "") + ")" : "")];
        var tl = ts.length > 0 ? "Targets: " + ts.join(", ") : "Targets: -";
        p.text(8, y, tl.length > 90 ? tl.substr(0, 89) + "." : tl, Panel.DIM, 12);
        y += 20;
        var wl = f.loadout.hand != "" ? "Weapons: " + f.loadout.hand + (f.loadout.handLevel > 0 ? " Lv" + f.loadout.handLevel : "")
            + (f.loadout.handUpgrade > 0 ? " +" + f.loadout.handUpgrade : "") + (f.loadout.second != "" ? " / " + f.loadout.second : "")
            + (f.loadout.off != "" ? " / " + f.loadout.off : "") : "Weapons: -";
        p.text(8, y, wl, Panel.DIM, 12);
        y += 22;
        if (graph) {
            DpsTables.timeline(p, 8, y, W - 16, GRAPH_H, f.timeline, f.timelineSec, f.dps, f.deaths);
            y += GRAPH_H + 10;
        }
        p.button(8, y, 44, "DMG", view == 0, () -> setView(0));
        p.button(56, y, 72, "PLAYERS", view == 1, () -> setView(1));
        if (f.deaths.length > 0) {
            p.button(132, y, 84, "DEATHS " + f.deaths.length, view == 2, () -> setView(2));
            p.tip(132, y, 84, 18, "Who died in this fight and the last hits they took");
        }
        if (f.imported) p.text(228, y + 1, "from the C++ overlay", Panel.DIM, 12);
        y += 26;
        switch (view) {
            case 1:
                if (f.players.length == 0) {
                    p.text(8, y, "No players were recorded for this fight.", Panel.DIM, 13);
                } else {
                    p.text(8, y, f.playerCount + " players   total " + Math.round(f.playersTotal), Panel.DIM, 13);
                    DpsTables.players(p, 6, y + 20, W - 12, f.players, meter.inGroup, expanded, (uid) -> {
                        expanded = expanded == uid ? -1 : uid;
                        dirty = true;
                    }, (r) -> if (onBuild != null && r.build != null) onBuild(r.build, "as read during fight #" + f.id), 12, scroll);
                }
            case 2:
                drawDeaths(f, y);
            default:
                if (scroll > Math.max(0, f.rows.length - 10)) scroll = Std.int(Math.max(0, f.rows.length - 10));
                DpsTables.skillsClassic(p, 8, y, W - 16, f.rows, f.totalDamage, f.durationSec, 10, scroll);
        }
        p.end();
    }

    static function bossName(f:FightLogEntry):String {
        var b = Records.bossOf(f);
        return b == null ? "?" : b.name;
    }

    public static function recordTip(r:fo.logic.Records.BossRecord, group:Bool):String {
        var d = Date.fromTime(r.endedUnixMs);
        return "Best " + (group ? "group" : "solo") + " boss DPS on " + r.boss + ": " + Math.round(r.dps) + "\n" + DpsTables.secs(r.durationSec)
            + (r.weapon != "" ? ", " + r.weapon : "") + (r.endedUnixMs > 0 ? ", " + DateTools.format(d, "%d/%m %H:%M") : "")
            + "\nBoss DPS = damage on bosses / fight time (adds do not count)";
    }

    /** Each death: a line with who and the killer, then the hits taken, newest first. */
    function drawDeaths(f:FightLogEntry, y:Float):Void {
        var lines:Array<{d:DeathRecap, h:TakenHit}> = [];
        for (d in f.deaths) {
            lines.push({d: d, h: null});
            for (h in d.hits) lines.push({d: d, h: h});
        }
        if (scroll > Math.max(0, lines.length - 14)) scroll = Std.int(Math.max(0, lines.length - 14));
        for (i in 0...Std.int(Math.min(14, lines.length - scroll))) {
            var l = lines[i + scroll];
            var ry = y + i * 18;
            if (l.h == null) {
                var d = l.d;
                var who = d.name + (d.isSelf ? " (you)" : "");
                p.box(8, ry, W - 16, 18, 0x3A1420, 0.8);
                p.text(12, ry + 1, who + " died" + (d.atSec >= 0 ? " at " + DeathTracker.clock(d.atSec) : ""), 0xFCA5A5, 13);
                if (d.hits.length > 0) {
                    var k = d.hits[0];
                    p.text(250, ry + 1, "killed by " + (k.source != "" ? k.source : DpsTables.skillName(k.skill)), Panel.TEXT, 13);
                    p.text(8, ry + 1, Math.round(d.total()) + " dmg in the last " + d.hits.length + " hits", Panel.DIM, 12, W - 20);
                } else p.text(250, ry + 1, "no hits seen before it", Panel.DIM, 12);
            } else {
                var h = l.h;
                p.text(28, ry + 1, "-" + h.agoSec + "s", Panel.DIM, 12);
                var nm = h.skill != "" ? DpsTables.skillName(h.skill) : "?";
                p.text(80, ry + 1, nm + (h.source != "" ? "  (" + h.source + ")" : ""), Panel.TEXT, 12);
                p.text(8, ry + 1, Math.round(h.amount) + (h.crit ? " crit" : ""), h.crit ? 0xFCA5A5 : DpsTables.CELL, 12, W - 20);
            }
        }
    }
}
