package fo;

import fo.logic.Build;
import fo.logic.GameNames;

/**
 * Reads a player's gear and talents from their ent.Hero, by field name. Same
 * sources as the C++ reader: Hero.loadout.equipment.content for gear and
 * Hero.specialization.talents (filled for players not loaded nearby, unlike
 * Hero.skills) for talents. Read only.
 */
class BuildReader {
    static var loggedSlot = false;

    public static function read(hero:Dynamic, uid:Float, now:Float):PlayerBuild {
        var b = new PlayerBuild();
        b.uid = uid;
        b.readAt = now;
        b.name = G.str(G.f(hero, "name"));
        if (b.name == null) b.name = "";
        b.className = G.str(G.f(hero, "kind"));
        if (b.className == null) b.className = "";
        try b.level = G.int(G.call("ent.Unit", "get_level", hero, [])) catch (_:Dynamic) b.level = G.int(G.f(hero, "_level"));
        try readGear(hero, b) catch (e:Dynamic) Log.once("gear", "build: gear read failed: " + Std.string(e), 3);
        try readTalents(hero, b) catch (e:Dynamic) Log.once("talents", "build: talents read failed: " + Std.string(e), 3);
        return b;
    }

    /**
     * Gear through the game's own getters: st.Inventory.getSize / getItem(i)
     * (Equipment extends Inventory). Slots are virtuals, so they are never
     * walked by hand.
     */
    static function readGear(hero:Dynamic, b:PlayerBuild):Void {
        var eq = G.f(G.f(hero, "loadout"), "equipment");
        if (eq == null || !G.isA(eq, "st.Inventory")) return;
        var n = Std.int(Math.min(G.int(G.call("st.Inventory", "getSize", eq, [])), PlayerBuild.MAX_GEAR));
        for (i in 0...n) {
            var item:Dynamic = G.call("st.Inventory", "getItem", eq, [i]);
            if (item == null || !G.isA(item, "st.Item")) continue;
            var id = G.str(G.f(item, "kind"));
            if (id == null || id == "") continue;
            var it = new BuildItem();
            it.slot = i;
            it.id = id;
            it.name = GameNames.item(id);
            var ic = GameNames.icon(id);
            if (ic != null) {
                it.icon = ic.cell;
                it.rarity = ic.rarity;
            }
            if (G.isA(item, "st.item.Weapon")) {
                // A weapon's own rarity wins when set (it was null on the ones checked live).
                var own = Rarity.fromName(G.str(G.f(item, "rarity")));
                if (own != Unknown) it.rarity = own;
            }
            if (G.isA(item, "st.item.Gear")) {
                var lv = G.int(G.f(item, "level"));
                var up = G.int(G.f(item, "upgradeLevel"));
                if (lv > 0 && lv <= 1000) it.level = lv;
                if (up > 0 && up <= 1000) it.upgrade = up;
                var inf = G.str(G.f(item, "infusion"));
                if (inf != null && inf != "") it.infusion = GameNames.humanize(inf, "Infusion_");
                var bonus = G.str(G.f(item, "infusionBonusStat"));
                if (bonus != null && bonus != "") it.bonus = GameNames.humanize(bonus, "");
                var slots = G.f(item, "slots");
                var arr = slots == null ? null : G.f(slots, "array");
                if (arr != null && (G.isA(arr, "hl.types.ArrayDyn") || G.isA(arr, "hl.types.ArrayObj")))
                    for (k in 0...Std.int(Math.min(G.alen(arr), 4))) {
                        var a = G.str(G.aget(arr, k));
                        if (a != null && a != "") it.augments.push(GameNames.item(a));
                    }
            }
            b.gear.push(it);
        }
    }

    /**
     * The local hero's weapons for the fight history: the one in hand
     * (Hero.weaponInHand), the other of slots 0/1 and the off-hand (slot 2),
     * through st.Inventory.getItem. Null when nothing is in hand.
     */
    public static function readLoadout(hero:Dynamic):fo.logic.CombatTracker.FightLoadout {
        var inHand:Dynamic = G.f(hero, "weaponInHand");
        if (inHand == null || !G.isA(inHand, "st.Item")) return null;
        var handId = G.str(G.f(inHand, "kind"));
        if (handId == null || handId == "") return null;
        var l = new fo.logic.CombatTracker.FightLoadout();
        l.hand = GameNames.item(handId);
        if (G.isA(inHand, "st.item.Gear")) {
            var lv = G.int(G.f(inHand, "level"));
            var up = G.int(G.f(inHand, "upgradeLevel"));
            if (lv > 0 && lv <= 1000) l.handLevel = lv;
            if (up > 0 && up <= 1000) l.handUpgrade = up;
        }
        var eq = G.f(G.f(hero, "loadout"), "equipment");
        if (eq == null || !G.isA(eq, "st.Inventory")) return l;
        var n = G.int(G.call("st.Inventory", "getSize", eq, []));
        for (i in 0...Std.int(Math.min(n, 3))) {
            var item:Dynamic = G.call("st.Inventory", "getItem", eq, [i]);
            if (item == null || !G.isA(item, "st.Item")) continue;
            var id = G.str(G.f(item, "kind"));
            if (id == null || id == "") continue;
            if (i < 2 && id != handId && l.second == "") l.second = GameNames.item(id);
            if (i == 2) l.off = GameNames.item(id);
        }
        return l;
    }

    /** Talents through HeroSpecialization.getTalent(id), for each id the table knows. */
    static function readTalents(hero:Dynamic, b:PlayerBuild):Void {
        var spec = G.f(hero, "specialization");
        if (spec == null || !G.isA(spec, "st.player.HeroSpecialization")) return;
        if (G.f(spec, "talents") == null) return;
        b.talentsRead = true;
        try b.talentTotal = G.int(G.call("st.player.HeroSpecialization", "getTotalTalentPoints", spec, [])) catch (_:Dynamic) {}
        try b.talentFree = G.int(G.call("st.player.HeroSpecialization", "getTalentPoints", spec, []), -1) catch (_:Dynamic) {}
        for (id in GameNames.talentIds()) {
            var rank = G.int(G.call("st.player.HeroSpecialization", "getTalent", spec, [id]));
            if (rank < 1 || rank > 99) continue;
            var t = GameNames.talent(id);
            b.talentPoints += rank;
            if (b.talents.length < 24) b.talents.push(new BuildTalent(t.name, rank, t.branch, t.tier));
        }
        b.sortTalents();
    }
}
