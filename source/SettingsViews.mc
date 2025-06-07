using Toybox.WatchUi;
using Toybox.Application;

// Settings view class
class SettingsView extends WatchUi.View {
    function initialize() {
        View.initialize();
    }

    function onLayout(dc) {
        setLayout(Rez.Layouts.SettingsLayout(dc));
    }

    function onShow() {
    }

    function onUpdate(dc) {
        View.onUpdate(dc);
    }

    function onHide() {
    }
}

// Settings delegate class
class SettingsDelegate extends WatchUi.BehaviorDelegate {
    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onSelect() {
        return true;
    }
}

// App Settings view class for in-app settings management
class AppSettingsView extends WatchUi.View {
    function initialize() {
        View.initialize();
    }

    function onLayout(dc) {
        setLayout(Rez.Layouts.SettingsLayout(dc));
    }

    function onShow() {
        // Show settings menu when view is shown
        showSettingsMenu();
    }

    function onUpdate(dc) {
        View.onUpdate(dc);
    }

    function onHide() {
    }

    function showSettingsMenu() {
        var menu = new WatchUi.Menu2({:title => "Settings"});
        
        // Get current keepScreenOn setting
        var app = Application.getApp();
        var currentSetting = app.keepScreenOn;
        var statusText = currentSetting ? "Enabled" : "Disabled";
        
        menu.addItem(new WatchUi.MenuItem("Keep Screen On", statusText, :toggle_keep_screen_on, {}));
        
        WatchUi.pushView(menu, new AppSettingsMenuDelegate(), WatchUi.SLIDE_UP);
    }
}

// App Settings delegate class
class AppSettingsDelegate extends WatchUi.BehaviorDelegate {
    var view;
    
    function initialize(view) {
        BehaviorDelegate.initialize();
        self.view = view;
    }

    function onSelect() {
        return true;
    }
}

// App Settings Menu delegate class
class AppSettingsMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item) {
        var itemId = item.getId();
        if (itemId == :toggle_keep_screen_on) {
            // Toggle the keepScreenOn setting
            var app = Application.getApp();
            var newSetting = !app.keepScreenOn;
            
            // Update the app's setting
            app.keepScreenOn = newSetting;
            
            // Save to Properties
            Application.Properties.setValue("keepScreenOn", newSetting);
            
            // Apply the setting immediately if we're in the main view
            if (AppView.current != null) {
                AppView.current.applyScreenTimeoutSetting();
            }
            
            System.println("[AppSettings] keepScreenOn toggled to: " + newSetting);
            
            // Pop back to app menu - pop both the settings menu and AppSettingsView
            WatchUi.popView(WatchUi.SLIDE_DOWN); // Pop the settings menu
            WatchUi.popView(WatchUi.SLIDE_DOWN); // Pop the AppSettingsView
            
            return;
        }
        return;
    }

    function onBack() {
        System.println("[AppSettingsMenuDelegate] Back button pressed, returning to app menu");
        // Handle back button - pop both the settings menu and the AppSettingsView 
        // to return to the main app menu (the one with "About the app")
        WatchUi.popView(WatchUi.SLIDE_DOWN); // Pop the settings menu
        WatchUi.popView(WatchUi.SLIDE_DOWN); // Pop the AppSettingsView
    }
}
