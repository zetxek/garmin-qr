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
}

class AppView extends WatchUi.View {
    var images as Lang.Array<Null or WatchUi.BitmapResource>;
    var currentIndex as Lang.Number;
    var isDownloading;
    var isNewCodeMode;
    var errorMessage as Null or Lang.String;
    var errorTimer as Null or Timer.Timer;
    var pendingText as Null or Lang.String;
    var pendingCodeType as Lang.String; // "qr" or "barcode"
    var returnToListAfterDownload as Lang.Boolean;
    var pendingGlanceCodeType as Lang.String;
    var pendingGlanceText as Lang.String;
    var pendingTitle as Null or Lang.String; // New property for title

    function initialize() {
        View.initialize();
        System.println("AppView initialized");
        images = new [0];
        currentIndex = 0;
        isDownloading = false;
        isNewCodeMode = false;
        pendingCodeType = "qr"; // Default to QR
        returnToListAfterDownload = false;
        pendingGlanceCodeType = "qr";
        pendingGlanceText = "";
        pendingTitle = null;
        
        // Load cached images
        loadCachedImages();
    }

    function loadCachedImages() {
        System.println("Loading cached images");
        try {
            var count = Application.getApp().getProperty("qr_count");
            if (count != null) {
                System.println("Count: " + count);
                // We'll just store the count and codes info - don't try to cache the actual bitmaps
                for (var i = 0; i < count; i++) {
                    downloadStoredCode(i);
                }
            } else {
                System.println("No cached images");
            }
        } catch (e) {
            System.println("Error loading cached images: " + e.getErrorMessage());
        }
    }
    
    // Download a previously stored code
    function downloadStoredCode(index) {
        if (index >= 0) {
            var text = getStorageValue("qr_text_" + index);
            if (text != null && text.length() > 0) {
                System.println("Re-downloading stored code for index " + index + ": '" + text + "'");
                
                // We don't need to modify currentIndex here, as we're just populating the array
                var isQR = true; // Default to QR
                var codeType = Application.getApp().getProperty("qr_type_" + index);
                if (codeType != null && codeType.equals("barcode")) {
                    isQR = false;
                }
                
                // Create a placeholder for now (will be replaced when download completes)
                images.add(null);
                
                // Start the download
                var url;
                if (!isQR) {
                    url = "https://qr-generator-329626796314.europe-west4.run.app/barcode?text=" + text;
                    self.pendingCodeType = "barcode";
                } else {
                    url = "https://qr-generator-329626796314.europe-west4.run.app/qr?text=" + text;
                    self.pendingCodeType = "qr";
                }
                
                // Special case for loading stored codes
                self.pendingText = text;
                self.pendingGlanceText = text;
                self.pendingGlanceCodeType = self.pendingCodeType;
                
                var params = null;
                var options = {
                    :maxWidth => 200,
                    :maxHeight => 200
                };
                
                try {
                    System.println("Making stored code request for index " + index);
                    var indexCopy = index; // Create a copy to use in callback
                    Communications.makeImageRequest(
                        url,
                        params,
                        options,
                        method(:storedCodeCallback)
                    );
                } catch (e) {
                    System.println("Error requesting stored code: " + e.getErrorMessage());
                }
            } else {
                System.println("No text found for stored code at index " + index);
            }
        }
    }
    
    // Callback for stored code downloads
    function storedCodeCallback(responseCode as Lang.Number, data as Null or Graphics.BitmapResource) as Void {
        System.println("=== storedCodeCallback, response code: " + responseCode);
        
        try {
            if (responseCode == 200 && data != null) {
                // Store the image in memory at the current index
                var bitmapResource = data as WatchUi.BitmapResource;
                
                // Update the current image
                images[currentIndex] = bitmapResource;
                
                // Request UI update
                WatchUi.requestUpdate();
            } else {
                System.println("Failed to download stored code image. Response code: " + responseCode);
            }
        } catch (e) {
            System.println("Error in storedCodeCallback: " + e.getErrorMessage());
        }
    }

