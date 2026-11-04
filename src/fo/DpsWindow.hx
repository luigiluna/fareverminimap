package fo;

import fo.logic.Build;
import fo.logic.CombatTracker;
import fo.logic.Deaths;
import fo.logic.Records;

enum DpsTab {
    Dmg;
    Heal;
    Shield;
    Players;
    History;
}

/**
 * The DPS meter window, in the first hlx window's look:
 *   title bar "DPS Meter"
 *   [DMG] [HEAL] [SHIELD] [PLAYERS] [HISTORY]      Reset  [ ] Boss reset
 *   DMG: status, Time, big DPS, Total, Hits/Crit/Casts, type bar, skill table
 *   HEAL / SHIELD: the same for your heals and absorbs (HPS / SPS)
 *   PLAYERS: ALL / GROUP, class icon, weapons, DPS bar, skills, Build
 *   HISTORY: star, Ended, Target, Time, DPS, Damage; a row opens the fight window
 *   footer: keys and the type colors
 */
class DpsWindow {
    var p:Panel;
    var meter:Meter;
    public var tab = Dmg;
    var groupOnly = false;
    var expanded = -1.0;
    var lastRefresh = -1e9;
    var forceRefresh = true;
    var scroll = 0;
    /** HISTORY shows the records instead of the fights. */
    var showRecords = false;

    public var onBuild:PlayerBuild->String->Void;
    public var onFight:FightLogEntry->Void;
    public var selectedFight = -1;

    static inline var ROW = 22.0;
    static inline var TOP = 54.0; // below the title bar and the tab row
    static inline var FOOT = 26.0;
    static inline var MIN_W = 520.0;

    // Size: width from the grip, rows from the height (saved as dpsW / dpsH).
    var W = 560.0;
    var H = 150.0 + 12 * ROW;

    function layout(w:Float, h:Float):Void {
        W = Math.max(MIN_W, w);
        H = Math.max(150 + 4 * ROW, h);
    }

    /** Skill rows that fit under the summary. */
    var skillRows(get, never):Int;
    function get_skillRows() return Std.int(Math.max(3, (H - TOP - 46 - ROW - FOOT) / ROW));

    public function new(parent:Dynamic, meter:Meter, x:Float, y:Float) {
        this.meter = meter;
        p = new Panel(parent);
        p.x = x;
        p.y = y;
        p.resizable = true;
    }

    public function setSize(w:Float, h:Float):Void {
        if (w > 0 && h > 0) {
            layout(w, h);
            p.reqW = W;
            p.reqH = H;
        }
        forceRefresh = true;
    }

    /** Size to save after a resize; null when unchanged. */
    public function resizedTo():{w:Float, h:Float} {
        if (!p.resized) return null;
        p.resized = false;
        layout(p.reqW, p.reqH);
        return {w: W, h: H};
    }

    public function dispose() p.dispose();

    public function show(v:Bool) p.show(v);

    public var x(get, never):Float;
    inline function get_x() return p.x;
    public var y(get, never):Float;
    inline function get_y() return p.y;

    public function contains(mx:Float, my:Float) return p.contains(mx, my);

    public function hoveredTip() return p.hoveredTip();

    public function refresh() forceRefresh = true;

    public function moved():Bool {
        var m = p.moved;
        p.moved = false;
        return m;
    }

    public function update(cfg:Dynamic, now:Float, sw:Float, sh:Float):Void {
        var over = p.input(sw, sh);
        if (p.isResizing && p.reqW > 0) {
            layout(p.reqW, p.reqH);
            forceRefresh = true;
        }
        if (over && Input.wheel != 0) {
            scroll = Std.int(Math.max(0, scroll - Input.wheel * 2));
            forceRefresh = true;
        }
        if (Input.leftPressed && over) forceRefresh = true;
        // Text and boxes are rebuilt 4 times a second; the panel moves every frame.
        if (!forceRefresh && now - lastRefresh < (p.isResizing ? 33 : 250)) return;
        forceRefresh = false;
        lastRefresh = now;
        draw(cfg, now);
    }

