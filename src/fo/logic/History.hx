package fo.logic;

import fo.logic.Build;
import fo.logic.CombatTracker;

/**
 * fight_history.json, in the same shape the C++ overlay writes (the fields this
 * mod knows; builds are not kept). The overlay's own file is only ever read, to
 * import it once; this mod writes its own copy under hlx/config/farever-overlay/.
 */
class History {
    static function f(o:Dynamic, k:String, d:Float = 0):Float {
        var v:Dynamic = Reflect.field(o, k);
        if (v == null) return d;
        if (Std.isOfType(v, Bool)) return v ? 1 : 0;
        return (v : Float);
    }

    static function s(o:Dynamic, k:String):String {
        var v:Dynamic = Reflect.field(o, k);
        return v == null ? "" : Std.string(v);
    }

    static function arr(o:Dynamic, k:String):Array<Dynamic> {
        var v:Dynamic = Reflect.field(o, k);
        return Std.isOfType(v, Array) ? v : [];
    }

    static function rowFrom(r:Dynamic):SkillRow {
        var x = new SkillRow(CombatTracker.clip(s(r, "skill")));
        x.hitCount = Std.int(f(r, "hit_count"));
        x.total = f(r, "total");
        x.maxHit = f(r, "max_hit");
        x.critCount = Std.int(f(r, "crit_count"));
        x.castCount = Std.int(f(r, "cast_count"));
        x.physical = f(r, "physical");
        x.magic = f(r, "magic");
        x.raw = f(r, "raw");
        return x;
    }

    static function rowTo(r:SkillRow):Dynamic {
        return {
            skill: r.skill, hit_count: r.hitCount, total: r.total, max_hit: r.maxHit, crit_count: r.critCount,
            cast_count: r.castCount, physical: r.physical, magic: r.magic, raw: r.raw
        };
    }

    public static function entryFrom(o:Dynamic, ?builds:Map<String, PlayerBuild>):FightLogEntry {
        var e = new FightLogEntry();
        e.id = Std.int(f(o, "id"));
        e.favorite = f(o, "favorite") != 0;
        e.endedUnixMs = f(o, "ended_unix_ms");
        e.durationSec = f(o, "duration_sec");
        e.totalDamage = f(o, "total_damage");
        e.dps = f(o, "dps");
        e.totalHeal = f(o, "total_heal");
        e.hps = f(o, "hps");
        e.hitCount = Std.int(f(o, "hit_count"));
        e.totalShield = f(o, "total_shield");
        e.sps = f(o, "sps");
        e.topSkill = s(o, "top_skill");
        e.loadout.hand = s(o, "weapon_hand");
        e.loadout.handLevel = Std.int(f(o, "weapon_hand_level"));
        e.loadout.handUpgrade = Std.int(f(o, "weapon_hand_upgrade"));
        e.loadout.second = s(o, "weapon_second");
        e.loadout.off = s(o, "weapon_off");
        e.targetCount = Std.int(f(o, "target_count"));
        e.targets = [for (t in arr(o, "targets")) {
            var x = new FightTarget(s(t, "name"), (Std.int(f(t, "rank")) : TargetRank));
            x.total = f(t, "total");
            x.kills = Std.int(f(t, "kills"));
            x;
        }];
        if (e.targets.length > CombatTracker.MAX_FIGHT_TARGETS) e.targets.resize(CombatTracker.MAX_FIGHT_TARGETS);
        if (e.targetCount < e.targets.length) e.targetCount = e.targets.length;
        e.playerCount = Std.int(f(o, "player_count"));
        e.playersTotal = f(o, "players_total");
        e.players = [for (p in arr(o, "players")) {
            var r = new PlayerRow();
            r.uid = f(p, "uid");
            r.name = s(p, "name");
            r.className = s(p, "class");
            r.level = Std.int(f(p, "level"));
            r.isSelf = f(p, "self") != 0;
            r.inGroup = f(p, "group") != 0;
            r.total = f(p, "total");
            r.maxHit = f(p, "max_hit");
            r.dps = f(p, "dps");
            r.activeSec = f(p, "active_sec");
            r.hitCount = Std.int(f(p, "hit_count"));
            r.critCount = Std.int(f(p, "crit_count"));
            r.physical = f(p, "physical");
            r.magic = f(p, "magic");
            r.raw = f(p, "raw");
            r.talentsRead = f(p, "talents_read") != 0;
            r.talentPoints = Std.int(f(p, "talent_points"));
            r.buildKey = s(p, "build");
            if (builds != null && builds.exists(r.buildKey)) {
                r.build = builds.get(r.buildKey);
                r.weapons = r.build.weapons();
            } else r.weapons = [for (w in arr(p, "weapons")) {
                var g = PlayerBuild.fromJson({gear: [w]}).gear[0];
                g;
            }];
            r.skills = [for (k in arr(p, "skills")) {
                var x = new PlayerSkillRow(s(k, "skill"));
                x.hitCount = Std.int(f(k, "hit_count"));
                x.critCount = Std.int(f(k, "crit_count"));
                x.total = f(k, "total");
                x;
            }];
            r;
        }];
        e.rows = [for (r in arr(o, "rows")) rowFrom(r)];
        e.healRows = [for (r in arr(o, "heal_rows")) rowFrom(r)];
        e.shieldRows = [for (r in arr(o, "shield_rows")) rowFrom(r)];
        e.imported = f(o, "imported") != 0;
        e.bossDamage = f(o, "boss_damage");
        e.group = f(o, "group") != 0;
        e.newRecord = f(o, "record") != 0;
        e.deaths = [for (d in arr(o, "deaths")) fo.logic.Deaths.DeathRecap.fromJson(d)];
        e.timeline = [for (v in arr(o, "timeline")) (v : Float)];
        e.timelineSec = f(o, "timeline_sec") > 0 ? f(o, "timeline_sec") : 1;
        return e;
    }

