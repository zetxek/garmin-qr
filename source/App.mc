import Toybox.Lang;
import Toybox.Application;
import Toybox.WatchUi;

//! Application entry point.
//!
//! This class is linked into *both* the app process and the much smaller glance process, so its
//! lifecycle hooks have to stay glance-safe. `initialize`, `onStart` and `onStop` all run when
//! the glance is drawn, and the app-only classes they would otherwise touch (`AppView`, the
//! download queue, the connectivity timer) do not exist in that process. Everything is
//! therefore deferred to `getInitialView` and gated behind `started`.
(:app)
class App extends Application.AppBase {

    //! Held on by default: the whole point of the app is a code someone can scan, and a screen
    //! that dims while the wrist is held up to a reader defeats it. `Backlight` caps how long it
    //! will hold, so this cannot pin the display on indefinitely.
    var keepScreenOn as Boolean = true;
    //! False while running as a glance. Guards every path that touches app-only classes.
    var started as Boolean = false;
    var backlight as Backlight?;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
    }

    (:app)
    function onStop(state) {
        if (!started) { return; }
        Connectivity.get().stop();
        ImageService.get().stopWatchdog();
        if (backlight != null) {
            backlight.disable();
        }
    }

    (:app)
    function getInitialView() {
        started = true;
        backlight = new Backlight();
        loadSettings();
        // Before anything reads storage: an install upgraded from an older release still has
        // legacy type values and settings entries the editor cannot save.
        Migration.run();
        CodeStore.reconcile();

        var view = new AppView();
        return [ view, new AppDelegate(view) ];
    }

    function getGlanceView() {
        return [ new GlanceView() ];
    }

    //! Fired when the phone pushes new settings. `codesList` is authoritative here — the user
    //! has just edited it — so it is copied into Storage, invalidating only the codes whose
    //! encoded content actually changed.
    (:app)
    function onSettingsChanged() {
        Log.debug("[App] settings changed");
        loadSettings();

        try {
            CodeStore.adoptProperties();
        } catch (e) {
            Log.warn("[App] could not adopt settings: " + e.getErrorMessage());
        }

        var view = AppView.current;
        if (view != null) {
            view.onCodesChanged();
            view.applyScreenTimeout();
        }
        WatchUi.requestUpdate();
    }

    function loadSettings() as Void {
        var value = null;
        try {
            value = Application.Properties.getValue("keepScreenOn");
        } catch (e) {
            value = null;
        }
        keepScreenOn = (value instanceof Boolean) ? value : true;
    }
}
