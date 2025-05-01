using Toybox.Application;
using Toybox.WatchUi;
using Toybox.System;
using Toybox.Graphics;
using Toybox.Lang;

class App extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
    }

    function onStop(state) {
    }

    function getInitialView() {
        return [ new AppView() ];
    }
}

class AppView extends WatchUi.View {
    var images;
    var currentImageIndex;
    var imageY;

    function initialize() {
        View.initialize();
        images = [
            Application.loadResource(Rez.Drawables.DisplayImage1),
            Application.loadResource(Rez.Drawables.DisplayImage2)
        ];
        currentImageIndex = 0;
        imageY = 0;
    }

    function onLayout(dc) {
    }

    function onShow() {
    }

    function onUpdate(dc) {
        View.onUpdate(dc);
        
        // Clear the screen
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        
        // Draw the current image
        var image = images[currentImageIndex];
        var imageWidth = image.getWidth();
        var imageHeight = image.getHeight();
        var screenWidth = dc.getWidth();
        
        var x = (screenWidth - imageWidth) / 2;
        
        dc.drawBitmap(x, imageY, image);
    }

    function onHide() {
    }

    function onSwipe(swipeEvent) {
        if (swipeEvent.getDirection() == WatchUi.SWIPE_UP) {
            // Scroll up to next image
            currentImageIndex = (currentImageIndex + 1) % images.size();
            WatchUi.requestUpdate();
        } else if (swipeEvent.getDirection() == WatchUi.SWIPE_DOWN) {
            // Scroll down to previous image
            currentImageIndex = (currentImageIndex - 1) % images.size();
            if (currentImageIndex < 0) {
                currentImageIndex = images.size() - 1;
            }
            WatchUi.requestUpdate();
        }
        return true;
    }
} 