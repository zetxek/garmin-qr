using Toybox.Application;
using Toybox.WatchUi;
using Toybox.System;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Timer;
using Toybox.Communications;
using Toybox.Application.Storage;
using Toybox.Attention;

(:app)
class App extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
        onSettingsChanged();
    }

    function onStop(state) {
    }

    function getInitialView() {
        var view = new AppView();
        return [ view, new AppDelegate(view) ];
    }

    function getGlanceView() {
        return [ new GlanceView() ];
    }

    // Settings provider implementation
    function getSettingsView() {
        return [ new SettingsView(), new SettingsDelegate() ];
    }

    function onSettingsChanged() {
        System.println("Settings changed, updating codes...");
        var settings = Application.Properties.getValue("codesList") as Lang.Array<Lang.Dictionary>;
        System.println("Settings: " + settings);
        if (settings != null) {
            for (var i = 0; i < settings.size(); i++) {
                var code = settings[i];
                var keys = code.keys();
                for (var k = 0; k < keys.size(); k++) {
                    var key = keys[k];
                    System.println("[OnSettingsChanged] Key: " + key + ", Value: " + code.get(key));
                }
                // Save to Storage using the literal keys from settings
                var text = code.get("code_$index_text") as Lang.String;
                var title = code.get("code_$index_title") as Lang.String;
                var type = code.get("code_$index_type") as Lang.String;
                if (text != null && text.length() > 0) {
                    Storage.setValue("code_" + i + "_text", text);
                    Storage.setValue("code_" + i + "_title", title);
                    Storage.setValue("code_" + i + "_type", type);
                    System.println("[OnSettingsChanged] Saved code_" + i + "_text = " + text);
                } else {
                    Storage.deleteValue("code_" + i + "_text");
                    Storage.deleteValue("code_" + i + "_title");
                    Storage.deleteValue("code_" + i + "_type");
                }
            }
        }
    }
}

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

class AppView extends WatchUi.View {
    var images as Lang.Array<Null or WatchUi.BitmapResource>;
    var currentIndex as Lang.Number;
    var isDownloading;
    var errorMessage as Null or Lang.String;
    var errorTimer as Null or Timer.Timer;

    function initialize() {
        View.initialize();
        System.println("AppView initialized");
        images = new [10]; // Fixed size array for 10 codes
        currentIndex = 0;
        isDownloading = false;
        
        // Load all codes
        loadAllCodes();
    }

    function loadAllCodes() {
        System.println("Loading all codes from Storage");
        for (var i = 0; i < images.size(); i++) {
            images[i] = null;
        }
        var i = 0;
        while (i < images.size()) {
            var text = Storage.getValue("code_" + i + "_text");
            var title = Storage.getValue("code_" + i + "_title");
            System.println("[LoadAllCodes] Code " + i + " - Text: " + (text != null ? text : "null") + ", Title: " + (title != null ? title : "null"));

            if (text != null && text.length() > 0) {
                downloadImage(text, i);
            }
            i++;
        }
        System.println("Loaded " + i + " codes");

        for (var j = 0; j < images.size(); j++) {
            var text = Storage.getValue("code_" + j + "_text");
            System.println("[LoadAllCodes] code_" + j + "_text = " + text);
        }
    }

    function downloadImage(text as Lang.String, index as Lang.Number) {
        if (isDownloading) {
            System.println("Already downloading");
            return;
        }
        
        isDownloading = true;
        System.println("Starting download for text: " + text + " at index: " + index);
        
        var codeType = Storage.getValue("code_" + index + "_type");
        if (codeType == null) {
            codeType = "qr";
        }
        
        var url;
        if (codeType.equals("barcode")) {
            url = "https://qr-generator-329626796314.europe-west4.run.app/barcode?text=" + text;
        } else {
            url = "https://qr-generator-329626796314.europe-west4.run.app/qr?text=" + text;
        }
        
        System.println("URL: " + url);
        var params = null;
        var options = {
            :maxWidth => 200,
            :maxHeight => 200
        };

        Communications.makeImageRequest(
            url,
            params,
            options,
            method(:responseCallback)
        );
    }

