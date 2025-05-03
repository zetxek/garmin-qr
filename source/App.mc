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
    var errorMessage as Null or Lang.String;
    var errorTimer as Null or Timer.Timer;

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
        System.println("Starting download for text: " + text);
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
                if (data == null) {
                    System.println("Error: Received null data");
                    showError("Failed to generate QR code");
                    return;
                }
                
                System.println("Processing downloaded image");
                var bitmapResource = data as WatchUi.BitmapResource;
                
                // Update current code
                images[currentIndex] = bitmapResource;
                Storage.setValue("qr_image_" + currentIndex, bitmapResource);
                System.println("Updated code at index: " + currentIndex);
                
                WatchUi.requestUpdate();
                System.println("Image downloaded and processed successfully");
            } catch (e) {
                System.println("Error saving image: " + e.getErrorMessage());
                showError("Failed to save QR code");
            }
        } else {
            System.println("Download failed with code: " + responseCode);
            if (responseCode == -100) {  // Network timeout
                showError("Network timeout");
            } else if (responseCode == -101) {  // Network request failed
                showError("Network error");
            } else {
                showError("Failed to generate QR code");
            }
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
        
        if (images.size() == 0) {
            // Show empty state
            System.println("Drawing empty state");
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                dc.getWidth() / 2,
                dc.getHeight() / 2,
                Graphics.FONT_MEDIUM,
                "No QR codes yet\nPress any key to add one",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
        } else if (currentIndex < images.size()) {
            // Show current QR code
            System.println("Drawing image " + currentIndex);
            drawImage(dc, images[currentIndex]);
            
            // Draw text at the bottom
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                dc.getWidth() / 2,
                dc.getHeight() - 40,  // 40 pixels from bottom
                Graphics.FONT_XTINY,
                "Code " + (currentIndex + 1) + " of " + images.size(),
                Graphics.TEXT_JUSTIFY_CENTER
            );
        }
        
        // Show error message if there is one
        if (errorMessage != null) {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                dc.getWidth() / 2,
                dc.getHeight() - 20,  // 20 pixels from bottom
                Graphics.FONT_XTINY,
                errorMessage,
                Graphics.TEXT_JUSTIFY_CENTER
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
        // Clear any error message when a key is pressed
        if (errorMessage != null) {
            errorMessage = null;
            WatchUi.requestUpdate();
        }

        var key = keyEvent.getKey();
        System.println("onKey: " + key + " (images.size: " + images.size() + ", currentIndex: " + currentIndex + ")");
        
        if (images.size() == 0) {
            // If no items, any key press shows the add menu
            showAddMenu();
            return true;
        }
        
        if (key == WatchUi.KEY_UP) {
            System.println("UP pressed");
            if (currentIndex > 0) {
                currentIndex--;
            } else {
                currentIndex = images.size() - 1;  // Wrap to end
            }
            System.println("Moved to code: " + currentIndex);
            WatchUi.requestUpdate();
            return true;
        } else if (key == WatchUi.KEY_DOWN) {
            System.println("DOWN pressed");
            if (currentIndex < images.size() - 1) {
                currentIndex++;
            } else {
                currentIndex = 0;  // Wrap to beginning
            }
            System.println("Moved to code: " + currentIndex);
            WatchUi.requestUpdate();
            return true;
        } else if (key == WatchUi.KEY_ENTER) {
            System.println("ENTER pressed - showing menu");
            showItemMenu();
            return true;
        }
        
        return false;
    }

    function showAddMenu() {
        var menu = new WatchUi.Menu();
        menu.setTitle("Add QR Code");
        menu.addItem("Add New", :add);
        WatchUi.pushView(menu, new CodeMenuDelegate(self), WatchUi.SLIDE_UP);
    }

    function showItemMenu() {
        var menu = new WatchUi.Menu();
        menu.setTitle("Code Options");
        menu.addItem("Remove", :remove);
        menu.addItem("Add New", :add);
        WatchUi.pushView(menu, new CodeMenuDelegate(self), WatchUi.SLIDE_UP);
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

    function startNewCodeMode() {
        System.println("Starting text input");
        var textPicker = new WatchUi.TextPicker("Enter QR Text");
        WatchUi.pushView(textPicker, new TextPickerDelegate(self), WatchUi.SLIDE_UP);
    }

    function onTap(clickEvent) {
        if (isNewCodeMode) {
            System.println("Tap in new code mode");
            // Start download for new code
            downloadImage("new_code_" + System.getTimer());
            return true;
        }
        return false;
    }

    function onSwipe(swipeEvent) {
        if (isNewCodeMode) {
            // Cancel new code mode on swipe
            isNewCodeMode = false;
            WatchUi.requestUpdate();
            return true;
        }
        return false;
    }

    function showError(message as Lang.String) {
        errorMessage = message;
        WatchUi.requestUpdate();
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
        } else if (item == :add) {
            view.startNewCodeMode();
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

class TextPickerDelegate extends WatchUi.TextPickerDelegate {
    var view;
    var currentText;

    function initialize(view) {
        TextPickerDelegate.initialize();
        self.view = view;
        self.currentText = "";
    }

    function onTextEntered(text, changed) {
        System.println("Text entered: " + text);
        if (text != null && text.length() > 0) {
            try {
                if (changed) {
                    System.println("Text changed, regenerating QR code");
                    view.downloadImage(text);
                } else {
                    System.println("Text unchanged, keeping current QR code");
                }
            } catch (e) {
                System.println("Error in onTextEntered: " + e.getErrorMessage());
            }
        } else {
            System.println("Empty text entered");
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }

    function onCancel() {
        System.println("Text input cancelled");
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
} 