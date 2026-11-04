import fo.logic.CombatTracker;
import fo.logic.Deaths;
import fo.logic.History;
import fo.logic.PlayerMeter;
import fo.logic.Records;

/** Deaths, boss records, weapon averages, the damage timeline and their history fields. */
class TestRecords {
    static inline function check(c:Bool, ?pos:haxe.PosInfos) T.check(c, pos);

    public static function run():Void {
        deathRecap();
        deathDedupAndWindow();
        timelineBuckets();
        bossDamageAndDeathsInFight();
        records();
        recordsJson();
        historyFields();
        othersShare();
    }

    static function deathRecap() {
        var d = new DeathTracker();
        d.onTaken(1000, 7, "Slam", "Reblochonk", 300, false);
        d.onTaken(2000, 7, "Bite", "Rat", 50, true);
        d.onTaken(2500, 8, "Slam", "Reblochonk", 999, false); // someone else
        var r = d.onDeath(2600, 7, "Hero", true);
        check(r != null && r.isSelf && r.name == "Hero");
        check(r.hits.length == 2);
        check(r.hits[0].skill == "Bite" && r.hits[0].crit && T.near(r.hits[0].agoSec, 0.6)); // newest first
        check(r.killer == "Rat");
        check(T.near(r.total(), 350));
        var txt = DeathTracker.describe(r);
        check(txt.indexOf("killed by Rat - Bite 50 crit") >= 0);
        // The buffer is spent: a later death starts empty.
        var r2 = d.onDeath(9000, 7, "Hero", true);
        check(r2 != null && r2.hits.length == 0);
        check(DeathTracker.describe(r2).indexOf("no hits") >= 0);
    }

    static function deathDedupAndWindow() {
        var d = new DeathTracker();
        for (i in 0...12) d.onTaken(i * 100, 1, "Hit" + i, "Mob", 10, false);
        var r = d.onDeath(1200, 1, "A", false);
        check(r.hits.length == DeathTracker.MAX_HITS);
        check(r.hits[0].skill == "Hit11");
        check(d.onDeath(2000, 1, "A", false) == null); // reported twice
        check(d.onDeath(5000, 1, "A", false) != null);
        d.onTaken(0, 2, "Old", "Mob", 10, false);
        d.onTaken(15000, 2, "New", "Mob", 10, false);
        var r3 = d.onDeath(15100, 2, "B", false);
        check(r3.hits.length == 1 && r3.hits[0].skill == "New");
        check(DeathTracker.clock(75.4) == "1:15");
    }

    static function timelineBuckets() {
        var t = new CombatTracker();
        t.onDamage(0, "A", 100, false, Physical);
        t.onDamage(500, "A", 50, false, Physical);
        t.onDamage(2100, "A", 30, false, Physical);
        var e = t.reset(3000);
        check(e.timelineSec == 1);
        check(e.timeline.length == 3 && e.timeline[0] == 150 && e.timeline[1] == 0 && e.timeline[2] == 30);
        // Long fight: resolution halves, the sum stays.
        var t2 = new CombatTracker();
        var sum = 0.0;
        for (i in 0...700) {
            t2.onDamage(i * 1000, "A", 10, false, Physical);
            t2.onTarget("Boss", Boss, 10, false);
            sum += 10;
        }
        var e2 = t2.reset(700000);
        check(e2.timelineSec == 4);
        check(e2.timeline.length <= CombatTracker.TIMELINE_MAX);
        var got = 0.0;
        for (v in e2.timeline) got += v;
        check(T.near(got, sum));
        // The next fight starts back at 1 s.
        t2.onDamage(800000, "A", 5, false, Physical);
        check(t2.reset(801000).timelineSec == 1);
    }

    static function bossDamageAndDeathsInFight() {
        var t = new CombatTracker();
        var d = new DeathTracker();
        t.onDeath(0, d.onDeath(0, 1, "Early", false)); // no fight yet: dropped
        t.onDamage(1000, "A", 100, false, Physical);
        t.onTarget("Rat", Normal, 100, true);
        t.onDamage(2000, "A", 400, false, Physical);
        t.onTarget("Reblochonk", Boss, 400, false);
        t.publish(2000, true, true);
        check(T.near(t.snap.bossDamage, 400) && t.snap.bossName == "Reblochonk");
        d.onTaken(2500, 1, "Slam", "Reblochonk", 200, false);
        t.onDeath(3500, d.onDeath(3500, 1, "Drakon", false));
        t.publish(3600, true, true);
        check(t.snap.deaths.length == 1 && T.near(t.snap.deaths[0].atSec, 2.5));
        var e = t.reset(4000);
        check(T.near(e.bossDamage, 400));
        check(e.deaths.length == 1 && e.deaths[0].name == "Drakon");
        t.onDamage(5000, "A", 1, false, Physical);
        check(t.reset(5100).deaths.length == 0);
    }

