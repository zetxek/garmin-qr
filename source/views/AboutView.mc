import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Application;
import Toybox.Graphics;

//! About screen. Tap, swipe or press start to flip between the text and a QR code pointing at
//! the repository.
(:app)
class AboutView extends WatchUi.View {

    var showQr as Boolean;

    function initialize() {
        View.initialize();
        showQr = false;
    }

    function onLayout(dc as Graphics.Dc) as Void {
        setLayout(Rez.Layouts.AboutLayout(dc));
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        View.onUpdate(dc);

        var aboutText = findDrawableById("AboutText");
        var githubQr = findDrawableById("GithubQR");

        if (aboutText != null) {
            var version = Application.Properties.getValue("appVersion");
            if (!(version instanceof String)) { version = "Unknown"; }
            (aboutText as WatchUi.Text).setText(
                "About the app\n\nAuthor: Adrián Moreno Peña\nVersion: " + version +
                "\nCode: github.com/zetxek/garmin-qr"
            );
            aboutText.setVisible(!showQr);
        }
        if (githubQr != null) {
            githubQr.setVisible(showQr);
        }
    }

    function toggle() as Boolean {
        showQr = !showQr;
        WatchUi.requestUpdate();
        return true;
    }
}

(:app)
class AboutViewDelegate extends WatchUi.BehaviorDelegate {
    var view as AboutView;

    function initialize(view as AboutView) {
        BehaviorDelegate.initialize();
        self.view = view;
    }

    function onTap(clickEvent as WatchUi.ClickEvent) as Boolean { return view.toggle(); }
    function onSwipe(swipeEvent as WatchUi.SwipeEvent) as Boolean { return view.toggle(); }
    function onSelect() as Boolean { return view.toggle(); }

    function onKey(keyEvent as WatchUi.KeyEvent) as Boolean {
        var key = keyEvent.getKey();
        if (key == WatchUi.KEY_START || key == WatchUi.KEY_UP || key == WatchUi.KEY_DOWN) {
            return view.toggle();
        }
        return false;
    }
}
