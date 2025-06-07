using Toybox.WatchUi;

class AppDelegate extends WatchUi.BehaviorDelegate {
    var view;

    function initialize(view) {
        BehaviorDelegate.initialize();
        self.view = view;
    }

    function onKey(keyEvent) {
        return view.onKey(keyEvent);
    }

    function onSwipe(swipeEvent) {
        return view.onSwipe(swipeEvent);
    }
}
