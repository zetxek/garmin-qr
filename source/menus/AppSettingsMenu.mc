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
        // Named for the symptom, not the mechanism: someone reaches for this because a code will
        // not scan, not because they want a wider one. The property key stays `wideBarcode` --
        // renaming it would orphan the value on watches that already have it set.
        menu.addItem(new WatchUi.MenuItem(
            "Thicker bars", WideBarcode.enabled() ? "Enabled" : "Disabled", :toggle_wide_barcode, {}));
        menu.addItem(new WatchUi.MenuItem(
            "Sort by", SortOrder.label(SortOrder.current()), :sort_by, {}));
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
        } else if (item.getId() == :sort_by) {
            WatchUi.pushView(
                SortByMenu.build(), new SortByMenuDelegate(view, item), WatchUi.SLIDE_LEFT);
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
        try {
            Application.Properties.setValue(WideBarcode.SETTING, !WideBarcode.enabled());
        } catch (e) {
            Log.warn("[AppSettingsMenu] could not persist wideBarcode: " + e.getErrorMessage());
        }

        // Read back rather than trust the value just written: if setValue threw, the property is
        // unchanged, and the label must say so rather than claim the flip that didn't happen.
        item.setSubLabel(WideBarcode.enabled() ? "Enabled" : "Disabled");
        WatchUi.requestUpdate();
    }
}

//! The "Sort by" submenu behind the Settings entry of the same name.
(:app)
module SortByMenu {

    function build() as WatchUi.Menu2 {
        var menu = new WatchUi.Menu2({:title => "Sort by"});
        var current = SortOrder.current();
        addOrder(menu, SortOrder.DATE, :sort_date, current);
        addOrder(menu, SortOrder.TITLE, :sort_title, current);
        addOrder(menu, SortOrder.CODE, :sort_code, current);
        return menu;
    }

    function addOrder(menu as WatchUi.Menu2, order as Number, id as Symbol, current as Number) as Void {
        menu.addItem(new WatchUi.MenuItem(
            SortOrder.label(order), order == current ? "Selected" : null, id, {}));
    }
}

(:app)
class SortByMenuDelegate extends WatchUi.Menu2InputDelegate {
    var view as AppView;
    var settingsItem as WatchUi.MenuItem;

    function initialize(view as AppView, settingsItem as WatchUi.MenuItem) {
        Menu2InputDelegate.initialize();
        self.view = view;
        self.settingsItem = settingsItem;
    }

    function onSelect(item) as Void {
        var id = item.getId();
        var order = SortOrder.DATE;
        if (id == :sort_title) {
            order = SortOrder.TITLE;
        } else if (id == :sort_code) {
            order = SortOrder.CODE;
        }

        try {
            Application.Properties.setValue(SortOrder.SETTING, order);
        } catch (e) {
            Log.warn("[SortByMenu] could not persist sortBy: " + e.getErrorMessage());
        }

        // Read back rather than trust the value just written: if setValue threw, the setting is
        // unchanged, and the parent label must say so.
        settingsItem.setSubLabel(SortOrder.label(SortOrder.current()));
        view.onCodesChanged();
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        WatchUi.requestUpdate();
    }
}
