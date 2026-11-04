import fo.logic.CombatTracker;
import fo.logic.History;
import fo.logic.MapMath;
import fo.logic.Pois;

/** Map projection, POI file and fight history file, against copies of the real files. */
class TestMapAndHistory {
    static inline function near(a:Float, b:Float, eps = 1e-6) return Math.abs(a - b) < eps;
    static inline function check(c:Bool, ?pos:haxe.PosInfos) T.check(c, pos);

    public static function run():Void {
        projection();
        pois();
        history();
        angles();
    }

    static function projection() {
        var m = new MapMath();
        m.loadCalibration(haxe.Json.parse(sys.io.File.getContent("tests/fixtures/minimap_calibration.json")));
        check(near(m.scaleX, 1.7756499661218983));
        check(!m.flipY);
        // Round trip world -> uv -> world.
        for (p in [[0.0, 0.0], [-981.9369, 1445.6479], [175.3416, 769.918]]) {
            check(near(m.worldX(m.u(p[0])), p[0], 1e-6));
            check(near(m.worldY(m.v(p[1])), p[1], 1e-6));
        }
        // Altar 1 sits inside the image.
        var u = m.u(-981.9369), v = m.v(1445.6479);
        check(u > 0 && u < 1 && v > 0 && v < 1);
        // Missing keys keep the defaults.
        var d = new MapMath();
        d.loadCalibration({scale_x: 2.0});
        check(d.scaleX == 2.0 && near(d.scaleY, 1.7707905370196702));
    }

    static function pois() {
        var list = Pois.parse(sys.io.File.getContent("tests/fixtures/pois_W1_Siagarta.json"));
        check(list.length == 1232);
        var altars = list.filter(p -> p.kind == "soulstone");
        check(altars.length == 8);
        var bel = altars.filter(p -> p.name == "Belzebeat");
        check(bel.length == 1);
        var tip = Pois.tooltip(altars[0], 123.4);
        check(tip.indexOf(altars[0].name + " altar - 123 m") == 0);
        for (p in list) check(Pois.style(p.kind).label != p.kind); // every kind in the file has a style
        check(Pois.parse('[{"kind":"chest"},{"kind":"ore","x":1,"y":2}]').length == 1);
    }

    static function history() {
        var text = sys.io.File.getContent("tests/fixtures/fight_history_overlay.json");
        var fights = History.parse(text);
        check(fights.length > 0);
        var raw:Dynamic = haxe.Json.parse(text);
        var first:Dynamic = raw.fights[0];
        check(fights[0].id == first.id);
        check(near(fights[0].totalDamage, first.total_damage));
        check(fights[0].rows.length == first.rows.length);
        check(fights[0].players.length == first.players.length);
        // Round trip keeps what the meter shows.
        var again = History.parse(History.stringify(fights));
        check(again.length == fights.length);
        for (i in 0...fights.length) {
            var a = fights[i], b = again[i];
            check(a.id == b.id && a.favorite == b.favorite && near(a.dps, b.dps));
            check(CombatTracker.targetLabel(a) == CombatTracker.targetLabel(b));
            check(a.rows.length == b.rows.length);
            for (j in 0...a.rows.length) check(a.rows[j].skill == b.rows[j].skill && a.rows[j].castCount == b.rows[j].castCount);
            check(a.players.length == b.players.length);
        }
        // Restored into a tracker, history keeps order and ids continue.
        var t = new CombatTracker();
        for (e in fights) t.restoreHistory(e);
        var maxId = 0;
        for (e in fights) if (e.id > maxId) maxId = e.id;
        check(t.nextFightId == maxId + 1);
        // Old/odd files: no fights key, empty arrays.
        check(History.parse("{}").length == 0);
        check(History.parse('{"fights":[{"id":3}]}')[0].rows.length == 0);
        // Fights saved with game Strings as objects are dropped, the rest kept.
        var mixed = '{"fights":[{"id":5,"top_skill":"{bytes : ???, length : 5}","rows":[]},{"id":4,"top_skill":"Slash","rows":[{"skill":"Slash"}]}]}';
        var kept = History.parse(mixed);
        check(kept.length == 1 && kept[0].id == 4);
    }

    static function angles() {
        check(near(MapMath.rotationFor(-Math.PI / 2), 0));
        var r = MapMath.lerpAngle(3.0, -3.0, 1.0);
        check(near(Math.cos(r), Math.cos(-3.0)) && near(Math.sin(r), Math.sin(-3.0))); // reaches the target, the short way
        var mid = MapMath.lerpAngle(3.0, -3.0, 0.5);
        check(Math.abs(Math.abs(mid) - Math.PI) < 0.3); // passes through pi, not through 0
    }
}
