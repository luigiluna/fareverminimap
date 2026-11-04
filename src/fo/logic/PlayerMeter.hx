package fo.logic;

import fo.logic.Build;
import fo.logic.CombatTracker;

/**
 * Everyone's damage as seen by this client (PLAYERS view). Ported from
 * player_meter.cpp, without the build reader (gear and talents).
 *
 * Keeps its own session apart from the local fight: in a busy zone others are
 * always hitting something and would otherwise never let a fight end.
 */
class PlayerMeter {
    public static inline var MAX_ROWS = 64;
    public static inline var MAX_SKILL_ROWS = 8;
    public static inline var MAX_FIGHT_PLAYERS = 20;
    static inline var MAX_TRACKED_PLAYERS = 256;
    static inline var MAX_TRACKED_SKILLS = 64;
    static inline var MIN_ACTIVE_SEC = 1.0;

    public var idleResetMs = 10000.0;
    public var publishIntervalMs = 250.0;

    var haveData = false;
    var firstMs = 0.0;
    var lastMs = 0.0;
    var lastPublishMs = -1e18;
    var dirty = true;
    var force = true;
    var players = new Map<String, Player>();
    var playerCount = 0;

    public var snap(default, null) = new PlayerMeterSnapshot();
    var builds = new Map<String, PlayerBuild>();
    var buildCount = 0;

    public function new(?idleResetMs:Float, ?publishIntervalMs:Float) {
        if (idleResetMs != null) this.idleResetMs = idleResetMs;
        if (publishIntervalMs != null) this.publishIntervalMs = publishIntervalMs;
    }

    static inline function key(uid:Float):String return Std.string(uid);

    public function onHit(now:Float, uid:Float, name:String, isSelf:Bool, skillIn:String, amount:Float, crit:Bool, type:DamageType):Void {
        if (haveData && now - lastMs >= idleResetMs) reset();
        if (!haveData) {
            haveData = true;
            firstMs = now;
        }
        lastMs = now;
        var p = players.get(key(uid));
        if (p == null) {
            if (playerCount >= MAX_TRACKED_PLAYERS) return;
            p = new Player(uid);
            p.firstMs = now;
            players.set(key(uid), p);
            playerCount++;
        }
        p.name = CombatTracker.clip(name);
        p.isSelf = isSelf;
        p.lastMs = now;
        p.total += amount;
        p.hitCount++;
        if (crit) p.critCount++;
        if (amount > p.maxHit) p.maxHit = amount;
        switch (type) {
            case Physical: p.physical += amount;
            case Magic: p.magic += amount;
            case Raw: p.raw += amount;
            case Unclassified:
        }
        var skill = CombatTracker.normaliseSkill(CombatTracker.clip(skillIn));
        var s = p.skills.get(skill);
        if (s == null && p.skillCount < MAX_TRACKED_SKILLS) {
            s = new PlayerSkillRow(skill);
            p.skills.set(skill, s);
            p.skillCount++;
        }
        if (s != null) {
            s.total += amount;
            s.hitCount++;
            if (crit) s.critCount++;
        }
        dirty = true;
    }

    /** Keeps the latest per player, through session resets: gear does not change because everyone stopped hitting. */
    public function onBuild(b:PlayerBuild):Void {
        var k = key(b.uid);
        if (buildCount >= MAX_TRACKED_PLAYERS && !builds.exists(k)) {
            builds = new Map();
            buildCount = 0;
        }
        if (!builds.exists(k)) buildCount++;
        builds.set(k, b);
        dirty = true;
    }

    public function build(uid:Float):PlayerBuild return builds.get(key(uid));

    /** Share of the damage seen that came from other players (0 when none seen). */
    public function othersShare():Float {
        var all = 0.0, others = 0.0;
        for (p in players) {
            all += p.total;
            if (!p.isSelf) others += p.total;
        }
        return all > 0 ? others / all : 0;
    }

    public function reset():Void {
        players = new Map();
        playerCount = 0;
        haveData = false;
        firstMs = lastMs = 0;
        dirty = true;
        force = true;
    }

