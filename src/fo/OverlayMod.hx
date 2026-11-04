package fo;

import hlx.runtime.Bus;
import hlx.runtime.ModConfig;

typedef Filters = {
    var soulstone:Bool;
    var dungeon:Bool;
    var obelisk:Bool;
    var respawn:Bool;
    var merchant:Bool;
    var activity:Bool;
    var chest:Bool;
    var red_orb:Bool;
    var plant:Bool;
    var ore:Bool;
}

typedef OverlayConfig = {
    var enabled:Bool;
    var showMinimap:Bool;
    var minimapSize:Int;
    var minimapX:Float;
    var minimapY:Float;
    var minimapLocked:Bool;
    var minimapRangeM:Float;
    var minimapAlpha:Float;
    var rotateMinimap:Bool;
    var followCamera:Bool;
    var bigPxPerM:Float;
    var showPlayers:Bool;
    var playerNames:Bool;
    var showDps:Bool;
    var dpsCollapsed:Bool;
    var dpsLocked:Bool;
    var dpsX:Float;
    var dpsW:Float;
    var dpsH:Float;
    var dpsY:Float;
    var bossReset:Bool;
    /** Switches for the newer readers, to isolate a problem without a rebuild. */
    var featBuilds:Bool;
    var featAtlas:Bool;
    var featMapLevel:Bool;
    var featSkillIcons:Bool;
    var keyBigMap:String;
    var keyMinimap:String;
    var keyDps:String;
    var keyReset:String;
    var keyPause:String;
    var filters:Filters;
}

/**
 * Farever Overlay (hlx): minimap, large map and DPS meter drawn with the game's
 * own 2D engine. Starts disabled; turn it on in Esc > Mod Settings.
 *
 * Read only: the hooks are postfixes that observe, and nothing the game does is
 * skipped or changed. The panels place h2d.Interactive blockers over themselves,
 * like any game window, so clicks on them do not reach the world behind.
 */
@:build(hlx.runtime.Mod.build())
class OverlayMod {
    @:hlx.config
    static var config:OverlayConfig = {
        enabled: false,
        showMinimap: true,
        minimapSize: 220,
        minimapX: -1,
        minimapY: -1,
        minimapLocked: false,
        minimapRangeM: 170,
        minimapAlpha: 1.0,
        rotateMinimap: true,
        followCamera: true,
        bigPxPerM: 0.6,
        showPlayers: true,
        playerNames: true,
        showDps: true,
        dpsCollapsed: false,
        dpsLocked: false,
        dpsX: 20,
        dpsW: 660,
        dpsH: 470,
        dpsY: 380,
        bossReset: false,
        featBuilds: true,
        featAtlas: true,
        featMapLevel: true,
        featSkillIcons: true,
        keyBigMap: "F6",
        keyMinimap: "F8",
        keyDps: "F10",
        keyReset: "F9",
        keyPause: "F12",
        filters: {
            soulstone: true, dungeon: true, obelisk: true, respawn: true, merchant: true, activity: true, chest: true, red_orb: true,
            plant: false, ore: false
        },
    };

    static inline var DATA_DIR = "hlx/mods/farever-overlay/data";
    static inline var HISTORY = "hlx/config/farever-overlay/fight_history.json";

    static var root:Dynamic;
    static var minimap:Minimap;
    static var dps:DpsWindow;
    static var buildWin:BuildWindow;
    static var fightWin:FightWindow;
    static var tooltip:Minimap.Tooltip;
    static var mapOpts:MapOptions;
    /** Last build read per player uid (ms). */
    static var buildReadAt = new Map<String, Float>();
    static var meter:Meter;
    static var casts = new DpsCapture.CastWatch();
    static var pending:Array<Dynamic> = [];
    static var built = false;
    static var buildFailed = false;
    static var lastNow = 0.0;
    static var saveAt = -1.0;
    static var lastGroupRead = -1e9;
    static var lastLoadoutRead = -1e9;
    static var stats = {hits: 0, mine: 0, frames: 0, builds: 0, lastLog: 0.0};

    static function main():Void {
        Log.info("loaded (enabled=" + config.enabled + ")");
        Bus.subscribe("better-mod-settings/config-changed/" + HlxRuntime.moduleName(), (_:Dynamic) -> {
            var was = config.enabled;
            config = ModConfig.load(HlxRuntime.moduleName(), config);
            Log.info("settings changed (enabled=" + config.enabled + ")");
            if (was && !config.enabled) teardown();
        });
    }

    public static function iconsOn():Bool return config.featSkillIcons;

    /** Saves the config at most once a second (map zoom, filters, window position). */
    public static function saveSoon():Void if (saveAt < 0) saveAt = lastNow + 1000;

    // ---- hooks (observation only) ----

    @:hlx.postfix(GameApp.update)
    static function afterUpdate(app:Dynamic, dt:Float, result:Void):Void {
        if (!config.enabled) {
            pending = [];
            return;
        }
        try tick(app, dt) catch (e:Dynamic) Log.once("tick", "tick failed: " + Std.string(e), 5);
    }