    function setTab(t:DpsTab) {
        tab = t;
        scroll = 0;
        forceRefresh = true;
    }

    function draw(cfg:Dynamic, now:Float):Void {
        var s = meter.tracker.snap;
        p.resizable = !cfg.dpsCollapsed;
        if (cfg.dpsCollapsed) {
            // Minimized: only the title bar, with the live numbers.
            p.begin(320, 26);
            p.button(6, 4, 22, " +", false, () -> {
                cfg.dpsCollapsed = false;
                forceRefresh = true;
                OverlayMod.saveSoon();
            });
            p.tip(6, 4, 22, 18, "Restore the window");
            p.text(34, 4, "DPS " + DpsTables.fmt(s.dps) + "   " + DpsTables.fmt(s.totalDamage) + "   " + DpsTables.secs(s.elapsedSec),
                s.inCombat ? 0xFFFFFF : 0xC4B5FD, 14);
            p.button(320 - 30, 4, 24, " x", false, () -> {
                cfg.showDps = false;
                OverlayMod.saveSoon();
            });
            p.end();
            return;
        }

        p.begin(W, H);
        p.button(6, 4, 22, " -", false, () -> {
            cfg.dpsCollapsed = true;
            forceRefresh = true;
            OverlayMod.saveSoon();
        });
        p.tip(6, 4, 22, 18, "Minimize");
        p.text(34, 4, "DPS Meter", 0xFFFFFF, 15);
        p.button(W - 30, 4, 24, " x", false, () -> {
            cfg.showDps = false;
            OverlayMod.saveSoon();
        });
        p.tip(W - 30, 4, 24, 18, "Hide (" + cfg.keyDps + ")");
        p.locked = cfg.dpsLocked;
        p.button(W - 88, 4, 54, cfg.dpsLocked ? "Locked" : "Lock", cfg.dpsLocked, () -> {
            cfg.dpsLocked = !cfg.dpsLocked;
            forceRefresh = true;
            OverlayMod.saveSoon();
        });
        p.tip(W - 88, 4, 54, 18, cfg.dpsLocked ? "Window locked: click to move and resize again" : "Lock the window in place (no move, no resize)");
        var tx = 130.0;
        if (meter.paused) {
            p.text(tx, 5, "PAUSED (" + cfg.keyPause + ")", 0xFACC15, 13);
            tx += 110;
        }
        if (s.deaths.length > 0) {
            var label = s.deaths.length == 1 ? s.deaths[0].name + " died" : s.deaths.length + " deaths";
            p.text(tx, 5, label, 0xFF6B6B, 13);
            p.tip(tx, 4, 130, 18, [for (d in s.deaths) DeathTracker.describe(d, DpsTables.skillName)].join("\n\n"));
        }

        var ty = 30.0;
        p.button(8, ty, 44, "DMG", tab == Dmg, () -> setTab(Dmg));
        p.button(56, ty, 46, "HEAL", tab == Heal, () -> setTab(Heal));
        p.button(106, ty, 58, "SHIELD", tab == Shield, () -> setTab(Shield));
        p.button(168, ty, 72, "PLAYERS", tab == Players, () -> setTab(Players));
        p.button(244, ty, 70, "HISTORY", tab == History, () -> setTab(History));
        p.tip(244, ty, 70, 18, s.history.length + " fight(s) kept");
        p.button(W - 172, ty, 52, "Reset", false, () -> {
            meter.manualReset(now);
            forceRefresh = true;
        });
        p.tip(W - 172, ty, 52, 18, "Ends this fight and keeps it in the history (" + cfg.keyReset + ")");
        p.button(W - 114, ty, 106, (cfg.bossReset ? "[x]" : "[ ]") + " Boss reset", cfg.bossReset, () -> {
            cfg.bossReset = !cfg.bossReset;
            forceRefresh = true;
            OverlayMod.saveSoon();
        });
        p.tip(W - 114, ty, 106, 18, "Your first hit on a boss or miniboss starts clean.\nWhat came before it stays in the history.");

        switch (tab) {
            case Dmg: drawDmg(s);
            case Heal: drawSupport(s, true);
            case Shield: drawSupport(s, false);
            case Players: drawPlayers();
            case History: drawHistory(s.history);
        }
        footer(cfg);
        p.end();
    }

