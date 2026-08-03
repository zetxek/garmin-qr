import Toybox.Lang;
import Toybox.WatchUi;

//! The menu behind the start/menu button on the code screen.
(:app)
module CodeMenu {

    function build(view as AppView) as WatchUi.Menu2 {
        var menu = new WatchUi.Menu2({:title => "Code Info"});
        var slot = view.activeSlot();

        if (slot >= 0) {
            var text = CodeStore.getText(slot);
            var title = CodeStore.getTitle(slot);
            menu.addItem(new WatchUi.MenuItem(
                "Type", CodeStore.isBarcode(slot) ? "Barcode" : "QR Code", :info_type, {}));
            menu.addItem(new WatchUi.MenuItem(
                "Title", title.length() > 0 ? title : "N/A", :info_title, {}));
            menu.addItem(new WatchUi.MenuItem(
                "Text", text != null ? text : "N/A", :info_text, {}));
            menu.addItem(new WatchUi.MenuItem("Delete Code", null, :delete_code, {}));
        }

        menu.addItem(new WatchUi.MenuItem("Add Code", null, :add_code, {}));
        menu.addItem(new WatchUi.MenuItem(
            "Refresh Codes", null, :refresh_codes, {:icon => Rez.Drawables.refresh}));

        var pending = ImageService.get().pendingCount();
        if (pending > 0) {
            menu.addItem(new WatchUi.MenuItem("Sync Now", pending + " pending", :sync_now, {}));
        }

        menu.addItem(new WatchUi.MenuItem("Settings", null, :app_settings, {}));
        menu.addItem(new WatchUi.MenuItem("About the app", null, :about_app, {}));
        return menu;
    }
}

(:app)
class CodeMenuDelegate extends WatchUi.Menu2InputDelegate {
    var view as AppView;

    function initialize(view as AppView) {
        Menu2InputDelegate.initialize();
        self.view = view;
    }

    function onSelect(item) as Void {
        var id = item.getId();

        if (id == :refresh_codes) {
            view.forceReload();
            WatchUi.popView(WatchUi.SLIDE_DOWN);

        } else if (id == :sync_now) {
            ImageService.get().pump();
            WatchUi.popView(WatchUi.SLIDE_DOWN);

        } else if (id == :about_app) {
            var about = new AboutView();
            WatchUi.pushView(about, new AboutViewDelegate(about), WatchUi.SLIDE_UP);

        } else if (id == :app_settings) {
            WatchUi.pushView(AppSettingsMenu.build(), new AppSettingsMenuDelegate(view), WatchUi.SLIDE_UP);

        } else if (id == :add_code) {
            new AddCodeMenu(view).show();

        } else if (id == :delete_code) {
            var confirm = new WatchUi.Menu2({:title => "Delete this code?"});
            confirm.addItem(new WatchUi.MenuItem("Delete", null, :yes_delete, {}));
            confirm.addItem(new WatchUi.MenuItem("Keep", null, :no_delete, {}));
            WatchUi.pushView(confirm, new ConfirmDeleteDelegate(view), WatchUi.SLIDE_UP);

        } else {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        }
    }
}

(:app)
class ConfirmDeleteDelegate extends WatchUi.Menu2InputDelegate {
    var view as AppView;

    function initialize(view as AppView) {
        Menu2InputDelegate.initialize();
        self.view = view;
    }

    function onSelect(item) as Void {
        if (item.getId() != :yes_delete) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            return;
        }

        var slot = view.activeSlot();
        if (slot >= 0) {
            Log.debug("[CodeMenu] deleting slot " + slot);
            // Clears the code and its cached image together, so a slot reused by the next
            // "Add code" cannot come up showing the deleted code.
            CodeStore.deleteSlot(slot);
            ImageService.get().forget(slot);
            CodeStore.publishProperties();
        }

        WatchUi.popView(WatchUi.SLIDE_DOWN); // confirmation
        WatchUi.popView(WatchUi.SLIDE_DOWN); // code menu
        view.onCodesChanged();
    }
}
