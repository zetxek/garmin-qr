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
    var image;

    function initialize() {
        View.initialize();
        image = Application.loadResource(Rez.Drawables.DisplayImage);
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
        
        // Draw the image in the center
        var imageWidth = image.getWidth();
        var imageHeight = image.getHeight();
        var screenWidth = dc.getWidth();
        var screenHeight = dc.getHeight();
        
        var x = (screenWidth - imageWidth) / 2;
        var y = (screenHeight - imageHeight) / 2;
        
        dc.drawBitmap(x, y, image);
    }

    function onHide() {
    }
} 