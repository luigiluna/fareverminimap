package fo;

import fo.logic.CombatTracker;
import fo.logic.GameNames;

/** One decoded hit, ready for the trackers. Plain data: no game object is kept. */
typedef Hit = {
    var skill:String;
    var skillName:String;
    var amount:Float;
    var crit:Bool;
    var kill:Bool;
    var type:DamageType;
    var isMine:Bool;
    var playerUid:Float; // 0: not a player
    var playerName:String;
    var playerObj:Dynamic; // st.Player, for the group test
    var heroObj:Dynamic; // ent.Hero behind the hit, for the build reader (not stored)
    var targetName:String;
    var targetRank:TargetRank;
    var heal:Bool; // a heal by the local hero (only those are kept)
    var taken:Bool; // a hit a hero took: playerUid / playerName / heroObj are the victim, targetName the attacker
}

/**
 * Turns the DamageResult the client receives into a Hit. Called from a postfix on
 * ent.Unit.rpcReceiveDamage__impl: it only reads, and any failure is swallowed.
 */
class DpsCapture {
    public static var seen = 0;
    public static var dropped = 0;
    public static var hero:Dynamic;

    /** Skill icons as game tiles (lib.CssParser.getTile on the skill's inf.gfx), by skill id; null when none. */
    public static var skillIcons = new Map<String, Dynamic>();
    static var iconFailures = 0;

    static function cacheIcon(kind:String, skill:Dynamic):Void {
        if (skillIcons.exists(kind) || skill == null || iconFailures > 20) return;
        var tile:Dynamic = null;
        try {
            var gfx = G.f(G.f(skill, "inf"), "gfx");
            if (gfx != null) tile = G.scall("lib.CssParser", "getTile", [gfx, null, null]);
        } catch (e:Dynamic) {
            iconFailures++;
            Log.once("skillicon", "skill icon failed: " + Std.string(e), 2);
        }
        skillIcons.set(kind, tile);
    }

    /** Display names for skill ids, from the skill's CDB row when it has one. */
    public static var skillNames = new Map<String, String>();

    static var lastKillKey = "";
    static var lastKillAt = -1.0;

    public static function decode(dr:Dynamic, now:Float):Hit {
        seen++;
        if (dr == null) return null;
        // 0 is damage; 1 is a heal (only the local hero's are kept, for HEAL).
        var effect = G.int(G.f(dr, "effect"));
        if (effect == 1) return decodeHeal(dr);
        if (effect != 0) return drop();
        if (G.f(dr, "blocker") != null) return drop(); // InvulnerableHit, DamageDodge: nothing dealt
        var amount = G.num(G.f(dr, "_amount"));
        if (!(amount > 0)) return drop();

        var target = G.f(dr, "target");
        if (target == null) return drop();
        if (G.isA(target, "ent.Hero")) return decodeTaken(dr, target, amount);

        var src:Dynamic = G.call("st.skill.DamageResult", "get_sourceUnit", dr, []);
        var skill:Dynamic = G.f(dr, "skill");
        var origin = originSkill(skill);
        // The player behind the hit: the source unit, or the owner of a summon.
        var owner:Dynamic = src;
        if (owner != null && !G.isA(owner, "ent.Hero")) {
            var so = G.f(owner, "summonOwner");
            if (so != null) owner = so;
        }
        if ((owner == null || !G.isA(owner, "ent.Hero")) && origin != null) {
            var o = G.f(origin, "owner");
            if (o != null && !G.isA(o, "ent.Hero")) {
                var so = G.f(o, "summonOwner");
                if (so != null) o = so;
            }
            if (o != null && G.isA(o, "ent.Hero")) owner = o;
        }
        if (owner == null || !G.isA(owner, "ent.Hero")) return drop(); // a mob's hit

        var kind = origin != null ? G.str(G.f(origin, "kind")) : null;
        if (kind == null || kind == "") kind = skill != null ? G.str(G.f(skill, "kind")) : "Unknown";
        if (kind == null) kind = "Unknown";
        var display = skillNames.get(kind);
        if (display == null) {
            display = kind;
            try {
                var inf = G.f(origin != null ? origin : skill, "inf");
                var n = G.str(G.f(inf, "name"));
                if (n != null && n != "") display = n;
            } catch (_:Dynamic) {}
            skillNames.set(kind, display);
        }

        if (OverlayMod.iconsOn()) cacheIcon(kind, origin != null ? origin : skill);
        var crit = G.bool(G.f(dr, "_critical"));
        var kill = G.bool(G.f(dr, "_kill"));
        // Name from the table first ("Lady Bee" is Mokshi), the game's getName as the fallback.
        var targetKind = G.str(G.f(target, "kind"));
        var known = targetKind == null ? null : GameNames.unit(targetKind);
        var targetName:String = known != null ? known.name : null;
        if (targetName == null || targetName == "") try targetName = G.str(G.call("ent.Unit", "getName", target, [])) catch (_:Dynamic) {}
        if (targetName == null || targetName == "") targetName = targetKind;
        var rank:TargetRank = Normal;
        try {
            if (G.bool(G.call("ent.Unit", "isBoss", target, []))) rank = Boss;
            else if (G.bool(G.call("ent.Unit", "isMiniboss", target, []))) rank = Miniboss;
            else if (G.bool(G.call("ent.Unit", "isElite", target, []))) rank = Elite;
        } catch (_:Dynamic) {}
        if (known != null && known.rank > rank) rank = known.rank;

        var player = G.f(owner, "player");
        var uid = G.num(G.f(owner, "__uid"));
        var name = G.str(G.f(owner, "name"));
        if ((name == null || name == "") && player != null) name = G.str(G.f(player, "name"));

        // The same killing blow can arrive twice; keep one.
        if (kill) {
            var kk = uid + "|" + kind + "|" + amount + "|" + targetName;
            if (kk == lastKillKey && now - lastKillAt < 100) return drop();
            lastKillKey = kk;
            lastKillAt = now;
        }

        return {
            skill: kind,
            skillName: display,
            amount: amount,
            crit: crit,
            kill: kill,
            type: DamageType.classify(G.str(G.f(dr, "affinity"))),
            isMine: hero != null && owner == hero,
            playerUid: uid,
            playerName: name == null ? "?" : name,
            playerObj: player,
            heroObj: owner,
            targetName: targetName == null ? "" : targetName,
            targetRank: rank,
            heal: false,
            taken: false,
        };
    }

