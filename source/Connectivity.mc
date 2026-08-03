import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

//! Tracks whether the phone is reachable and nudges the download queue when it comes back.
//!
//! Only started once the main view exists; the glance process never runs a timer.
(:app)
class Connectivity {

    //! 15s. The previous 5s poll ran a timer, a queue scan and a UI update three times as often
    //! for a screen that shows a static image.
    const POLL_MS = 15000;

    static var instance as Connectivity? = null;

    static function get() as Connectivity {
        if (instance == null) {
            instance = new Connectivity();
        }
        return instance;
    }

    //! Best-effort phone reachability.
    //!
    //! When the device does not report a state we assume connected and let the request fail
    //! with -104, which the download queue already handles. Assuming disconnected — as the
    //! previous version did — meant the app would never even try.
    static function isConnected() as Boolean {
        try {
            // `!= false` rather than `== true`: an unreported state reads as connected, so a
            // device that does not populate the field still attempts the request.
            return System.getDeviceSettings().phoneConnected != false;
        } catch (e) {
            return true;
        }
    }

    var connected as Boolean;
    var timer as Timer.Timer?;

    function initialize() {
        connected = Connectivity.isConnected();
        timer = null;
    }

    function start() as Void {
        if (timer != null) { return; }
        try {
            timer = new Timer.Timer();
            timer.start(method(:poll), POLL_MS, true);
        } catch (e) {
            Log.warn("[Connectivity] could not start poll timer: " + e.getErrorMessage());
            timer = null;
        }
    }

    function stop() as Void {
        if (timer != null) {
            timer.stop();
            timer = null;
        }
    }

    function poll() as Void {
        try {
            var now = Connectivity.isConnected();
            if (now != connected) {
                connected = now;
                Log.debug("[Connectivity] phone " + (now ? "reconnected" : "disconnected"));
                WatchUi.requestUpdate();
            }

            // Also the heartbeat that lets a backed-off download try again: `pump` is a no-op
            // when nothing is queued or everything is still waiting out its backoff.
            ImageService.get().pump();
        } catch (e) {
            Log.warn("[Connectivity] poll failed: " + e.getErrorMessage());
        }
    }
}