    function responseCallback(responseCode as Lang.Number, data as Null or Graphics.BitmapResource) as Void {
        System.println("=== responseCallback start. Response code: " + responseCode);
        System.println("responseCallback state - pendingText: '" + self.pendingText + "', currentIndex: " + currentIndex);
        isDownloading = false;
        
        try {
            if (responseCode == 200) {
                if (data == null) {
                    System.println("Error: Received null data");
                    showError("Failed to generate QR code");
                    return;
                }
                
                System.println("Processing downloaded image");
                var bitmapResource = data as WatchUi.BitmapResource;
                
                // Log memory info
                System.println("Memory before adding image: " + System.getSystemStats().usedMemory + "/" + System.getSystemStats().totalMemory);
                
                if (currentIndex < images.size()) {
                    // Edit existing code
                    System.println("Editing existing code at index: " + currentIndex);
                    images[currentIndex] = bitmapResource;
                } else {
                    // Add new code
                    System.println("Adding new code at index: " + images.size());
                    images.add(bitmapResource);
                    currentIndex = images.size() - 1;
                    System.println("New currentIndex: " + currentIndex);
                }
                
                // First try to update just the text and count (skip image storage)
                try {
                    var textToStore = self.pendingText;
                    // If pendingText is somehow null/empty, try to recover from backup
                    if (textToStore == null || textToStore.equals("")) {
                        textToStore = Application.getApp().getProperty("qr_pending_text_backup");
                        System.println("Recovered text from backup: '" + textToStore + "'");
                    }
                    
                    // Debug the pendingText value before saving
                    System.println("Saving text to storage: '" + textToStore + "'");
                    
                    // Use multiple storage methods for redundancy
                    try {
                        Storage.setValue("qr_text_" + currentIndex, textToStore);
                        System.println("Text saved using Storage.setValue");
                    } catch(eStorage) {
                        System.println("Error in Storage.setValue: " + eStorage.getErrorMessage());
                    }
                    
                    try {
                        Application.getApp().setProperty("qr_text_" + currentIndex, textToStore);
                        System.println("Text saved using App.setProperty");
                    } catch(eApp) {
                        System.println("Error in App.setProperty: " + eApp.getErrorMessage());
                    }
                    
                    // Save the code type too
                    try {
                        Application.getApp().setProperty("qr_type_" + currentIndex, self.pendingCodeType);
                        System.println("Code type saved: " + self.pendingCodeType);
                    } catch(eType) {
                        System.println("Error saving code type: " + eType.getErrorMessage());
                    }
                    
                    // Verify text was saved correctly by reading it back
                    var savedText = getStorageValue("qr_text_" + currentIndex);
                    System.println("Verification - Read back saved text: '" + savedText + "'");
                    
                    System.println("Saving qr_count: " + images.size());
                    Application.getApp().setProperty("qr_count", images.size());
                    System.println("Updated code at index: " + currentIndex);
                } catch(e) {
                    System.println("Error in text storage operations: " + e.getErrorMessage());
                    showError("Text storage error");
                    // Continue anyway
                }
                
                try {
                    System.println("Requesting UI update");
                    WatchUi.requestUpdate();
                    System.println("Image downloaded and processed successfully");
                } catch(e) {
                    System.println("Error requesting update: " + e.getErrorMessage());
                }

                try {
                    System.println("Preparing glance image");
                    var glanceUrl;
                    if (self.pendingGlanceCodeType.equals("barcode")) {
                        glanceUrl = "https://qr-generator-329626796314.europe-west4.run.app/barcode?text=" + self.pendingGlanceText + "&size=60";
                    } else {
                        glanceUrl = "https://qr-generator-329626796314.europe-west4.run.app/qr?text=" + self.pendingGlanceText + "&size=60";
                    }
                    System.println("Glance URL: " + glanceUrl + " (type: " + self.pendingGlanceCodeType + ")");
                    var params = null;
                    var options = {
                        :maxWidth => 60,
                        :maxHeight => 60
                    };
                    
                    try {
                        // Pass the index to the glance callback
                        System.println("Making glance image request");
                        Communications.makeImageRequest(
                            glanceUrl,
                            params,
                            options,
                            method(:glanceCallback)
                        );
                        System.println("Glance image request made successfully");
                    } catch(e) {
                        System.println("Error making glance image request: " + e.getErrorMessage());
                    }

                    self.pendingText = null;
                } catch(e) {
                    System.println("Error in glance preparation: " + e.getErrorMessage());
                }

                try {
                    if (self.returnToListAfterDownload) {
                        System.println("Returning to list after download");
                        self.currentIndex = images.size() - 1;
                        
                        // Safer way to pop views without using while loop
                        try {
                            // Instead of popping views, just request an update
                            // This avoids issues with UI navigation timing
                            WatchUi.requestUpdate();
                            System.println("Requested UI update instead of popping view");
                        } catch (e) {
                            System.println("Error updating UI: " + e.getErrorMessage());
                        }
                        
                        self.returnToListAfterDownload = false;
                        System.println("Returned to list successfully");
                    }
                } catch(e) {
                    System.println("Error returning to list: " + e.getErrorMessage());
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
        } catch (e) {
            System.println("MAJOR ERROR in responseCallback: " + e.getErrorMessage());
            showError("Error: " + e.getErrorMessage());
        }
        System.println("=== responseCallback end");
    }

    function glanceCallback(responseCode as Lang.Number, data as Null or Graphics.BitmapResource) as Void {
        System.println("=== glanceCallback start. Response code: " + responseCode);
        try {
            if (responseCode == 200 && data != null) {
                System.println("Storing glance QR code at index: " + self.currentIndex);
                Application.getApp().setProperty("qr_glance_image_" + self.currentIndex, data as WatchUi.BitmapResource);
                System.println("Stored glance QR code at index: " + self.currentIndex);
            } else {
                System.println("Failed to download glance QR code. Response code: " + responseCode);
            }
        } catch(e) {
            System.println("Error in glanceCallback: " + e.getErrorMessage());
        }
        System.println("=== glanceCallback end");
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
            drawImage(dc, images[currentIndex]);
            
            // Draw text at the bottom, always visible
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
                dc.getHeight() - 6,  // 6 pixels from bottom
                Graphics.FONT_XTINY,
                errorMessage,
                Graphics.TEXT_JUSTIFY_CENTER
            );
        }
    }