    function footer(cfg:Dynamic):Void {
        var fy = H - 22;
        p.text(8, fy, cfg.keyDps + " window  " + cfg.keyReset + " reset  " + cfg.keyPause + " pause", 0x8C849E, 12);
        var x = 252.0;
        var names = ["Physical", "Magic", "Raw", "unknown"];
        var cols = [Panel.PHYS, Panel.MAGIC, Panel.RAW, Panel.UNKNOWN];
        for (i in 0...names.length) {
            p.box(x, fy + 5, 8, 8, cols[i]);
            p.text(x + 11, fy, names[i], i == 3 ? 0x9CA3AF : cols[i], 12);
            x += 11 + names[i].length * 6.6 + 12;
        }
    }

    /** Status, Time, big DPS, Total, Hits/Crit/Casts, then the type bar and its percentages. */
    function summary(y:Float, s:AggSnapshot):Void {
        var status = meter.paused ? "PAUSED" : (s.inCombat ? "IN COMBAT" : (s.haveFight ? "idle" : "waiting"));
        p.dot(14, y + 9, 4.5, s.inCombat ? 0xFF5050 : 0x8C8C8C, s.inCombat);
        p.text(24, y, status, s.inCombat ? 0xFF8A8A : 0xA78BFA, 13);
        p.text(106, y, "Time " + DpsTables.secs(s.elapsedSec), 0xEDE9FE, 13);
        p.text(192, y - 3, "DPS " + DpsTables.fmt(s.dps), 0xFFFFFF, 18);
        p.text(312, y, "Total " + DpsTables.fmt(s.totalDamage), 0xEDE9FE, 13);
        p.text(8, y, "Hits " + s.hitCount + "  Crit " + DpsTables.pct(s.critCount, s.hitCount) + "  Casts " + s.castCount, DpsTables.CELL, 13, W - 16);
        p.typeBar(8, y + 20, W - 16, 6, s.totalDamage, s.totalPhysical, s.totalMagic, s.totalRaw);
        var t = s.totalDamage;
        if (s.bossDamage > 0 && s.haveFight) {
            // Boss vs adds, and the record bar for this boss in the current mode.
            p.text(8, y + 28, "P " + DpsTables.pct(s.totalPhysical, t) + "  M " + DpsTables.pct(s.totalMagic, t) + "  R " + DpsTables.pct(s.totalRaw, t),
                0x9CA3AF, 12);
            p.tip(8, y + 20, 130, 22, "Physical / Magic / Raw");
            bossLine(y + 28, s);
        } else {
            p.text(8, y + 28, "Physical " + DpsTables.pct(s.totalPhysical, t) + "   Magic " + DpsTables.pct(s.totalMagic, t) + "   Raw "
                + DpsTables.pct(s.totalRaw, t), 0x9CA3AF, 12);
            var extra = (s.totalHeal > 0 ? "HPS " + DpsTables.fmt(s.hps) + "   " : "") + (s.totalShield > 0 ? "SPS " + DpsTables.fmt(s.sps) : "");
            if (extra != "") p.text(8, y + 28, extra, 0x86EFAC, 12, W - 16);
        }
    }

