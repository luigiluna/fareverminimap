import fo.logic.CombatTracker;

/** Port of repo/tools/test_combat_tracker.cpp. */
class TestCombatTracker {
    static function noThrottle():Timing {
        var t = new Timing();
        t.rowsPublishIntervalMs = 0;
        return t;
    }

    static function row(s:AggSnapshot, skill:String):SkillRow {
        for (r in s.rows) if (r.skill == skill) return r;
        return null;
    }

    static inline function near(a:Float, b:Float) return T.near(a, b);
    static inline function check(c:Bool, ?pos:haxe.PosInfos) T.check(c, pos);

    public static function run():Void {
        targetsNameTheFight();
        singleOrNoTargetLabel();
        contextIgnoredOutsideFight();
        weaponThatDealtMost();
        contextSurvivesRestore();
        affinity();
        baseAttackChain();
        metrics();
        unclassified();
        casts();
        autoResetNeedsBothSignals();
        recentDamageKeepsOpen();
        manualReset();
        hardBoundary();
        heals();
        largeClock();
        throttle();
        manySkills();
        longNames();
        historyRingAndRestore();
        favorites();
    }

    static function affinity() {
        check(DamageType.classify("Raw") == Raw);
        check(DamageType.classify("Physical") == Physical);
        check(DamageType.classify("Magic") == Magic);
        check(DamageType.classify("Violence") == Physical);
        check(DamageType.classify("Earth") == Physical);
        check(DamageType.classify("Fire") == Magic);
        check(DamageType.classify("Electric") == Magic);
        check(DamageType.classify(null) == Unclassified);
        check(DamageType.classify("") == Unclassified);
        check(DamageType.classify("Plasma") == Unclassified);
    }

    static function baseAttackChain() {
        check(CombatTracker.normaliseSkill("DS_Base_Attack_3") == "DS_Base_Attack");
        check(CombatTracker.normaliseSkill("Bow_Base_Attack2") == "Bow_Base_Attack");
        check(CombatTracker.normaliseSkill("DS_Bladeleaf_Skill1") == "DS_Bladeleaf_Skill1");
    }

    static function metrics() {
        var t = new CombatTracker(noThrottle());
        check(t.onDamage(1000, "Fireball", 100, true, Magic));
        check(!t.onDamage(1500, "Fireball", 50, false, Magic));
        check(!t.onDamage(2000, "Slash", 300, false, Physical));
        check(!t.onDamage(2500, "Slash", 50, true, Raw));
        t.publish(3000, true, true);
        var s = t.snap;
        check(s.haveFight);
        check(s.inCombat);
        check(near(s.totalDamage, 500));
        check(near(s.elapsedSec, 2.0));
        check(near(s.dps, 250));
        check(s.hitCount == 4);
        check(s.critCount == 2);
        check(near(s.totalPhysical, 300));
        check(near(s.totalMagic, 150));
        check(near(s.totalRaw, 50));
        check(s.rows.length == 2);
        check(s.rows[0].skill == "Slash");
        var fb = row(s, "Fireball");
        check(fb != null && fb.hitCount == 2 && fb.critCount == 1);
        check(fb != null && near(fb.maxHit, 100) && near(fb.magic, 150));
        var sl = row(s, "Slash");
        check(sl != null && near(sl.physical, 300) && near(sl.raw, 50));
    }

    static function unclassified() {
        var t = new CombatTracker(noThrottle());
        t.onDamage(0, "Mystery", 100, false, Unclassified);
        t.onDamage(10, "Mystery", 100, false, Physical);
        t.publish(20, true, true);
        var s = t.snap;
        check(near(s.totalDamage, 200));
        check(near(s.totalPhysical, 100));
        check(near(s.totalMagic + s.totalRaw, 0));
    }

    static function casts() {
        var t = new CombatTracker(noThrottle());
        t.onCast(1000, "Fireball");
        t.onCast(8000, "Fireball");
        t.onCast(9000, "DS_Base_Attack_2");
        check(!t.fightActive);
        check(t.onDamage(10000, "Fireball", 10, false, Magic));
        t.onDamage(10100, "DS_Base_Attack_1", 10, false, Physical);
        t.onCast(10500, "DS_Base_Attack_3");
        t.onCast(10600, "Dash");
        t.onDamage(10700, "Passive", 10, false, Magic);
        t.publish(11000, true, true);
        var s = t.snap;
        var fb = row(s, "Fireball"), ba = row(s, "DS_Base_Attack"), pa = row(s, "Passive");
        check(fb != null && fb.castCount == 1);
        check(ba != null && ba.castCount == 2);
        check(pa != null && pa.castCount == 0);
        check(row(s, "Dash") == null);
        check(s.castCount == 3);
        check(s.rows.length == 3);
    }

