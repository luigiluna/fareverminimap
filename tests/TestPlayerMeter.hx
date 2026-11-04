import fo.logic.Build;
import fo.logic.CombatTracker;
import fo.logic.GameNames;
import fo.logic.History;
import fo.logic.PlayerMeter;

/** Port of repo/tools/test_player_meter.cpp, plus the generated name tables and builds in the history file. */
class TestPlayerMeter {
    static inline function near(a:Float, b:Float) return T.near(a, b);
    static inline function check(c:Bool, ?pos:haxe.PosInfos) T.check(c, pos);

    static function noThrottle() return new PlayerMeter(10000, 0);

    static function hit(m:PlayerMeter, now:Float, uid:Float, name:String, skill:String, amount:Float, crit = false, ?type:DamageType,
            self = false) {
        m.onHit(now, uid, name, self, skill, amount, crit, type == null ? Physical : type);
    }

    public static function run():Void {
        fightPlayersKeepSelfAndGroup();
        ranks();
        dpsActiveTime();
        idleKeepsNumbers();
        steadyHits();
        resetDespiteThrottle();
        caps();
        largeClock();
        longNames();
        builds();
        talentsSort();
        slotNames();
        rowsCarryWeapons();
        fingerprint();
        tables();
        historyBuilds();
        talentPointsSplit();
    }

    static function makeBuild(uid:Float, cls:String, level:Int):PlayerBuild {
        var b = new PlayerBuild();
        b.uid = uid;
        b.className = cls;
        b.level = level;
        return b;
    }

    static function builds() {
        var m = new PlayerMeter(10000, 0);
        check(m.build(7) == null);
        m.onHit(1000, 7, "Rulo", false, "Skill", 10, false, Physical);
        m.publish(1000);
        check(m.snap.rows[0].className == "");
        m.onBuild(makeBuild(7, "Warrior", 25));
        m.publish(1001);
        check(m.snap.rows[0].className == "Warrior");
        check(m.snap.rows[0].level == 25);
        m.reset();
        m.publish(1002);
        check(m.snap.rows.length == 0);
        check(m.build(7) != null);
        m.onHit(2000, 7, "Rulo", false, "Skill", 10, false, Physical);
        m.publish(2000);
        check(m.snap.rows[0].className == "Warrior");
        m.onBuild(makeBuild(7, "Warrior", 26));
        check(m.build(7).level == 26);
        for (uid in 100...1100) m.onBuild(makeBuild(uid, "Mage", 1));
        check(m.build(1099) != null);
    }

    static function talentsSort() {
        var b = new PlayerBuild();
        for (r in [{n: "C", b: 2, t: 1}, {n: "A", b: 1, t: 3}, {n: "Root", b: 0, t: 0}, {n: "B", b: 1, t: 1}]) b.talents.push(new BuildTalent(r.n, 1, r.b, r.t));
        b.sortTalents();
        check(b.talents[0].name == "Root");
        check(b.talents[1].name == "B");
        check(b.talents[2].name == "A");
        check(b.talents[3].name == "C");
    }

    static function slotNames() {
        check(PlayerBuild.slotName(0) == "Weapon 1");
        check(PlayerBuild.slotName(2) == "Off-hand");
        check(PlayerBuild.slotName(14) == "Ring");
        check(PlayerBuild.slotName(15) == "");
        check(PlayerBuild.slotName(-1) == "");
    }

    static function rowsCarryWeapons() {
        var m = new PlayerMeter();
        var b = new PlayerBuild();
        b.uid = 5;
        b.talentsRead = true;
        b.talentPoints = 9;
        for (i in 0...4) {
            var g = new BuildItem();
            g.slot = i;
            g.name = "Item" + i;
            b.gear.push(g);
        }
        m.onBuild(b);
        m.onHit(1000, 5, "A", false, "Skill", 1, false, Physical);
        m.publishNow(1000);
        var r = m.snap.rows[0];
        check(r.weapons.length == PlayerBuild.MAX_WEAPONS);
        check(r.weapons[2].name == "Item2");
        check(r.talentsRead && r.talentPoints == 9);
        m.reset();
        m.onHit(2000, 6, "B", false, "Skill", 1, false, Physical);
        m.publishNow(2000);
        check(m.snap.rows[0].weapons.length == 0);
        check(!m.snap.rows[0].talentsRead);
    }

    static function fingerprint() {
        function make() {
            var a = new PlayerBuild();
            a.uid = 5;
            a.name = "A";
            var g = new BuildItem();
            g.id = "Axe";
            a.gear.push(g);
            a.talents.push(new BuildTalent("T", 1, 0, 0));
            return a;
        }
        var key = make().fingerprint();
        check(key != "" && key != "0");
        check(make().fingerprint() == key);
        var b = make();
        b.gear[0].upgrade = 1;
        check(b.fingerprint() != key);
        b = make();
        b.talents[0].rank = 2;
        check(b.fingerprint() != key);
        b = make();
        b.uid = 6;
        check(b.fingerprint() != key);
        b = make();
        b.gear = [];
        check(b.fingerprint() != key);
        b = make();
        b.name = "Ab";
        var c = make();
        c.name = "A";
        c.className = "b";
        check(b.fingerprint() != c.fingerprint()); // "ab"+"" differs from "a"+"b"
    }

