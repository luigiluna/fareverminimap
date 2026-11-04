package fo.logic;

/**
 * The DPS meter's core, ported from the C++ overlay's combat_tracker.cpp.
 *
 * Takes decoded combat events and turns them into fights, rows and a snapshot.
 * It knows nothing about the game or the UI and every call takes the time
 * explicitly, so it runs under `haxe --interp` (see tests/).
 *
 * Time is a Float in milliseconds from any monotonic clock.
 */
class CombatTracker {
    public static inline var MAX_ROWS = 64;
    public static inline var MAX_FIGHT_TARGETS = 4;
    public static inline var RECENT_MAX = 10;
    public static inline var FAVORITES_MAX = 20;
    public static inline var HISTORY_MAX = RECENT_MAX + FAVORITES_MAX;
    public static inline var NAME_MAX = 63;

    public var timing(default, null):Timing;

    var haveFirst = false;
    var firstMs = 0.0;
    var lastMs = 0.0;
    var idleSince = 0.0;
    var idleArmed = false;
    var rows = new Map<String, SkillRow>();
    var healRows = new Map<String, SkillRow>();
    var shieldRows = new Map<String, SkillRow>();
    var casts = new Map<String, Int>();
    var targets = new Map<String, FightTarget>();
    var loadouts:Array<{loadout:FightLoadout, total:Float}> = [];
    var recentCasts:Array<{at:Float, skill:String}> = [];
    /** Own damage per bucket of `bucketSec` seconds from the fight's first hit. */
    var timeline:Array<Float> = [];
    var bucketSec = 1.0;
    var deaths:Array<fo.logic.Deaths.DeathRecap> = [];

    public static inline var TIMELINE_MAX = 300;
    public static inline var DEATHS_MAX = 6;

    /** Newest first. */
    public var history(default, null):Array<FightLogEntry> = [];
    public var nextFightId(default, null) = 1;

    public var snap(default, null) = new AggSnapshot();
    var rowsDirty = true;
    var forceRows = true;
    var historyDirty = true;
    var lastRowsMs = 0.0;

    public function new(?timing:Timing) {
        this.timing = timing == null ? new Timing() : timing;
    }

    public static function clip(s:String):String {
        if (s == null) return "";
        return s.length > NAME_MAX ? s.substr(0, NAME_MAX) : s;
    }

    /** "DS_Base_Attack_3" and "Bow_Base_Attack2" collapse to one row. */
    public static function normaliseSkill(skill:String):String {
        if (skill == null) return "";
        if (skill.indexOf("Base_Attack") < 0) return skill;
        var n = skill.length;
        while (n > 0) {
            var c = skill.charCodeAt(n - 1);
            if (c < "0".code || c > "9".code) break;
            n--;
        }
        if (n > 0 && skill.charAt(n - 1) == "_") n--;
        return skill.substr(0, n);
    }

    public var fightActive(get, never):Bool;
    inline function get_fightActive() return haveFirst;

    function foldRow(map:Map<String, SkillRow>, skill:String, amount:Float, crit:Bool, type:DamageType):Void {
        var r = map.get(skill);
        if (r == null) {
            r = new SkillRow(skill);
            map.set(skill, r);
        }
        // One event is one impact: DamageResult._hitCount is a tick ordinal, never summed.
        r.hitCount++;
        r.total += amount;
        if (amount > r.maxHit) r.maxHit = amount;
        if (crit) r.critCount++;
        switch (type) {
            case Physical: r.physical += amount;
            case Magic: r.magic += amount;
            case Raw: r.raw += amount;
            case Unclassified:
        }
        rowsDirty = true;
    }