    static function autoResetNeedsBothSignals() {
        var t = new CombatTracker(noThrottle());
        t.onCast(900, "Fireball");
        t.onDamage(1000, "Fireball", 100, false, Magic);
        t.onDamage(3000, "Fireball", 100, false, Magic);
        check(t.update(20000, true, true) == null);
        check(t.fightActive);
        check(t.update(21000, true, false) == null);
        check(t.update(22999, true, false) == null);
        check(t.update(22999, true, true) == null);
        check(t.update(23000, true, false) == null);
        check(t.update(24999, true, false) == null);
        var sealed = t.update(25000, true, false);
        check(sealed != null);
        check(!t.fightActive);
        if (sealed != null) {
            check(sealed.id == 1);
            check(near(sealed.durationSec, 2.0));
            check(near(sealed.dps, 100));
            check(sealed.castCount == 1);
            check(sealed.rows[0].castCount == 1);
            check(near(sealed.totalMagic, 200));
            check(sealed.topSkill == "Fireball");
        }
        t.publish(25001, true, false);
        var s = t.snap;
        check(!s.haveFight);
        check(s.rows.length == 0);
        check(near(s.totalDamage, 0));
        check(s.castCount == 0);
        check(s.history.length == 1);
        check(t.onDamage(30000, "Slash", 5, false, Physical));
        t.publish(30001, true, true);
        check(near(t.snap.totalDamage, 5));
        check(t.nextFightId == 2);
    }

    static function recentDamageKeepsOpen() {
        var t = new CombatTracker(noThrottle());
        t.onDamage(1000, "Slash", 1, false, Physical);
        t.onDamage(5999, "Slash", 1, false, Physical);
        check(t.update(9000, true, false) == null);
        check(t.fightActive);
    }

    static function manualReset() {
        var t = new CombatTracker(noThrottle());
        check(t.reset(500) == null);
        t.onCast(900, "Slash");
        t.onDamage(1000, "Slash", 100, false, Physical);
        var sealed = t.reset(3000);
        check(sealed != null);
        if (sealed != null) check(near(sealed.durationSec, 2.0));
        check(!t.fightActive);
        t.onDamage(3100, "Slash", 100, false, Physical);
        t.publish(3200, true, true);
        var r = row(t.snap, "Slash");
        check(r != null && r.castCount == 0);
        check(t.snap.history.length == 1);
    }

    static function hardBoundary() {
        var t = new CombatTracker(noThrottle());
        t.onDamage(1000, "Slash", 100, false, Physical);
        t.onDamage(2000, "Slash", 100, false, Physical);
        var sealed = t.endFight();
        check(sealed != null);
        if (sealed != null) check(near(sealed.durationSec, 1.0));
        check(!t.fightActive);
        check(t.endFight() == null);
    }

    static function heals() {
        var t = new CombatTracker(noThrottle());
        check(!t.onHeal(100, "HoT", 50, false, false));
        check(!t.fightActive);
        check(t.onHeal(200, "HoT", 50, false, true));
        check(t.reset(1000) == null);
        t.onDamage(2000, "Slash", 100, false, Physical);
        check(!t.onHeal(2500, "HoT", 80, true, true));
        t.onShield("Bubble", 40);
        t.onShield("", 10);
        t.publish(3000, true, true);
        var s = t.snap;
        check(near(s.totalHeal, 80));
        check(near(s.hps, 80));
        check(near(s.totalShield, 50));
        check(s.shieldRows.length == 2);
        check(near(s.totalDamage, 100));
    }

    /** The C++ test checked GetTickCount wraparound; here the clock is a Float, so check a huge one instead. */
    static function largeClock() {
        var t = new CombatTracker(noThrottle());
        var start = 4294967040.0 * 1000;
        t.onDamage(start, "Slash", 100, false, Physical);
        t.publish(start + 1000, true, true);
        check(near(t.snap.elapsedSec, 1.0));
        check(t.update(start + 1000, true, false) == null);
        var sealed = t.reset(start + 2000);
        check(sealed != null && near(sealed.durationSec, 2.0));
    }

