package fo.logic;

import fo.data.GameTables;
import fo.logic.Build;
import fo.logic.CombatTracker.TargetRank;

/** Id -> display name lookups from the generated tables (no game memory involved). */
class GameNames {
    static var units:Map<String, {name:String, rank:TargetRank}>;
    static var items:Map<String, String>;
    static var talents:Map<String, {name:String, branch:Int, tier:Int}>;
    static var classes:Map<String, Int>;
    static var icons:Map<String, {cell:Int, rarity:Rarity}>;
    static var skills:Map<String, String>;

    static function init():Void {
        if (units != null) return;
        units = new Map();
        items = new Map();
        talents = new Map();
        classes = new Map();
        icons = new Map();
        skills = new Map();
        for (line in GameTables.DATA.split("\n")) {
            var p = line.split("|");
            switch (p[0]) {
                case "U": units.set(p[1], {name: p[2], rank: switch (p[3]) {
                        case "Boss": Boss;
                        case "Miniboss": Miniboss;
                        case "Elite": Elite;
                        default: Normal;
                    }});
                case "I": items.set(p[1], p[2]);
                case "T": talents.set(p[1], {name: p[2], branch: Std.parseInt(p[3]), tier: Std.parseInt(p[4])});
                case "C": classes.set(p[1], Std.parseInt(p[2]));
                case "G": icons.set(p[1], {cell: Std.parseInt(p[2]), rarity: Rarity.fromName(p[3])});
                case "S": skills.set(p[1], p[2]);
                default:
            }
        }
    }

    public static function count(kind:String):Int {
        init();
        return switch (kind) {
            case "U": Lambda.count(units);
            case "I": Lambda.count(items);
            case "T": Lambda.count(talents);
            case "C": Lambda.count(classes);
            case "G": Lambda.count(icons);
            case "S": Lambda.count(skills);
            default: 0;
        }
    }

    public static function unit(id:String):Null<{name:String, rank:TargetRank}> {
        init();
        return units.get(id);
    }

    /** Item display name, or a readable form of the id. */
    public static function item(id:String):String {
        init();
        var n = items.get(id);
        return n != null ? n : humanize(id, "");
    }

    public static function icon(id:String):Null<{cell:Int, rarity:Rarity}> {
        init();
        return icons.get(id);
    }

    /** Every talent id the table knows (the build reader asks the game for each). */
    public static function talentIds():Array<String> {
        init();
        return [for (k in talents.keys()) k];
    }

    public static function classCell(cls:String):Int {
        init();
        var c = classes.get(cls);
        return c == null ? -1 : c;
    }

    public static function talent(id:String):Null<{name:String, branch:Int, tier:Int}> {
        init();
        return talents.get(id);
    }

    /** Skill display name, or a readable form of the id ("Bow_Craft_Skill1" -> "Bow Craft Skill1"). */
    public static function skill(id:String):String {
        init();
        var n = skills.get(id);
        return n != null ? n : humanize(id, "");
    }

    public static function hasSkill(id:String):Bool {
        init();
        return skills.exists(id);
    }

    /** "Infusion_CritChance" with prefix "Infusion_" -> "Crit Chance". */
    public static function humanize(id:String, prefix:String):String {
        if (id == null) return "";
        var s = prefix != "" && StringTools.startsWith(id, prefix) ? id.substr(prefix.length) : id;
        var out = new StringBuf();
        for (i in 0...s.length) {
            var c = s.charAt(i);
            if (c == "_") {
                out.add(" ");
                continue;
            }
            var code = c.charCodeAt(0);
            var prev = i > 0 ? s.charCodeAt(i - 1) : 0;
            if (code >= "A".code && code <= "Z".code && prev >= "a".code && prev <= "z".code) out.add(" ");
            out.add(c);
        }
        return out.toString();
    }
}