    /** Returns true when this hit opened a new fight. */
    public function onDamage(now:Float, skillIn:String, amount:Float, crit:Bool, type:DamageType):Bool {
        var skill = normaliseSkill(clip(skillIn));
        var started = false;
        if (!haveFirst) {
            haveFirst = true;
            firstMs = now;
            started = true;
            for (c in recentCasts)
                if (now - c.at <= timing.openingCastWindowMs) casts.set(c.skill, (casts.exists(c.skill) ? casts.get(c.skill) : 0) + 1);
            recentCasts = [];
        }
        lastMs = now;
        foldRow(rows, skill, amount, crit, type);
        addTimeline(now, amount);
        return started;
    }

    /** Heals feed the meter only while the hero is in combat (passive HoTs would keep a fight open). */
    public function onHeal(now:Float, skillIn:String, amount:Float, crit:Bool, heroInCombat:Bool):Bool {
        if (!heroInCombat) return false;
        var skill = normaliseSkill(clip(skillIn));
        var started = false;
        if (!haveFirst) {
            haveFirst = true;
            firstMs = now;
            started = true;
        }
        lastMs = now;
        foldRow(healRows, skill, amount, crit, Unclassified);
        return started;
    }

    function addTimeline(now:Float, amount:Float):Void {
        var idx = Std.int((now - firstMs) / 1000 / bucketSec);
        if (idx < 0) idx = 0;
        // Long fights: halve the resolution instead of growing past TIMELINE_MAX.
        while (idx >= TIMELINE_MAX) {
            timeline = [for (i in 0...Std.int((timeline.length + 1) / 2)) timeline[2 * i] + (2 * i + 1 < timeline.length ? timeline[2 * i + 1] : 0)];
            bucketSec *= 2;
            idx = Std.int((now - firstMs) / 1000 / bucketSec);
        }
        while (timeline.length <= idx) timeline.push(0);
        timeline[idx] += amount;
    }

    /** A death of you or your group: kept in the fight when one is open. */
    public function onDeath(now:Float, d:fo.logic.Deaths.DeathRecap):Void {
        if (!haveFirst || d == null) return;
        d.atSec = Math.round((now - firstMs) / 100) / 10;
        if (deaths.length < DEATHS_MAX) deaths.push(d);
        rowsDirty = true;
    }

    public function onShield(kind:String, amount:Float):Void {
        foldRow(shieldRows, (kind != null && kind != "") ? clip(kind) : "Shield", amount, false, Unclassified);
    }

    /** One activation. Never opens or extends a fight. */
    public function onCast(now:Float, skillIn:String):Void {
        var skill = normaliseSkill(clip(skillIn));
        if (haveFirst) {
            casts.set(skill, (casts.exists(skill) ? casts.get(skill) : 0) + 1);
            rowsDirty = true;
            return;
        }
        while (recentCasts.length > 0 && now - recentCasts[0].at > timing.openingCastWindowMs) recentCasts.shift();
        recentCasts.push({at: now, skill: skill});
    }

    public function onTarget(name:String, rank:TargetRank, amount:Float, kill:Bool):Void {
        if (!haveFirst || name == null || name == "") return;
        var t = targets.get(name);
        if (t == null) {
            t = new FightTarget(clip(name), rank);
            targets.set(name, t);
        }
        t.total += amount;
        if (kill) t.kills++;
        if (rank > t.rank) t.rank = rank;
    }

    public function onLoadoutDamage(l:FightLoadout, amount:Float):Void {
        if (!haveFirst || l == null || l.hand == "") return;
        for (k in loadouts) {
            if (k.loadout.hand != l.hand) continue;
            k.total += amount;
            if (k.loadout.second == "") k.loadout.second = l.second;
            if (k.loadout.off == "") k.loadout.off = l.off;
            k.loadout.handLevel = l.handLevel;
            k.loadout.handUpgrade = l.handUpgrade;
            return;
        }
        loadouts.push({loadout: l.copy(), total: amount});
    }