    function drawImage(dc, image) {
        var screenWidth = dc.getWidth();
        var screenHeight = dc.getHeight();
        var bottomTextHeight = 30; // Reserve space for text at the bottom
        var margin = 10; // Margin from top and sides
        var bmp = image as WatchUi.BitmapResource;
        var bmpWidth = bmp.getWidth();
        var bmpHeight = bmp.getHeight();
        var x = (screenWidth - bmpWidth) / 2;
        var y = (screenHeight - bottomTextHeight - bmpHeight) / 2 + margin;
        
        // Draw title if available (higher above the QR code)
        var title = Application.getApp().getProperty("qr_title_" + currentIndex);
        if (title != null && title.length() > 0) {
            // Draw background for better readability
            var textWidth = dc.getTextWidthInPixels(title, Graphics.FONT_SMALL);
            var textHeight = dc.getFontHeight(Graphics.FONT_SMALL);
            var bgPadding = 4;
            
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(
                (screenWidth - textWidth) / 2 - bgPadding,
                y - 60 - bgPadding,
                textWidth + (bgPadding * 2),
                textHeight + (bgPadding * 2)
            );
            
            // Draw title text
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                screenWidth / 2,
                y - 60, // Position much higher above the QR code - increased from 50
                Graphics.FONT_SMALL, // Slightly larger font
                title,
                Graphics.TEXT_JUSTIFY_CENTER
            );
        }
        
