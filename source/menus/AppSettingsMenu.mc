import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Application;

//! On-watch settings, for the handful of options that make sense without the phone.
(:app)
module AppSettingsMenu {

    function build() as WatchUi.Menu2 {
        var menu = new WatchUi.Menu2({:title => "Settings"});
        var enabled = (Application.getApp() as App).keepScreenOn;
        menu.addItem(new WatchUi.MenuItem(
            "Keep Screen On", enabled ? "Enabled" : "Disabled", :toggle_keep_screen_on, {}));
        menu.addItem(new WatchUi.MenuItem(
            "Wide Barcode", WideBarcode.enabled() ? "Enabled" : "Disabled", :toggle_wide_barcode, {}));
        return menu;
    }
}

(:app)
class AppSettingsMenuDelegate extends WatchUi.Menu2InputDelegate {
    var view as AppView;

    function initialize(view as AppView) {
        Menu2InputDelegate.initialize();
        self.view = view;
    }

    function onSelect(item) as Void {
        if (item.getId() == :toggle_keep_screen_on) {
            toggleKeepScreenOn(item);
        } else if (item.getId() == :toggle_wide_barcode) {
            toggleWideBarcode(item);
        }
    }

    function toggleKeepScreenOn(item) as Void {
        var app = Application.getApp() as App;
        app.keepScreenOn = !app.keepScreenOn;
        try {
            Application.Properties.setValue("keepScreenOn", app.keepScreenOn);
        } catch (e) {
            Log.warn("[AppSettingsMenu] could not persist keepScreenOn: " + e.getErrorMessage());
        }

        item.setSubLabel(app.keepScreenOn ? "Enabled" : "Disabled");
        view.applyScreenTimeout();
        WatchUi.requestUpdate();
    }

    function toggleWideBarcode(item) as Void {
        var next = !WideBarcode.enabled();
        try {
            Application.Properties.setValue(WideBarcode.SETTING, next);
        } catch (e) {
            Log.warn("[AppSettingsMenu] could not persist wideBarcode: " + e.getErrorMessage());
        }

        item.setSubLabel(next ? "Enabled" : "Disabled");
        WatchUi.requestUpdate();
    }
}