    /** HEAL or SHIELD: your heals / absorbs this fight. */
    function drawSupport(s:AggSnapshot, heal:Bool):Void {
        var y = TOP + 2;
        var total = heal ? s.totalHeal : s.totalShield;
        var rows = heal ? s.healRows : s.shieldRows;
        var status = meter.paused ? "PAUSED" : (s.inCombat ? "IN COMBAT" : (s.haveFight ? "idle" : "waiting"));
        p.dot(14, y + 9, 4.5, s.inCombat ? 0xFF5050 : 0x8C8C8C, s.inCombat);
        p.text(24, y, status, s.inCombat ? 0xFF8A8A : 0xA78BFA, 13);
        p.text(106, y, "Time " + DpsTables.secs(s.elapsedSec), 0xEDE9FE, 13);
        p.text(192, y - 3, (heal ? "HPS " : "SPS ") + DpsTables.fmt(heal ? s.hps : s.sps), 0x86EFAC, 18);
        p.text(312, y, "Total " + DpsTables.fmt(total), 0xEDE9FE, 13);
        p.text(8, y, "DPS " + DpsTables.fmt(s.dps), DpsTables.CELL, 13, W - 16);
        p.text(8, y + 24, heal ? "Your heals while in combat (on anyone)." : "Absorbs on you: up when the fight starts, then each new one.", 0x9CA3AF, 12);
        var n = skillRows;
        if (scroll > Math.max(0, rows.length - n)) scroll = Std.int(Math.max(0, rows.length - n));
        if (rows.length == 0) {
            p.text(8, TOP + 48, heal ? "No heals this fight." : "No shields this fight.", Panel.DIM, 13);
            return;
        }
        DpsTables.skillsClassic(p, 8, TOP + 48, W - 16, rows, total, s.elapsedSec, n, scroll, ROW, heal ? "HPS" : "SPS");
    }

    /** "Boss 320  Adds 90   PB solo 340 [bar]", right-aligned on the summary's second line. */
    function bossLine(y:Float, s:AggSnapshot):Void {
        var sec = Math.max(0.001, s.elapsedSec);
        var bossDps = s.bossDamage / sec, addsDps = (s.totalDamage - s.bossDamage) / sec;
        var group = meter.groupMode();
        var pb = meter.records.best(s.bossName, group);
        var right = W - 8.0;
        if (pb != null && pb.dps > 0) {
            var ratio = bossDps / pb.dps;
            var col = ratio >= 1 ? 0x86EFAC : (ratio >= 0.9 ? 0xFACC15 : 0xFCA5A5);
            // Ghost bar: the record is the full width, the fill is where you are now.
            var bw = 64.0;
            p.box(right - bw, y + 5, bw, 6, 0x2A2438, 1);
            p.box(right - bw, y + 5, bw * Math.min(1, ratio), 6, col, 1);
            if (ratio > 1) p.box(right - 2, y + 3, 2, 10, 0xFFFFFF, 1);
            right -= bw + 6;
            var diff = Math.round((ratio - 1) * 100);
            var tw = p.text(8, y, "PB " + (group ? "group " : "solo ") + DpsTables.fmt(pb.dps) + " (" + (diff >= 0 ? "+" : "") + diff + "%)", col, 12,
                right - 8);
            p.tip(right - tw, y - 2, tw + bw + 6, 18, FightWindow.recordTip(pb, group));
            right -= tw + 12;
        } else {
            var tw = p.text(8, y, "no " + (group ? "group" : "solo") + " record yet", Panel.DIM, 12, right - 8);
            p.tip(right - tw, y - 2, tw, 18, "Kill " + s.bossName + " in a fight of 10 s or more to set one.\nSolo and group records are kept apart.");
            right -= tw + 12;
        }
        var tw = p.text(8, y, "Boss " + DpsTables.fmt(bossDps) + "  Adds " + DpsTables.fmt(addsDps), 0xFACC15, 12, right - 8);
        p.tip(right - tw, y - 2, tw, 18, "DPS on " + s.bossName + " (bosses and minibosses) and on everything else");
    }