    public static function entryTo(e:FightLogEntry):Dynamic {
        return {
            id: e.id, ended_unix_ms: e.endedUnixMs, duration_sec: e.durationSec, total_damage: e.totalDamage, dps: e.dps,
            total_heal: e.totalHeal, hps: e.hps, hit_count: e.hitCount, total_shield: e.totalShield, sps: e.sps,
            top_skill: e.topSkill, weapon_hand: e.loadout.hand, weapon_hand_level: e.loadout.handLevel,
            weapon_hand_upgrade: e.loadout.handUpgrade, weapon_second: e.loadout.second, weapon_off: e.loadout.off,
            target_count: e.targetCount,
            targets: [for (t in e.targets) {name: t.name, total: t.total, kills: t.kills, rank: (t.rank : Int)}],
            favorite: e.favorite ? 1 : 0, imported: e.imported ? 1 : 0, player_count: e.playerCount, players_total: e.playersTotal,
            players: [for (p in e.players) {
                uid: p.uid, name: p.name, "class": p.className, level: p.level, self: p.isSelf ? 1 : 0, group: p.inGroup ? 1 : 0,
                total: p.total, max_hit: p.maxHit, dps: p.dps, active_sec: p.activeSec, hit_count: p.hitCount,
                crit_count: p.critCount, physical: p.physical, magic: p.magic, raw: p.raw,
                talents_read: p.talentsRead ? 1 : 0, talent_points: p.talentPoints,
                build: p.build != null ? p.build.fingerprint() : p.buildKey,
                skills: [for (k in p.skills) {skill: k.skill, hit_count: k.hitCount, crit_count: k.critCount, total: k.total}]
            }],
            rows: [for (r in e.rows) rowTo(r)], heal_rows: [for (r in e.healRows) rowTo(r)],
            shield_rows: [for (r in e.shieldRows) rowTo(r)],
            boss_damage: e.bossDamage, group: e.group ? 1 : 0, record: e.newRecord ? 1 : 0,
            deaths: [for (d in e.deaths) d.toJson()], timeline: e.timeline, timeline_sec: e.timelineSec
        };
    }

    public static var dropped = 0;

    static function corrupt(o:Dynamic):Bool {
        var bad = s(o, "top_skill").indexOf("{bytes") == 0;
        if (!bad) for (r in arr(o, "rows")) if (s(r, "skill").indexOf("{bytes") == 0) bad = true;
        if (bad) dropped++;
        return bad;
    }

    /** Newest first, as stored. */
    public static function parse(text:String):Array<FightLogEntry> {
        var root:Dynamic = haxe.Json.parse(text);
        var builds = new Map<String, PlayerBuild>();
        for (b in arr(root, "builds")) {
            var key = s(b, "key");
            if (key != "") builds.set(key, PlayerBuild.fromJson(b));
        }
        // Fights written by the build that saved game Strings as objects are unreadable: skip them.
        return [for (o in arr(root, "fights")) if (!corrupt(o)) entryFrom(o, builds)];
    }

    /** Builds go once each in a `builds` list, before `fights`, keyed by fingerprint; unused ones are dropped. */
    public static function stringify(history:Array<FightLogEntry>):String {
        var builds:Array<Dynamic> = [];
        var seen = new Map<String, Bool>();
        for (e in history) for (p in e.players) {
            if (p.build == null) continue;
            var k = p.build.fingerprint();
            if (seen.exists(k)) continue;
            seen.set(k, true);
            var j:Dynamic = p.build.toJson();
            j.key = k;
            builds.push(j);
        }
        return haxe.Json.stringify({version: 1, source: "farever-overlay (hlx)", builds: builds, fights: [for (e in history) entryTo(e)]}, null, " ");
    }
}