    /** Readable name of any unit: the name table, then the game's getName, then its kind. */
    public static function unitName(u:Dynamic):String {
        if (u == null) return "";
        var kind = G.str(G.f(u, "kind"));
        var known = kind == null ? null : GameNames.unit(kind);
        if (known != null && known.name != "") return known.name;
        var n:String = null;
        try n = G.str(G.call("ent.Unit", "getName", u, [])) catch (_:Dynamic) {}
        if (n == null || n == "") n = G.str(G.f(u, "name"));
        return n == null || n == "" ? (kind == null ? "" : kind) : n;
    }

    /** A hit on a hero (for the death recap). The meter keeps only yours and your group's. */
    static function decodeTaken(dr:Dynamic, target:Dynamic, amount:Float):Hit {
        var src:Dynamic = G.call("st.skill.DamageResult", "get_sourceUnit", dr, []);
        var skill:Dynamic = G.f(dr, "skill");
        var origin = originSkill(skill);
        var kind = origin != null ? G.str(G.f(origin, "kind")) : null;
        if (kind == null || kind == "") kind = skill != null ? G.str(G.f(skill, "kind")) : "";
        if (kind == null) kind = "";
        if (kind != "" && !skillNames.exists(kind)) {
            var display = kind;
            try {
                var n = G.str(G.f(G.f(origin != null ? origin : skill, "inf"), "name"));
                if (n != null && n != "") display = n;
            } catch (_:Dynamic) {}
            skillNames.set(kind, display);
        }
        var name = G.str(G.f(target, "name"));
        return {
            skill: kind, skillName: kind, amount: amount, crit: G.bool(G.f(dr, "_critical")), kill: G.bool(G.f(dr, "_kill")),
            type: Unclassified, isMine: hero != null && target == hero, playerUid: G.num(G.f(target, "__uid")),
            playerName: name == null ? "?" : name, playerObj: null, heroObj: target,
            targetName: unitName(src), targetRank: Normal, heal: false, taken: true,
        };
    }