    function sortedRows(map:Map<String, SkillRow>, withCasts:Bool):Array<SkillRow> {
        var all = [for (r in map) r];
        all.sort((a, b) -> a.total > b.total ? -1 : (a.total < b.total ? 1 : 0));
        if (all.length > MAX_ROWS) all.resize(MAX_ROWS);
        return [for (r in all) {
            var c = r.copy();
            c.castCount = withCasts && casts.exists(r.skill) ? casts.get(r.skill) : 0;
            c;
        }];
    }

    function seal(elapsedSec:Float):FightLogEntry {
        if (!haveFirst || !rows.iterator().hasNext()) return null;
        while (true) {
            var recent = 0, oldest = -1;
            for (i in 0...history.length) {
                if (history[i].favorite) continue;
                recent++;
                oldest = i;
            }
            if (recent < RECENT_MAX) break;
            history.splice(oldest, 1);
        }
        var e = new FightLogEntry();
        e.id = nextFightId++;
        e.durationSec = elapsedSec > 0.001 ? elapsedSec : 0.001;
        e.rows = sortedRows(rows, true);
        for (r in rows) {
            e.totalDamage += r.total;
            e.hitCount += r.hitCount;
            e.totalPhysical += r.physical;
            e.totalMagic += r.magic;
            e.totalRaw += r.raw;
        }
        for (r in e.rows) e.castCount += r.castCount;
        e.dps = e.totalDamage / e.durationSec;
        e.healRows = sortedRows(healRows, false);
        for (r in healRows) e.totalHeal += r.total;
        e.hps = e.totalHeal / e.durationSec;
        e.shieldRows = sortedRows(shieldRows, false);
        for (r in shieldRows) e.totalShield += r.total;
        e.sps = e.totalShield / e.durationSec;
        if (e.rows.length > 0) e.topSkill = e.rows[0].skill;
        for (t in targets) if (t.rank == Boss || t.rank == Miniboss) e.bossDamage += t.total;
        e.timeline = [for (v in timeline) Math.round(v)];
        e.timelineSec = bucketSec;
        e.deaths = deaths.copy();

        var ts = [for (t in targets) t];
        ts.sort((a, b) -> {
            if (a.rank != b.rank) return a.rank > b.rank ? -1 : 1;
            if (a.total != b.total) return a.total > b.total ? -1 : 1;
            return a.name < b.name ? -1 : (a.name > b.name ? 1 : 0);
        });
        e.targetCount = ts.length;
        e.targets = [for (i in 0...Std.int(Math.min(ts.length, MAX_FIGHT_TARGETS))) ts[i].copy()];

        var best:{loadout:FightLoadout, total:Float} = null;
        for (k in loadouts) if (best == null || k.total > best.total) best = k;
        if (best != null) e.loadout = best.loadout.copy();

        history.unshift(e);
        historyDirty = true;
        return e;
    }

    function clearFight():Void {
        rows = new Map();
        healRows = new Map();
        shieldRows = new Map();
        casts = new Map();
        recentCasts = [];
        targets = new Map();
        loadouts = [];
        timeline = [];
        bucketSec = 1;
        deaths = [];
        haveFirst = false;
        firstMs = 0;
        lastMs = 0;
        idleArmed = false;
        idleSince = 0;
        rowsDirty = true;
        forceRows = true;
    }

    /** Automatic seal once the fight has gone idle: no damage for a while AND the game says out of combat. */
    public function update(now:Float, heroLocked:Bool, heroInCombat:Bool):FightLogEntry {
        if (!haveFirst) return null;
        var damageIdle = now - lastMs >= timing.damageIdleMs;
        var heroIdle = !heroLocked || !heroInCombat;
        if (!damageIdle || !heroIdle) {
            idleArmed = false;
            return null;
        }
        if (!idleArmed) {
            idleArmed = true;
            idleSince = now;
        }
        if (now - idleSince < timing.outOfCombatGraceMs) return null;
        var sealed = seal((lastMs - firstMs) / 1000.0);
        clearFight();
        return sealed;
    }