    static function throttle() {
        var t = new CombatTracker();
        t.publish(1000, true, true);
        t.onDamage(1100, "Slash", 1, false, Physical);
        t.publish(1100, true, true);
        check(near(t.snap.totalDamage, 1));
        t.onDamage(1150, "Slash", 1, false, Physical);
        t.publish(1150, true, true);
        check(near(t.snap.totalDamage, 1));
        t.publish(1200, true, true);
        check(near(t.snap.totalDamage, 2));
        t.onDamage(1210, "Slash", 1, false, Physical);
        t.reset(1210);
        t.publish(1210, true, true);
        check(t.snap.rows.length == 0);
    }

    static function manySkills() {
        var t = new CombatTracker(noThrottle());
        var n = CombatTracker.MAX_ROWS + 10;
        for (i in 0...n) t.onDamage(1000, "Skill" + i, i + 1.0, false, Raw);
        t.publish(2000, true, true);
        var s = t.snap;
        var expected = n * (n + 1) / 2.0;
        check(s.rows.length == CombatTracker.MAX_ROWS);
        check(near(s.totalDamage, expected));
        check(near(s.rows[0].total, n));
        check(near(s.rows[CombatTracker.MAX_ROWS - 1].total, n - CombatTracker.MAX_ROWS + 1.0));
        var sealed = t.endFight();
        check(sealed != null && near(sealed.totalDamage, expected));
    }

    static function longNames() {
        var t = new CombatTracker(noThrottle());
        var long = StringTools.lpad("", "x", 200);
        t.onDamage(1000, long, 1, false, Raw);
        t.onCast(1000, long);
        t.publish(2000, true, true);
        check(t.snap.rows.length == 1);
        check(t.snap.rows[0].skill.length == 63);
        check(t.snap.rows[0].castCount == 1);
    }

    static function historyRingAndRestore() {
        var t = new CombatTracker(noThrottle());
        for (i in 0...CombatTracker.RECENT_MAX + 5) {
            t.onDamage(1000, "Slash", 1, false, Physical);
            t.endFight();
        }
        t.publish(2000, true, false);
        check(t.snap.history.length == CombatTracker.RECENT_MAX);
        check(t.snap.history[0].id == CombatTracker.RECENT_MAX + 5);

        var e = new FightLogEntry();
        e.id = 41;
        var r0 = new SkillRow("A");
        r0.physical = 10;
        r0.castCount = 3;
        var r1 = new SkillRow("B");
        r1.raw = 5;
        r1.castCount = 1;
        e.rows = [r0, r1];
        var fresh = new CombatTracker(noThrottle());
        fresh.restoreHistory(e);
        fresh.publish(1, true, false);
        var h = fresh.snap.history[0];
        check(near(h.totalPhysical, 10));
        check(near(h.totalRaw, 5));
        check(h.castCount == 4);
        check(fresh.nextFightId == 42);
    }

    static function favorites() {
        var t = new CombatTracker(noThrottle());
        function fight() {
            t.onDamage(1000, "Slash", 1, false, Physical);
            return t.endFight();
        }
        var first = fight();
        check(first != null && first.id == 1 && !first.favorite);
        check(t.setFavorite(1, true));
        check(!t.setFavorite(999, true));
        for (i in 0...25) {
            var e = fight();
            check(e != null);
            if (e != null) e.endedUnixMs = i;
        }
        function has(id:Int) {
            for (e in t.history) if (e.id == id) return true;
            return false;
        }
        check(has(1));
        check(t.history.length == CombatTracker.RECENT_MAX + 1);
        check(t.history[0].id == 26);
        check(t.history[t.history.length - 1].id == 1);
        check(!has(16));
        check(has(17));
        t.publish(2000, true, false);
        check(t.snap.history.length == CombatTracker.RECENT_MAX + 1);
        check(t.snap.history[CombatTracker.RECENT_MAX].favorite);
        check(t.setFavorite(1, false));
        fight();
        check(!has(1));

        var c = new CombatTracker(noThrottle());
        var id = 0;
        for (i in 0...CombatTracker.FAVORITES_MAX) {
            c.onDamage(1000, "Slash", 1, false, Physical);
            id = c.endFight().id;
            check(c.setFavorite(id, true));
        }
        c.onDamage(1000, "Slash", 1, false, Physical);
        var extra = c.endFight().id;
        check(!c.setFavorite(extra, true));
        check(c.setFavorite(id, false));
        check(c.setFavorite(extra, true));
        for (i in 0...CombatTracker.HISTORY_MAX) {
            c.onDamage(1000, "Slash", 1, false, Physical);
            check(c.endFight() != null);
        }
        check(c.history.length <= CombatTracker.HISTORY_MAX);
        c.publish(2000, true, false);
        check(c.snap.history.length == c.history.length);
    }