    static function tables() {
        check(GameNames.count("U") == 500 && GameNames.count("I") == 1094 && GameNames.count("T") == 88);
        check(GameNames.item("Axe_Boomerang") == "Cheese Moon");
        var ic = GameNames.icon("Axe_Boomerang");
        check(ic != null && ic.rarity == Rare && ic.cell == 4);
        check(GameNames.unit("Bee_Prisoner").name == "Apix Prisoner");
        var t = GameNames.talent("Mage_Talent_Amplification");
        check(t != null && t.name == "Amplification" && t.branch == 2 && t.tier == 3);
        check(GameNames.classCell("Warrior") == 3);
        check(GameNames.skill("AddToCollection") == "Add to Collection");
        check(GameNames.humanize("Infusion_CritChance", "Infusion_") == "Crit Chance");
        check(GameNames.skill("Never_Seen_Skill") == "Never Seen Skill");
    }

    static function historyBuilds() {
        var text = sys.io.File.getContent("tests/fixtures/fight_history_overlay.json");
        var raw:Dynamic = haxe.Json.parse(text);
        var fights = History.parse(text);
        // Every player of the overlay's file points at a build it also saved.
        var withBuild = 0, keyed = 0;
        for (e in fights) for (p in e.players) {
            if (p.buildKey != "" && p.buildKey != "0") keyed++;
            if (p.build != null) withBuild++;
        }
        check(keyed > 0 && withBuild == keyed);
        for (e in fights) for (p in e.players) if (p.build != null) check(p.weapons.length == p.build.weapons().length);
        // Round trip: same builds, deduplicated.
        var out = History.stringify(fights);
        var again = History.parse(out);
        var j:Dynamic = haxe.Json.parse(out);
        var keys = new Map<String, Bool>();
        for (b in (j.builds : Array<Dynamic>)) {
            check(!keys.exists(b.key));
            keys.set(b.key, true);
        }
        for (i in 0...fights.length) for (k in 0...fights[i].players.length) {
            var a = fights[i].players[k].build, b = again[i].players[k].build;
            if (a == null) {
                check(b == null);
                continue;
            }
            check(b != null && a.fingerprint() == b.fingerprint());
            check(a.gear.length == b.gear.length && a.talents.length == b.talents.length);
        }
    }

    static function ranks() {
        var m = noThrottle();
        hit(m, 1000, 1, "Hero", "Bow_Base_Attack2", 100, true, Physical, true);
        hit(m, 2000, 2, "Lichking", "GS_Nova_Skill1", 900, true, Raw);
        hit(m, 3000, 1, "Hero", "Bow_Base_Attack3", 100, false, Magic, true);
        m.publish(3000);
        var s = m.snap;
        check(s.haveData && s.active);
        check(s.playerCount == 2 && s.rows.length == 2);
        check(near(s.totalDamage, 1100));
        check(near(s.elapsedSec, 2.0));
        check(s.rows[0].name == "Lichking");
        check(!s.rows[0].isSelf);
        check(near(s.rows[0].raw, 900));
        var me = s.rows[1];
        check(me.isSelf && me.uid == 1);
        check(me.hitCount == 2 && me.critCount == 1);
        check(near(me.physical, 100) && near(me.magic, 100));
        check(near(me.activeSec, 2.0) && near(me.dps, 100));
        check(me.skills.length == 1);
        check(me.skills[0].skill == "Bow_Base_Attack");
        check(me.skills[0].hitCount == 2 && me.skills[0].critCount == 1);
    }

    static function dpsActiveTime() {
        var m = noThrottle();
        hit(m, 0, 1, "Early", "A", 100);
        hit(m, 7000, 2, "Late", "A", 400);
        hit(m, 8000, 1, "Early", "A", 700);
        hit(m, 8500, 3, "Once", "A", 50);
        hit(m, 9000, 2, "Late", "A", 500);
        m.publish(9000);
        var s = m.snap;
        check(s.rows[0].name == "Late" && near(s.rows[0].dps, 450));
        check(s.rows[1].name == "Early" && near(s.rows[1].dps, 100));
        check(s.rows[2].name == "Once" && near(s.rows[2].dps, 50));
    }

    static function idleKeepsNumbers() {
        var m = noThrottle();
        hit(m, 1000, 1, "A", "X", 100);
        m.publish(5000);
        check(m.snap.active);
        m.publish(11000);
        check(!m.snap.active);
        check(m.snap.haveData);
        check(m.snap.rows.length == 1);
        hit(m, 12000, 2, "B", "Y", 5);
        m.publish(12001);
        check(m.snap.active);
        check(m.snap.playerCount == 1);
        check(m.snap.rows[0].name == "B");
        check(near(m.snap.totalDamage, 5));
    }