    function responseCallback(responseCode as Lang.Number, data as Null or Graphics.BitmapResource) as Void {
        System.println("=== responseCallback start. Response code: " + responseCode);
        isDownloading = false;
        if (responseCode == 200 && data != null) {
            images[currentIndex] = data as WatchUi.BitmapResource;
            WatchUi.requestUpdate();
        }
        
        try {
            if (responseCode == 200) {
                if (data == null) {
                    System.println("Error: Received null data");
                    showError("Failed to generate code");
                    return;
                }
                
                System.println("Processing downloaded image");
                var bitmapResource = data as WatchUi.BitmapResource;
                images[currentIndex] = bitmapResource;
                
                try {
                    System.println("Saving image to storage at index: " + currentIndex);
                    Storage.setValue("qr_image_" + currentIndex, bitmapResource);
                    System.println("Updated code at index: " + currentIndex);
                } catch(e) {
                    System.println("Error in storage operations: " + e.getErrorMessage());
                    showError("Storage error: " + e.getErrorMessage());
                    return;
                }
                
                try {
                    System.println("Requesting UI update");
                    WatchUi.requestUpdate();
                    System.println("Image downloaded and processed successfully");
                } catch(e) {
                    System.println("Error requesting update: " + e.getErrorMessage());
                }
            } else {
                System.println("Download failed with code: " + responseCode);
                if (responseCode == -100) {
                    showError("Network timeout");
                } else if (responseCode == -101) {
                    showError("Network error");
                } else {
                    showError("Failed to generate code");
                }
            }
        } catch (e) {
            System.println("MAJOR ERROR in responseCallback: " + e.getErrorMessage());
            showError("Error: " + e.getErrorMessage());
        }
        System.println("=== responseCallback end");
    }

    function onLayout(dc) {
    }

    function onShow() {
        System.println("onShow");
    }

    function onUpdate(dc) {
        View.onUpdate(dc);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var hasAnyCodes = false;
        for (var i = 0; i < images.size(); i++) {
            if (images[i] != null) {
                hasAnyCodes = true;
                break;
            }
        }
        if (!hasAnyCodes) {
            // Show empty state
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            var centerY = dc.getHeight() / 2;
            
            // Get text heights
            var mainText = "No codes configured";
            var subText = "Configure in settings";
            var mainFont = Graphics.FONT_TINY;
            var subFont = Graphics.FONT_XTINY;
            var mainTextHeight = dc.getFontHeight(mainFont);
            var subTextHeight = dc.getFontHeight(subFont);
            
            // Draw main text
            dc.drawText(
                dc.getWidth() / 2,
                centerY - (mainTextHeight / 2) - (subTextHeight / 2),
                mainFont,
                mainText,
                Graphics.TEXT_JUSTIFY_CENTER
            );
            
            // Draw sub text
            dc.drawText(
                dc.getWidth() / 2,
                centerY + (mainTextHeight / 2) + (subTextHeight / 2) - subTextHeight,
                subFont,
                subText,
                Graphics.TEXT_JUSTIFY_CENTER
            );
        } else if (images[currentIndex] != null) {
            drawImage(dc, images[currentIndex]);
            
            // Draw text at the bottom
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                dc.getWidth() / 2,
                dc.getHeight() - 40,
                Graphics.FONT_XTINY,
                "Code " + (currentIndex + 1) + " of 10",
                Graphics.TEXT_JUSTIFY_CENTER
            );
        }
        
