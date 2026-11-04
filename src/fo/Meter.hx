package fo;

import fo.DpsCapture.Hit;
import fo.logic.CombatTracker;
import fo.logic.History;
import fo.logic.PlayerMeter;
import fo.logic.Deaths;
import fo.logic.Records;

/** Feeds the trackers, seals fights, keeps the history file. Runs on the game thread. */
class Meter {
    public var tracker = new CombatTracker();
    /** Live PLAYERS session. */
    public var players = new PlayerMeter();
    /** Everyone's hits during the current local fight only, for the history. */
    var fightPlayers = new PlayerMeter(1e12, 0);

    var historyPath:String;
    var saveDirty = false;
    var lastSaveAt = 0.0;
    var bossEngaged = false;
    var lastHero:Dynamic;
    var lastLayer:Dynamic;
    public var group:Array<Dynamic> = [];
    public var groupUids:Array<Float> = [];
    var myUid = 0.0;
    /** Local hero's weapons, refreshed about once a second by OverlayMod. */
    public var loadout:FightLoadout = null;

    public function new(historyPath:String, overlayHistory:String) {
        this.historyPath = historyPath;
        recordsPath = haxe.io.Path.directory(historyPath) + "/records.json";
        var loaded:Array<FightLogEntry> = null;
        try {
            if (sys.FileSystem.exists(historyPath)) loaded = History.parse(sys.io.File.getContent(historyPath));
        } catch (e:Dynamic) Log.err("history: own file unreadable, starting empty: " + Std.string(e));
        if (loaded == null && overlayHistory != null) {
            // First run: import the C++ overlay's history, read only. That file is never written.
            try {
                if (sys.FileSystem.exists(overlayHistory)) {
                    loaded = History.parse(sys.io.File.getContent(overlayHistory));
                    for (e in loaded) e.imported = true;
                    Log.info('history: imported ${loaded.length} fight(s) from the overlay (read only): $overlayHistory');
                    saveDirty = true;
                }
            } catch (e:Dynamic) Log.err("history: overlay file unreadable: " + Std.string(e));
        }
        if (loaded != null) {
            for (e in loaded) tracker.restoreHistory(e);
            Log.info('history: ${tracker.history.length} fight(s) loaded' + (History.dropped > 0 ? ', ${History.dropped} unreadable dropped' : ""));
            if (History.dropped > 0) saveDirty = true;
        }
        try {
            if (sys.FileSystem.exists(recordsPath)) records = Records.parse(sys.io.File.getContent(recordsPath));
            else if (loaded != null) {
                // First run with records: seed them from the history, oldest first.
                var i = loaded.length - 1;
                while (i >= 0) records.offer(loaded[i--]);
                saveRecords();
            }
            Log.info('records: ${records.bossNames().length} boss(es), ${records.weaponNames().length} weapon(s)');
        } catch (e:Dynamic) Log.err("records unreadable, starting empty: " + Std.string(e));
    }

    /** Paused: hits, heals and shields are ignored (the fight timer still runs). */
    public var paused = false;
    var prevShield = 0.0;
    var prevHaveFight = false;
    var lastShieldRead = -1e9;

    var deathTracker = new DeathTracker();
    /** Boss records and weapon averages (records.json, next to the history). */
    public var records = new Records();
    var recordsPath:String;

    /** You, or someone of your group. */
    function watched(uid:Float, isSelf:Bool):Bool return isSelf || inGroup(uid);

    /** A group fight: in a party with someone, or others did a real share of this fight's damage. */
    public function groupMode():Bool return groupUids.length > 1 || fightPlayers.othersShare() >= Records.GROUP_SHARE;

    function died(now:Float, uid:Float, name:String, isSelf:Bool, why:String):Void {
        var d = deathTracker.onDeath(now, uid, name, isSelf);
        if (d == null) return;
        tracker.onDeath(now, d);
        Log.info('death ($why): ${d.name} self=$isSelf hits=${d.hits.length} killer=${d.killer} inFight=${d.atSec >= 0}');
    }

    /** Postfix of ent.Unit.onDeath: any unit; only heroes of interest count. */
    public function onUnitDeath(unit:Dynamic, now:Float):Void {
        if (unit == null || !G.isA(unit, "ent.Hero")) return;
        var uid = G.num(G.f(unit, "__uid"));
        var isSelf = DpsCapture.hero != null && unit == DpsCapture.hero;
        if (!watched(uid, isSelf)) return;
        var name = G.str(G.f(unit, "name"));
        died(now, uid, name == null ? "?" : name, isSelf, "onDeath");
    }

    public function onHit(h:Hit, now:Float, bossReset:Bool):Void {
        if (h.taken) {
            if (!watched(h.playerUid, h.isMine)) return;
            deathTracker.onTaken(now, h.playerUid, h.skill, h.targetName, h.amount, h.crit);
            if (h.kill) died(now, h.playerUid, h.playerName, h.isMine, "killing blow");
            return;
        }
        if (paused) return;
        if (h.heal) {
            tracker.onHeal(now, h.skill, h.amount, h.crit, DpsCapture.hero != null && G.bool(G.f(DpsCapture.hero, "isInCombat")));
            return;
        }
        if (h.isMine) {
            myUid = h.playerUid;
            if (bossReset && !bossEngaged && (h.targetRank == Boss || h.targetRank == Miniboss)) {
                // First own hit on a boss: what came before is its own fight.
                bossEngaged = true;
                seal(tracker.reset(now), now, "boss reset");
                players.reset();
                fightPlayers.reset();
            }
            tracker.onDamage(now, h.skill, h.amount, h.crit, h.type);
            tracker.onTarget(h.targetName, h.targetRank, h.amount, h.kill);
            tracker.onLoadoutDamage(loadout, h.amount);
        }
        var isSelf = h.isMine;
        players.onHit(now, h.playerUid, h.playerName, isSelf, h.skill, h.amount, h.crit, h.type);
        if (tracker.fightActive) fightPlayers.onHit(now, h.playerUid, h.playerName, isSelf, h.skill, h.amount, h.crit, h.type);
    }

