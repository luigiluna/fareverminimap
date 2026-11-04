/** Runs every logic test under `haxe tests.hxml` (eval interpreter, no game needed). */
class TestMain {
    static function main() {
        var suites:Array<{name:String, run:Void->Void}> = [
            {name: "combat_tracker", run: TestCombatTracker.run},
            {name: "player_meter", run: TestPlayerMeter.run},
            {name: "map_and_history", run: TestMapAndHistory.run},
            {name: "records", run: TestRecords.run},
        ];
        for (s in suites) {
            var c0 = T.checks, f0 = T.failures;
            s.run();
            Sys.println('${s.name}: ${T.checks - c0} checks, ${T.failures - f0} failures');
        }
        Sys.println('total: ${T.checks} checks, ${T.failures} failures');
        Sys.exit(T.failures == 0 ? 0 : 1);
    }
}
