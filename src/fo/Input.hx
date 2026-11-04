package fo;

/**
 * Reads the game's own input state (hxd.Key, h2d.Scene mouse). Read only: nothing
 * here changes what the game receives.
 */
class Input {
    static var codes = new Map<String, Int>();
    static var isDownFn:Dynamic;
    static var isPressedFn:Dynamic;
    static var isReleasedFn:Dynamic;

    public static var mouseX = 0.0;
    public static var mouseY = 0.0;
    public static var leftDown = false;
    public static var leftPressed = false;
    public static var leftReleased = false;
    public static var rightPressed = false;
    public static var wheel = 0;
    /** Two left presses within 350 ms at about the same spot. */
    public static var doubleClick = false;

    static var lastClickAt = -1.0;
    static var lastClickX = 0.0;
    static var lastClickY = 0.0;

    /** Key code by hxd.Key constant name ("F6", "MOUSE_LEFT"); -1 if unknown. */
    public static function code(name:String):Int {
        if (name == null) return -1;
        if (codes.exists(name)) return codes.get(name);
        var v = G.stat("hxd.Key", name);
        var c = v == null ? -1 : G.int(v, -1);
        if (c < 0 && name.length == 1) {
            // Letters and digits are their ASCII code in hxd.Key.
            var ch = name.toUpperCase().charCodeAt(0);
            if ((ch >= "A".code && ch <= "Z".code) || (ch >= "0".code && ch <= "9".code)) c = ch;
        }
        codes.set(name, c);
        if (c < 0) Log.once("key-" + name, "unknown key name: " + name, 1);
        return c;
    }

    static function fn(name:String):Dynamic return G.stat("hxd.Key", name);

    static function callKey(f:Dynamic, c:Int, name:String):Bool {
        if (c < 0) return false;
        if (f == null) return G.bool(G.scall("hxd.Key", name, [c]));
        try return G.bool(Reflect.callMethod(null, f, [c])) catch (_:Dynamic) return false;
    }

    public static function isDown(c:Int):Bool {
        if (isDownFn == null) isDownFn = fn("isDown");
        return callKey(isDownFn, c, "isDown");
    }

    public static function isPressed(c:Int):Bool {
        if (isPressedFn == null) isPressedFn = fn("isPressed");
        return callKey(isPressedFn, c, "isPressed");
    }

    public static function isReleased(c:Int):Bool {
        if (isReleasedFn == null) isReleasedFn = fn("isReleased");
        return callKey(isReleasedFn, c, "isReleased");
    }

    public static function pressed(name:String):Bool return isPressed(code(name));

    public static function shift():Bool return isDown(code("SHIFT"));

    /** Once per frame, before anything reads the fields above. */
    public static function poll(s2d:Dynamic, now:Float):Void {
        mouseX = G.num(G.call("h2d.Scene", "get_mouseX", s2d, []));
        mouseY = G.num(G.call("h2d.Scene", "get_mouseY", s2d, []));
        leftDown = isDown(code("MOUSE_LEFT"));
        leftPressed = isPressed(code("MOUSE_LEFT"));
        leftReleased = isReleased(code("MOUSE_LEFT"));
        rightPressed = isPressed(code("MOUSE_RIGHT"));
        wheel = (isPressed(code("MOUSE_WHEEL_UP")) ? 1 : 0) - (isPressed(code("MOUSE_WHEEL_DOWN")) ? 1 : 0);
        doubleClick = false;
        if (leftPressed) {
            if (now - lastClickAt < 0.35 && Math.abs(mouseX - lastClickX) < 6 && Math.abs(mouseY - lastClickY) < 6) {
                doubleClick = true;
                lastClickAt = -1;
            } else {
                lastClickAt = now;
                lastClickX = mouseX;
                lastClickY = mouseY;
            }
        }
    }

    public static inline function inside(x:Float, y:Float, w:Float, h:Float):Bool
        return mouseX >= x && mouseX < x + w && mouseY >= y && mouseY < y + h;
}