    @:hlx.postfix(ent.Unit.rpcReceiveDamage__impl)
    static function afterReceiveDamage(unit:Dynamic, dr:Dynamic, result:Void):Void {
        if (!config.enabled || pending.length > 512) return;
        pending.push(dr);
    }

    @:hlx.postfix(ent.Unit.onDeath)
    static function afterDeath(unit:Dynamic, dr:Dynamic, result:Void):Void {
        if (!config.enabled || meter == null) return;
        try meter.onUnitDeath(unit, haxe.Timer.stamp() * 1000) catch (e:Dynamic) Log.once("death", "death hook failed: " + Std.string(e), 3);
    }

    @:hlx.postfix(ent.Hero.playDeath)
    static function afterPlayDeath(hero:Dynamic, result:Void):Void {
        if (!config.enabled || meter == null) return;
        try meter.onUnitDeath(hero, haxe.Timer.stamp() * 1000) catch (e:Dynamic) Log.once("death2", "death hook failed: " + Std.string(e), 3);
    }

    @:hlx.prefix(GameApp.dispose)
    static function beforeDispose(app:Dynamic):hlx.runtime.HlxPrefixResult<Void> {
        try {
            if (meter != null) meter.save(lastNow);
            teardown();
        } catch (_:Dynamic) {}
        return Continue;
    }

    // ---- frame ----

    static function tick(app:Dynamic, dt:Float):Void {
        var now = haxe.Timer.stamp() * 1000;
        lastNow = now;
        stats.frames++;
        if (meter == null) meter = new Meter(HISTORY, overlayHistoryPath());

        var hero = G.f(app, "hero");
        DpsCapture.hero = hero;
        // Weapons for the history: read about once a second, before this frame's hits.
        if (hero == null) meter.loadout = null;
        else if (now - lastLoadoutRead > 1000) {
            lastLoadoutRead = now;
            Log.stage("loadout");
            try {
                var l = BuildReader.readLoadout(hero);
                if (l != null && (meter.loadout == null || meter.loadout.hand != l.hand))
                    Log.once("loadout", 'loadout: hand=${l.hand} lv${l.handLevel} +${l.handUpgrade} second=${l.second} off=${l.off}', 5);
                meter.loadout = l;
            } catch (e:Dynamic) Log.once("loadoutfail", "loadout read failed: " + Std.string(e), 3);
        }
        // Hits first, so a fight boundary below sees them.
        if (pending.length > 0) {
            var list = pending;
            pending = [];
            var readsThisFrame = 0;
            Log.stage("decode hits");
            for (dr in list) {
                var h = null;
                try h = DpsCapture.decode(dr, now) catch (e:Dynamic) Log.once("decode", "decode failed: " + Std.string(e), 5);
                if (h == null) continue;
                if (h.taken) {
                    meter.onHit(h, now, config.bossReset);
                    continue;
                }
                stats.hits++;
                if (h.isMine) stats.mine++;
                meter.onHit(h, now, config.bossReset);
                // Build: on a player's first hit, then at most every 10 s, 2 players per frame.
                var key = Std.string(h.playerUid);
                var last = buildReadAt.get(key);
                if (h.heroObj != null && readsThisFrame < 2 && (last == null || now - last > 10000)) {
                    readsThisFrame++;
                    buildReadAt.set(key, now);
                    if (config.featBuilds) try {
                        Log.stage("build read");
                        var b = BuildReader.read(h.heroObj, h.playerUid, now);
                        meter.onBuild(b);
                        if (stats.builds++ < 3) Log.info('build read: ${b.name} ${b.className} lv${b.level} gear=${b.gear.length} talents=${b.talents.length}/${b.talentPoints}pts read=${b.talentsRead} total=${b.talentTotal} free=${b.talentFree} unlisted=${b.unlistedPoints()}');
                    } catch (e:Dynamic) Log.once("buildread", "build read failed: " + Std.string(e), 3);
                }
            }
        }
        if (hero != null) Log.stage("casts");
        if (hero != null) casts.poll(hero, (skill) -> meter.onCast(skill, now));
        if (now - lastGroupRead > 2000) {
            lastGroupRead = now;
            Log.stage("group");
            try meter.readGroup(app) catch (e:Dynamic) Log.once("group", "group read failed: " + Std.string(e), 2);
        }
        Log.stage("meter");
        meter.update(app, hero, now);

        var ui = G.stat("ui.BaseUI", "current");
        var s2d = G.f(ui, "s2d");
        if (s2d == null) return;
        if (!built) {
            if (buildFailed || hero == null) return;
            Log.stage("build ui");
            build(s2d);
            if (!built) return;
        }
        if (G.f(root, "parent") == null) Gfx.addChild(s2d, root);

        var sw = G.num(G.f(s2d, "width"), 1920), sh = G.num(G.f(s2d, "height"), 1080);
        Input.poll(s2d, now / 1000);
        if (hero == null) {
            Gfx.visible(root, false);
            return;
        }
        Gfx.visible(root, true);
        if (Input.pressed(config.keyBigMap)) minimap.toggleBig();
        if (Input.pressed(config.keyMinimap)) {
            config.showMinimap = !config.showMinimap;
            saveSoon();
        }
        if (Input.pressed(config.keyDps)) {
            config.showDps = !config.showDps;
            saveSoon();
        }
        if (Input.pressed(config.keyReset)) meter.manualReset(now);
        if (Input.pressed(config.keyPause)) {
            meter.paused = !meter.paused;
            dps.refresh();
            Log.info("meter " + (meter.paused ? "paused" : "resumed"));
        }

        Log.stage("minimap");
        minimap.update(config, app, hero, sw, sh, dt, now, meter.groupUids);
        Log.stage("map options");
        mapOpts.update(config, sw, sh);
        Log.stage("dps window");
        dps.show(config.showDps);
        if (!config.showDps && buildWin.isOpen) buildWin.close();
        if (!config.showDps && fightWin.isOpen) fightWin.close();
        if (config.showDps) {
            dps.update(config, now, sw, sh);
            fightWin.update(sw, sh);
            buildWin.update(sw, sh);
            var rs = dps.resizedTo();
            if (rs != null) {
                config.dpsW = rs.w;
                config.dpsH = rs.h;
                saveSoon();
            }
            if (dps.moved()) {
                config.dpsX = dps.x;
                config.dpsY = dps.y;
                saveSoon();
            }
        }

        // One tooltip for all windows (the map draws its own).
        var tipText:String = null;
        tipText = mapOpts.hoveredTip();
        if (tipText == null && config.showDps) {
            tipText = buildWin.hoveredTip();
            if (tipText == null) tipText = fightWin.hoveredTip();
            if (tipText == null) tipText = dps.hoveredTip();
        }
        if (tipText != null) tooltip.show(tipText, Input.mouseX + 16, Input.mouseY + 14, sw, sh) else tooltip.hide();

        if (saveAt >= 0 && now >= saveAt) {
            saveAt = -1;
            try config.save() catch (e:Dynamic) Log.err("config save failed: " + Std.string(e));
        }
        if (now - stats.lastLog > 60000) {
            stats.lastLog = now;
            Log.info('alive: frames=${stats.frames} hits=${stats.hits} mine=${stats.mine} seen=${DpsCapture.seen} dropped=${DpsCapture.dropped} history=${meter.tracker.history.length}');
        }
    }