    function rebuild():Void {
        var s = snap;
        s.playerCount = playerCount;
        s.totalDamage = 0;
        var sorted = [for (p in players) p];
        for (p in sorted) s.totalDamage += p.total;
        sorted.sort((a, b) -> a.total > b.total ? -1 : (a.total < b.total ? 1 : 0));
        if (sorted.length > MAX_ROWS) sorted.resize(MAX_ROWS);
        s.rows = [for (p in sorted) {
            var r = new PlayerRow();
            r.uid = p.uid;
            r.name = p.name;
            r.isSelf = p.isSelf;
            r.total = p.total;
            r.maxHit = p.maxHit;
            r.hitCount = p.hitCount;
            r.critCount = p.critCount;
            r.physical = p.physical;
            r.magic = p.magic;
            r.raw = p.raw;
            r.activeSec = Math.max(MIN_ACTIVE_SEC, (p.lastMs - p.firstMs) / 1000.0);
            r.dps = p.total / r.activeSec;
            var b = build(p.uid);
            if (b != null) {
                r.className = b.className;
                r.level = b.level;
                r.talentsRead = b.talentsRead;
                r.talentPoints = b.talentPoints;
                r.weapons = b.weapons();
                r.build = b;
            }
            var sk = [for (x in p.skills) x];
            sk.sort((a, b) -> a.total > b.total ? -1 : (a.total < b.total ? 1 : 0));
            if (sk.length > MAX_SKILL_ROWS) sk.resize(MAX_SKILL_ROWS);
            r.skills = [for (x in sk) {
                var c = new PlayerSkillRow(x.skill);
                c.hitCount = x.hitCount;
                c.critCount = x.critCount;
                c.total = x.total;
                c;
            }];
            r;
        }];
    }

    public function publishNow(now:Float):Void {
        force = true;
        publish(now);
    }

    public function publish(now:Float):Void {
        var s = snap;
        if (dirty && (force || now - lastPublishMs >= publishIntervalMs)) {
            rebuild();
            dirty = false;
            force = false;
            lastPublishMs = now;
        }
        s.haveData = haveData;
        s.active = haveData && now - lastMs < idleResetMs;
        s.elapsedSec = haveData ? (lastMs - firstMs) / 1000.0 : 0;
    }

    /** Copies the snapshot into a fight: the biggest rows, plus self and `group` (uids) whatever their rank. */
    public static function fillFightPlayers(s:PlayerMeterSnapshot, group:Array<Float>, fight:FightLogEntry):Void {
        inline function grouped(uid:Float) return group.indexOf(uid) >= 0;
        var reserved = 0;
        for (r in s.rows) if (r.isSelf || grouped(r.uid)) reserved++;
        fight.playerCount = s.playerCount;
        fight.playersTotal = s.totalDamage;
        fight.players = [];
        var othersLeft = reserved < MAX_FIGHT_PLAYERS ? MAX_FIGHT_PLAYERS - reserved : 0;
        for (r in s.rows) {
            var inGroup = grouped(r.uid);
            if (!r.isSelf && !inGroup) {
                if (othersLeft == 0) continue;
                othersLeft--;
            }
            if (fight.players.length == MAX_FIGHT_PLAYERS) break;
            var out = r.copy();
            out.inGroup = inGroup;
            fight.players.push(out);
        }
    }
}

private class Player {
    public var uid:Float;
    public var name = "";
    public var isSelf = false;
    public var firstMs = 0.0;
    public var lastMs = 0.0;
    public var total = 0.0;
    public var maxHit = 0.0;
    public var hitCount = 0;
    public var critCount = 0;
    public var physical = 0.0;
    public var magic = 0.0;
    public var raw = 0.0;
    public var skills = new Map<String, PlayerSkillRow>();
    public var skillCount = 0;

    public function new(uid:Float) this.uid = uid;
}

class PlayerMeterSnapshot {
    public var haveData = false;
    public var active = false;
    public var elapsedSec = 0.0;
    public var totalDamage = 0.0;
    public var playerCount = 0;
    public var rows:Array<PlayerRow> = [];

    public function new() {}
}