    /** Hard boundary (zone or character change). */
    public function endFight():FightLogEntry {
        var sealed = seal((lastMs - firstMs) / 1000.0);
        clearFight();
        return sealed;
    }

    /** Manual reset; what was fought goes to the history. */
    public function reset(now:Float):FightLogEntry {
        var sealed = seal((now - firstMs) / 1000.0);
        clearFight();
        return sealed;
    }

    function rebuildRows():Void {
        var s = snap;
        s.totalDamage = s.totalHeal = s.totalShield = 0;
        s.totalPhysical = s.totalMagic = s.totalRaw = 0;
        s.hitCount = s.critCount = s.castCount = 0;
        for (r in rows) {
            s.totalDamage += r.total;
            s.totalPhysical += r.physical;
            s.totalMagic += r.magic;
            s.totalRaw += r.raw;
            s.hitCount += r.hitCount;
            s.critCount += r.critCount;
        }
        for (r in healRows) s.totalHeal += r.total;
        for (r in shieldRows) s.totalShield += r.total;
        s.rows = sortedRows(rows, true);
        for (r in s.rows) s.castCount += r.castCount;
        s.healRows = sortedRows(healRows, false);
        s.shieldRows = sortedRows(shieldRows, false);
        s.bossDamage = 0;
        s.bossName = "";
        var top:FightTarget = null;
        for (t in targets) if (t.rank == Boss || t.rank == Miniboss) {
            s.bossDamage += t.total;
            if (top == null || t.rank > top.rank || (t.rank == top.rank && t.total > top.total)) top = t;
        }
        if (top != null) s.bossName = top.name;
        s.deaths = deaths.copy();
    }

    public function publish(now:Float, heroLocked:Bool, heroInCombat:Bool):Void {
        var s = snap;
        s.haveFight = haveFirst;
        var elapsed = 0.0, idle = 0.0;
        if (haveFirst) {
            elapsed = (now - firstMs) / 1000.0;
            if (elapsed < 0.001) elapsed = 0.001;
            idle = (now - lastMs) / 1000.0;
        }
        var damageRecent = haveFirst && now - lastMs < timing.damageIdleMs;
        s.inCombat = damageRecent || (heroLocked && heroInCombat);
        if (rowsDirty && (forceRows || now - lastRowsMs >= timing.rowsPublishIntervalMs)) {
            rebuildRows();
            rowsDirty = false;
            forceRows = false;
            lastRowsMs = now;
        }
        s.elapsedSec = elapsed;
        s.idleSec = idle;
        s.dps = elapsed > 0.001 ? s.totalDamage / elapsed : 0;
        s.hps = elapsed > 0.001 ? s.totalHeal / elapsed : 0;
        s.sps = elapsed > 0.001 ? s.totalShield / elapsed : 0;
        if (historyDirty) {
            s.history = history.copy();
            historyDirty = false;
        }
    }

    /** False when the fight is gone or favorites are at the cap. */
    public function setFavorite(id:Int, favorite:Bool):Bool {
        var fight:FightLogEntry = null;
        var favorites = 0;
        for (e in history) {
            if (e.id == id) fight = e;
            if (e.favorite) favorites++;
        }
        if (fight == null) return false;
        if (favorite && !fight.favorite && favorites >= FAVORITES_MAX) return false;
        fight.favorite = favorite;
        historyDirty = true;
        return true;
    }

    /** History as loaded from disk, newest first, oldest pushed last. */
    public function restoreHistory(e:FightLogEntry):Void {
        if (history.length >= HISTORY_MAX) return;
        e.totalPhysical = e.totalMagic = e.totalRaw = 0;
        e.castCount = 0;
        for (r in e.rows) {
            e.totalPhysical += r.physical;
            e.totalMagic += r.magic;
            e.totalRaw += r.raw;
            e.castCount += r.castCount;
        }
        history.push(e);
        if (e.id >= nextFightId) nextFightId = e.id + 1;
        historyDirty = true;
    }

