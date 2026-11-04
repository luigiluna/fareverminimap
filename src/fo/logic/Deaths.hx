package fo.logic;

/** One hit a hero took, for the death recap. */
class TakenHit {
    public var skill = "";
    public var source = "";
    public var amount = 0.0;
    public var crit = false;
    /** Seconds before the death (0 = the killing blow). */
    public var agoSec = 0.0;
    var atMs = 0.0;

    public function new() {}

    public static function make(atMs:Float, skill:String, source:String, amount:Float, crit:Bool):TakenHit {
        var h = new TakenHit();
        h.atMs = atMs;
        h.skill = CombatTracker.clip(skill);
        h.source = CombatTracker.clip(source);
        h.amount = amount;
        h.crit = crit;
        return h;
    }

    public function at(deathMs:Float):TakenHit {
        var h = make(atMs, skill, source, amount, crit);
        h.agoSec = Math.max(0, Math.round((deathMs - atMs) / 100) / 10);
        return h;
    }

    public function toJson():Dynamic return {skill: skill, source: source, amount: amount, crit: crit ? 1 : 0, ago: agoSec};

    public static function fromJson(o:Dynamic):TakenHit {
        var h = new TakenHit();
        h.skill = o.skill == null ? "" : Std.string(o.skill);
        h.source = o.source == null ? "" : Std.string(o.source);
        h.amount = o.amount == null ? 0 : (o.amount : Float);
        h.crit = o.crit != null && (o.crit : Float) != 0;
        h.agoSec = o.ago == null ? 0 : (o.ago : Float);
        return h;
    }
}

/** A hero's death: who, when in the fight, and the last hits taken (newest first). */
class DeathRecap {
    public var name = "";
    public var isSelf = false;
    /** Seconds into the fight; -1 when it happened outside one. */
    public var atSec = -1.0;
    public var hits:Array<TakenHit> = [];

    public function new() {}

    public var killer(get, never):String;
    function get_killer() return hits.length == 0 ? "" : (hits[0].source != "" ? hits[0].source : hits[0].skill);

    public function total():Float {
        var t = 0.0;
        for (h in hits) t += h.amount;
        return t;
    }

    public function toJson():Dynamic return {name: name, self: isSelf ? 1 : 0, at: atSec, hits: [for (h in hits) h.toJson()]};

    public static function fromJson(o:Dynamic):DeathRecap {
        var d = new DeathRecap();
        d.name = o.name == null ? "" : Std.string(o.name);
        d.isSelf = o.self != null && (o.self : Float) != 0;
        d.atSec = o.at == null ? -1 : (o.at : Float);
        var hs:Array<Dynamic> = Std.isOfType(o.hits, Array) ? o.hits : [];
        d.hits = [for (h in hs) TakenHit.fromJson(h)];
        return d;
    }
}

/**
 * Keeps the last hits each hero took, and turns a death into a recap. A death
 * can be reported twice (the killing blow's flag and Unit.onDeath): the second
 * one within a few seconds is ignored.
 */
class DeathTracker {
    public static inline var MAX_HITS = 8;
    public static inline var WINDOW_MS = 10000.0;
    static inline var DEDUP_MS = 3000.0;

    var taken = new Map<String, Array<TakenHit>>();
    var takenAt = new Map<String, Array<Float>>();
    var lastDeath = new Map<String, Float>();

    public function new() {}

    static inline function key(uid:Float) return Std.string(uid);

    public function onTaken(now:Float, uid:Float, skill:String, source:String, amount:Float, crit:Bool):Void {
        if (!(amount > 0)) return;
        var k = key(uid);
        var l = taken.get(k), t = takenAt.get(k);
        if (l == null) {
            l = [];
            t = [];
            taken.set(k, l);
            takenAt.set(k, t);
        }
        l.push(TakenHit.make(now, skill, source, amount, crit));
        t.push(now);
        while (l.length > MAX_HITS || (t.length > 0 && now - t[0] > WINDOW_MS)) {
            l.shift();
            t.shift();
        }
    }

    /** Null when the same hero was already reported dead a moment ago. */
    public function onDeath(now:Float, uid:Float, name:String, isSelf:Bool):DeathRecap {
        var k = key(uid);
        var last = lastDeath.get(k);
        if (last != null && now - last < DEDUP_MS) return null;
        lastDeath.set(k, now);
        var d = new DeathRecap();
        d.name = CombatTracker.clip(name);
        d.isSelf = isSelf;
        var l = taken.get(k), t = takenAt.get(k);
        if (l != null) {
            var i = l.length - 1;
            while (i >= 0) {
                if (now - t[i] <= WINDOW_MS) d.hits.push(l[i].at(now));
                i--;
            }
            taken.remove(k);
            takenAt.remove(k);
        }
        return d;
    }

    /** Recap as tooltip text. */
    public static function describe(d:DeathRecap, ?skillName:String->String):String {
        var nm = skillName == null ? (s:String) -> s : skillName;
        var when = d.atSec >= 0 ? " at " + clock(d.atSec) : "";
        var s = d.name + " died" + when;
        if (d.hits.length == 0) return s + "\n(no hits seen before it)";
        var k = d.hits[0];
        s += "\nkilled by " + (k.source != "" ? k.source + " - " : "") + nm(k.skill) + " " + Math.round(k.amount) + (k.crit ? " crit" : "");
        s += "\nlast " + d.hits.length + " hits, " + Math.round(d.total()) + " damage:";
        for (h in d.hits)
            s += "\n  -" + h.agoSec + "s  " + nm(h.skill) + (h.source != "" ? " (" + h.source + ")" : "") + "  " + Math.round(h.amount) + (h.crit ? " crit" : "");
        return s;
    }

    public static function clock(sec:Float):String {
        var m = Std.int(sec / 60), r = Std.int(sec - m * 60);
        return m + ":" + (r < 10 ? "0" : "") + r;
    }
}
