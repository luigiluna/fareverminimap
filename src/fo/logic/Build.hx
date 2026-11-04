package fo.logic;

enum abstract Rarity(Int) to Int from Int {
    var Unknown = 0;
    var Common = 1;
    var Uncommon = 2;
    var Rare = 3;
    var Epic = 4;
    var Legendary = 5;

    public static function fromName(s:String):Rarity {
        if (s == null) return Unknown;
        return switch (s.toLowerCase()) {
            case "common": Common;
            case "uncommon": Uncommon;
            case "rare": Rare;
            case "epic": Epic;
            case "legendary": Legendary;
            default: Unknown;
        }
    }

    public function name():String {
        return switch ((cast this : Rarity)) {
            case Common: "Common";
            case Uncommon: "Uncommon";
            case Rare: "Rare";
            case Epic: "Epic";
            case Legendary: "Legendary";
            case Unknown: "";
        }
    }

    /** The game's rarity colors (from the C++ overlay's table). Unknown draws as Common. */
    public function color():Int {
        return switch ((cast this : Rarity)) {
            case Uncommon: 0x57BD38;
            case Rare: 0x3698FD;
            case Epic: 0xAA45FF;
            case Legendary: 0xFFC444;
            default: 0xE1E1E1;
        }
    }
}

class BuildItem {
    public var slot = 0;
    public var level = 0;
    public var upgrade = 0;
    public var icon = -1; // cell in players_gear_atlas.png
    public var rarity:Rarity = Unknown;
    public var id = "";
    public var name = "";
    public var infusion = "";
    public var bonus = "";
    public var augments:Array<String> = [];

    public function new() {}

    public function copy():BuildItem {
        var b = new BuildItem();
        b.slot = slot;
        b.level = level;
        b.upgrade = upgrade;
        b.icon = icon;
        b.rarity = rarity;
        b.id = id;
        b.name = name;
        b.infusion = infusion;
        b.bonus = bonus;
        b.augments = augments.copy();
        return b;
    }
}

class BuildTalent {
    public var name:String;
    public var rank:Int;
    public var branch:Int;
    public var tier:Int;

    public function new(name:String, rank:Int, branch:Int, tier:Int) {
        this.name = name;
        this.rank = rank;
        this.branch = branch;
        this.tier = tier;
    }
}

/** What a player wears and has specced, as display names. Ported from player_meter.h. */
class PlayerBuild {
    public static inline var MAX_GEAR = 15;
    public static inline var MAX_WEAPONS = 3;

    public var uid:Float = 0;
    public var name = "";
    public var className = "";
    public var level = 0;
    public var gear:Array<BuildItem> = [];
    /** False: unknown, not "no talents". */
    public var talentsRead = false;
    public var talentPoints = 0;
    /** Points the level allows (HeroSpecialization.getTotalTalentPoints); 0 unknown. Talents the table lacks make up the gap. */
    public var talentTotal = 0;
    /** Unspent points (HeroSpecialization.getTalentPoints); -1 unknown. */
    public var talentFree = -1;
    public var talents:Array<BuildTalent> = [];
    public var readAt = 0.0;

    public function new() {}

    /** Points spent in talents the name table does not know (0 when unknown). */
    public function unlistedPoints():Int {
        if (talentFree < 0 || talentTotal <= 0) return 0;
        var spent = talentTotal - talentFree;
        return spent > talentPoints ? spent - talentPoints : 0;
    }

    public static function slotName(slot:Int):String {
        var names = [
            "Weapon 1", "Weapon 2", "Off-hand", "Head", "Neck", "Shoulders", "Chest", "Back", "Hands", "Waist", "Legs", "Feet", "Ring",
            "Trinket", "Ring"
        ];
        return slot >= 0 && slot < names.length ? names[slot] : "";
    }

    public function sortTalents():Void {
        talents.sort((a, b) -> {
            if (a.branch != b.branch) return a.branch - b.branch;
            if (a.tier != b.tier) return a.tier - b.tier;
            return a.name < b.name ? -1 : (a.name > b.name ? 1 : 0);
        });
    }

