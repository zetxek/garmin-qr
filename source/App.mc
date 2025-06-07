// Main application file - now split into multiple modules for better maintainability
// See REFACTORING_PLAN.md for details on the new structure

// Using statements for remaining classes
using Toybox.Application;
using Toybox.WatchUi;
using Toybox.System;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Timer;
using Toybox.Communications;
using Toybox.Application.Storage;
using Toybox.Attention;

// Note: The App class is now in AppCore.mc
// This file contains the main AppView and supporting classes



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
    
    // Add retry tracking to prevent infinite loops
    var failedDownloads as Lang.Dictionary;
    var lastDownloadAttempt as Lang.Number;

    function initialize() {
        View.initialize();
        System.println("AppView initialized");
        AppView.current = self;
        images = [];
        currentIndex = 0;
        isDownloading = false;
        
        // Initialize retry tracking
        failedDownloads = {};
        lastDownloadAttempt = 0;
        
        // Load all codes
        loadAllCodes();
    }

    function loadAllCodes() {
        System.println("[loadAllCodes] Loading all codes from Storage");
        images = [];
        for (var i = 0; i < 10; i++) {
            var text = Storage.getValue("code_" + i + "_text");
            var title = Storage.getValue("code_" + i + "_title");
            System.println("[LoadAllCodes] Code " + i + " - Text: " + (text != null ? text : "null") + ", Title: " + (title != null ? title : "null") + ", Type: " + Storage.getValue("code_" + i + "_type"));
            if (text != null && text.length() > 0) {
                // Try to load cached image first - be more thorough
                var cachedImage = Storage.getValue("qr_image_" + i);
                
                // If no cached image found, check if it might be stored under a different key
                if (cachedImage == null) {
                    System.println("[LoadAllCodes] No cached image found for qr_image_" + i + ", checking storage keys");
                    // Try to find any cached image for this text/type combination
                    var currentType = Storage.getValue("code_" + i + "_type");
                    var cachedText = Storage.getValue("qr_image_meta_text_" + i);
                    var cachedType = Storage.getValue("qr_image_meta_type_" + i);
                    
                    // Check if metadata matches current text/type
                    if (cachedText != null && cachedText.equals(text) && 
                        ((currentType == null && cachedType == null) || 
                         (currentType != null && currentType.equals(cachedType)))) {
                        // Metadata matches, try again to get the image
                        cachedImage = Storage.getValue("qr_image_" + i);
                        if (cachedImage != null) {
                            System.println("[LoadAllCodes] Found cached image after metadata check for code " + i);
                        }
                    }
                }
                
                images.add({:index => i, :image => cachedImage});
                
                var imgStatus = cachedImage != null ? "cached" : "not cached";
                System.println("[LoadAllCodes] Code " + i + " loaded with " + imgStatus + " image");
            }
        }
        System.println("[loadAllCodes] Loaded " + images.size() + " codes");
        for (var j = 0; j < images.size(); j++) {
            var imgStatus = images[j][:image] != null ? "cached" : "needs download";
            var idx = images[j][:index];
            var text = Storage.getValue("code_" + idx + "_text");
            System.println("[LoadAllCodes] code_" + idx + "_text = " + text + ", image: " + imgStatus + ", type: " + Storage.getValue("code_" + idx + "_type"));
        }
        refreshMissingImages();
    }

    function refreshMissingImages() {
        System.println("[refreshMissingImages] Refreshing missing images and checking for changes");
        
        // Check connectivity first - if offline, only use cached images
        var appInstance = Application.getApp();
        var isConnected = appInstance.isConnected();
        
        for (var i = 0; i < images.size(); i++) {
            var idx = images[i][:index];
            var text = Storage.getValue("code_" + idx + "_text");
            var currentType = Storage.getValue("code_" + idx + "_type");
            var imgStatus = images[i][:image] != null ? "downloaded" : "not downloaded";
            System.println("[refreshMissingImages] code_" + idx + "_text = " + text + ", image: " + imgStatus + ", type: " + currentType);
            
            if (text != null && text.length() > 0) {
                if (images[i][:image] == null) {
                    // No image - check if we have a cached version
                    var cachedImage = Storage.getValue("qr_image_" + idx);
                    if (cachedImage != null) {
                        System.println("[refreshMissingImages] Found cached image for code " + idx + ", using it");
                        images[i][:image] = cachedImage;
                    } else if (isConnected) {
                        // No cached image and we're connected, download it
                        System.println("[refreshMissingImages] No cached image and connected, downloading for code " + idx);
                        downloadImage(text, i);
                    } else {
                        // No cached image and offline, add to sync queue for later
                        System.println("[refreshMissingImages] No cached image and offline, adding to sync queue for code " + idx);
                        if (text instanceof Lang.String) {
                            appInstance.addToPendingSync(text as Lang.String, idx);
                        }
                    }
                } else {
                    // Image exists, check if text or type has changed
                    var cachedText = Storage.getValue("qr_image_meta_text_" + idx);
                    var cachedType = Storage.getValue("qr_image_meta_type_" + idx);
                    
                    if (text != cachedText || currentType != cachedType || cachedText == null) {
                        if (isConnected) {
                            // Text or type changed and we're connected, clear cache and re-download
                            System.println("[refreshMissingImages] Content changed for code " + idx + " and connected (text: '" + cachedText + "' -> '" + text + "', type: '" + cachedType + "' -> '" + currentType + "'), re-downloading");
                            images[i][:image] = null;
                            Storage.deleteValue("qr_image_" + idx);
                            Storage.deleteValue("qr_image_meta_text_" + idx);
                            Storage.deleteValue("qr_image_meta_type_" + idx);
                            Storage.deleteValue("qr_image_glance_0"); // Clear glance cache too
                            downloadImage(text, i);
                        } else {
                            // Content changed but offline, keep cached image and add to sync queue
                            System.println("[refreshMissingImages] Content changed for code " + idx + " but offline, keeping cached image and adding to sync queue");
                            if (text instanceof Lang.String) {
                                appInstance.addToPendingSync(text as Lang.String, idx);
                            }
                        }
                    }
                }
            }
        }
    }

    function downloadImage(text as Lang.String, imagesIdx as Lang.Number) {
        System.println("[downloadImage] Downloading image for text: " + text + " at index: " + imagesIdx);
        if (isDownloading) {
            System.println("[DownloadImage] Already downloading " + text + " at index: " + imagesIdx);
            return;
        }
        
        // Check if we already have a cached image
        var index = images[imagesIdx][:index];
        var cachedImage = Storage.getValue("qr_image_" + index);
        if (cachedImage != null) {
            System.println("[downloadImage] Using cached image for index: " + index);
            images[imagesIdx][:image] = cachedImage;
            WatchUi.requestUpdate();
            return;
        }
        
        // Check connectivity before attempting download
        var appInstance = Application.getApp();
        if (!appInstance.isConnected()) {
            System.println("[downloadImage] No connection available and no cached image, adding to sync queue");
            appInstance.addToPendingSync(text, index);
            return;
        }
        
        // Check if this download has failed recently (prevent infinite loops)
        var currentTime = System.getTimer();
        var failureKey = "code_" + index;
        
        if (failedDownloads.hasKey(failureKey)) {
            var lastFailure = failedDownloads.get(failureKey) as Lang.Number;
            var timeSinceFailure = currentTime - lastFailure;
            if (timeSinceFailure < 30000) {  // 30 second cooldown
                System.println("[downloadImage] Recent failure for " + text + ", skipping (cooldown: " + (30000 - timeSinceFailure) / 1000 + "s)");
                return;
            }
        }
        
        // Check if we're attempting downloads too frequently
        var timeSinceLastAttempt = currentTime - lastDownloadAttempt;
        if (timeSinceLastAttempt < 2000) {  // 2 second minimum between attempts
            System.println("[downloadImage] Download attempt too soon, waiting");
            return;
        }
        
        lastDownloadAttempt = currentTime;
        
        isDownloading = true;
        downloadingImageIdx = imagesIdx;
        System.println("[DownloadImage]Starting download for text: " + text + " at index: " + index);
        var codeType = Storage.getValue("code_" + index + "_type");
        if (codeType == null) {
            codeType = "0";  // Default to QR code
        }
        var url;
        if (codeType.equals("1")) {  // Check for "1" instead of "barcode"
            url = "https://qr-gen.adrianmoreno.info/barcode?text=" + text + "&shape=rectangle";
        } else {
            url = "https://qr-gen.adrianmoreno.info/qr?text=" + text;
        }
        System.println("[DownloadImage]URL: " + url);
        var params = null;
        
        // Dynamic image size based on screen dimensions for better quality on larger screens
        var screenWidth = System.getDeviceSettings().screenWidth;
        var screenHeight = System.getDeviceSettings().screenHeight;
        var maxDimension = screenWidth > screenHeight ? screenWidth : screenHeight;
        
        // Scale image request size based on screen size, with reasonable limits
        var imageSize = 200;  // Default size
        if (maxDimension >= 454) {      // Large screens (Fenix 8, Epix 2 Pro, etc.)
            imageSize = 400;
        } else if (maxDimension >= 280) { // Medium screens (Fenix 7, Venu series)
            imageSize = 300;
        } else if (maxDimension >= 240) { // Standard screens (Fenix 6, etc.)
            imageSize = 250;
        }
        
        var options = {
            :maxWidth => imageSize,
            :maxHeight => imageSize
        };
        Communications.makeImageRequest(
            url,
            params,
            options,
            method(:responseCallback)
        );
    }

    function responseCallback(responseCode as Lang.Number, data as Null or WatchUi.BitmapResource) as Void {
        var imagesIdx = downloadingImageIdx;
        System.println("=== responseCallback start. Response code: " + responseCode);
        isDownloading = false;
        
        try {
            if (responseCode == 200) {
                if (data == null) {
                    System.println("[responseCallback] Error: Received null data");
                    showError("[responseCallback] Failed to generate code");
                    return;
                }
                
                System.println("[responseCallback] Processing downloaded image");
                var bitmapResource = data as WatchUi.BitmapResource;
                images[imagesIdx][:image] = bitmapResource;
                
                // Get the storage index (fix: use storage index, not images array index)
                var idx = images[imagesIdx][:index];
                
                // Clear any failure tracking for this code since it succeeded
                var failureKey = "code_" + idx;
                if (failedDownloads.hasKey(failureKey)) {
                    failedDownloads.remove(failureKey);
                    Storage.deleteValue("last_error_code_" + idx);
                    System.println("[responseCallback] Cleared failure tracking for successful download");
                }
                
                // Get the current text and type that were used for this download
                var currentText = Storage.getValue("code_" + idx + "_text");
                var currentType = Storage.getValue("code_" + idx + "_type");
                
                try {
                    System.println("[responseCallback] Saving image and metadata to storage at index: " + idx);
                    // Store image with correct storage index
                    Storage.setValue("qr_image_" + idx, bitmapResource);
                    // Store metadata to track what was used to generate this image
                    Storage.setValue("qr_image_meta_text_" + idx, currentText);
                    Storage.setValue("qr_image_meta_type_" + idx, currentType);
                    System.println("[responseCallback] Updated code at index: " + idx);
                } catch(e) {
                    System.println("[responseCallback] Error in storage operations: " + e.getErrorMessage());
                    showError("Storage error: " + e.getErrorMessage());
                    return;
                }
                
                try {
                    System.println("[responseCallback] Requesting UI update");
                    WatchUi.requestUpdate();
                    // Download glance image with correct storage index
                    if (currentText instanceof Lang.String) {
                        AppView.downloadGlanceImage(currentText as Lang.String, idx);
                    }
                    System.println("[responseCallback] Image downloaded and processed successfully");
                } catch(e) {
                    System.println("[responseCallback] Error requesting update: " + e.getErrorMessage());
                }
            } else {
                System.println("[responseCallback] Download failed with code: " + responseCode);
                
                // Track the failure to prevent infinite loops
                var idx = images[imagesIdx][:index];
                var failureKey = "code_" + idx;
                failedDownloads.put(failureKey, System.getTimer());
                
                // Store the last error code for better status messaging
                Storage.setValue("last_error_code_" + idx, responseCode);
                
                // Handle different types of failures
                var app = Application.getApp();
                if (responseCode == -104) {
                    // Phone not connected - specific offline state
                    var text = Storage.getValue("code_" + idx + "_text");
                    if (text != null && text instanceof Lang.String) {
                        app.addToPendingSync(text as Lang.String, idx);
                        showError("Phone offline - will sync later");
                        System.println("[responseCallback] Phone not connected, added to sync queue: " + text);
                    } else {
                        showError("Phone offline");
                    }
                } else if (responseCode == -100 || responseCode == -101 || responseCode == -102) {
                    // Other network issues (timeout, network error, no connectivity)
                    var text = Storage.getValue("code_" + idx + "_text");
                    if (text != null && text instanceof Lang.String) {
                        app.addToPendingSync(text as Lang.String, idx);
                        showError("Network error - will retry");
                        System.println("[responseCallback] Added failed download to sync queue: " + text);
                    } else {
                        showError("Network error");
                    }
                } else if (responseCode >= 400 && responseCode < 500) {
                    // Client errors (4xx) - don't retry these
                    showError("Invalid code data");
                } else if (responseCode >= 500) {
                    // Server errors (5xx) - can retry these
                    var text = Storage.getValue("code_" + idx + "_text");
                    if (text != null && text instanceof Lang.String) {
                        app.addToPendingSync(text as Lang.String, idx);
                        showError("Server error - will retry");
                    } else {
                        showError("Server error");
                    }
                } else {
                    showError("Error: " + responseCode);
                }
            }
        } catch (e) {
            System.println("[responseCallback] MAJOR ERROR in responseCallback: " + e.getErrorMessage());
            showError("Error: " + e.getErrorMessage());
        }
        System.println("[responseCallback] === responseCallback end");
    }

    function onLayout(dc) {
        // We'll set the layout in onUpdate based on state
    }

    function applyScreenTimeoutSetting() {
        var app = Application.getApp();
        if (app has :keepScreenOn) { // Check if the property exists in the app object
            var shouldKeepScreenOn = app.keepScreenOn;
            System.println("[AppView.applyScreenTimeoutSetting] Setting Attention.setEnabled to: " + shouldKeepScreenOn);
            setAttentionMode(shouldKeepScreenOn);
        } else {
            System.println("[AppView.applyScreenTimeoutSetting] keepScreenOn property not found in App. Defaulting to Attention.setEnabled(false).");
            setAttentionMode(false); // Default to false if property is missing for safety
        }
    }

    function setAttentionMode(enabled as Lang.Boolean) {
        try {
            // Try WatchUi.requestUpdate to keep screen active
            if (enabled) {
                // Keep requesting updates to maintain screen activity
                WatchUi.requestUpdate();
                System.println("[setAttentionMode] Screen timeout disabled via requestUpdate");
            } else {
                System.println("[setAttentionMode] Screen timeout enabled (normal behavior)");
            }
        } catch (e) {
            System.println("[setAttentionMode] Error setting attention mode: " + e.getErrorMessage());
        }
    }

    function onShow() {
        System.println("[AppView.onShow] View is being shown.");
        // Check connectivity when app becomes visible
        var appInstance = Application.getApp();
        if (appInstance != null) {
            appInstance.checkConnectivityNow();
        }
        // Apply screen timeout setting when view is shown
        applyScreenTimeoutSetting();
    }

    function onUpdate(dc) {
        System.println("[onUpdate]");
        View.onUpdate(dc);
        
        // reload codes in case there has been a settings change
        //loadAllCodes();

        if (images.size() == 0) {
            System.println("[onUpdate] Showing empty state layout");
            // Try using layout
            try {
                setLayout(Rez.Layouts.EmptyStateLayout(dc));
                View.onUpdate(dc); // Make sure layout is rendered
                System.println("[onUpdate] Layout set successfully");
            } catch (e) {
                System.println("[onUpdate] Error setting layout: " + e.getErrorMessage());
            }
            emptyState = true;
            return; // Let the layout handle drawing
        } else if (emptyState) {
            System.println("[onUpdate] Clearing empty state layout");
            // Clear layout if we were showing empty state
            setLayout(null);
            emptyState = false;
        }
        
        // Check if currentIndex is valid after deletion
        if (currentIndex >= images.size()) {
            // Reset to a valid index
            currentIndex = 0;
            System.println("[onUpdate] Reset currentIndex to 0 after deletion");
        }
        
        // Only proceed with drawing if not in empty state
        if (!emptyState) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            dc.clear();
            
            // Show status at top (offline or syncing)
            var appInstance = Application.getApp();
            
            // Check actual connectivity status first
            var isConnected = appInstance.isConnected();
            
            if (!isConnected) {
                // Phone is not connected, show offline status
                dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
                dc.drawText(
                    dc.getWidth() / 2,
                    8,
                    Graphics.FONT_XTINY,
                    "OFFLINE",
                    Graphics.TEXT_JUSTIFY_CENTER
                );
            } else if (appInstance.pendingSyncQueue.size() > 0) {
                // Connected and have items to sync
                dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
                dc.drawText(
                    dc.getWidth() / 2,
                    8,
                    Graphics.FONT_XTINY,
                    "SYNCING...",
                    Graphics.TEXT_JUSTIFY_CENTER
                );
            }
            
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
                var statusText = "Loading image...";
                var statusColor = Graphics.COLOR_WHITE;
                
                // Check if download is in cooldown and determine status
                var failureKey = "code_" + idx;
                if (failedDownloads.hasKey(failureKey)) {
                    var lastFailure = failedDownloads.get(failureKey) as Lang.Number;
                    var timeSinceFailure = System.getTimer() - lastFailure;
                    if (timeSinceFailure < 30000) {
                        var remainingCooldown = (30000 - timeSinceFailure) / 1000;
                        // Check if this was a "phone not connected" error specifically
                        var lastErrorCode = Storage.getValue("last_error_code_" + idx);
                        if (lastErrorCode != null && lastErrorCode.equals(-104)) {
                            statusText = "Offline\nPhone not connected";
                            statusColor = Graphics.COLOR_YELLOW;
                        } else {
                            statusText = "Download failed\nRetry in " + remainingCooldown.toNumber() + "s";
                            statusColor = Graphics.COLOR_YELLOW;
                        }
                    }
                }
                
                if (!isDownloading && text != null && text.length() > 0) {
                    // Check if we should attempt download or if we're in cooldown
                    var downloadKey = "code_" + idx;
                    var shouldAttemptDownload = true;
                    
                    if (failedDownloads.hasKey(downloadKey)) {
                        var lastFailure = failedDownloads.get(downloadKey) as Lang.Number;
                        var timeSinceFailure = System.getTimer() - lastFailure;
                        if (timeSinceFailure < 30000) {
                            shouldAttemptDownload = false;
                        }
                    }
                    
                    if (shouldAttemptDownload) {
                        System.println("[onUpdate] Image not downloaded for code_" + idx + ", checking cache and connection");
                        // Try one more time to find cached image before downloading
                        var cachedImage = Storage.getValue("qr_image_" + idx);
                        if (cachedImage != null) {
                            System.println("[onUpdate] Found cached image for code_" + idx + ", using it");
                            images[currentIndex][:image] = cachedImage;
                            WatchUi.requestUpdate();
                        } else {
                            downloadImage(text, currentIndex);
                        }
                    }
                }
                
                // Show loading or error state with better positioning
                dc.setColor(statusColor, Graphics.COLOR_TRANSPARENT);
                dc.drawText(
                    dc.getWidth() / 2,
                    dc.getHeight() / 2 - 10,
                    Graphics.FONT_SMALL,
                    statusText,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
                );
            }
            
            if (errorMessage != null) {
                dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
                dc.drawText(
                    dc.getWidth() / 2,
                    dc.getHeight() - 8,
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
        var bmp = image as WatchUi.BitmapResource;
        var bmpWidth = bmp.getWidth();
        var bmpHeight = bmp.getHeight();
        
        // Check if this is a barcode or QR code
        var codeType = Storage.getValue("code_" + index + "_type");
        var isBarcode = (codeType != null && codeType.equals("1"));
        
        // Calculate layout areas with better scaling for different screen sizes
        var topStatusHeight = screenHeight * 0.12;  // 12% of screen height for status
        var bottomCounterHeight = screenHeight * 0.15;  // 15% of screen height for counter
        var titleHeight = 0;
        
        var title = Storage.getValue("code_" + index + "_title");
        if (title != null && title.length() > 0) {
            titleHeight = screenHeight * 0.1;  // 10% of screen height for title
        }
        
        var availableHeight = screenHeight - topStatusHeight - bottomCounterHeight - titleHeight;
        var availableWidth = screenWidth - (screenWidth * 0.1);  // 5% margin each side
        
        // Calculate scaling based on code type with improved logic
        var finalWidth, finalHeight, codeX, codeY;
        var scale = 1.0;
        
        if (isBarcode) {
            // For barcodes: prefer width, maintain aspect ratio
            var scaleX = availableWidth / bmpWidth;
            var scaleY = (availableHeight * 0.8) / bmpHeight;  // Use 80% of available height for margin
            scale = scaleX < scaleY ? scaleX : scaleY;
            
            finalWidth = bmpWidth * scale;
            finalHeight = bmpHeight * scale;
            
            // Ensure minimum size for readability
            var minBarcodeWidth = screenWidth * 0.7;  // At least 70% of screen width
            if (finalWidth < minBarcodeWidth) {
                scale = minBarcodeWidth / bmpWidth;
                finalWidth = minBarcodeWidth;
                finalHeight = bmpHeight * scale;
                
                // Check if height still fits
                if (finalHeight > availableHeight * 0.8) {
                    scale = (availableHeight * 0.8) / bmpHeight;
                    finalWidth = bmpWidth * scale;
                    finalHeight = bmpHeight * scale;
                }
            }
            
            codeX = (screenWidth - finalWidth) / 2;
        } else {
            // For QR codes: improved scaling that works better on larger screens
            var maxQRSize = availableHeight * 0.85;  // Use 85% of available height
            var maxQRWidth = availableWidth * 0.85;   // Use 85% of available width
            
            // Use the smaller of height or width constraint to maintain square aspect ratio
            var maxDimension = maxQRSize < maxQRWidth ? maxQRSize : maxQRWidth;
            
            if (bmpWidth > maxDimension || bmpHeight > maxDimension) {
                var largestDimension = bmpWidth > bmpHeight ? bmpWidth : bmpHeight;
                scale = maxDimension / largestDimension;
            } else {
                // On larger screens, scale up QR codes for better visibility
                var targetSize = maxDimension;
                var currentSize = bmpWidth > bmpHeight ? bmpWidth : bmpHeight;
                scale = targetSize / currentSize;
                
                // Cap the maximum scale to avoid pixelation
                var maxScale = 4.0;
                if (scale > maxScale) {
                    scale = maxScale;
                }
            }
            
            finalWidth = bmpWidth * scale;
            finalHeight = bmpHeight * scale;
            codeX = (screenWidth - finalWidth) / 2;
        }
        
        // Position everything
        var currentY = topStatusHeight;
        
        // Draw title if present
        if (title != null && title.length() > 0) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                screenWidth / 2,
                currentY + (titleHeight / 2),
                Graphics.FONT_TINY,
                title,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
            currentY += titleHeight;
        }
        
        // Center code vertically in remaining space
        codeY = currentY + (availableHeight - finalHeight) / 2;
        
        // Use scaled drawing for both barcodes and QR codes for consistency
        dc.drawScaledBitmap(codeX, codeY, finalWidth, finalHeight, bmp);
    }

    function onHide() {
        System.println("[AppView.onHide] View is being hidden. Forcing Attention.setEnabled(false).");
        // Always disable attention mode when the view is hidden to conserve battery
        setAttentionMode(false);
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
        
        // Add sync option if there are pending items
        var appInstance = Application.getApp();
        if (appInstance.pendingSyncQueue.size() > 0) {
            menu.addItem(new WatchUi.MenuItem("Sync Now", null, :sync_now, {}));
        }
        
        menu.addItem(new WatchUi.MenuItem("Settings", null, :app_settings, {}));
        menu.addItem(new WatchUi.MenuItem("About the app", null, :about_app, {}));
        
        WatchUi.pushView(menu, new CodeInfoMenu2InputDelegate(self), WatchUi.SLIDE_UP);
    }

    public function downloadGlanceImage(text as Lang.String, index as Lang.Number) {
        var codeType = Storage.getValue("code_" + index + "_type");
        if (codeType == null) { codeType = "0"; }  // Default to QR
        
        // Dynamic glance image size based on screen dimensions
        var screenWidth = System.getDeviceSettings().screenWidth;
        var screenHeight = System.getDeviceSettings().screenHeight;
        var maxDimension = screenWidth > screenHeight ? screenWidth : screenHeight;
        
        // Scale glance image request size based on screen size
        var glanceImageSize = 80;  // Default size
        if (maxDimension >= 454) {      // Large screens
            glanceImageSize = 120;
        } else if (maxDimension >= 280) { // Medium screens
            glanceImageSize = 100;
        }
        
        var url;
        if (codeType.equals("1")) {  // Check for "1" instead of "barcode"
            url = "https://qr-gen.adrianmoreno.info/barcode?text=" + text + "&size=" + glanceImageSize + "&shape=rectangle";
        } else {
            url = "https://qr-gen.adrianmoreno.info/qr?text=" + text + "&size=" + glanceImageSize;
        }
        var options = { :maxWidth => glanceImageSize, :maxHeight => glanceImageSize };
        Communications.makeImageRequest(
            url,
            null,
            options,
            method(:glanceResponseCallback)
        );
    }

    public static function glanceResponseCallback(responseCode as Lang.Number, data as Null or WatchUi.BitmapResource) as Void {
        if (responseCode == 200 && data != null) {
            Storage.setValue("qr_image_glance_0", data as WatchUi.BitmapResource);
            // Store metadata for glance image as well
            var text = Storage.getValue("code_0_text");
            var type = Storage.getValue("code_0_type");
            Storage.setValue("qr_image_glance_meta_text_0", text);
            Storage.setValue("qr_image_glance_meta_type_0", type);
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
        } else if (itemId == :sync_now) {
            var appInstance = Application.getApp();
            appInstance.performSyncIfNeeded();
            appView.refreshMissingImages();
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        } else if (itemId == :about_app) {
            var aboutView = new AboutView();
            WatchUi.pushView(aboutView, new AboutViewDelegate(aboutView), WatchUi.SLIDE_UP);
        } else if (itemId == :app_settings) {
            var settingsView = new AppSettingsView();
            WatchUi.pushView(settingsView, new AppSettingsDelegate(settingsView), WatchUi.SLIDE_UP);
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
            
            var currentTime = System.getTimer();
            
            // 1. Save to Storage for app internal use
            Storage.setValue("code_" + newIndex + "_text", self.parentDelegate.codeText);
            Storage.setValue("code_" + newIndex + "_title", self.parentDelegate.codeTitle);
            Storage.setValue("code_" + newIndex + "_type", self.parentDelegate.codeType);
            Storage.setValue("code_" + newIndex + "_timestamp", currentTime);
            
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
                "code_$index_type" => self.parentDelegate.codeType,  // Already "0" or "1"
                "code_$index_timestamp" => currentTime
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
            var currentImageData = appView.images[appView.currentIndex];
            var idx = currentImageData.get(:index);
            System.println("Deleting code at index: " + idx);
            
            // 1. Delete from Storage
            Storage.deleteValue("code_" + idx + "_text");
            Storage.deleteValue("code_" + idx + "_title");
            Storage.deleteValue("code_" + idx + "_type");
            
            // 2. Delete from Application.Properties
            try {
                var codesList = Application.Properties.getValue("codesList") as Lang.Array;
                if (codesList != null && idx < codesList.size()) {
                    // Set to null instead of empty dictionary
                    codesList[idx] = null;
                    Application.Properties.setValue("codesList", codesList);
                    System.println("Deleted code from Application.Properties");
                }
            } catch (e) {
                System.println("Error deleting from Properties: " + e.getErrorMessage());
            }
            
            // Save current index before reloading
            var currentPosition = appView.currentIndex;

            // Sync storage and properties
            Application.getApp().syncStorageAndProperties();
            
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