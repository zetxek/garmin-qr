import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.Attention;

//! Holds the display on while a code is on screen, for the "keep screen on" setting.
//!
//! The setting previously called `WatchUi.requestUpdate()` and nothing else, which does not
//! affect the display timeout — the feature never worked. `Attention.backlight(true)` does,
//! but the backlight only stays on until the device's own timeout, so it has to be re-armed,
//! and devices with burn-in protection throw once it has been held on for around a minute.
(:app)
class Backlight {

    const REARM_MS = 25000;
    //! Give up after this long so a code left on screen cannot pin the display on.
    const MAX_HOLD_MS = 120000;

    var timer as Timer.Timer?;
    var heldMs as Number;

    function initialize() {
        timer = null;
        heldMs = 0;
    }

    static function isSupported() as Boolean {
        return (Toybox has :Attention) && (Attention has :backlight);
    }

    function enable() as Void {
        if (!isSupported() || timer != null) { return; }
        heldMs = 0;
        if (!arm()) { return; }
        try {
            timer = new Timer.Timer();
            timer.start(method(:onTick), REARM_MS, true);
        } catch (e) {
            Log.warn("[Backlight] could not start timer: " + e.getErrorMessage());
            timer = null;
        }
    }

    function disable() as Void {
        if (timer != null) {
            timer.stop();
            timer = null;
        }
        heldMs = 0;
        if (!isSupported()) { return; }
        try {
            Attention.backlight(false);
        } catch (e) {
            // Nothing to do; the display will time out on its own.
        }
    }

    function onTick() as Void {
        heldMs += REARM_MS;
        if (heldMs >= MAX_HOLD_MS || !arm()) {
            disable();
        }
    }

    //! Returns false when the device refused, which is the signal to stop trying.
    function arm() as Boolean {
        try {
            Attention.backlight(true);
            return true;
        } catch (e) {
            Log.debug("[Backlight] device refused to hold the backlight: " + e.getErrorMessage());
            return false;
        }
    }
}