    function drawDmg(s:AggSnapshot):Void {
        summary(TOP + 2, s);
        var n = skillRows;
        if (scroll > Math.max(0, s.rows.length - n)) scroll = Std.int(Math.max(0, s.rows.length - n));
        DpsTables.skillsClassic(p, 8, TOP + 48, W - 16, s.rows, s.totalDamage, s.elapsedSec, n, scroll, ROW);
    }

    function visiblePlayers():Array<PlayerRow> {
        var rows = meter.players.snap.rows;
        return groupOnly ? rows.filter(r -> r.isSelf || meter.inGroup(r.uid)) : rows;
    }

    function drawPlayers():Void {
        var ps = meter.players.snap;
        var y = TOP + 2;
        p.button(8, y, 46, "ALL", !groupOnly, () -> {
            groupOnly = false;
            scroll = 0;
            forceRefresh = true;
        });
        p.button(58, y, 64, "GROUP", groupOnly, () -> {
            groupOnly = true;
            scroll = 0;
            forceRefresh = true;
        });
        var rows = visiblePlayers();
        var total = 0.0;
        for (r in rows) total += r.total;
        var status = ps.active ? "live" : (ps.haveData ? "idle" : "no hits yet");
        p.text(132, y + 1, status, 0xA78BFA, 13);
        p.text(180, y + 1, rows.length + " player(s)   Total " + DpsTables.fmt(total) + "   " + DpsTables.secs(ps.elapsedSec), 0xEDE9FE, 13);
        p.tip(132, y, W - 140, 18, "Only what reaches this client: far players are missing.\nClick a player for skills and the Build button.");
        y += 24;
        var maxLines = Std.int(Math.max(3, (H - y - 20 - FOOT) / 24));
        DpsTables.players(p, 6, y, W - 12, rows, meter.inGroup, expanded, (uid) -> {
            expanded = expanded == uid ? -1 : uid;
            forceRefresh = true;
        }, (r) -> if (onBuild != null && r.build != null) onBuild(r.build, "live, read " + Math.round((haxe.Timer.stamp() * 1000 - r.build.readAt) / 1000) + " s ago"),
            maxLines, scroll);
    }