        // Draw the QR code
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
            // Add haptic feedback
            Attention.vibrate([new Attention.VibeProfile(50, 100)]);
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
            // Add haptic feedback
            Attention.vibrate([new Attention.VibeProfile(50, 100)]);
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
        menu.setTitle("Select Code Type");
        menu.addItem("QR Code", :qr);
        menu.addItem("Barcode", :barcode);
        WatchUi.pushView(menu, new CodeTypeMenuDelegate(self), WatchUi.SLIDE_UP);
    }

    function showItemMenu() {
        var menu = new WatchUi.Menu();
        menu.setTitle("Code Options");
        
        // Make the title item actionable to edit the title
        var currentTitle = Application.getApp().getProperty("qr_title_" + currentIndex);
        if (currentTitle == null) {
            currentTitle = "";
        }
        menu.addItem("Title: " + (currentTitle.length() > 0 ? currentTitle : "(none)"), :edit_title);
        
        // Make the text item actionable to edit the text
        System.println("About to get code text for menu display");
        var codeText = getCurrentCodeText();
        System.println("Menu will display text: '" + codeText + "'");
        menu.addItem("Text: " + codeText, :edit_text);
        
        // Add other menu options (removed Edit button)
        menu.addItem("[-] Remove", :remove);
        menu.addItem("[+] Add New", :add);
        
        // Push to WatchUI
        WatchUi.pushView(menu, new CodeMenuDelegate(self), WatchUi.SLIDE_UP);
    }

    function getStorageValue(key) {
        var value = null;
        
        // Try using Application.getApp().getProperty with error handling
        try {
            value = Application.getApp().getProperty(key);
            System.println("getStorageValue - App.getProperty('" + key + "') returned: '" + value + "'");
        } catch(e) {
            System.println("getStorageValue - Error in App.getProperty: " + e.getErrorMessage());
        }
        
        // If that didn't work, try using Storage directly as fallback
        if (value == null) {
            try {
                value = Storage.getValue(key);
                System.println("getStorageValue - Storage.getValue('" + key + "') returned: '" + value + "'");
                
                // If we got it from Storage but not from getProperty, save it back
                // to ensure consistency between the two methods
                if (value != null) {
                    try {
                        Application.getApp().setProperty(key, value);
                        System.println("getStorageValue - Synced value from Storage to App.Property");
                    } catch(e) {
                        System.println("getStorageValue - Error syncing to App.Property: " + e.getErrorMessage());
                    }
                }
            } catch (e) {
                System.println("getStorageValue - Error accessing Storage: " + e.getErrorMessage());
            }
        }
        
        // Last fallback for QR text: check if we're looking for text and try the backup
        if (value == null && key.find("qr_text_") == 0) {
            try {
                var backupText = Application.getApp().getProperty("qr_pending_text_backup");
                if (backupText != null && backupText.length() > 0) {
                    System.println("getStorageValue - Using backup text as last resort: '" + backupText + "'");
                    value = backupText;
                    
                    // Try to save it to the proper place
                    try {
                        Storage.setValue(key, value);
                        System.println("getStorageValue - Saved backup to proper Storage key");
                    } catch(e) {
                        System.println("getStorageValue - Error saving backup to Storage: " + e.getErrorMessage());
                    }
                    
                    try {
                        Application.getApp().setProperty(key, value);
                        System.println("getStorageValue - Saved backup to proper App.Property key");
                    } catch(e) {
                        System.println("getStorageValue - Error saving backup to App.Property: " + e.getErrorMessage());
                    }
                }
            } catch(e) {
                System.println("getStorageValue - Error checking backup: " + e.getErrorMessage());
            }
        }
        
        return value;
    }

    function getCurrentCodeText() {
        System.println("Beginning getCurrentCodeText, currentIndex=" + currentIndex);
        var text = getStorageValue("qr_text_" + currentIndex);
        System.println("getCurrentCodeText: currentIndex=" + currentIndex + ", raw text='" + text + "'");
        
        // If no text found, try the last backup text as a failsafe
        if (text == null || text.equals("")) {
            // Try the backup as last resort
            var backupText = Application.getApp().getProperty("qr_pending_text_backup");
            if (backupText != null && !backupText.equals("")) {
                System.println("Found backup text, using it: '" + backupText + "'");
                
                // Save it to the right place while we're at it
                Application.getApp().setProperty("qr_text_" + currentIndex, backupText);
                Storage.setValue("qr_text_" + currentIndex, backupText);
                
                text = backupText;
            } else {
                System.println("Text is null or empty and no backup found, returning 'Unknown'");
                return "Unknown";
            }
        }
        
        // Truncate long text for display in menu
        if (text.length() > 20) {
            var truncated = text.substring(0, 17) + "...";
            System.println("Text is long, truncated to: '" + truncated + "'");
            return truncated;
        }
        
        System.println("Returning original text: '" + text + "'");
        return text;
    }

    function removeCurrentCode() {
        if (images.size() > 0) {
            // Remove current code
            images.remove(images[currentIndex]);
            
            // Update storage
            Application.getApp().deleteProperty("qr_image_" + currentIndex);
            Application.getApp().deleteProperty("qr_text_" + currentIndex);  // Remove stored text
            Application.getApp().deleteProperty("qr_title_" + currentIndex); // Remove stored title
            
            for (var i = currentIndex; i < images.size(); i++) {
                Application.getApp().setProperty("qr_image_" + i, images[i]);
                
                // Move text storage
                var text = Application.getApp().getProperty("qr_text_" + (i + 1));
                if (text != null) {
                    Application.getApp().setProperty("qr_text_" + i, text);
                    Application.getApp().deleteProperty("qr_text_" + (i + 1));
                }
                
                // Move title storage
                var title = Application.getApp().getProperty("qr_title_" + (i + 1));
                if (title != null) {
                    Application.getApp().setProperty("qr_title_" + i, title);
                    Application.getApp().deleteProperty("qr_title_" + (i + 1));
                }
            }
            
            Application.getApp().setProperty("qr_count", images.size());
            
            // Adjust current index
            if (currentIndex >= images.size()) {
                currentIndex = images.size() > 0 ? images.size() - 1 : 0;
            }
            
            WatchUi.requestUpdate();
        }
    }

    function startNewCodeMode() {
        System.println("Starting text input");
        var initialText = "";
        if (currentIndex < images.size()) {
            // Editing: load saved text if available
            var savedText = getStorageValue("qr_text_" + currentIndex);
            if (savedText != null) {
                initialText = savedText;
            }
        }
        var textPicker = new WatchUi.TextPicker(initialText == "" ? "Your_text" : initialText);
        WatchUi.pushView(textPicker, new TextPickerDelegate(self), WatchUi.SLIDE_UP);
    }
    
    function startTitleInput() {
        System.println("Starting title input");
        var initialTitle = "";
        if (currentIndex < images.size()) {
            // Editing: load saved title if available
            var savedTitle = Application.getApp().getProperty("qr_title_" + currentIndex);
            if (savedTitle != null) {
                initialTitle = savedTitle;
            }
        }
        var textPicker = new WatchUi.TextPicker(initialTitle);
        WatchUi.pushView(textPicker, new TitleInputDelegate(self), WatchUi.SLIDE_UP);
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
        if (images.size() == 0) {
            return false;
        }

        var direction = swipeEvent.getDirection();
        System.println("Swipe detected: " + direction);
        
        if (direction == WatchUi.SWIPE_DOWN) {
            // Move to next code
            if (currentIndex < images.size() - 1) {
                currentIndex++;
            } else {
                currentIndex = 0;  // Wrap to beginning
            }
            System.println("Moved to code: " + currentIndex);
            WatchUi.requestUpdate();
            // Add haptic feedback
            Attention.vibrate([new Attention.VibeProfile(50, 100)]);
            return true;
        } else if (direction == WatchUi.SWIPE_UP) {
            // Move to previous code
            if (currentIndex > 0) {
                currentIndex--;
            } else {
                currentIndex = images.size() - 1;  // Wrap to end
            }
            System.println("Moved to code: " + currentIndex);
            WatchUi.requestUpdate();
            // Add haptic feedback
            Attention.vibrate([new Attention.VibeProfile(50, 100)]);
            return true;
        }
        
        return false;
    }

    function showError(message as Lang.String) {
        errorMessage = message;
        WatchUi.requestUpdate();
    }

    function downloadImage(text as Lang.String) {
        if (isDownloading) {
            System.println("Already downloading");
            return;
        }
        
        // Clean up memory - remove unnecessary images to make room
        if (images.size() > 10) {
            System.println("Too many images, removing oldest to free memory");
            var oldestToRemove = images.size() - 10;
            for (var i = images.size() - 1; i >= 10; i--) {
                // Remove images starting from the end of the array
                System.println("Removing extra image at index: " + i);
                images.remove(images[i]);
                Storage.deleteValue("qr_text_" + i);
            }
        }
        
        isDownloading = true;
        System.println("Starting download for text: '" + text + "'");
        var url;
        if (pendingCodeType.equals("barcode")) {
            url = "https://qr-generator-329626796314.europe-west4.run.app/barcode?text=" + text;
        } else {
            url = "https://qr-generator-329626796314.europe-west4.run.app/qr?text=" + text;
        }
        System.println("URL: " + url);
        var params = null;
        var options = {
            :maxWidth => 200,  // Reduced size to use less memory
            :maxHeight => 200  // Reduced size to use less memory
        };

        // Store the text for later reference (in memory, not storage)
        self.pendingText = text;
        self.pendingGlanceCodeType = self.pendingCodeType;
        self.pendingGlanceText = text;
        
        // Store the text early using a special key as well - redundancy safety
        try {
            // Store a copy with a temporary key in case pendingText is lost
            Application.getApp().setProperty("qr_pending_text_backup", text);
            System.println("Stored backup text in 'qr_pending_text_backup': '" + text + "'");
        } catch (e) {
            System.println("Error storing backup text: " + e.getErrorMessage());
        }
        
        System.println("Downloaded state - pendingText: '" + self.pendingText + "', currentIndex: " + currentIndex);
        System.println("pendingCodeType: " + self.pendingCodeType + ", pendingGlanceCodeType: " + self.pendingGlanceCodeType + ", text: " + text);

        System.println("Making Communications.makeImageRequest call...");
        try {
            Communications.makeImageRequest(
                url,
                params,
                options,
                method(:responseCallback)
            );
            System.println("Communications.makeImageRequest call succeeded");
        } catch (e) {
            System.println("ERROR in makeImageRequest: " + e.getErrorMessage());
            isDownloading = false;
            showError("Network error: " + e.getErrorMessage());
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
        if (item == :edit_text) {
            view.startNewCodeMode();
        } else if (item == :edit_title) {
            view.startTitleInput();
        } else if (item == :remove) {
            view.removeCurrentCode();
        } else if (item == :add) {
            view.showAddMenu();
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
        System.println("Text entered: '" + text + "' (changed: " + changed + ")");
        
        if (text != null && text.length() > 0) {
            try {
                System.println("Generating QR code for entered text: '" + text + "'");
                view.returnToListAfterDownload = true;
                
                // Handle long text by truncating if needed (prevent memory issues)
                if (text.length() > 100) {
                    text = text.substring(0, 100);
                    System.println("Text truncated to 100 chars to prevent memory issues: '" + text + "'");
                }
                
                // First pop the view before starting the download
                // to avoid UI navigation timing issues
                try {
                    WatchUi.popView(WatchUi.SLIDE_DOWN);
                } catch (e) {
                    System.println("Error popping view before download: " + e.getErrorMessage());
                }
                
                // Then start the download
                view.downloadImage(text);
            } catch (e) {
                System.println("Error in onTextEntered: " + e.getErrorMessage());
                view.showError("Error: " + e.getErrorMessage());
                
                // Ensure view is popped if there was an error
                try {
                    WatchUi.popView(WatchUi.SLIDE_DOWN);
                } catch (e2) {
                    // Ignore nested error
                }
            }
        } else {
            System.println("Empty text entered");
            try {
                WatchUi.popView(WatchUi.SLIDE_DOWN);
            } catch (e) {
                System.println("Error popping view for empty text: " + e.getErrorMessage());
            }
        }
        
        return true;
    }

    function onCancel() {
        System.println("Text input cancelled");
        try {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        } catch (e) {
            System.println("Error popping view on cancel: " + e.getErrorMessage());
        }
        return true;
    }
}

class TitleInputDelegate extends WatchUi.TextPickerDelegate {
    var view;

    function initialize(view) {
        TextPickerDelegate.initialize();
        self.view = view;
    }

    function onTextEntered(title, changed) {
        System.println("Title entered: " + title);
        
        // Store the title directly in storage
        if (title != null && title.length() > 0) {
            try {
                // Use Property API for 3.1.0 compatibility
                Application.getApp().setProperty("qr_title_" + view.currentIndex, title);
                System.println("Saved title to storage: " + title + " for index " + view.currentIndex);
            } catch (e) {
                System.println("Error saving title: " + e.getErrorMessage());
            }
        } else {
            // If empty title, remove the title
            try {
                // Use Property API for 3.1.0 compatibility
                Application.getApp().deleteProperty("qr_title_" + view.currentIndex);
                System.println("Deleted title from storage for index " + view.currentIndex);
            } catch (e) {
                System.println("Error deleting title: " + e.getErrorMessage());
            }
        }
        
        // Return to the main view
        try {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            // Request update after view is popped
            WatchUi.requestUpdate();
        } catch (e) {
            System.println("Error popping view after title entry: " + e.getErrorMessage());
            // Try to request update anyway
            try {
                WatchUi.requestUpdate();
            } catch (e2) {
                // Ignore nested error
            }
        }
        
        return true;
    }

    function onCancel() {
        System.println("Title input cancelled");
        // Return to the main view
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        
        return true;
    }
}

(:glance)
class GlanceView extends WatchUi.GlanceView {
    var images as Lang.Array<Null or WatchUi.BitmapResource>;

    function initialize() {
        GlanceView.initialize();
        images = new [0];
        loadCachedImages();
    }

    function loadCachedImages() {
        try {
            var count = Application.getApp().getProperty("qr_count");
            if (count != null) {
                for (var i = 0; i < count; i++) {
                    var cachedImage = Application.getApp().getProperty("qr_glance_image_" + i);
                    if (cachedImage != null) {
                        images.add(cachedImage as WatchUi.BitmapResource);
                    }
                }
            }
        } catch (e) {
            System.println("Error loading cached images for glance: " + e.getErrorMessage());
        }
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        if (images.size() > 0) {
            var bmp = images[0] as WatchUi.BitmapResource;
            var bmpWidth = bmp.getWidth();
            var bmpHeight = bmp.getHeight();
            var screenHeight = dc.getHeight();
            var screenWidth = dc.getWidth();

            var marginLeft = 10; // Increase margin for clarity
            var x = marginLeft;
            var y = (screenHeight - bmpHeight) / 2;
            dc.drawBitmap(x, y, bmp);

            // Get the title and text
            var title = Application.getApp().getProperty("qr_title_0");
            var text = Application.getApp().getProperty("qr_text_0");
            
            // Available width for text
            var textX = x + bmpWidth + 10; // 10px padding to the right of the QR
            var availableWidth = screenWidth - textX - 5; // 5px margin on right
            
            // Draw the title if available
            if (title != null && title.length() > 0) {
                // Draw title with emphasis
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                
                // Truncate title if needed
                var titleText = title;
                var titleWidth = dc.getTextWidthInPixels(titleText, Graphics.FONT_TINY);
                if (titleWidth > availableWidth) {
                    // Try to ensure at least part of the title is visible
                    var maxChars = titleText.length() * availableWidth / titleWidth;
                    if (maxChars > 3) { // Need at least 3 chars plus "..."
                        titleText = titleText.substring(0, maxChars.toNumber() - 3) + "...";
                    }
                }
                
                dc.drawText(
                    textX,
                    y + 5, // Position near top of QR code
                    Graphics.FONT_TINY,
                    titleText,
                    Graphics.TEXT_JUSTIFY_LEFT
                );
                
                // Draw text below title if there's room
                if (text != null) {
                    var displayText = text;
                    var textWidth = dc.getTextWidthInPixels(displayText, Graphics.FONT_XTINY);
                    if (textWidth > availableWidth) {
                        var maxChars = displayText.length() * availableWidth / textWidth;
                        if (maxChars > 3) {
                            displayText = displayText.substring(0, maxChars.toNumber() - 3) + "...";
                        }
                    }
                    
                    dc.drawText(
                        textX,
                        y + 25, // Position below title
                        Graphics.FONT_XTINY,
                        displayText,
                        Graphics.TEXT_JUSTIFY_LEFT
                    );
                }
            } else {
                // No title, just display the text
                var displayText = text;
                if (displayText == null) {
                    displayText = "";
                }
                
                // Truncate text if needed
                var textWidth = dc.getTextWidthInPixels(displayText, Graphics.FONT_XTINY);
                if (textWidth > availableWidth) {
                    var maxChars = displayText.length() * availableWidth / textWidth;
                    if (maxChars > 3) {
                        displayText = displayText.substring(0, maxChars.toNumber() - 3) + "...";
                    }
                }
                
                dc.drawText(
                    textX,
                    screenHeight / 2, // Center vertically when no title
                    Graphics.FONT_XTINY,
                    displayText,
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER
                );
            }
        } else {
            // No QR codes - show message
            dc.drawText(
                dc.getWidth() / 2,
                dc.getHeight() / 2,
                Graphics.FONT_TINY,
                "No QR codes",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
        }
    }
}

class CodeTypeMenuDelegate extends WatchUi.MenuInputDelegate {
    var view;
    function initialize(view) {
        MenuInputDelegate.initialize();
        self.view = view;
    }
    function onMenuItem(item) {
        if (item == :qr) {
            view.pendingCodeType = "qr";
        } else if (item == :barcode) {
            view.pendingCodeType = "barcode";
        }
        view.currentIndex = view.images.size();
        
        // Go directly to text input (skipping title input)
        view.startNewCodeMode();
    }
}