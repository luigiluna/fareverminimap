/** Minimal check counter, like the CHECK macro of the C++ tests. */
class T {
    public static var checks = 0;
    public static var failures = 0;

    public static function check(c:Bool, ?pos:haxe.PosInfos):Void {
        checks++;
        if (!c) {
            failures++;
            Sys.println('FAIL ${pos.className}.${pos.methodName}:${pos.lineNumber}');
        }
    }

    public static inline function near(a:Float, b:Float):Bool return Math.abs(a - b) < 1e-6;
}