    static function steadyHits() {
        var m = noThrottle();
        var t = 0;
        while (t <= 60000) {
            hit(m, t, 1, "A", "X", 1);
            t += 5000;
        }
        m.publish(60000);
        check(m.snap.rows[0].hitCount == 13);
    }

    static function resetDespiteThrottle() {
        var m = new PlayerMeter();
        m.publish(1000);
        hit(m, 1300, 1, "A", "X", 1);
        m.publish(1300);
        check(m.snap.rows.length == 1);
        hit(m, 1310, 1, "A", "X", 1);
        m.publish(1310);
        check(near(m.snap.totalDamage, 1));
        m.publish(1560);
        check(near(m.snap.totalDamage, 2));
        m.reset();
        m.publish(1561);
        check(!m.snap.haveData);
        check(m.snap.rows.length == 0);
        check(near(m.snap.totalDamage, 0));
    }

    static function caps() {
        var m = noThrottle();
        var players = PlayerMeter.MAX_ROWS + 6;
        for (i in 1...players + 1) hit(m, 1000, i, "P" + i, "X", i);
        var skills = 100;
        for (i in 0...skills) hit(m, 1000, 999, "Many", "S" + i, 1000);
        m.publish(2000);
        var s = m.snap;
        check(s.playerCount == players + 1);
        check(s.rows.length == PlayerMeter.MAX_ROWS);
        check(near(s.totalDamage, players * (players + 1) / 2.0 + skills * 1000.0));
        check(s.rows[0].name == "Many");
        check(near(s.rows[0].total, skills * 1000.0));
        check(s.rows[0].skills.length == PlayerMeter.MAX_SKILL_ROWS);
        check(s.rows[1].uid == players);
    }

    static function largeClock() {
        var m = noThrottle();
        var start = 4294967040.0 * 1000;
        hit(m, start, 1, "A", "X", 300);
        hit(m, start + 3000, 1, "A", "X", 300);
        m.publish(start + 3000);
        check(near(m.snap.elapsedSec, 3.0));
        check(near(m.snap.rows[0].dps, 200));
        check(m.snap.active);
    }

    static function longNames() {
        var m = noThrottle();
        var long = StringTools.lpad("", "x", 200);
        hit(m, 1, 1, long, long, 1);
        m.publish(2);
        check(m.snap.rows[0].name.length == 63);
        check(m.snap.rows[0].skills[0].skill.length == 63);
    }

    static function fightPlayersKeepSelfAndGroup() {
        var m = new PlayerMeter();
        m.onHit(1000, 1, "Me", true, "Skill", 1, false, Physical);
        m.onHit(1000, 2, "Friend", false, "Skill", 2, false, Physical);
        for (uid in 100...128) m.onHit(1000, uid, "Stranger", false, "Skill", 1000.0 + uid, false, Physical);
        m.publishNow(1000);
        var fight = new FightLogEntry();
        PlayerMeter.fillFightPlayers(m.snap, [2], fight);
        check(fight.playerCount == 30);
        check(fight.players.length == PlayerMeter.MAX_FIGHT_PLAYERS);
        check(fight.players[0].uid == 127);
        var last = fight.players[PlayerMeter.MAX_FIGHT_PLAYERS - 1];
        var prev = fight.players[PlayerMeter.MAX_FIGHT_PLAYERS - 2];
        check(last.isSelf);
        check(prev.uid == 2 && prev.inGroup);
        check(!fight.players[0].inGroup);
        var expected = 3.0;
        for (uid in 100...128) expected += 1000.0 + uid;
        check(near(fight.playersTotal, expected));
    }

    /** Spent = total - free; what the listed ranks do not cover is "unlisted". Old saves (no talent_free) stay unknown. */
    static function talentPointsSplit():Void {
        var b = new PlayerBuild();
        b.talentsRead = true;
        b.talentPoints = 12;
        b.talentTotal = 16;
        check(b.unlistedPoints() == 0); // free unknown
        b.talentFree = 4;
        check(b.unlistedPoints() == 0); // 12 spent, all listed
        b.talentFree = 1;
        check(b.unlistedPoints() == 3);
        b.talentFree = 20; // inconsistent read: never negative
        check(b.unlistedPoints() == 0);
        b.talentFree = 1;
        var back = PlayerBuild.fromJson(haxe.Json.parse(haxe.Json.stringify(b.toJson())));
        check(back.talentFree == 1 && back.talentTotal == 16 && back.unlistedPoints() == 3);
        var old = PlayerBuild.fromJson(haxe.Json.parse('{"talents_read":1,"talent_points":5,"talent_total":9}'));
        check(old.talentFree == -1 && old.unlistedPoints() == 0);
    }
}
