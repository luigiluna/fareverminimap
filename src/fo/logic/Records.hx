package fo.logic;

import fo.logic.CombatTracker;

/** Best boss DPS on one boss, in one mode. */
class BossRecord {
    public var boss = "";
    public var dps = 0.0;
    public var durationSec = 0.0;
    public var weapon = "";
    public var endedUnixMs = 0.0;

    public function new() {}

    public function toJson():Dynamic return {boss: boss, dps: dps, duration_sec: durationSec, weapon: weapon, ended_unix_ms: endedUnixMs};

    public static function fromJson(o:Dynamic):BossRecord {
        var r = new BossRecord();
        r.boss = o.boss == null ? "" : Std.string(o.boss);
        r.dps = o.dps == null ? 0 : (o.dps : Float);
        r.durationSec = o.duration_sec == null ? 0 : (o.duration_sec : Float);
        r.weapon = o.weapon == null ? "" : Std.string(o.weapon);
        r.endedUnixMs = o.ended_unix_ms == null ? 0 : (o.ended_unix_ms : Float);
        return r;
    }
}

/** Damage and time with one weapon in hand, in one mode. */
class WeaponStat {
    public var weapon = "";
    public var fights = 0;
    public var damage = 0.0;
    public var seconds = 0.0;
    public var best = 0.0;

    public function new() {}

    public var avg(get, never):Float;
    function get_avg() return seconds > 0 ? damage / seconds : 0;

    public function toJson():Dynamic return {weapon: weapon, fights: fights, damage: damage, seconds: seconds, best: best};

    public static function fromJson(o:Dynamic):WeaponStat {
        var w = new WeaponStat();
        w.weapon = o.weapon == null ? "" : Std.string(o.weapon);
        w.fights = o.fights == null ? 0 : Std.int((o.fights : Float));
        w.damage = o.damage == null ? 0 : (o.damage : Float);
        w.seconds = o.seconds == null ? 0 : (o.seconds : Float);
        w.best = o.best == null ? 0 : (o.best : Float);
        return w;
    }
}

/**
 * Personal bests per boss and averages per weapon, kept apart for solo and
 * group fights (a group fight: in a party with someone, or others did at
 * least GROUP_SHARE of the damage). Lives in its own file, so records outlast
 * the 30 fights of the history.
 *
 * A boss record needs the boss dead and MIN_SEC of fight; its value is the
 * damage on bosses / minibosses over the fight time (adds do not count).
 */
class Records {
    public static inline var MIN_SEC = 10.0;
    public static inline var GROUP_SHARE = 0.10;

    var bosses = [new Map<String, BossRecord>(), new Map<String, BossRecord>()];
    var weapons = [new Map<String, WeaponStat>(), new Map<String, WeaponStat>()];

    public function new() {}

    static inline function m(group:Bool) return group ? 1 : 0;

    /** Damage dealt to bosses and minibosses; from the targets when the fight predates the field. */
    public static function bossDamage(e:FightLogEntry):Float {
        if (e.bossDamage > 0) return e.bossDamage;
        var t = 0.0;
        for (x in e.targets) if (x.rank == Boss || x.rank == Miniboss) t += x.total;
        return t;
    }

    /** The boss a fight is about (top-ranked boss target), or "". */
    public static function bossOf(e:FightLogEntry):FightTarget {
        var best:FightTarget = null;
        for (x in e.targets)
            if ((x.rank == Boss || x.rank == Miniboss) && (best == null || x.rank > best.rank || (x.rank == best.rank && x.total > best.total)))
                best = x;
        return best;
    }

    public function best(boss:String, group:Bool):BossRecord return boss == null ? null : bosses[m(group)].get(boss);

    /**
     * Folds a sealed fight in. Returns true when it set a new boss record
     * (the first kill of a boss counts as one).
     */
    public function offer(e:FightLogEntry):Bool {
        if (e.durationSec < MIN_SEC || e.imported && e.totalDamage <= 0) return false;
        var g = m(e.group);
        if (e.loadout.hand != "") {
            var w = weapons[g].get(e.loadout.hand);
            if (w == null) {
                w = new WeaponStat();
                w.weapon = e.loadout.hand;
                weapons[g].set(w.weapon, w);
            }
            w.fights++;
            w.damage += e.totalDamage;
            w.seconds += e.durationSec;
            if (e.dps > w.best) w.best = e.dps;
        }
        var b = bossOf(e);
        if (b == null || b.kills <= 0) return false;
        var dps = bossDamage(e) / e.durationSec;
        var cur = bosses[g].get(b.name);
        if (cur != null && cur.dps >= dps) return false;
        var r = new BossRecord();
        r.boss = b.name;
        r.dps = dps;
        r.durationSec = e.durationSec;
        r.weapon = e.loadout.hand;
        r.endedUnixMs = e.endedUnixMs;
        bosses[g].set(b.name, r);
        return true;
    }

    /** Bosses with a record in either mode, best first. */
    public function bossNames():Array<String> {
        var seen = new Map<String, Float>();
        for (g in 0...2) for (r in bosses[g]) seen.set(r.boss, Math.max(r.dps, seen.exists(r.boss) ? seen.get(r.boss) : 0));
        var names = [for (k in seen.keys()) k];
        names.sort((a, b) -> seen.get(a) > seen.get(b) ? -1 : (seen.get(a) < seen.get(b) ? 1 : (a < b ? -1 : 1)));
        return names;
    }

    public function weapon(name:String, group:Bool):WeaponStat return weapons[m(group)].get(name);

    /** Weapons used in either mode, most time first. */
    public function weaponNames():Array<String> {
        var secs = new Map<String, Float>();
        for (g in 0...2) for (w in weapons[g]) secs.set(w.weapon, (secs.exists(w.weapon) ? secs.get(w.weapon) : 0) + w.seconds);
        var names = [for (k in secs.keys()) k];
        names.sort((a, b) -> secs.get(a) > secs.get(b) ? -1 : (secs.get(a) < secs.get(b) ? 1 : (a < b ? -1 : 1)));
        return names;
    }

    public var isEmpty(get, never):Bool;
    function get_isEmpty() {
        for (g in 0...2) {
            if (bosses[g].iterator().hasNext()) return false;
            if (weapons[g].iterator().hasNext()) return false;
        }
        return true;
    }

    public function stringify():String {
        inline function list<T:{function toJson():Dynamic;}>(mp:Map<String, T>) return [for (x in mp) x.toJson()];
        return haxe.Json.stringify({
            version: 1,
            solo: {bosses: list(bosses[0]), weapons: list(weapons[0])},
            group: {bosses: list(bosses[1]), weapons: list(weapons[1])}
        }, null, " ");
    }

    public static function parse(text:String):Records {
        var r = new Records();
        var o:Dynamic = haxe.Json.parse(text);
        for (g in 0...2) {
            var part:Dynamic = Reflect.field(o, g == 0 ? "solo" : "group");
            if (part == null) continue;
            var bs:Array<Dynamic> = Std.isOfType(part.bosses, Array) ? part.bosses : [];
            for (b in bs) {
                var x = BossRecord.fromJson(b);
                if (x.boss != "") r.bosses[g].set(x.boss, x);
            }
            var ws:Array<Dynamic> = Std.isOfType(part.weapons, Array) ? part.weapons : [];
            for (w in ws) {
                var x = WeaponStat.fromJson(w);
                if (x.weapon != "") r.weapons[g].set(x.weapon, x);
            }
        }
        return r;
    }
}