    static function build(s2d:Dynamic):Void {
        try {
            var t0 = haxe.Timer.stamp();
            if (Gfx.font == null) Gfx.font = Gfx.pickFont(s2d);
            if (Gfx.font == null) {
                Log.once("nofont", "no game font found yet, waiting");
                return;
            }
            Log.info("font: " + G.str(G.f(Gfx.font, "name")) + " " + Gfx.fontSize);
            root = Gfx.obj(s2d);
            minimap = new Minimap(root, DATA_DIR);
            if (config.featAtlas) {
                Log.stage("atlas");
                Panel.atlas = MapTexture.loadTile(DATA_DIR + "/players_gear_atlas.png");
            }
            dps = new DpsWindow(root, meter, config.dpsX, config.dpsY);
            dps.setSize(config.dpsW, config.dpsH);
            fightWin = new FightWindow(root, meter, config.dpsX + 680, config.dpsY);
            buildWin = new BuildWindow(root, config.dpsX + 680, config.dpsY + 40);
            dps.onBuild = (b, sub) -> buildWin.open(b, sub);
            fightWin.onBuild = (b, sub) -> buildWin.open(b, sub);
            dps.onFight = (f) -> fightWin.open(f);
            fightWin.onClose = () -> {
                dps.selectedFight = -1;
                dps.refresh();
            };
            mapOpts = new MapOptions(root, 400, 80);
            minimap.onOptions = () -> mapOpts.toggle();
            minimap.onFiltersChanged = () -> mapOpts.refresh();
            tooltip = new Minimap.Tooltip(root); // last: drawn above the windows
            built = true;
            Log.info("ui built in " + Math.round((haxe.Timer.stamp() - t0) * 1000) + " ms");
        } catch (e:Dynamic) {
            buildFailed = true;
            Log.err("ui build failed, the mod stays idle: " + Std.string(e));
        }
    }

    static function teardown():Void {
        if (!built) return;
        try {
            if (meter != null) meter.save(lastNow);
            Gfx.remove(root);
        } catch (_:Dynamic) {}
        root = null;
        minimap = null;
        dps = null;
        built = false;
        Log.info("ui removed");
    }

    /** The C++ overlay's history, imported once and never written. */
    static function overlayHistoryPath():String {
        var local = Sys.getEnv("LOCALAPPDATA");
        return local == null ? null : local + "/farever-minimap/fight_history.json";
    }
}
