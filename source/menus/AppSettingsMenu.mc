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
        if (item.getId() != :toggle_keep_screen_on) { return; }

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
}