    function drawHistory(hist:Array<FightLogEntry>):Void {
        var y = TOP + 2;
        p.button(8, y - 2, 52, "Fights", !showRecords, () -> {
            showRecords = false;
            scroll = 0;
            forceRefresh = true;
        });
        p.button(64, y - 2, 66, "Records", showRecords, () -> {
            showRecords = true;
            scroll = 0;
            forceRefresh = true;
        });
        p.tip(64, y - 2, 66, 18, "Best boss DPS per boss and average DPS per weapon, solo and group apart");
        if (showRecords) {
            drawRecords(y + 22);
            return;
        }
        p.text(140, y, hist.length + " fight(s). The star keeps a fight. Click a row for details.", 0x8C849E, 12);
        y += 20;
        var w = W - 16, x = 8.0;
        var c = [x, x + 26, x + w * 0.16, x + w * 0.62, x + w * 0.74, x + w * 0.86];
        p.text(c[1], y, "Ended", DpsTables.HEAD, 13);
        p.text(c[2], y, "Target", DpsTables.HEAD, 13);
        p.text(c[3], y, "Time", DpsTables.HEAD, 13);
        p.text(c[4], y, "DPS", DpsTables.HEAD, 13);
        p.text(c[5], y, "Damage", DpsTables.HEAD, 13);
        var max = Std.int(Math.max(3, (H - y - ROW - FOOT) / ROW));
        if (scroll > Math.max(0, hist.length - max)) scroll = Std.int(Math.max(0, hist.length - max));
        for (i in 0...Std.int(Math.max(0, Math.min(max, hist.length - scroll)))) {
            var f = hist[i + scroll];
            var ry = y + ROW * (i + 1);
            var sel = f.id == selectedFight;
            if (sel) p.box(x, ry, w, ROW, 0x3B2A66, 0.9) else if (i % 2 == 0) p.box(x, ry, w, ROW, 0x1A1430, 0.8);
            star(c[0] + 10, ry + ROW / 2, f.favorite);
            var id = f.id;
            p.click(c[0], ry, 22, ROW, () -> {
                meter.setFavorite(id, !f.favorite);
                forceRefresh = true;
            });
            p.tip(c[0], ry, 22, ROW, f.favorite ? "Kept (click to unstar)" : "Keep this fight");
            var d = Date.fromTime(f.endedUnixMs);
            var two = (n:Int) -> (n < 10 ? "0" : "") + n;
            p.text(c[1], ry + 2, f.endedUnixMs > 0 ? two(d.getHours()) + ":" + two(d.getMinutes()) : "-", DpsTables.CELL, 13);
            var label = CombatTracker.targetLabel(f);
            var maxChars = Std.int((c[3] - c[2] - 8) / 7.2) - (f.imported ? 10 : 0);
            if (label.length > maxChars) label = label.substr(0, maxChars - 1) + ".";
            var rank = f.targets.length > 0 ? f.targets[0].rank : Normal;
            p.text(c[2], ry + 2, label + (f.imported ? "  (overlay)" : ""), rank == Boss || rank == Miniboss ? 0xFACC15 : 0xFFFFFF, 13);
            var tagX = c[2] + (label.length + (f.imported ? 11 : 0)) * 7.0 + 6;
            if (f.newRecord && tagX < c[3] - 20) p.text(tagX, ry + 3, "PB", 0x86EFAC, 11);
            if (f.deaths.length > 0 && tagX + 22 < c[3] - 10) p.text(tagX + (f.newRecord ? 22 : 0), ry + 3, "x" + f.deaths.length, 0xFF6B6B, 11);
            p.text(c[3], ry + 2, DpsTables.secs(f.durationSec), DpsTables.CELL, 13);
            p.text(c[4], ry + 2, DpsTables.fmt(f.dps), Panel.TEXT, 13);
            p.text(c[5], ry + 2, DpsTables.fmt(f.totalDamage), DpsTables.CELL, 13);
            var tip = (f.loadout.hand != "" ? f.loadout.hand + (f.loadout.second != "" ? " / " + f.loadout.second : "") + "\n" : "")
                + "top: " + DpsTables.skillName(f.topSkill) + "   |   " + f.hitCount + " hits   |   click for details"
                + (f.players.length > 0 ? "\n" + f.playerCount + " players recorded" : "") + (f.imported ? "\n(from the C++ overlay)" : "")
                + "\n" + (f.group ? "group fight" : "solo fight") + (f.newRecord ? "  -  new boss record" : "")
                + (f.deaths.length > 0 ? "\n" + [for (d in f.deaths) d.name + " died" + (d.atSec >= 0 ? " at " + DeathTracker.clock(d.atSec) : "")].join(", ") : "");
            p.tip(c[1], ry, w - 26, ROW, tip);
            p.click(c[1], ry, w - 26, ROW, () -> {
                selectedFight = selectedFight == id ? -1 : id;
                if (onFight != null) onFight(selectedFight == id ? f : null);
                forceRefresh = true;
            });
        }
        if (hist.length == 0) p.text(8, y + ROW, "No fights yet.", 0x8C849E, 13);
    }