    public function weapons():Array<BuildItem> {
        var out = [];
        for (g in gear) if (g.slot < MAX_WEAPONS && out.length < MAX_WEAPONS) out.push(g);
        return out;
    }

    /**
     * Same value for the same player wearing and speccing the same things, so
     * fights can share one saved copy. Never "0". FNV-1a over the fields, as hex.
     */
    public function fingerprint():String {
        // Two 32-bit FNV-1a lanes with different seeds: enough to tell builds apart.
        var h1 = 0x811C9DC5, h2 = 0x050C5D1F;
        function bytes(s:String) {
            for (i in 0...s.length) {
                var c = s.charCodeAt(i);
                h1 = (h1 ^ c) * 0x01000193;
                h2 = (h2 ^ c) * 0x01000193;
            }
            h1 = (h1 ^ 0) * 0x01000193; // terminator, so "ab"+"c" differs from "a"+"bc"
            h2 = (h2 ^ 0xFF) * 0x01000193;
        }
        bytes(Std.string(uid));
        bytes(name);
        bytes(className);
        bytes(Std.string(level));
        bytes(talentsRead ? "1" : "0");
        bytes(Std.string(talentPoints));
        bytes(Std.string(gear.length));
        for (g in gear) {
            bytes(g.slot + "/" + g.level + "/" + g.upgrade + "/" + (g.rarity : Int));
            bytes(g.id);
            bytes(g.name);
            bytes(g.infusion);
            bytes(g.bonus);
            bytes(Std.string(g.augments.length));
            for (a in g.augments) bytes(a);
        }
        bytes(Std.string(talents.length));
        for (t in talents) bytes(t.name + "/" + t.rank + "/" + t.branch + "/" + t.tier);
        var s = StringTools.hex(h1 & 0xFFFFFFFF, 8) + StringTools.hex(h2 & 0xFFFFFFFF, 8);
        return s == "0000000000000000" ? "1" : s.toLowerCase();
    }

    public function toJson():Dynamic {
        return {
            uid: uid, name: name, "class": className, level: level, talents_read: talentsRead ? 1 : 0, talent_points: talentPoints, talent_total: talentTotal, talent_free: talentFree,
            gear: [for (g in gear) {
                slot: g.slot, id: g.id, name: g.name, level: g.level, upgrade: g.upgrade, rarity: g.rarity.name(), icon: g.icon,
                infusion: g.infusion, bonus: g.bonus, augments: g.augments
            }],
            talents: [for (t in talents) {name: t.name, rank: t.rank, branch: t.branch, tier: t.tier}],
        };
    }

    public static function fromJson(o:Dynamic):PlayerBuild {
        var b = new PlayerBuild();
        inline function s(v:Dynamic) return v == null ? "" : Std.string(v);
        inline function n(v:Dynamic) return v == null ? 0 : Std.int((v : Float));
        b.uid = o.uid == null ? 0 : (o.uid : Float);
        b.name = s(o.name);
        b.className = s(Reflect.field(o, "class"));
        b.level = n(o.level);
        b.talentsRead = n(o.talents_read) != 0;
        b.talentPoints = n(o.talent_points);
        b.talentTotal = n(o.talent_total);
        b.talentFree = o.talent_free == null ? -1 : n(o.talent_free);
        var gear:Array<Dynamic> = Std.isOfType(o.gear, Array) ? o.gear : [];
        for (g in gear) {
            var it = new BuildItem();
            it.slot = n(g.slot);
            it.id = s(g.id);
            it.name = s(g.name);
            it.level = n(g.level);
            it.upgrade = n(g.upgrade);
            it.rarity = Rarity.fromName(s(g.rarity));
            it.icon = g.icon == null ? -1 : n(g.icon);
            it.infusion = s(g.infusion);
            it.bonus = s(g.bonus);
            var aug:Array<Dynamic> = Std.isOfType(g.augments, Array) ? g.augments : [];
            it.augments = [for (a in aug) s(a)];
            b.gear.push(it);
        }
        var ts:Array<Dynamic> = Std.isOfType(o.talents, Array) ? o.talents : [];
        for (t in ts) b.talents.push(new BuildTalent(s(t.name), n(t.rank), n(t.branch), n(t.tier)));
        return b;
    }
}