        // Show error message if there is one
        if (errorMessage != null) {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                dc.getWidth() / 2,
                dc.getHeight() - 6,
                Graphics.FONT_XTINY,
                errorMessage,
                Graphics.TEXT_JUSTIFY_CENTER
            );
        }
    }

    function drawImage(dc, image) {
        var screenWidth = dc.getWidth();
        var screenHeight = dc.getHeight();
        var bottomTextHeight = 30;
        var margin = 10;
        var bmp = image as WatchUi.BitmapResource;
        var bmpWidth = bmp.getWidth();
        var bmpHeight = bmp.getHeight();
        var x = (screenWidth - bmpWidth) / 2;
        var y = (screenHeight - bottomTextHeight - bmpHeight) / 2 + margin;
        
        // Draw title if available
        var title = Storage.getValue("code_" + currentIndex + "_title");
        if (title != null && title.length() > 0) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                screenWidth / 2,
                y - 50,
                Graphics.FONT_TINY,
                title,
                Graphics.TEXT_JUSTIFY_CENTER
            );
        }
        
        // Draw the code
        dc.drawBitmap(x, y, bmp);
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
        System.println("onKey: " + key + " (currentIndex: " + currentIndex + ")");
        
        if (key == WatchUi.KEY_UP) {
            System.println("UP pressed");
            if (currentIndex > 0) {
                currentIndex--;
            } else {
                currentIndex = 9;  // Wrap to end
            }
            System.println("Moved to code: " + currentIndex);
            WatchUi.requestUpdate();
            Attention.vibrate([new Attention.VibeProfile(50, 100)]);
            return true;
        } else if (key == WatchUi.KEY_DOWN) {
            System.println("DOWN pressed");
            if (currentIndex < 9) {
                currentIndex++;
            } else {
                currentIndex = 0;  // Wrap to beginning
            }
            System.println("Moved to code: " + currentIndex);
            WatchUi.requestUpdate();
            Attention.vibrate([new Attention.VibeProfile(50, 100)]);
            return true;
        } else if (key == 4) { // Key 4 pressed
            showCodeMenu();
            return true;
        }
        
        return false;
    }

    function showError(message as Lang.String) {
        errorMessage = message;
        WatchUi.requestUpdate();
    }

    function showCodeMenu() {
        var menu = new WatchUi.Menu();
        menu.setTitle("Code Info");

        var codeType = Storage.getValue("code_" + currentIndex + "_type");
        var title = Storage.getValue("code_" + currentIndex + "_title");
        var text = Storage.getValue("code_" + currentIndex + "_text");

        menu.addItem("Type: " + (codeType != null ? codeType : "N/A"), :info_type);
        menu.addItem("Title: " + (title != null ? title : "N/A"), :info_title);
        menu.addItem("Text: " + (text != null ? text : "N/A"), :info_text);
        menu.addItem("Refresh Codes", :refresh_codes);

        WatchUi.pushView(menu, new CodeMenuDelegate(self), WatchUi.SLIDE_UP);
    }
}

class CodeMenuDelegate extends WatchUi.BehaviorDelegate {
    var appView;
    function initialize(appView) {
        BehaviorDelegate.initialize();
        self.appView = appView;
    }
    function onMenuItem(item) {
        if (item == :refresh_codes) {
            appView.loadAllCodes();
        }
        return true;
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
}

(:glance)
class GlanceView extends WatchUi.GlanceView {
    var images as Lang.Array<Null or WatchUi.BitmapResource>;

    function initialize() {
        GlanceView.initialize();
        images = new [10];
        loadCachedImages();
    }

    function loadCachedImages() {
        try {
            for (var i = 0; i < 10; i++) {
                var cachedImage = Storage.getValue("qr_image_" + i);
                if (cachedImage != null) {
                    images[i] = cachedImage as WatchUi.BitmapResource;
                }
            }
        } catch (e) {
            System.println("Error loading cached images for glance: " + e.getErrorMessage());
        }
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var hasAnyCodes = false;
        for (var i = 0; i < 10; i++) {
            if (images[i] != null) {
                hasAnyCodes = true;
                break;
            }
        }

        if (hasAnyCodes) {
            var bmp = images[0];
            if (bmp != null) {
                try {
                    var bmpWidth = bmp.getWidth();
                    var bmpHeight = bmp.getHeight();
                    var screenHeight = dc.getHeight();

                    var marginLeft = 10;
                    var x = marginLeft;
                    var y = (screenHeight - bmpHeight) / 2;
                    dc.drawBitmap(x, y, bmp);

                    // Get the title and text
                    var title = Storage.getValue("code0_title");
                    var text = Storage.getValue("code0_text");
                    var displayText = "";
                    
                    if (text != null) {
                        displayText = text;
                    }
                    
                    if (title != null && title.length() > 0) {
                        displayText = title + " (" + displayText + ")";
                    }
                    
                    dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                    var textX = x + bmpWidth + 10;
                    var textY = screenHeight / 2;
                    
                    var maxWidth = dc.getWidth() - textX - 5;
                    var textWidth = dc.getTextWidthInPixels(displayText, Graphics.FONT_XTINY);
                    if (textWidth > maxWidth) {
                        var maxChars = displayText.length() * maxWidth / textWidth;
                        if (maxChars > 3) {
                            displayText = displayText.substring(0, maxChars.toNumber() - 3) + "...";
                        }
                    }
                    
                    dc.drawText(
                        textX,
                        textY,
                        Graphics.FONT_XTINY,
                        displayText,
                        Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER
                    );
                } catch (e) {
                    System.println("Error drawing glance: " + e.getErrorMessage());
                    dc.drawText(
                        dc.getWidth() / 2,
                        dc.getHeight() / 2,
                        Graphics.FONT_TINY,
                        "Error displaying code",
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
                    );
                }
            }
        } else {
            dc.drawText(
                dc.getWidth() / 2,
                dc.getHeight() / 2,
                Graphics.FONT_TINY,
                "No codes configured",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
        }
    }
}