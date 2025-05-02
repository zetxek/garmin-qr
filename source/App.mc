using Toybox.Application;
using Toybox.WatchUi;
using Toybox.System;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Timer;
using Toybox.Communications;
using Toybox.Application.Storage;

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
    var image as Null or Graphics.BitmapResource;
    var isDownloading;

    function initialize() {
        View.initialize();
        System.println("AppView initialized");
        image = null;
        isDownloading = false;        
    }


    function downloadImage() {
        if (isDownloading) {
            System.println("Already downloading");
            return;
        }
        else {
            System.println("Downloading image");
            isDownloading = true;
            var url = "https://qr-generator-329626796314.europe-west4.run.app/qr?text=zetxek";
            var params = null;
            var options = {
                :maxWidth => 150,
                :maxHeight => 150
            };


            Communications.makeImageRequest(
               url,
               params,
               options,
               method(:responseCallback)
            );
        }
    }

    var responseCode;
    // Set up the responseCallback function to return an image or null
    function responseCallback(responseCode as Lang.Number, data as Null or Graphics.BitmapResource) as Void {
        System.println("responseCallback. Response code: " + responseCode);
        responseCode = responseCode;
        if (responseCode == 200) {
            image = data;
            WatchUi.requestUpdate();
            System.println("Image downloaded");
        } else {
            image = null;
        }
    }


    function onLayout(dc) {
    }

    function onShow() {
        System.println("onShow");
        downloadImage();
    }

    function onUpdate(dc) {
        View.onUpdate(dc);
        
        // Clear the screen
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        
        if (image != null) {
            System.println("Drawing image");
            drawImage(dc);
        } else if (isDownloading) {
            System.println("Drawing loading");
            // Show loading message
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                dc.getWidth() / 2,
                dc.getHeight() / 2,
                Graphics.FONT_MEDIUM,
                "Loading...",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
        } else {
            System.println("Drawing text");
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                dc.getWidth() / 2,
                dc.getHeight() / 2,
                Graphics.FONT_MEDIUM,
                "Press UP to refresh",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
        }
    }

    function drawImage(dc) {
        var screenWidth = dc.getWidth();
        var screenHeight = dc.getHeight();
        var x = (screenWidth - 150) / 2;  // Center the 150x150 image
        var y = (screenHeight - 150) / 2;
        dc.drawBitmap(x, y, image as WatchUi.BitmapResource);
    }

    function onHide() {
    }

    function onKey(keyEvent) {
        System.println("onKey");
        var key = keyEvent.getKey();
        
        if (key == WatchUi.KEY_UP || key == WatchUi.KEY_ENTER) {
            // Force refresh the image
            downloadImage();
            return true;
        }
        
        return false;
    }
} 