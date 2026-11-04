package fo.logic;

/**
 * World <-> map image projection, from the C++ overlay's calibration
 * (data/minimap_calibration.json). The image covers the whole 11264 px mosaic;
 * world metres map to mosaic pixels linearly, with no flip on W1.
 */
class MapMath {
    public static inline var MOSAIC_PX = 11264.0;

    public var scaleX = 1.7756499661218983;
    public var scaleY = 1.7707905370196702;
    public var offsetX = 4096.76539455183;
    public var offsetY = 6150.390302226916;
    public var flipY = false;

    public function new() {}

    /** Reads the overlay's calibration JSON text; keeps the defaults for missing keys. */
    public function loadCalibration(json:Dynamic):Void {
        if (json == null) return;
        inline function num(k:String, d:Float):Float {
            var v:Dynamic = Reflect.field(json, k);
            return v == null ? d : (v : Float);
        }
        scaleX = num("scale_x", scaleX);
        scaleY = num("scale_y", scaleY);
        offsetX = num("offset_x", offsetX);
        offsetY = num("offset_y", offsetY);
        var f:Dynamic = Reflect.field(json, "flip_y");
        if (f != null) flipY = f == true;
    }

    /** World metres to image UV (0..1). */
    public inline function u(wx:Float):Float return (wx * scaleX + offsetX) / MOSAIC_PX;

    public inline function v(wy:Float):Float {
        var fy = wy * scaleY + offsetY;
        if (flipY) fy = MOSAIC_PX - fy;
        return fy / MOSAIC_PX;
    }

    public inline function worldX(u:Float):Float return (u * MOSAIC_PX - offsetX) / scaleX;

    public inline function worldY(v:Float):Float {
        var fy = v * MOSAIC_PX;
        if (flipY) fy = MOSAIC_PX - fy;
        return (fy - offsetY) / scaleY;
    }

    /**
     * Rotation that puts `upAngle` (a world heading, radians, measured like
     * atan2(dy, dx) in world axes) at the top of the screen. Screen y grows down
     * like world y here, so a world angle is also its screen angle.
     */
    public static inline function rotationFor(upAngle:Float):Float return -upAngle - Math.PI / 2;

    /** Shortest-way lerp of an angle. */
    public static function lerpAngle(cur:Float, target:Float, a:Float):Float {
        var d = target - cur;
        while (d > Math.PI) d -= 2 * Math.PI;
        while (d < -Math.PI) d += 2 * Math.PI;
        return cur + d * a;
    }
}
