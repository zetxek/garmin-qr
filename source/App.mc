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
        // Do not call onSettingsChanged here
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
    var images as Lang.Array<Lang.Dictionary>;
    var currentIndex as Lang.Number;
    var isDownloading;
    var errorMessage as Null or Lang.String;
    var errorTimer as Null or Timer.Timer;
    var downloadingImageIdx as Null or Lang.Number;
    // Add a static reference to the current AppView
    public static var current as Null or AppView;
    var emptyState = false;

    function initialize() {
        View.initialize();
        System.println("AppView initialized");
        AppView.current = self;
        images = [];
        currentIndex = 0;
        isDownloading = false;
        
        // Load all codes
        loadAllCodes();
    }

    function loadAllCodes() {
        System.println("Loading all codes from Storage");
        images = [];
        for (var i = 0; i < 10; i++) {
            var text = Storage.getValue("code_" + i + "_text");
            var title = Storage.getValue("code_" + i + "_title");
            System.println("[LoadAllCodes] Code " + i + " - Text: " + (text != null ? text : "null") + ", Title: " + (title != null ? title : "null") + ", Type: " + Storage.getValue("code_" + i + "_type"));
            if (text != null && text.length() > 0) {
                images.add({:index => i, :image => null});
            }
        }
        System.println("Loaded " + images.size() + " codes");
        for (var j = 0; j < images.size(); j++) {
            var imgStatus = images[j][:image] != null ? "downloaded" : "not downloaded";
            var idx = images[j][:index];
            var text = Storage.getValue("code_" + idx + "_text");
            System.println("[LoadAllCodes] code_" + idx + "_text = " + text + ", image: " + imgStatus + ", type: " + Storage.getValue("code_" + idx + "_type"));
        }
        refreshMissingImages();
    }

    function refreshMissingImages() {
        for (var i = 0; i < images.size(); i++) {
            var idx = images[i][:index];
            var text = Storage.getValue("code_" + idx + "_text");
            var imgStatus = images[i][:image] != null ? "downloaded" : "not downloaded";
            System.println("[refreshMissingImages] code_" + idx + "_text = " + text + ", image: " + imgStatus);
            if (images[i][:image] == null) {
                if (text != null && text.length() > 0) {
                    downloadImage(text, i);
                }
            }
        }
    }

    function downloadImage(text as Lang.String, imagesIdx as Lang.Number) {
        if (isDownloading) {
            System.println("Already downloading");
            return;
        }
        isDownloading = true;
        downloadingImageIdx = imagesIdx;
        var index = images[imagesIdx][:index];
        System.println("Starting download for text: " + text + " at index: " + index);
        var codeType = Storage.getValue("code_" + index + "_type");
        if (codeType == null) {
            codeType = "0";  // Default to QR code
        }
        var url;
        if (codeType.equals("1")) {  // Check for "1" instead of "barcode"
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
        var imagesIdx = downloadingImageIdx;
        System.println("=== responseCallback start. Response code: " + responseCode);
        isDownloading = false;
        if (responseCode == 200 && data != null) {
            images[imagesIdx][:image] = data as WatchUi.BitmapResource;
            WatchUi.requestUpdate();
            AppView.downloadGlanceImage(Storage.getValue("code_" + imagesIdx + "_text"), imagesIdx);
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
                images[imagesIdx][:image] = bitmapResource;
                
                try {
                    System.println("Saving image to storage at index: " + imagesIdx);
                    Storage.setValue("qr_image_" + imagesIdx, bitmapResource);
                    System.println("Updated code at index: " + imagesIdx);
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
        // We'll set the layout in onUpdate based on state
    }

    function onShow() {
        System.println("onShow");
    }

    function onUpdate(dc) {
        System.println("onUpdate");
        View.onUpdate(dc);
        
        if (images.size() == 0) {
            System.println("Showing empty state layout");
            // Try using layout
            try {
                setLayout(Rez.Layouts.EmptyStateLayout(dc));
                View.onUpdate(dc); // Make sure layout is rendered
                System.println("Layout set successfully");
            } catch (e) {
                System.println("Error setting layout: " + e.getErrorMessage());
            }
            emptyState = true;
            return; // Let the layout handle drawing
        } else if (emptyState) {
            // Clear layout if we were showing empty state
            setLayout(null);
            emptyState = false;
        }
        
        // Check if currentIndex is valid after deletion
        if (currentIndex >= images.size()) {
            // Reset to a valid index
            currentIndex = 0;
            System.println("Reset currentIndex to 0 after deletion");
        }
        
        // Only proceed with drawing if not in empty state
        if (!emptyState) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            dc.clear();
            
            if (images[currentIndex][:image] != null) {
                drawImage(dc, images[currentIndex][:image], images[currentIndex][:index]);
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.drawText(
                    dc.getWidth() / 2,
                    dc.getHeight() - 40,
                    Graphics.FONT_XTINY,
                    "Code " + (currentIndex + 1) + " of " + images.size(),
                    Graphics.TEXT_JUSTIFY_CENTER
                );
            } else {
                // If image is not downloaded, trigger download
                var idx = images[currentIndex][:index];
                var text = Storage.getValue("code_" + idx + "_text");
                if (!isDownloading && text != null && text.length() > 0) {
                    System.println("[onUpdate] Image not downloaded for code_" + idx + ", starting download");
                    downloadImage(text, currentIndex);
                }
                // Show loading or error state
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.drawText(
                    dc.getWidth() / 2,
                    dc.getHeight() / 2,
                    Graphics.FONT_TINY,
                    "Loading image...",
                    Graphics.TEXT_JUSTIFY_CENTER
                );
            }
            
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
    }

    function drawImage(dc, image, index) {
        var screenWidth = dc.getWidth();
        var screenHeight = dc.getHeight();
        var bottomTextHeight = 30;
        var margin = 10;
        var bmp = image as WatchUi.BitmapResource;
        var bmpWidth = bmp.getWidth();
        var bmpHeight = bmp.getHeight();
        var x = (screenWidth - bmpWidth) / 2;
        var y = (screenHeight - bottomTextHeight - bmpHeight) / 2 + margin;
        var title = Storage.getValue("code_" + index + "_title");
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
        dc.drawBitmap(x, y, bmp);
    }

    function onHide() {
    }

    function onKey(keyEvent) {
        if (errorMessage != null) {
            errorMessage = null;
            WatchUi.requestUpdate();
        }
        var key = keyEvent.getKey();
        System.println("onKey: " + key + " (currentIndex: " + currentIndex + ")");
        if (key == WatchUi.KEY_UP) {
            if (images.size() > 0) {
                currentIndex = (currentIndex - 1 + images.size()) % images.size();
                WatchUi.requestUpdate();
                Attention.vibrate([new Attention.VibeProfile(50, 100)]);
            }
            return true;
        } else if (key == WatchUi.KEY_DOWN) {
            if (images.size() > 0) {
                currentIndex = (currentIndex + 1) % images.size();
                WatchUi.requestUpdate();
                Attention.vibrate([new Attention.VibeProfile(50, 100)]);
            }
            return true;
        } else if (key == 4) {
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
        var menu = new WatchUi.Menu2({:title => "Code Info"});
        
        if (images.size() > 0) {
            var idx = images[currentIndex][:index];
            var codeType = Storage.getValue("code_" + idx + "_type");
            var title = Storage.getValue("code_" + idx + "_title");
            var text = Storage.getValue("code_" + idx + "_text");
            var typeLabel = "N/A";
            
            System.println("Code type for index " + idx + ": " + codeType);
            
            if (codeType == null || codeType.equals("0") || codeType.equals("qr")) {
                typeLabel = "QR Code";
            } else if (codeType.equals("1") || codeType.equals("barcode")) {
                typeLabel = "Barcode";
            }
            
            menu.addItem(new WatchUi.MenuItem("Type", typeLabel, :info_type, {}));
            menu.addItem(new WatchUi.MenuItem("Title", title != null ? title : "N/A", :info_title, {}));
            menu.addItem(new WatchUi.MenuItem("Text", text != null ? text : "N/A", :info_text, {}));
            menu.addItem(new WatchUi.MenuItem("Delete Code", null, :delete_code, {}));
        }
        
        // Always show these options
        menu.addItem(new WatchUi.MenuItem("Add Code", null, :add_code, {}));
        menu.addItem(new WatchUi.MenuItem("Refresh Codes", null, :refresh_codes, {:icon => Rez.Drawables.refresh}));
        menu.addItem(new WatchUi.MenuItem("About the app", null, :about_app, {}));
        
        WatchUi.pushView(menu, new CodeInfoMenu2InputDelegate(self), WatchUi.SLIDE_UP);
    }

    public function downloadGlanceImage(text as Lang.String, index as Lang.Number) {
        var codeType = Storage.getValue("code_" + index + "_type");
        if (codeType == null) { codeType = "0"; }  // Default to QR
        var url;
        if (codeType.equals("1")) {  // Check for "1" instead of "barcode"
            url = "https://qr-generator-329626796314.europe-west4.run.app/barcode?text=" + text + "&size=80";
        } else {
            url = "https://qr-generator-329626796314.europe-west4.run.app/qr?text=" + text + "&size=80";
        }
        var options = { :maxWidth => 80, :maxHeight => 80 };
        Communications.makeImageRequest(
            url,
            null,
            options,
            method(:glanceResponseCallback)
        );
    }

    public static function glanceResponseCallback(responseCode as Lang.Number, data as Null or Graphics.BitmapResource) as Void {
        if (responseCode == 200 && data != null) {
            Storage.setValue("qr_image_glance_0", data as WatchUi.BitmapResource);
        }
    }

    function onSwipe(swipeEvent) {
        var direction = swipeEvent.getDirection();
        System.println("Swipe detected: " + direction);

        if (images.size() == 0) {
            return false;
        }
        
        if (direction == WatchUi.SWIPE_DOWN) {
            // Next code (same as KEY_DOWN)
            currentIndex = (currentIndex + 1) % images.size();
            WatchUi.requestUpdate();
            Attention.vibrate([new Attention.VibeProfile(50, 100)]);
            return true;
        } else if (direction == WatchUi.SWIPE_UP) {
            // Previous code (same as KEY_UP)
            currentIndex = (currentIndex - 1 + images.size()) % images.size();
            WatchUi.requestUpdate();
            Attention.vibrate([new Attention.VibeProfile(50, 100)]);
            return true;
        }
        return false;
    }
}

class CodeInfoMenu2InputDelegate extends WatchUi.Menu2InputDelegate {
    var appView;
    
    function initialize(appView) {
        Menu2InputDelegate.initialize();
        self.appView = appView;
    }
    
    function onSelect(item) {
        var itemId = item.getId();
        if (itemId == :refresh_codes) {
            appView.loadAllCodes();
            appView.refreshMissingImages();
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        } else if (itemId == :about_app) {
            var aboutView = new AboutView();
            WatchUi.pushView(aboutView, new AboutViewDelegate(aboutView), WatchUi.SLIDE_UP);
        } else if (itemId == :add_code) {
            var delegate = new AddCodeMenuDelegate(self.appView);
            delegate.showMenu();
        } else if (itemId == :delete_code) {
            var confirmMenu = new WatchUi.Menu2({:title => "Confirm Delete"});
            confirmMenu.addItem(new WatchUi.MenuItem("Yes", null, :yes_delete, {}));
            confirmMenu.addItem(new WatchUi.MenuItem("No", null, :no_delete, {}));
            WatchUi.pushView(confirmMenu, new ConfirmDeleteDelegate(self.appView), WatchUi.SLIDE_UP);
        } else {
            // For info items, just go back to main view
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        }
        return;
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

    function onSwipe(swipeEvent) {
        return view.onSwipe(swipeEvent);
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

        var hasAnyCodes = false;
        for (var i = 0; i < 10; i++) {
            if (images[i] != null) {
                hasAnyCodes = true;
                break;
            }
        }

        if (hasAnyCodes) {
            var bmp = Storage.getValue("qr_image_glance_0");
            if (bmp != null) {
                try {
                    var bmpWidth = bmp.getWidth();
                    var bmpHeight = bmp.getHeight();
                    var screenWidth = dc.getWidth();
                    var screenHeight = dc.getHeight();

                    // Calculate scale factor to fit QR code within screen
                    var maxSize = min(screenWidth, screenHeight) - 20; // 10px margin each side
                    var scale = 1.0;
                    if (bmpWidth > maxSize || bmpHeight > maxSize) {
                        scale = min(maxSize / bmpWidth, maxSize / bmpHeight);
                    }
                    var drawWidth = bmpWidth * scale;
                    var drawHeight = bmpHeight * scale;
                    var x = (screenWidth - drawWidth) / 2;
                    var y = (screenHeight - drawHeight) / 2;
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
                    var textX = x + drawWidth + 10;
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

    function min(a, b) {
        return (a < b) ? a : b;
    }

    function downloadGlanceImage(text as Lang.String, index as Lang.Number) {
        var codeType = Storage.getValue("code_" + index + "_type");
        if (codeType == null) { codeType = "0"; }  // Default to QR
        var url;
        if (codeType.equals("1")) {  // Check for "1" instead of "barcode"
            url = "https://qr-generator-329626796314.europe-west4.run.app/barcode?text=" + text + "&size=80";
        } else {
            url = "https://qr-generator-329626796314.europe-west4.run.app/qr?text=" + text + "&size=80";
        }
        var options = { :maxWidth => 80, :maxHeight => 80 };
        Communications.makeImageRequest(
            url,
            null,
            options,
            method(:glanceResponseCallback)
        );
    }

    function glanceResponseCallback(responseCode as Lang.Number, data as Null or Graphics.BitmapResource) as Void {
        if (responseCode == 200 && data != null) {
            Storage.setValue("qr_image_glance_0", data as WatchUi.BitmapResource);
        }
    }
}

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
        return true;
    }
    function onKey(keyEvent) {
        var key = keyEvent.getKey();
        if (key == WatchUi.KEY_START) {
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

class AddCodeTextPickerDelegate extends WatchUi.TextPickerDelegate {
    var parentDelegate;
    var field;
    function initialize(parentDelegate, field) {
        TextPickerDelegate.initialize();
        self.parentDelegate = parentDelegate;
        self.field = field;
    }
    function onTextEntered(text, changed) {
        System.println("[TextPickerDelegate] onTextEntered: field=" + self.field + ", text=" + text);
        if (text != null) {
            if (self.field == :input_title) {
                self.parentDelegate.codeTitle = text;
            } else if (self.field == :input_text) {
                self.parentDelegate.codeText = text;
            }
        }
        System.println("[TextPickerDelegate] After update: codeTitle=" + self.parentDelegate.codeTitle + ", codeText=" + self.parentDelegate.codeText);
        self.parentDelegate.showMenu();
        return true;
    }
}

class TypeMenu2InputDelegate extends WatchUi.Menu2InputDelegate {
    var parentDelegate;
    
    function initialize(parentDelegate) {
        Menu2InputDelegate.initialize();
        self.parentDelegate = parentDelegate;
    }
    
    function onSelect(item) {
        System.println("[TypeMenu2InputDelegate] onSelect: id=" + item.getId());
        if (item.getId() == :type_qr) {
            self.parentDelegate.codeType = "0";  // Use "0" for QR consistently
        } else if (item.getId() == :type_barcode) {
            self.parentDelegate.codeType = "1";  // Use "1" for barcode consistently
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        self.parentDelegate.showMenu();
        return;
    }
}

class AddCodeMenu2InputDelegate extends WatchUi.Menu2InputDelegate {
    var parentDelegate;
    function initialize(parentDelegate) {
        Menu2InputDelegate.initialize();
        self.parentDelegate = parentDelegate;
    }
    function onSelect(item) {
        System.println("[Menu2InputDelegate] onSelect: itemId=" + item.getId());
        if (item.getId() == :input_title) {
            var picker = new WatchUi.TextPicker("Title");
            var pickerDelegate = new AddCodeTextPickerDelegate(self.parentDelegate, :input_title);
            WatchUi.pushView(picker, pickerDelegate, WatchUi.SLIDE_UP);
        } else if (item.getId() == :input_text) {
            var picker = new WatchUi.TextPicker("Code");
            var pickerDelegate = new AddCodeTextPickerDelegate(self.parentDelegate, :input_text);
            WatchUi.pushView(picker, pickerDelegate, WatchUi.SLIDE_UP);
        } else if (item.getId() == :input_type) {
            // Show the type selection menu
            var typeMenu = new WatchUi.Menu2({:title => "Select Type"});
            typeMenu.addItem(new WatchUi.MenuItem("QR Code", null, :type_qr, {}));
            typeMenu.addItem(new WatchUi.MenuItem("Barcode", null, :type_barcode, {}));
            var typeMenuDelegate = new TypeMenu2InputDelegate(self.parentDelegate);
            WatchUi.pushView(typeMenu, typeMenuDelegate, WatchUi.SLIDE_UP);
        } else if (item.getId() == :save_code) {
            System.println("Saving code: title=" + self.parentDelegate.codeTitle + ", text=" + self.parentDelegate.codeText + ", type=" + self.parentDelegate.codeType);
            
            // Find next available slot in storage
            var newIndex = 0;
            for (var i = 0; i < 10; i++) {
                if (Storage.getValue("code_" + i + "_text") == null) {
                    newIndex = i;
                    break;
                }
            }
            
            // 1. Save to Storage for app internal use
            Storage.setValue("code_" + newIndex + "_text", self.parentDelegate.codeText);
            Storage.setValue("code_" + newIndex + "_title", self.parentDelegate.codeTitle);
            Storage.setValue("code_" + newIndex + "_type", self.parentDelegate.codeType);
            
            // 2. Save to Application.Properties for settings editor
            // Get or initialize the codesList array
            var codesList = [];
            try {
                var existingList = Application.Properties.getValue("codesList");
                if (existingList != null) {
                    codesList = existingList as Lang.Array;
                }
            } catch (e) {
                // Property doesn't exist yet, that's fine
                System.println("Creating new codesList array");
            }
            
            // Ensure the array has enough entries
            while (codesList.size() <= newIndex) {
                codesList.add({});
            }
            
            // Create a dictionary with the correct format for settings.xml
            // IMPORTANT: The keys must exactly match the format in settings.xml
            var codeEntry = {
                "code_$index_text" => self.parentDelegate.codeText,
                "code_$index_title" => self.parentDelegate.codeTitle,
                "code_$index_type" => self.parentDelegate.codeType  // Already "0" or "1"
            };
            
            // Update this specific index in the array
            codesList[newIndex] = codeEntry;
            
            // Update the codesList property
            try {
                System.println("Saving codesList with entry at index " + newIndex + ": " + codeEntry);
                Application.Properties.setValue("codesList", codesList);
            } catch (e) {
                System.println("Error setting codesList: " + e.getErrorMessage());
            }
            
            System.println("Saved to index " + newIndex + " in both Storage and Properties");
            
            // Return to main screen
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            
            // Reload all codes to include the new one
            AppView.current.loadAllCodes();
            
            // Find the index of the newly added code in the loaded images
            var imagesIndex = -1;
            for (var j = 0; j < AppView.current.images.size(); j++) {
                if (AppView.current.images[j][:index] == newIndex) {
                    imagesIndex = j;
                    break;
                }
            }
            
            if (imagesIndex >= 0) {
                // Set the current index to show the new code
                AppView.current.currentIndex = imagesIndex;
                
                // Download the image
                if (self.parentDelegate.codeText != null && self.parentDelegate.codeText.length() > 0) {
                    AppView.current.downloadImage(self.parentDelegate.codeText, imagesIndex);
                    AppView.current.downloadGlanceImage(self.parentDelegate.codeText, newIndex);
                }
            } else {
                System.println("Warning: Could not find newly added code in images array");
            }
            
            // Request UI update to show the new code
            WatchUi.requestUpdate();
        }
        return;
    }
}

class AddCodeMenuDelegate extends WatchUi.BehaviorDelegate {
    var codeTitle = "";
    var codeText = "";
    var codeType = "0";  // Default to QR ("0")
    var parentView;
    var menu2; // Store reference to the menu
    var menu2Delegate;

    function initialize(parentView) {
        BehaviorDelegate.initialize();
        self.parentView = parentView;
        self.menu2Delegate = new AddCodeMenu2InputDelegate(self);
    }

    function showMenu() {
        System.println("[AddCodeMenuDelegate] showMenu: codeTitle=" + codeTitle + ", codeText=" + codeText + ", codeType=" + codeType);
        
        var typeLabel = codeType.equals("1") ? "Barcode" : "QR Code";
        
        if (menu2 == null) {
            // First time showing the menu
            menu2 = new WatchUi.Menu2({:title => "Add Code"});
            menu2.addItem(new WatchUi.MenuItem("Title", codeTitle.equals("") ? "<enter>" : codeTitle, :input_title, {}));
            menu2.addItem(new WatchUi.MenuItem("Code", codeText.equals("") ? "<enter>" : codeText, :input_text, {}));
            menu2.addItem(new WatchUi.MenuItem("Type", typeLabel, :input_type, {}));
            menu2.addItem(new WatchUi.MenuItem("Save", null, :save_code, {}));
            WatchUi.pushView(menu2, menu2Delegate, WatchUi.SLIDE_UP);
        } else {
            // Update existing menu items
            menu2.updateItem(new WatchUi.MenuItem("Title", codeTitle.equals("") ? "<enter>" : codeTitle, :input_title, {}), 0);
            menu2.updateItem(new WatchUi.MenuItem("Code", codeText.equals("") ? "<enter>" : codeText, :input_text, {}), 1);
            menu2.updateItem(new WatchUi.MenuItem("Type", typeLabel, :input_type, {}), 2);
            // Request UI refresh
            WatchUi.requestUpdate();
        }
    }
}

class ConfirmDeleteDelegate extends WatchUi.Menu2InputDelegate {
    var appView;
    
    function initialize(appView) {
        Menu2InputDelegate.initialize();
        self.appView = appView;
    }
    
    function onSelect(item) {
        var itemId = item.getId();
        if (itemId == :yes_delete) {
            // Get the index of the code to delete
            var idx = appView.images[appView.currentIndex][:index];
            System.println("Deleting code at index: " + idx);
            
            // 1. Delete from Storage
            Storage.deleteValue("code_" + idx + "_text");
            Storage.deleteValue("code_" + idx + "_title");
            Storage.deleteValue("code_" + idx + "_type");
            
            // 2. Delete from Application.Properties
            try {
                var codesList = Application.Properties.getValue("codesList") as Lang.Array;
                if (codesList != null && idx < codesList.size()) {
                    // Clear this entry (replace with empty dictionary instead of removing
                    // to keep index order consistent)
                    codesList[idx] = {};
                    Application.Properties.setValue("codesList", codesList);
                    System.println("Deleted code from Application.Properties");
                }
            } catch (e) {
                System.println("Error deleting from Properties: " + e.getErrorMessage());
            }
            
            // Save current index before reloading
            var currentPosition = appView.currentIndex;
            
            // Pop all menus and return to main view
            WatchUi.popView(WatchUi.SLIDE_DOWN); // Pop confirmation dialog
            WatchUi.popView(WatchUi.SLIDE_DOWN); // Pop the code info menu
            
            // Refresh codes on main screen
            appView.loadAllCodes();
            
            // If we deleted the last code, adjust the index
            if (appView.images.size() == 0) {
                appView.currentIndex = 0;
                System.println("All codes deleted, reset to index 0");
            } else if (currentPosition >= appView.images.size()) {
                // We deleted the last code, move to the previous one
                appView.currentIndex = appView.images.size() - 1;
                System.println("Deleted last code, now showing index: " + appView.currentIndex);
            }
            
            WatchUi.requestUpdate();
        } else if (itemId == :no_delete) {
            // Just pop the confirmation dialog
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        }
        return;
    }
}