    /** A heal whose source (or its summon's owner) is the local hero; null otherwise. */
    static function decodeHeal(dr:Dynamic):Hit {
        if (hero == null) return drop();
        var amount = G.num(G.f(dr, "_amount"));
        if (!(amount > 0)) return drop();
        var src:Dynamic = G.call("st.skill.DamageResult", "get_sourceUnit", dr, []);
        var skill:Dynamic = G.f(dr, "skill");
        var origin = originSkill(skill);
        var owner:Dynamic = src;
        if (owner != null && owner != hero) {
            var so = G.f(owner, "summonOwner");
            if (so != null) owner = so;
        }
        if (owner != hero && origin != null) owner = G.f(origin, "owner");
        if (owner != hero) return drop();
        var kind = origin != null ? G.str(G.f(origin, "kind")) : null;
        if (kind == null || kind == "") kind = skill != null ? G.str(G.f(skill, "kind")) : "Heal";
        if (kind == null) kind = "Heal";
        if (!skillNames.exists(kind)) {
            var display = kind;
            try {
                var n = G.str(G.f(G.f(origin != null ? origin : skill, "inf"), "name"));
                if (n != null && n != "") display = n;
            } catch (_:Dynamic) {}
            skillNames.set(kind, display);
        }
        if (OverlayMod.iconsOn()) cacheIcon(kind, origin != null ? origin : skill);
        return {
            skill: kind, skillName: skillNames.get(kind), amount: amount, crit: G.bool(G.f(dr, "_critical")), kill: false,
            type: Unclassified, isMine: true, playerUid: 0, playerName: "", playerObj: null, heroObj: null,
            targetName: "", targetRank: Normal, heal: true, taken: false,
        };
    }

    /**
     * The hero's absorb (ent.Unit.getShield, the game's own sum over statuses)
     * and the skill behind the biggest one, for the SHIELD rows.
     */
    public static function readShield(h:Dynamic):{amount:Float, kind:String} {
        var total = G.num(G.call("ent.Unit", "getShield", h, []));
        if (!(total > 0.5)) return {amount: 0, kind: ""};
        var kind = "";
        try {
            var arr = G.f(G.f(h, "statuses"), "array");
            if (arr != null && (G.isA(arr, "hl.types.ArrayDyn") || G.isA(arr, "hl.types.ArrayObj"))) {
                var best = 0.0;
                for (i in 0...Std.int(Math.min(G.alen(arr), 64))) {
                    var st = G.aget(arr, i);
                    if (st == null || !G.isA(st, "st.skill.Status")) continue;
                    var v = G.num(G.call("st.skill.Status", "getShield", st, []));
                    if (v <= best) continue;
                    best = v;
                    var src = originSkill(st);
                    kind = G.str(G.f(src != null ? src : st, "kind"));
                    if (src != null) cacheIcon(kind, src);
                }
            }
        } catch (e:Dynamic) Log.once("shieldkind", "shield kind read failed: " + Std.string(e), 2);
        return {amount: total, kind: kind == null ? "" : kind};
    }

    static inline function drop():Hit {
        dropped++;
        return null;
    }

    /** Same steps as the game's getSourceSkill: status -> instigator, summon -> its source skill, child -> parent. */
    static function originSkill(skill:Dynamic):Dynamic {
        var cur = skill;
        for (_ in 0...8) {
            if (cur == null) return null;
            if (G.isA(cur, "st.skill.Status")) {
                var next = G.f(cur, "instigatorSkill");
                if (next != null) {
                    cur = next;
                    continue;
                }
            }
            var owner = G.f(cur, "owner");
            if (owner != null && G.isA(owner, "ent.Foe")) {
                var src = G.f(owner, "summonSourceSkill");
                if (src != null && src != cur) {
                    cur = src;
                    continue;
                }
            }
            var parent = G.f(cur, "parent");
            if (parent != null && G.isA(parent, "st.skill.BaseSkill")) {
                cur = parent;
                continue;
            }
            return cur;
        }
        return cur;
    }
}

/** Polls the hero's active skills for new BaseSkill.startTime stamps (one stamp = one cast). */
class CastWatch {
    var stamps = new Map<String, Float>();
    var heroSeen:Dynamic;
    var tick = 0;

    public function new() {}

    public function poll(hero:Dynamic, onCast:String->Void):Void {
        if (hero == null) return;
        if (++tick % 2 != 0) return; // about 30 Hz
        var skills = G.f(hero, "skills");
        var n = G.alen(skills);
        var fresh = hero != heroSeen;
        heroSeen = hero;
        if (n > 96) n = 96;
        for (i in 0...n) {
            var s = G.aget(skills, i);
            if (s == null) continue;
            var kind = G.str(G.f(s, "kind"));
            if (kind == null) continue;
            var start = G.num(G.f(s, "startTime"), -1);
            var key = kind + "#" + i;
            var prev = stamps.get(key);
            stamps.set(key, start);
            if (fresh || prev == null) continue;
            if (start > prev + 0.05 && !passive(s)) onCast(kind);
        }
        if (fresh) Log.info("casts: watching " + n + " skills");
    }

    static function passive(s:Dynamic):Bool {
        var inf = G.f(s, "inf");
        var nature = G.f(inf, "nature");
        if (nature == null) return false;
        var v = G.int(nature, -1);
        // 4 Status, 5 Passive, 6 Area restart on their own (zone loads).
        return v == 4 || v == 5 || v == 6;
    }
}
