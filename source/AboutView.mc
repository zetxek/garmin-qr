using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Lang;

class AboutView extends WatchUi.View {
    var showQR as Lang.Boolean;
    function initialize() {
        View.initialize();
        showQR = false;
    }
    function onLayout(dc) {
        setLayout(Rez.Layouts.AboutLayout(dc));
    }
    function onUpdate(dc) {
        View.onUpdate(dc);
        var aboutText = findDrawableById("AboutText");
        var githubQR = findDrawableById("GithubQR");
        if (showQR) {
            if (aboutText != null) { aboutText.setVisible(false); }
            if (githubQR != null) { githubQR.setVisible(true); }
        } else {
            if (aboutText != null) { aboutText.setVisible(true); }
            if (githubQR != null) { githubQR.setVisible(false); }
        }
    }
    function onTap(tapEvent) {
        showQR = !showQR;
        WatchUi.requestUpdate();
    }
    function onKey(keyEvent) {
        var key = keyEvent.getKey();
        if (key == WatchUi.KEY_START || key == WatchUi.KEY_UP || key == WatchUi.KEY_DOWN) {
            showQR = !showQR;
            WatchUi.requestUpdate();
            return true;
        }
        return false;
    }
    function onSwipe(swipeEvent) {
        // Toggle between text and QR code on any swipe
        showQR = !showQR;
        WatchUi.requestUpdate();
        return true;
    }
}

class AboutViewDelegate extends WatchUi.BehaviorDelegate {
    var view;
    
    function initialize(view) {
        BehaviorDelegate.initialize();
        self.view = view;
    }
    
    function onSwipe(swipeEvent) {
        return view.onSwipe(swipeEvent);
    }
    
    function onTap(tapEvent) {
        return view.onTap(tapEvent);
    }
    
    function onKey(keyEvent) {
        return view.onKey(keyEvent);
    }
}
