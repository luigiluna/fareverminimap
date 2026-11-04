package fo;

/** Lines go to hlx/logs/hlx.log, tagged with the mod name by hlx-boot. */
class Log {
    static var seen = new Map<String, Int>();

    public static function info(msg:String):Void Sys.println(msg); // hlx-boot already tags lines with the mod name

    /** Marks the first run of a stage, so a crash leaves its last stage in hlx.log. */
    public static function stage(name:String):Void once("stage-" + name, "stage: " + name + " (first run)", 1);

    public static function err(msg:String):Void Sys.println("ERROR " + msg);

    /** Logs the first `max` times a given key happens, then stays quiet. */
    public static function once(key:String, msg:String, max = 3):Void {
        var n = seen.exists(key) ? seen.get(key) : 0;
        if (n >= max) return;
        seen.set(key, n + 1);
        info(msg + (n + 1 == max ? " (further repeats muted)" : ""));
    }
}