    static function loadout(hand:String, off:String):FightLoadout {
        var l = new FightLoadout();
        l.hand = hand;
        l.off = off;
        l.handLevel = 25;
        l.handUpgrade = 3;
        return l;
    }

    static function targetsNameTheFight() {
        var t = new CombatTracker(noThrottle());
        function hit(name:String, rank:TargetRank, amount:Float, kill:Bool) {
            t.onDamage(1000, "Skill", amount, false, Physical);
            t.onTarget(name, rank, amount, kill);
        }
        hit("Kobold", Normal, 500, true);
        hit("Kobold", Normal, 500, true);
        hit("Wolf", Normal, 300, false);
        hit("Boar", Elite, 200, false);
        hit("Lady Bee", Boss, 100, false);
        hit("Rat", Normal, 50, false);
        hit("", Normal, 40, false);
        var e = t.endFight();
        check(e != null);
        if (e == null) return;
        check(near(e.totalDamage, 1690));
        check(e.targetCount == 5);
        check(e.targets.length == CombatTracker.MAX_FIGHT_TARGETS);
        check(e.targets[0].name == "Lady Bee");
        check(e.targets[1].name == "Boar");
        check(e.targets[2].name == "Kobold");
        check(near(e.targets[2].total, 1000));
        check(e.targets[2].kills == 2);
        check(e.targets[3].name == "Wolf");
        check(CombatTracker.targetLabel(e) == "Lady Bee +4");
    }

    static function singleOrNoTargetLabel() {
        var t = new CombatTracker(noThrottle());
        t.onDamage(1000, "Skill", 10, false, Physical);
        t.onTarget("Kobold", Normal, 10, false);
        var e = t.endFight();
        check(e != null);
        if (e == null) return;
        check(CombatTracker.targetLabel(e) == "Kobold");
        t.onDamage(2000, "Skill", 10, false, Physical);
        e = t.endFight();
        check(e != null);
        if (e == null) return;
        check(CombatTracker.targetLabel(e) == "-");
        check(e.targetCount == 0);
        check(e.loadout.hand == "");
    }

    static function contextIgnoredOutsideFight() {
        var t = new CombatTracker(noThrottle());
        t.onTarget("Kobold", Normal, 10, true);
        t.onLoadoutDamage(loadout("Daggers", ""), 10);
        t.onDamage(1000, "Skill", 5, false, Physical);
        var e = t.endFight();
        check(e != null);
        if (e == null) return;
        check(e.targetCount == 0);
        check(e.loadout.hand == "");
    }

    static function weaponThatDealtMost() {
        var t = new CombatTracker(noThrottle());
        t.onDamage(1000, "Skill", 1, false, Physical);
        t.onLoadoutDamage(loadout("Daggers", ""), 600);
        t.onLoadoutDamage(loadout("Axe", "Daggers"), 100);
        t.onLoadoutDamage(loadout("Daggers", "Axe"), 50);
        var e = t.endFight();
        check(e != null);
        if (e == null) return;
        check(e.loadout.hand == "Daggers");
        check(e.loadout.off == "Axe");
        check(e.loadout.second == "");
        check(e.loadout.handLevel == 25);
        check(e.loadout.handUpgrade == 3);
    }

    static function contextSurvivesRestore() {
        var e = new FightLogEntry();
        e.id = 7;
        e.targetCount = 6;
        e.targets = [new FightTarget("Ratsar", Boss)];
        e.loadout = loadout("Bow", "Crescent");
        var fresh = new CombatTracker(noThrottle());
        fresh.restoreHistory(e);
        fresh.publish(1, true, false);
        var h = fresh.snap.history[0];
        check(CombatTracker.targetLabel(h) == "Ratsar +5");
        check(h.targets[0].rank == Boss);
        check(h.loadout.off == "Crescent");
    }
}
