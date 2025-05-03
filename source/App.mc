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
        var view = new AppView();
        return [ view, new AppDelegate(view) ];
    }
}

class AppView extends WatchUi.View {
    var images as Lang.Array<Null or WatchUi.BitmapResource>;
    var currentIndex as Lang.Number;
    var isDownloading;
    var isNewCodeMode;

    function initialize() {
        View.initialize();
        System.println("AppView initialized");
        images = new [0];
        currentIndex = 0;
        isDownloading = false;
        isNewCodeMode = false;
        
        // Load cached images
        loadCachedImages();
    }

    function loadCachedImages() {
        System.println("Loading cached images");
        try {
            var count = Storage.getValue("qr_count");
            if (count != null) {
                System.println("Count: " + count);  
                for (var i = 0; i < count; i++) {
                    var cachedImage = Storage.getValue("qr_image_" + i);
                    if (cachedImage != null) {
                        images.add(cachedImage as WatchUi.BitmapResource);
                    }
                }
                System.println("Loaded " + images.size() + " cached images");
            }else{
                System.println("No cached images");
            }
        } catch (e) {
            System.println("Error loading cached images: " + e.getErrorMessage());
        }
    }

    function downloadImage(text as Lang.String) {
        if (isDownloading) {
            System.println("Already downloading");
            return;
        }
        
        isDownloading = true;
        var url = "https://qr-generator-329626796314.europe-west4.run.app/qr?text=" + text;
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

    function responseCallback(responseCode as Lang.Number, data as Null or Graphics.BitmapResource) as Void {
        System.println("responseCallback. Response code: " + responseCode);
        isDownloading = false;
        
        if (responseCode == 200) {
            try {
                if (isNewCodeMode) {
                    // Add new code
                    images.add(data as WatchUi.BitmapResource);
                    Storage.setValue("qr_image_" + (images.size() - 1), data);
                    Storage.setValue("qr_count", images.size());
                    System.println("New code added");
                    isNewCodeMode = false;
                } else {
                    // Update current code
                    images[currentIndex] = data as WatchUi.BitmapResource;
                    Storage.setValue("qr_image_" + currentIndex, data);
                }
                WatchUi.requestUpdate();
                System.println("Image downloaded");
            } catch (e) {
                System.println("Error saving image: " + e.getErrorMessage());
            }
        } else {
            System.println("Download failed: " + responseCode);
        }
    }

    function onLayout(dc) {
    }

    function onShow() {
        System.println("onShow");
    }

    function onUpdate(dc) {
        View.onUpdate(dc);
        
        // Clear the screen
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        
        if (isNewCodeMode) {
            // Show new code input screen
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                dc.getWidth() / 2,
                dc.getHeight() / 2,
                Graphics.FONT_MEDIUM,
                "Enter text for QR",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
        } else if (images.size() > 0 && currentIndex < images.size()) {
            // Show current QR code
            System.println("Drawing image " + currentIndex);
            drawImage(dc, images[currentIndex]);
        } else if (isDownloading) {
            // Show loading message
            System.println("Drawing loading");
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                dc.getWidth() / 2,
                dc.getHeight() / 2,
                Graphics.FONT_MEDIUM,
                "Loading...",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
        } else {
            // Show empty state
            System.println("Drawing empty state");
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                dc.getWidth() / 2,
                dc.getHeight() / 2,
                Graphics.FONT_MEDIUM,
                "Press UP to add code",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
        }
    }

    function drawImage(dc, image) {
        var screenWidth = dc.getWidth();
        var screenHeight = dc.getHeight();
        var x = (screenWidth - 150) / 2;
        var y = (screenHeight - 150) / 2;
        dc.drawBitmap(x, y, image as WatchUi.BitmapResource);
    }

    function onHide() {
    }

    function onKey(keyEvent) {
        var key = keyEvent.getKey();
        System.println("onKey: " + key + " (isNewCodeMode: " + isNewCodeMode + ", images.size: " + images.size() + ", currentIndex: " + currentIndex + ")");
        
        if (isNewCodeMode) {
            if (key == WatchUi.KEY_ENTER) {
                System.println("Creating new code");
                // Start download for new code
                downloadImage("new_code_" + System.getTimer());
                return true;
            }
        } else {
            if (key == WatchUi.KEY_UP) {
                System.println("UP pressed");
                if (currentIndex > 0) {
                    currentIndex--;
                    System.println("Moved to previous code: " + currentIndex);
                    WatchUi.requestUpdate();
                } else if (images.size() == 0) {
                    System.println("Starting new code mode");
                    // Start new code mode
                    isNewCodeMode = true;
                    WatchUi.requestUpdate();
                }
                return true;
            } else if (key == WatchUi.KEY_DOWN) {
                System.println("DOWN pressed");
                if (currentIndex < images.size() - 1) {
                    currentIndex++;
                    System.println("Moved to next code: " + currentIndex);
                    WatchUi.requestUpdate();
                }
                return true;
            } else if (key == WatchUi.KEY_ENTER && images.size() > 0) {
                System.println("ENTER pressed - showing menu");
                // Show menu for current code
                var menu = new WatchUi.Menu();
                menu.setTitle("Code Options");
                menu.addItem("Remove", :remove);
                WatchUi.pushView(menu, new CodeMenuDelegate(self), WatchUi.SLIDE_UP);
                return true;
            }
        }
        
        return false;
    }

    function removeCurrentCode() {
        if (images.size() > 0) {
            // Remove current code
            images.remove(images[currentIndex]);
            
            // Update storage
            Storage.deleteValue("qr_image_" + currentIndex);
            for (var i = currentIndex; i < images.size(); i++) {
                Storage.setValue("qr_image_" + i, images[i]);
            }
            Storage.setValue("qr_count", images.size());
            
            // Adjust current index
            if (currentIndex >= images.size()) {
                currentIndex = images.size() > 0 ? images.size() - 1 : 0;
            }
            
            WatchUi.requestUpdate();
        }
    }
}

class CodeMenuDelegate extends WatchUi.MenuInputDelegate {
    var view;

    function initialize(view) {
        MenuInputDelegate.initialize();
        self.view = view;
    }

    function onMenuItem(item) {
        if (item == :remove) {
            view.removeCurrentCode();
        }
    }
}

class AppDelegate extends WatchUi.BehaviorDelegate {
    var view;

    function initialize(view) {
        BehaviorDelegate.initialize();
        self.view = view;
    }

    function onKey(keyEvent) {
        return view.onKey(keyEvent);
    }

    function onTap(clickEvent) {
        System.println(clickEvent.getType());      // e.g. CLICK_TYPE_TAP = 0
        return true;
    }

    function onSwipe(swipeEvent) {
        System.println(swipeEvent.getDirection()); // e.g. SWIPE_DOWN = 2
        return true;
    }
} 