    /** Marks the history changed (after an external edit such as stamping endedUnixMs). */
    public function touchHistory():Void historyDirty = true;

    /** "Lady Bee", or "Kobold +3" when others were hit too; "-" when unknown. */
    public static function targetLabel(f:FightLogEntry):String {
        if (f.targets.length == 0) return "-";
        if (f.targetCount > 1) return f.targets[0].name + " +" + (f.targetCount - 1);
        return f.targets[0].name;
    }
}

class Timing {
    public var damageIdleMs = 5000.0;
    public var outOfCombatGraceMs = 2000.0;
    public var openingCastWindowMs = 3000.0;
    public var rowsPublishIntervalMs = 100.0;

    public function new() {}
}

enum abstract DamageType(Int) to Int {
    var Unclassified = 0;
    var Physical = 1;
    var Magic = 2;
    var Raw = 3;

    /** The `affinity` sheet of data.cdb, each id walked up to its root. */
    public static function classify(affinity:String):DamageType {
        if (affinity == null || affinity == "") return Unclassified;
        return switch (affinity) {
            case "Raw": Raw;
            case "Physical", "Violence", "Earth": Physical;
            case "Magic", "Fire", "Water", "Nature", "Wind", "Chaos", "Light", "Cheese", "Shadow", "Spark", "Honey", "Flower", "Lava",
                "Electric": Magic;
            default: Unclassified;
        }
    }

    public function name():String {
        return switch (cast this : DamageType) {
            case Physical: "physical";
            case Magic: "magic";
            case Raw: "raw";
            case Unclassified: "unclassified";
        }
    }
}

enum abstract TargetRank(Int) to Int from Int {
    var Normal = 0;
    var Elite = 1;
    var Miniboss = 2;
    var Boss = 3;

    @:op(A > B) static function gt(a:TargetRank, b:TargetRank):Bool;
}

class SkillRow {
    public var skill:String;
    public var hitCount = 0;
    public var castCount = 0;
    public var total = 0.0;
    public var maxHit = 0.0;
    public var critCount = 0;
    public var physical = 0.0;
    public var magic = 0.0;
    public var raw = 0.0;

    public function new(skill:String) this.skill = skill;

    public function copy():SkillRow {
        var r = new SkillRow(skill);
        r.hitCount = hitCount;
        r.castCount = castCount;
        r.total = total;
        r.maxHit = maxHit;
        r.critCount = critCount;
        r.physical = physical;
        r.magic = magic;
        r.raw = raw;
        return r;
    }
}

class FightTarget {
    public var name:String;
    public var total = 0.0;
    public var kills = 0;
    public var rank:TargetRank;

    public function new(name:String, rank:TargetRank) {
        this.name = name;
        this.rank = rank;
    }

    public function copy():FightTarget {
        var t = new FightTarget(name, rank);
        t.total = total;
        t.kills = kills;
        return t;
    }
}

class FightLoadout {
    public var hand = "";
    public var second = "";
    public var off = "";
    public var handLevel = 0;
    public var handUpgrade = 0;

    public function new() {}

    public function copy():FightLoadout {
        var l = new FightLoadout();
        l.hand = hand;
        l.second = second;
        l.off = off;
        l.handLevel = handLevel;
        l.handUpgrade = handUpgrade;
        return l;
    }
}