    /** Boss records (Solo | Group) and weapon averages (Solo | Group | fights), one scrolled list. */
    function drawRecords(y:Float):Void {
        var r = meter.records;
        var w = W - 16, x = 8.0;
        var c = [x + 4, x + w * 0.52, x + w * 0.76];
        var lines:Array<{kind:Int, name:String}> = [{kind: 0, name: ""}];
        for (b in r.bossNames()) lines.push({kind: 1, name: b});
        if (r.bossNames().length == 0) lines.push({kind: 4, name: "No boss killed yet (fights of 10 s or more)."});
        lines.push({kind: 2, name: ""});
        for (wn in r.weaponNames()) lines.push({kind: 3, name: wn});
        if (r.weaponNames().length == 0) lines.push({kind: 4, name: "No fights of 10 s or more yet."});
        var max = Std.int(Math.max(3, (H - y - FOOT) / ROW));
        if (scroll > Math.max(0, lines.length - max)) scroll = Std.int(Math.max(0, lines.length - max));
        var two = (n:Int) -> (n < 10 ? "0" : "") + n;
        for (i in 0...Std.int(Math.min(max, lines.length - scroll))) {
            var l = lines[i + scroll];
            var ry = y + ROW * i;
            switch (l.kind) {
                case 0, 2:
                    p.box(x, ry, w, ROW, DpsTables.HEADER_BG, 0.94);
                    p.text(c[0], ry + 2, l.kind == 0 ? "Boss (best DPS on the boss)" : "Weapon in hand (average DPS)", DpsTables.HEAD, 13);
                    p.text(c[1], ry + 2, "Solo", DpsTables.HEAD, 13);
                    p.text(c[2], ry + 2, "Group", DpsTables.HEAD, 13);
                    p.tip(x, ry, w, ROW, l.kind == 0 ? "Damage on the boss / fight time, adds not counted.\nOnly fights of 10 s or more where the boss died."
                        : "All your fights of 10 s or more with that weapon in hand.\nHover a number for the best fight and the count.");
                case 4:
                    p.text(c[0], ry + 3, l.name, Panel.DIM, 12);
                case 1:
                    if (i % 2 == 0) p.box(x, ry, w, ROW, 0x1A1430, 0.8);
                    p.text(c[0], ry + 2, l.name.length > 34 ? l.name.substr(0, 33) + "." : l.name, 0xFACC15, 13);
                    for (g in 0...2) {
                        var b = r.best(l.name, g == 1);
                        var cx = c[1 + g];
                        if (b == null) {
                            p.text(cx, ry + 2, "-", Panel.DIM, 13);
                            continue;
                        }
                        p.text(cx, ry + 2, DpsTables.fmt(b.dps), Panel.TEXT, 13);
                        p.text(cx + 48, ry + 3, DpsTables.secs(b.durationSec), Panel.DIM, 12);
                        p.tip(cx, ry, c[2] - c[1], ROW, FightWindow.recordTip(b, g == 1));
                    }
                case 3:
                    if (i % 2 == 0) p.box(x, ry, w, ROW, 0x1A1430, 0.8);
                    p.text(c[0], ry + 2, l.name.length > 34 ? l.name.substr(0, 33) + "." : l.name, Panel.TEXT, 13);
                    for (g in 0...2) {
                        var st = r.weapon(l.name, g == 1);
                        var cx = c[1 + g];
                        if (st == null) {
                            p.text(cx, ry + 2, "-", Panel.DIM, 13);
                            continue;
                        }
                        p.text(cx, ry + 2, DpsTables.fmt(st.avg), Panel.TEXT, 13);
                        p.text(cx + 48, ry + 3, st.fights + (st.fights == 1 ? " fight" : " fights"), Panel.DIM, 12);
                        p.tip(cx, ry, c[2] - c[1], ROW, l.name + " (" + (g == 1 ? "group" : "solo") + ")\naverage " + Math.round(st.avg) + " DPS over "
                            + st.fights + " fight(s), " + DpsTables.secs(st.seconds) + " in all\nbest fight " + Math.round(st.best) + " DPS");
                    }
                case _:
            }
        }
    }

    function star(cx:Float, cy:Float, on:Bool):Void {
        var pts = [];
        for (i in 0...10) {
            var r = i % 2 == 0 ? 7.0 : 3.0;
            var a = -Math.PI / 2 + i * Math.PI / 5;
            pts.push(cx + Math.cos(a) * r);
            pts.push(cy + Math.sin(a) * r);
        }
        p.poly(pts, on ? 0xFFC444 : 0x2A2438, on ? 0xFFC444 : 0x968CAA);
    }
}