    static function fight(boss:String, dmgBoss:Float, dmgAdds:Float, sec:Float, killed:Bool, group:Bool, weapon:String):FightLogEntry {
        var e = new FightLogEntry();
        e.durationSec = sec;
        e.totalDamage = dmgBoss + dmgAdds;
        e.dps = e.totalDamage / sec;
        e.group = group;
        e.loadout.hand = weapon;
        if (boss != null) {
            var b = new FightTarget(boss, Boss);
            b.total = dmgBoss;
            b.kills = killed ? 1 : 0;
            e.targets.push(b);
        }
        if (dmgAdds > 0) {
            var a = new FightTarget("Add", Normal);
            a.total = dmgAdds;
            e.targets.push(a);
        }
        return e;
    }

    static function records() {
        var r = new Records();
        check(r.isEmpty);
        check(r.offer(fight("King", 3000, 1000, 10, true, false, "Fangs"))); // first kill = record, 300 boss DPS
        check(T.near(r.best("King", false).dps, 300));
        check(r.best("King", true) == null); // modes apart
        check(!r.offer(fight("King", 2000, 0, 10, true, false, "Fangs"))); // worse
        check(!r.offer(fight("King", 9000, 0, 10, false, false, "Fangs"))); // boss not dead
        check(!r.offer(fight("King", 9000, 0, 5, true, false, "Fangs"))); // too short
        check(r.offer(fight("King", 4000, 0, 10, true, true, "Moon"))); // group record
        check(r.offer(fight("King", 3500, 0, 10, true, false, "Moon")));
        check(T.near(r.best("King", false).dps, 350) && r.best("King", false).weapon == "Moon");
        check(!r.offer(fight(null, 0, 5000, 20, false, false, "Fangs"))); // trash fight: weapons only
        var w = r.weapon("Fangs", false);
        // Fangs solo: fights 1 (10 s, 4000), 2 (10 s, 2000), 3 (boss alive, 10 s, 9000), trash (20 s, 5000); the 5 s one is out.
        check(w.fights == 4 && T.near(w.avg, 20000 / 50.0) && T.near(w.best, 900));
        check(r.weapon("Moon", true).fights == 1);
        check(r.bossNames().join(",") == "King");
        check(r.weaponNames()[0] == "Fangs");
    }

    static function recordsJson() {
        var r = new Records();
        r.offer(fight("King", 3000, 0, 10, true, false, "Fangs"));
        r.offer(fight("Queen", 1000, 0, 10, true, true, "Moon"));
        var back = Records.parse(r.stringify());
        check(T.near(back.best("King", false).dps, 300) && back.best("King", false).weapon == "Fangs");
        check(T.near(back.best("Queen", true).dps, 100));
        check(back.weapon("Moon", true).fights == 1);
        check(Records.parse("{}").isEmpty);
    }

    static function historyFields() {
        var e = fight("King", 3000, 500, 12, true, true, "Fangs");
        e.id = 4;
        e.bossDamage = 3000;
        e.newRecord = true;
        e.timeline = [100, 0, 250];
        e.timelineSec = 2;
        var d = new DeathRecap();
        d.name = "Drakon";
        d.atSec = 8.5;
        var h = new TakenHit();
        h.skill = "Slam";
        h.source = "King";
        h.amount = 400;
        h.crit = true;
        h.agoSec = 0.3;
        d.hits.push(h);
        e.deaths.push(d);
        e.rows.push(new SkillRow("A"));
        var back = History.parse(History.stringify([e]))[0];
        check(T.near(back.bossDamage, 3000) && back.group && back.newRecord);
        check(back.timeline.length == 3 && back.timeline[2] == 250 && back.timelineSec == 2);
        check(back.deaths.length == 1 && back.deaths[0].name == "Drakon" && T.near(back.deaths[0].atSec, 8.5));
        check(back.deaths[0].hits[0].crit && back.deaths[0].hits[0].source == "King" && T.near(back.deaths[0].hits[0].agoSec, 0.3));
        // Old entries: no fields, sane defaults; boss damage from the targets.
        var old = History.parse('{"fights":[{"id":1,"duration_sec":5,"rows":[{"skill":"A","total":1}],"targets":[{"name":"K","rank":3,"total":70}]}]}')[0];
        check(old.timeline.length == 0 && old.timelineSec == 1 && old.deaths.length == 0 && !old.group && !old.newRecord);
        check(T.near(Records.bossDamage(old), 70));
    }

    static function othersShare() {
        var m = new PlayerMeter(10000, 0);
        check(m.othersShare() == 0);
        m.onHit(0, 1, "Me", true, "A", 900, false, Physical);
        m.onHit(0, 2, "You", false, "A", 100, false, Physical);
        check(T.near(m.othersShare(), 0.1));
    }
}