    public function onBuild(b:fo.logic.Build.PlayerBuild):Void {
        players.onBuild(b);
        fightPlayers.onBuild(b);
    }

    public function onCast(skill:String, now:Float):Void tracker.onCast(now, skill);

    public function inGroup(uid:Float):Bool return groupUids.indexOf(uid) >= 0;

    /** Every frame. */
    public function update(app:Dynamic, hero:Dynamic, now:Float):Void {
        var layer = hero == null ? null : G.f(hero, "layer");
        if (hero != lastHero || layer != lastLayer) {
            if (lastHero != null) seal(tracker.endFight(), now, "zone/character change");
            if (lastHero != null) players.reset();
            fightPlayers.reset();
            lastHero = hero;
            lastLayer = layer;
        }
        var locked = hero != null;
        var inCombat = hero != null && G.bool(G.f(hero, "isInCombat"));
        seal(tracker.update(now, locked, inCombat), now, "idle");
        if (hero != null && now - lastShieldRead >= 100) {
            lastShieldRead = now;
            try pollShield(hero) catch (e:Dynamic) Log.once("shield", "shield read failed: " + Std.string(e), 3);
        }
        tracker.publish(now, locked, inCombat);
        players.publish(now);
        if (saveDirty && now - lastSaveAt > 2000) save(now);
    }

    /**
     * Like the C++ aggregator: a shield up when a fight starts counts once, and
     * so does each rise during the fight (a rise is a new application; the absorb
     * only goes down as it soaks). Shields with no fight after them are not counted.
     */
    function pollShield(hero:Dynamic):Void {
        var sh = DpsCapture.readShield(hero);
        var fightNow = tracker.fightActive;
        var applied = sh.amount > prevShield + 0.5;
        if (!paused) {
            if (fightNow && !prevHaveFight) {
                if (sh.amount > 0.5) tracker.onShield(sh.kind, sh.amount);
            } else if (fightNow && applied) tracker.onShield(sh.kind, sh.amount - (prevShield > 0.5 ? prevShield : 0));
        }
        prevHaveFight = fightNow;
        prevShield = sh.amount;
    }

    public function manualReset(now:Float):Void {
        seal(tracker.reset(now), now, "manual reset");
        players.reset();
        fightPlayers.reset();
    }

    public function readGroup(app:Dynamic):Void {
        group = [];
        groupUids = [];
        var me = G.f(app, "me");
        var grp = G.f(me, "group");
        var list = G.f(G.f(grp, "players"), "array");
        for (i in 0...G.alen(list)) {
            var p = G.aget(list, i);
            if (p == null) continue;
            group.push(p);
            var h = G.f(p, "hero");
            if (h != null) groupUids.push(G.num(G.f(h, "__uid")));
        }
    }

    function seal(e:FightLogEntry, now:Float, why:String):Void {
        if (e == null) return;
        bossEngaged = false;
        e.endedUnixMs = Date.now().getTime();
        fightPlayers.publishNow(now);
        e.group = groupMode();
        PlayerMeter.fillFightPlayers(fightPlayers.snap, groupUids, e);
        fightPlayers.reset();
        e.newRecord = records.offer(e);
        saveRecords();
        if (e.newRecord) Log.info('new ${e.group ? "group" : "solo"} record: ${Records.bossOf(e).name} ${Math.round(Records.bossDamage(e) / e.durationSec)} boss DPS');
        tracker.touchHistory();
        saveDirty = true;
        Log.info('fight sealed ($why): id=${e.id} dmg=${Math.round(e.totalDamage)} dps=${Math.round(e.dps)} dur=${Math.round(e.durationSec * 10) / 10}s target=${CombatTracker.targetLabel(e)} players=${e.players.length}');
    }

    public function setFavorite(id:Int, on:Bool):Bool {
        var ok = tracker.setFavorite(id, on);
        if (ok) saveDirty = true;
        return ok;
    }

    function saveRecords():Void {
        try {
            var dir = haxe.io.Path.directory(recordsPath);
            if (!sys.FileSystem.exists(dir)) sys.FileSystem.createDirectory(dir);
            var tmp = recordsPath + ".tmp";
            sys.io.File.saveContent(tmp, records.stringify());
            if (sys.FileSystem.exists(recordsPath)) sys.FileSystem.deleteFile(recordsPath);
            sys.FileSystem.rename(tmp, recordsPath);
        } catch (e:Dynamic) Log.err("records save failed: " + Std.string(e));
    }

    public function save(now:Float):Void {
        saveDirty = false;
        lastSaveAt = now;
        try {
            var dir = haxe.io.Path.directory(historyPath);
            if (!sys.FileSystem.exists(dir)) sys.FileSystem.createDirectory(dir);
            // Temp file first, so a crash mid-write cannot truncate the history.
            var tmp = historyPath + ".tmp";
            sys.io.File.saveContent(tmp, History.stringify(tracker.history));
            if (sys.FileSystem.exists(historyPath)) sys.FileSystem.deleteFile(historyPath);
            sys.FileSystem.rename(tmp, historyPath);
        } catch (e:Dynamic) Log.err("history save failed: " + Std.string(e));
    }
}