class FightLogEntry {
    public var id = 0;
    public var favorite = false;
    public var endedUnixMs = 0.0;
    public var durationSec = 0.0;
    public var totalDamage = 0.0;
    public var dps = 0.0;
    public var totalHeal = 0.0;
    public var hps = 0.0;
    public var hitCount = 0;
    public var castCount = 0;
    public var totalPhysical = 0.0;
    public var totalMagic = 0.0;
    public var totalRaw = 0.0;
    public var topSkill = "";
    public var rows:Array<SkillRow> = [];
    public var healRows:Array<SkillRow> = [];
    public var totalShield = 0.0;
    public var sps = 0.0;
    public var shieldRows:Array<SkillRow> = [];
    /** Distinct names; may exceed `targets.length`. */
    public var targetCount = 0;
    public var targets:Array<FightTarget> = [];
    public var loadout = new FightLoadout();
    /** Everyone's damage during the fight (PLAYERS), biggest first. */
    public var playerCount = 0;
    public var playersTotal = 0.0;
    public var players:Array<PlayerRow> = [];
    /** Read from the C++ overlay's file; never written back there. */
    public var imported = false;
    /** Own damage on bosses and minibosses. */
    public var bossDamage = 0.0;
    /** A group fight (party, or others did a real share of the damage); set when sealed. */
    public var group = false;
    /** Set a boss record when sealed. */
    public var newRecord = false;
    public var deaths:Array<fo.logic.Deaths.DeathRecap> = [];
    /** Own damage per `timelineSec` seconds. */
    public var timeline:Array<Float> = [];
    public var timelineSec = 1.0;

    public function new() {}
}

class AggSnapshot {
    public var bossDamage = 0.0;
    public var bossName = "";
    public var deaths:Array<fo.logic.Deaths.DeathRecap> = [];
    public var haveFight = false;
    public var inCombat = false;
    public var elapsedSec = 0.0;
    public var idleSec = 0.0;
    public var totalDamage = 0.0;
    public var dps = 0.0;
    public var hps = 0.0;
    public var totalHeal = 0.0;
    public var hitCount = 0;
    public var critCount = 0;
    public var castCount = 0;
    public var totalPhysical = 0.0;
    public var totalMagic = 0.0;
    public var totalRaw = 0.0;
    public var rows:Array<SkillRow> = [];
    public var healRows:Array<SkillRow> = [];
    public var totalShield = 0.0;
    public var sps = 0.0;
    public var shieldRows:Array<SkillRow> = [];
    public var history:Array<FightLogEntry> = [];

    public function new() {}
}

class PlayerSkillRow {
    public var skill:String;
    public var hitCount = 0;
    public var critCount = 0;
    public var total = 0.0;

    public function new(skill:String) this.skill = skill;
}

class PlayerRow {
    public var uid:Float = 0; // Int64 uid as a Float: exact up to 2^53
    public var name = "";
    public var isSelf = false;
    public var inGroup = false;
    public var className = "";
    public var level = 0;
    public var total = 0.0;
    public var maxHit = 0.0;
    public var dps = 0.0;
    public var activeSec = 0.0;
    public var hitCount = 0;
    public var critCount = 0;
    public var physical = 0.0;
    public var magic = 0.0;
    public var raw = 0.0;
    public var skills:Array<PlayerSkillRow> = [];
    public var talentsRead = false;
    public var talentPoints = 0;
    public var weapons:Array<fo.logic.Build.BuildItem> = [];
    /** Kept with a fight: its saved build, by fingerprint; "" is none. */
    public var buildKey = "";
    public var build:fo.logic.Build.PlayerBuild = null;

    public function new() {}

    public function copy():PlayerRow {
        var r = new PlayerRow();
        r.uid = uid;
        r.name = name;
        r.isSelf = isSelf;
        r.inGroup = inGroup;
        r.className = className;
        r.level = level;
        r.total = total;
        r.maxHit = maxHit;
        r.dps = dps;
        r.activeSec = activeSec;
        r.hitCount = hitCount;
        r.critCount = critCount;
        r.physical = physical;
        r.magic = magic;
        r.raw = raw;
        r.talentsRead = talentsRead;
        r.talentPoints = talentPoints;
        r.weapons = [for (w in weapons) w.copy()];
        r.buildKey = buildKey;
        r.build = build;
        r.skills = [for (s in skills) {
            var c = new PlayerSkillRow(s.skill);
            c.hitCount = s.hitCount;
            c.critCount = s.critCount;
            c.total = s.total;
            c;
        }];
        return r;
    }
}
