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
    // Add connectivity and sync tracking
    var lastSyncTime as Lang.Number or Null;
    var pendingSyncQueue as Lang.Array;
    var connectivityTimer as Null or Timer.Timer;
    var lastConnectionState as Lang.Boolean or Null;
    var keepScreenOn as Lang.Boolean = false;

    function initialize() {
        AppBase.initialize();
        var storedSyncTime = Storage.getValue("lastSyncTime");
        if (storedSyncTime instanceof Lang.Number) {
            lastSyncTime = storedSyncTime;
        } else {
            lastSyncTime = null;
        }
        pendingSyncQueue = [];
        
        // Load keepScreenOn setting
        var keepScreenOnValue = Application.Properties.getValue("keepScreenOn");
        if (keepScreenOnValue instanceof Lang.Boolean) {
            keepScreenOn = keepScreenOnValue;
        } else {
            keepScreenOn = false; // Default if not set or invalid type
        }
        System.println("[initialize] keepScreenOn setting loaded: " + keepScreenOn);

        // Defer connectivity monitoring to avoid startup memory pressure
        // Will be started in onStart after initial sync
    }

    function onStart(state) {
        // Sync Storage and Properties on app startup
        syncStorageAndProperties();
        
        // Check for pending sync operations with error handling
        try {
            checkPendingSync();
        } catch (e) {
            System.println("[onStart] Error in checkPendingSync, clearing corrupted data: " + e.getErrorMessage());
            // Clear potentially corrupted sync data
            Storage.deleteValue("pendingSyncImages");
            pendingSyncQueue = [];
        }
        
        // Start connectivity monitoring after initial operations complete
        startConnectivityMonitoring();
    }

    function onStop(state) {
        // Stop connectivity monitoring
        if (connectivityTimer != null) {
            connectivityTimer.stop();
            connectivityTimer = null;
        }
    }

    function startConnectivityMonitoring() {
        try {
            // Initialize connection state
            lastConnectionState = isConnected();
            System.println("[startConnectivityMonitoring] Initial connection state: " + lastConnectionState);
            
            // Monitor connectivity more frequently for faster detection (every 5 seconds)
            connectivityTimer = new Timer.Timer();
            connectivityTimer.start(method(:onConnectivityCheck) as Lang.Method, 5000, true);
            System.println("[startConnectivityMonitoring] Started connectivity monitoring (5s interval)");
        } catch (e) {
            System.println("[startConnectivityMonitoring] Error starting timer: " + e.getErrorMessage());
            // Continue without connectivity monitoring if timer fails
        }
    }

    function onConnectivityCheck() {
        try {
            var currentConnectionState = isConnected();
            
            // Check if connection state has changed
            if (lastConnectionState != null && currentConnectionState != lastConnectionState) {
                if (currentConnectionState) {
                    System.println("[ConnectivityCheck] *** CONNECTION RESTORED *** - Phone reconnected");
                    // Immediately trigger UI update to show connection restored
                    WatchUi.requestUpdate();
                    
                    // Trigger sync if we have pending items
                    if (pendingSyncQueue != null && pendingSyncQueue.size() > 0) {
                        System.println("[ConnectivityCheck] Connection restored, triggering immediate sync");
                        performSyncIfNeeded();
                    }
                } else {
                    System.println("[ConnectivityCheck] *** CONNECTION LOST *** - Phone disconnected");
                    // Immediately trigger UI update to show offline status
                    WatchUi.requestUpdate();
                }
            }
            
            // Update last known state
            lastConnectionState = currentConnectionState;
            
            // Regular sync check if connected
            if (currentConnectionState) {
                // Only perform sync if we have items and app is ready
                if (pendingSyncQueue != null && pendingSyncQueue.size() > 0 && AppView.current != null && AppView.current.images != null) {
                    // Additional safety check - ensure AppView is fully initialized
                    if (AppView.current.images.size() > 0) {
                        performSyncIfNeeded();
                    } else {
                        System.println("[ConnectivityCheck] AppView not fully loaded yet, deferring sync");
                    }
                }
            }
        } catch (e) {
            System.println("[ConnectivityCheck] Error during connectivity check: " + e.getErrorMessage());
            // Reset queue if there's an error to prevent further crashes
            pendingSyncQueue = [];
        }
    }

    function isConnected() as Lang.Boolean {
        try {
            // Check device settings for phone connection status
            var deviceSettings = System.getDeviceSettings();
            
            // Check if phone is connected via Bluetooth
            var phoneConnected = deviceSettings.phoneConnected;
            if (phoneConnected != null) {
                System.println("[isConnected] Phone connected via Bluetooth: " + phoneConnected);
                return phoneConnected;
            }
            
            // Final fallback: if we can't determine connectivity, assume disconnected for safety
            System.println("[isConnected] Unable to determine connectivity, assuming disconnected");
            return false;
            
        } catch (e) {
            System.println("[isConnected] Error checking connectivity: " + e.getErrorMessage());
            // On error, assume disconnected to prevent failed downloads
            return false;
        }
    }

    function checkPendingSync() {
        System.println("[CheckPendingSync] Starting with simplified approach");
        
        // First, clear any potentially corrupted sync data during startup
        // This prevents memory issues from corrupted storage
        try {
            Storage.deleteValue("pendingSyncImages");
            System.println("[CheckPendingSync] Cleared potentially corrupted sync data");
        } catch (e) {
            System.println("[CheckPendingSync] Error clearing storage: " + e.getErrorMessage());
        }
        
        // Always start with empty queue during startup to avoid memory issues
        pendingSyncQueue = [];
        System.println("[CheckPendingSync] Initialized with empty sync queue for safety");
        
        // Don't check connectivity during startup - defer to avoid memory pressure
        // Sync will be handled later when user interacts with app or timer triggers
    }

    function performSyncIfNeeded() {
        try {
            // Add null check and bounds validation
            if (pendingSyncQueue == null) {
                pendingSyncQueue = [];
                System.println("[PerformSync] Sync queue was null, initialized to empty array");
                return;
            }
            
            if (pendingSyncQueue.size() > 0 && isConnected() && AppView.current != null) {
                System.println("[PerformSync] Starting sync of " + pendingSyncQueue.size() + " items");
                
                // Limit sync operations to prevent memory issues
                var queueSize = pendingSyncQueue.size();
                var maxSyncItems = queueSize > 5 ? 5 : queueSize;
                var syncedCount = 0;
                
                // Process pending image downloads (limited batch) with bounds checking
                for (var i = 0; i < maxSyncItems && i < queueSize; i++) {
                    try {
                        var syncItem = pendingSyncQueue[i];
                        if (syncItem != null) {
                            var text = syncItem.get("text");
                            var storageIndex = syncItem.get("index");
                            
                            if (text != null && storageIndex != null) {
                                // Find the corresponding index in the images array
                                var imagesIndex = -1;
                                if (AppView.current.images != null && AppView.current.images.size() > 0) {
                                    for (var j = 0; j < AppView.current.images.size(); j++) {
                                        try {
                                            if (j < AppView.current.images.size() && AppView.current.images[j] != null && AppView.current.images[j][:index] == storageIndex) {
                                                imagesIndex = j;
                                                break;
                                            }
                                        } catch (indexError) {
                                            System.println("[PerformSync] Error accessing images[" + j + "]: " + indexError.getErrorMessage());
                                            break;
                                        }
                                    }
                                }
                                
                                if (imagesIndex >= 0 && imagesIndex < AppView.current.images.size()) {
                                    // Before attempting download, check if we actually have a cached image
                                    var cachedImage = Storage.getValue("qr_image_" + storageIndex);
                                    if (cachedImage != null) {
                                        System.println("[PerformSync] Found cached image for storage index: " + storageIndex + ", using it instead of downloading");
                                        AppView.current.images[imagesIndex][:image] = cachedImage;
                                        syncedCount++;
                                        WatchUi.requestUpdate();
                                    } else {
                                        System.println("[PerformSync] No cached image found, attempting download for text: " + text + " (storage index: " + storageIndex + ", images index: " + imagesIndex + ")");
                                        AppView.current.downloadImage(text, imagesIndex);
                                        syncedCount++;
                                    }
                                } else {
                                    System.println("[PerformSync] Could not find images index for storage index: " + storageIndex + " or AppView not ready, deferring");
                                    // Don't reload codes during sync to avoid memory issues, just skip this item
                                }
                            }
                        }
                    } catch (itemError) {
                        System.println("[PerformSync] Error processing sync item " + i + ": " + itemError.getErrorMessage());
                        // Continue with next item instead of crashing
                    }
                }
                
                // Remove synced items from queue with bounds checking
                if (syncedCount > 0) {
                    var remainingQueue = [];
                    try {
                        for (var i = syncedCount; i < pendingSyncQueue.size(); i++) {
                            if (i < pendingSyncQueue.size()) {
                                remainingQueue.add(pendingSyncQueue[i]);
                            }
                        }
                        pendingSyncQueue = remainingQueue;
                    } catch (queueError) {
                        System.println("[PerformSync] Error rebuilding queue: " + queueError.getErrorMessage());
                        // Clear queue on error to prevent further issues
                        pendingSyncQueue = [];
                    }
                    
                    // Update storage with remaining items
                    try {
                        if (pendingSyncQueue.size() > 0) {
                            Storage.setValue("pendingSyncImages", pendingSyncQueue);
                        } else {
                            Storage.deleteValue("pendingSyncImages");
                        }
                    } catch (storageError) {
                        System.println("[PerformSync] Storage update error: " + storageError.getErrorMessage());
                    }
                    
                    lastSyncTime = System.getTimer();
                    Storage.setValue("lastSyncTime", lastSyncTime);
                    
                    System.println("[PerformSync] Sync completed, synced " + syncedCount + " items, " + pendingSyncQueue.size() + " remaining");
                }
            }
        } catch (e) {
            System.println("[PerformSync] Error during sync: " + e.getErrorMessage());
            // Reset queue on error to prevent further issues
            pendingSyncQueue = [];
        }
    }

    function addToPendingSync(text as Lang.String, index as Lang.Number) {
        try {
            // Very simple approach to avoid memory issues
            // Limit queue size strictly
            if (pendingSyncQueue.size() >= 5) {
                System.println("[AddToPendingSync] Queue at limit, clearing to make space");
                pendingSyncQueue = []; // Simple clear instead of complex array operations
            }
            
            // Simple duplicate check - just check last few items
            var isDuplicate = false;
            var checkLimit = pendingSyncQueue.size() > 3 ? 3 : pendingSyncQueue.size();
            for (var i = pendingSyncQueue.size() - checkLimit; i < pendingSyncQueue.size(); i++) {
                if (i >= 0) {
                    var existing = pendingSyncQueue[i];
                    if (existing != null && existing.get("text") != null && existing.get("text").equals(text)) {
                        isDuplicate = true;
                        break;
                    }
                }
            }
            
            if (!isDuplicate) {
                var syncItem = {
                    "text" => text,
                    "index" => index
                    // Remove imagesIndex - will be calculated at sync time
                };
                
                pendingSyncQueue.add(syncItem);
                System.println("[AddToPendingSync] Added item to sync queue: " + text + " (queue size: " + pendingSyncQueue.size() + ")");
                
                // Don't save to storage immediately to avoid memory issues during startup
                // Storage will be updated during performSyncIfNeeded
            }
        } catch (e) {
            System.println("[AddToPendingSync] Error adding to sync queue: " + e.getErrorMessage());
            // On any error, clear the queue to prevent cascading issues
            pendingSyncQueue = [];
        }
    }

    function checkConnectivityNow() {
        // Manual connectivity check - useful when user interacts with app
        try {
            System.println("[checkConnectivityNow] Manual connectivity check triggered");
            onConnectivityCheck();
        } catch (e) {
            System.println("[checkConnectivityNow] Error in manual connectivity check: " + e.getErrorMessage());
        }
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
        System.println("[onSettingsChanged] Settings changed, updating codes...");
        
        // Update keepScreenOn setting
        var keepScreenOnValue = Application.Properties.getValue("keepScreenOn");
        if (keepScreenOnValue instanceof Lang.Boolean) {
            keepScreenOn = keepScreenOnValue;
        } else {
            keepScreenOn = false; // Default if not set or invalid type
        }
        System.println("[onSettingsChanged] keepScreenOn setting updated: " + keepScreenOn);

        try {
            // On settings change, Properties is the source of truth - sync FROM Properties TO Storage
            var settings = Application.Properties.getValue("codesList") as Lang.Array<Lang.Dictionary>;
            
            // Clear all Storage entries first
            for (var i = 0; i < 10; i++) {
                Storage.deleteValue("code_" + i + "_text");
                Storage.deleteValue("code_" + i + "_title");
                Storage.deleteValue("code_" + i + "_type");
                // Also clear cached images since codes may have changed
                Storage.deleteValue("qr_image_" + i);
                Storage.deleteValue("qr_image_meta_text_" + i);
                Storage.deleteValue("qr_image_meta_type_" + i);
            }
            Storage.deleteValue("qr_image_glance_0");
            Storage.deleteValue("qr_image_glance_meta_text_0");
            Storage.deleteValue("qr_image_glance_meta_type_0");
            
            if (settings != null && settings.size() > 0) {
                // Sync Properties -> Storage
                var storageIndex = 0;
                for (var i = 0; i < settings.size(); i++) {
                    var code = settings[i];
                    if (code != null && code.keys().size() > 0) {
                        var text = code.get("code_$index_text") as Lang.String;
                        var title = code.get("code_$index_title") as Lang.String;
                        var type = code.get("code_$index_type") as Lang.String;
                        
                        if (text != null && text.length() > 0) {
                            var timestamp = code.get("code_$index_timestamp");
                            if (timestamp == null) {
                                timestamp = System.getTimer(); // Add timestamp if missing
                            }
                            
                            Storage.setValue("code_" + storageIndex + "_text", text);
                            Storage.setValue("code_" + storageIndex + "_title", title);
                            Storage.setValue("code_" + storageIndex + "_type", type);
                            Storage.setValue("code_" + storageIndex + "_timestamp", timestamp);
                            System.println("[onSettingsChanged] Synced code_" + storageIndex + " from Properties to Storage");
                            storageIndex++;
                        }
                    }
                }
            }
            System.println("[onSettingsChanged] Settings sync complete");
            
            // Refresh codes in the current app view if it exists
            if (AppView.current != null) {
                AppView.current.loadAllCodes();
                AppView.current.refreshMissingImages();
                System.println("[onSettingsChanged] Refreshed codes in AppView");
                // Notify AppView about the screen timeout setting change
                AppView.current.applyScreenTimeoutSetting();
            }
            
            WatchUi.requestUpdate();
        } catch (e) {
            System.println("[onSettingsChanged] Error during settings change: " + e.getErrorMessage());
        }
    }

    function syncStorageAndProperties() {
        System.println("[syncStorageAndProperties] Syncing Storage and Properties with timestamps...");
        
        var settings = Application.Properties.getValue("codesList") as Lang.Array<Lang.Dictionary>;
        var currentTime = System.getTimer();
        
        if (settings != null && settings.size() > 0) {
            // Properties has data - compare timestamps to determine sync direction
            System.println("[syncStorageAndProperties] Properties has data, checking timestamps");
            
            var cleanCodesList = [];
            var storageIndex = 0;
            
            for (var i = 0; i < settings.size(); i++) {
                var code = settings[i];
                if (code != null && code.keys().size() > 0) {
                    var text = code.get("code_$index_text") as Lang.String;
                    var title = code.get("code_$index_title") as Lang.String;
                    var type = code.get("code_$index_type") as Lang.String;
                    var propsTimestamp = code.get("code_$index_timestamp");
                    
                    if (text != null && text.length() > 0) {
                        // Check if Storage has this code and compare timestamps
                        var storageText = Storage.getValue("code_" + storageIndex + "_text");
                        var storageTimestamp = Storage.getValue("code_" + storageIndex + "_timestamp");
                        
                        var usePropertiesVersion = true;
                        
                        if (storageText != null && storageTimestamp != null && propsTimestamp != null) {
                            // Both have timestamps, use the newer one
                            var storageTime = storageTimestamp as Lang.Number;
                            var propsTime = propsTimestamp as Lang.Number;
                            if (storageTime > propsTime) {
                                usePropertiesVersion = false;
                                System.println("[syncStorageAndProperties] Storage version newer for code_" + storageIndex);
                            }
                        }
                        
                        if (usePropertiesVersion) {
                            // Use Properties version
                            var codeEntry = {
                                "code_$index_text" => text,
                                "code_$index_title" => title,
                                "code_$index_type" => type != null ? type : "0",
                                "code_$index_timestamp" => propsTimestamp != null ? propsTimestamp : currentTime
                            };
                            cleanCodesList.add(codeEntry);
                            
                            // Save to Storage
                            Storage.setValue("code_" + storageIndex + "_text", text);
                            Storage.setValue("code_" + storageIndex + "_title", title);
                            Storage.setValue("code_" + storageIndex + "_type", type);
                            Storage.setValue("code_" + storageIndex + "_timestamp", codeEntry.get("code_$index_timestamp"));
                            System.println("[syncStorageAndProperties] Used Properties version for code_" + storageIndex);
                        } else {
                            // Use Storage version
                            var storageTitle = Storage.getValue("code_" + storageIndex + "_title");
                            var storageType = Storage.getValue("code_" + storageIndex + "_type");
                            
                            var codeEntry = {
                                "code_$index_text" => storageText,
                                "code_$index_title" => storageTitle,
                                "code_$index_type" => storageType != null ? storageType : "0",
                                "code_$index_timestamp" => storageTimestamp
                            };
                            cleanCodesList.add(codeEntry);
                            System.println("[syncStorageAndProperties] Used Storage version for code_" + storageIndex);
                        }
                        
                        storageIndex++;
                    }
                }
            }
            
            // Clean up any remaining storage entries
            for (var i = storageIndex; i < 10; i++) {
                Storage.deleteValue("code_" + i + "_text");
                Storage.deleteValue("code_" + i + "_title");
                Storage.deleteValue("code_" + i + "_type");
                Storage.deleteValue("code_" + i + "_timestamp");
            }
            
            // Update Properties with cleaned array
            try {
                Application.Properties.setValue("codesList", cleanCodesList);
                System.println("[syncStorageAndProperties] Updated Properties with " + cleanCodesList.size() + " codes");
            } catch (e) {
                System.println("[syncStorageAndProperties] Error updating Properties: " + e.getErrorMessage());
            }
        } else {
            // Properties is empty - check if Storage has data to sync back
            System.println("[syncStorageAndProperties] Properties empty, checking Storage");
            
            var hasStorageData = false;
            var codesList = [];
            
            for (var i = 0; i < 10; i++) {
                var text = Storage.getValue("code_" + i + "_text");
                var title = Storage.getValue("code_" + i + "_title");
                var type = Storage.getValue("code_" + i + "_type");
                var timestamp = Storage.getValue("code_" + i + "_timestamp");
                
                if (text != null && text.length() > 0) {
                    hasStorageData = true;
                    
                    // Create entry in Properties format
                    var codeEntry = {
                        "code_$index_text" => text,
                        "code_$index_title" => title,
                        "code_$index_type" => type != null ? type : "0",
                        "code_$index_timestamp" => timestamp != null ? timestamp : currentTime
                    };
                    codesList.add(codeEntry);
                    
                    // Update Storage timestamp if missing
                    if (timestamp == null) {
                        Storage.setValue("code_" + i + "_timestamp", currentTime);
                    }
                    
                    System.println("[syncStorageAndProperties] Synced code_" + i + " from Storage to Properties");
                }
            }
            
            if (hasStorageData) {
                // Sync Storage -> Properties
                try {
                    Application.Properties.setValue("codesList", codesList);
                    System.println("[syncStorageAndProperties] Synced " + codesList.size() + " codes from Storage to Properties");
                } catch (e) {
                    System.println("[syncStorageAndProperties] Error syncing to Properties: " + e.getErrorMessage());
                }
            } else {
                System.println("[syncStorageAndProperties] No data in either Storage or Properties");
            }
        }
        
        System.println("[syncStorageAndProperties] Sync complete");
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

// App Settings view class for in-app settings management
class AppSettingsView extends WatchUi.View {
    function initialize() {
        View.initialize();
    }

    function onLayout(dc) {
        setLayout(Rez.Layouts.SettingsLayout(dc));
    }

    function onShow() {
        // Show settings menu when view is shown
        showSettingsMenu();
    }

    function onUpdate(dc) {
        View.onUpdate(dc);
    }

    function onHide() {
    }

    function showSettingsMenu() {
        var menu = new WatchUi.Menu2({:title => "Settings"});
        
        // Get current keepScreenOn setting
        var app = Application.getApp();
        var currentSetting = app.keepScreenOn;
        var statusText = currentSetting ? "Enabled" : "Disabled";
        
        menu.addItem(new WatchUi.MenuItem("Keep Screen On", statusText, :toggle_keep_screen_on, {}));
        
        WatchUi.pushView(menu, new AppSettingsMenuDelegate(), WatchUi.SLIDE_UP);
    }
}

// App Settings delegate class
class AppSettingsDelegate extends WatchUi.BehaviorDelegate {
    var view;
    
    function initialize(view) {
        BehaviorDelegate.initialize();
        self.view = view;
    }

    function onSelect() {
        return true;
    }
}

// App Settings Menu delegate class
class AppSettingsMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item) {
        var itemId = item.getId();
        if (itemId == :toggle_keep_screen_on) {
            // Toggle the keepScreenOn setting
            var app = Application.getApp();
            var newSetting = !app.keepScreenOn;
            
            // Update the app's setting
            app.keepScreenOn = newSetting;
            
            // Save to Properties
            Application.Properties.setValue("keepScreenOn", newSetting);
            
            // Apply the setting immediately if we're in the main view
            if (AppView.current != null) {
                AppView.current.applyScreenTimeoutSetting();
            }
            
            System.println("[AppSettings] keepScreenOn toggled to: " + newSetting);
            
            // Pop back to app menu - pop both the settings menu and AppSettingsView
            WatchUi.popView(WatchUi.SLIDE_DOWN); // Pop the settings menu
            WatchUi.popView(WatchUi.SLIDE_DOWN); // Pop the AppSettingsView
            
            return;
        }
        return;
    }

    function onBack() {
        System.println("[AppSettingsMenuDelegate] Back button pressed, returning to app menu");
        // Handle back button - pop both the settings menu and the AppSettingsView 
        // to return to the main app menu (the one with "About the app")
        WatchUi.popView(WatchUi.SLIDE_DOWN); // Pop the settings menu
        WatchUi.popView(WatchUi.SLIDE_DOWN); // Pop the AppSettingsView
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

    function initialize() {
        GlanceView.initialize();
    }

    function onUpdate(dc) {
        System.println("[GlanceView.onUpdate] Starting glance update");
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        // Find the first available code
        var firstCodeIndex = -1;
        for (var i = 0; i < 10; i++) {
            var text = Storage.getValue("code_" + i + "_text");
            if (text != null && text.length() > 0) {
                firstCodeIndex = i;
                System.println("[GlanceView.onUpdate] Found first code at index " + i + ": " + text.substring(0, 20) + "...");
                break;
            }
        }

        if (firstCodeIndex >= 0) {
            // Try to get an image for the first code
            var bmp = Storage.getValue("qr_image_glance_0");  // Try glance-specific image first
            if (bmp == null) {
                bmp = Storage.getValue("qr_image_" + firstCodeIndex);  // Fallback to regular image
                System.println("[GlanceView.onUpdate] Using regular image for code " + firstCodeIndex);
            } else {
                System.println("[GlanceView.onUpdate] Using glance image for code " + firstCodeIndex);
            }
            
            if (bmp != null) {
                System.println("[GlanceView.onUpdate] Drawing image for code " + firstCodeIndex);
                try {
                    var screenWidth = dc.getWidth();
                    var screenHeight = dc.getHeight();
                    var bmpWidth = bmp.getWidth();
                    var bmpHeight = bmp.getHeight();

                    // Check if this is a barcode
                    var codeType = Storage.getValue("code_" + firstCodeIndex + "_type");
                    var isBarcode = (codeType != null && codeType.equals("1")) || (bmpWidth > bmpHeight * 1.5);
                    
                    var drawWidth, drawHeight, x, y;
                    
                    if (isBarcode) {
                        // For barcodes: use most of the width with margins
                        var margin = screenWidth * 0.05;  // 5% margin on each side
                        drawWidth = screenWidth - (margin * 2);  // Use width minus margins
                        drawHeight = screenHeight * 0.7;  // Use 70% of screen height
                        
                        // Make sure height doesn't exceed bitmap proportions too much
                        var aspectRatio = bmpWidth / bmpHeight;
                        var calculatedHeight = drawWidth / aspectRatio;
                        if (calculatedHeight < drawHeight) {
                            drawHeight = calculatedHeight;
                        }
                        
                        x = margin;  // Add left margin
                        y = (screenHeight - drawHeight) / 2;
                        
                        dc.drawScaledBitmap(x, y, drawWidth, drawHeight, bmp);
                        System.println("[GlanceView.onUpdate] Drew full-width barcode at " + x + "," + y + " size " + drawWidth + "x" + drawHeight);
                    } else {
                        // For QR codes: smaller size, with text on the side
                        var maxSize = screenWidth * 0.4;
                        if (maxSize > screenHeight * 0.7) {
                            maxSize = screenHeight * 0.7;
                        }
                        
                        var scale = maxSize / (bmpWidth > bmpHeight ? bmpWidth : bmpHeight);
                        drawWidth = bmpWidth * scale;
                        drawHeight = bmpHeight * scale;
                        
                        x = 10;  // Small margin from left
                        y = (screenHeight - drawHeight) / 2;
                        
                        dc.drawScaledBitmap(x, y, drawWidth, drawHeight, bmp);
                        System.println("[GlanceView.onUpdate] Drew QR code at " + x + "," + y + " size " + drawWidth + "x" + drawHeight);
                        
                        // Draw text next to QR code
                        var title = Storage.getValue("code_" + firstCodeIndex + "_title");
                        var text = Storage.getValue("code_" + firstCodeIndex + "_text");
                        var displayText = text != null ? text : "";
                        if (title != null && title.length() > 0) {
                            displayText = title;
                        }
                        
                        if (displayText.length() > 0) {
                            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                            var textX = x + drawWidth + 10;
                            var textY = screenHeight / 2;
                            var maxTextWidth = screenWidth - textX - 5;
                            
                            // Truncate text based on available width
                            var textWidth = dc.getTextWidthInPixels(displayText, Graphics.FONT_XTINY);
                            while (textWidth > maxTextWidth && displayText.length() > 3) {
                                displayText = displayText.substring(0, displayText.length() - 4) + "...";
                                textWidth = dc.getTextWidthInPixels(displayText, Graphics.FONT_XTINY);
                            }
                            
                            dc.drawText(
                                textX,
                                textY,
                                Graphics.FONT_XTINY,
                                displayText,
                                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER
                            );
                            System.println("[GlanceView.onUpdate] Drew text: " + displayText);
                        }
                    }
                } catch (e) {
                    System.println("[GlanceView.onUpdate] Error drawing: " + e.getErrorMessage());
                    dc.drawText(
                        dc.getWidth() / 2,
                        dc.getHeight() / 2,
                        Graphics.FONT_TINY,
                        "Error displaying code",
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
                    );
                }
            } else {
                System.println("[GlanceView.onUpdate] No image available for code " + firstCodeIndex);
                dc.drawText(
                    dc.getWidth() / 2,
                    dc.getHeight() / 2,
                    Graphics.FONT_TINY,
                    "Loading code...",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
                );
            }
        } else {
            System.println("[GlanceView.onUpdate] No codes configured");
            dc.drawText(
                dc.getWidth() / 2,
                dc.getHeight() / 2,
                Graphics.FONT_TINY,
                "No codes configured",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
        }
        
        System.println("[GlanceView.onUpdate] Glance update complete");
    }

    function min(a, b) {
        return (a < b) ? a : b;
    }

    function downloadGlanceImage(text as Lang.String, index as Lang.Number) {
        var codeType = Storage.getValue("code_" + index + "_type");
        if (codeType == null) { codeType = "0"; }  // Default to QR
        
        // Dynamic glance image size based on screen dimensions
        var screenWidth = System.getDeviceSettings().screenWidth;
        var screenHeight = System.getDeviceSettings().screenHeight;
        var maxDimension = screenWidth > screenHeight ? screenWidth : screenHeight;
        
        var url;
        var options;
        
        if (codeType.equals("1")) {  // Barcode
            // For barcodes in glance view: request full-width image
            var barcodeWidth = screenWidth;
            var barcodeHeight = screenHeight * 0.7;  // 70% of screen height
            
            url = "https://qr-gen.adrianmoreno.info/barcode?text=" + text + "&size=" + barcodeWidth + "&shape=rectangle";
            options = { :maxWidth => barcodeWidth, :maxHeight => barcodeHeight };
        } else {
            // For QR codes: keep square aspect ratio
            var glanceImageSize = 80;  // Default size
            if (maxDimension >= 454) {      // Large screens
                glanceImageSize = 120;
            } else if (maxDimension >= 280) { // Medium screens
                glanceImageSize = 100;
            }
            
            url = "https://qr-gen.adrianmoreno.info/qr?text=" + text + "&size=" + glanceImageSize;
            options = { :maxWidth => glanceImageSize, :maxHeight => glanceImageSize };
        }
        
        Communications.makeImageRequest(
            url,
            null,
            options,
            method(:glanceResponseCallback)
        );
    }

    function glanceResponseCallback(responseCode as Lang.Number, data as Null or WatchUi.BitmapResource) as Void {
        if (responseCode == 200 && data != null) {
            Storage.setValue("qr_image_glance_0", data as WatchUi.BitmapResource);
            // Store metadata for glance image as well
            var text = Storage.getValue("code_0_text");
            var type = Storage.getValue("code_0_type");
            Storage.setValue("qr_image_glance_meta_text_0", text);
            Storage.setValue("qr_image_glance_meta_type_0", type);
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
        
        // Set the about text with dynamic version from properties
        if (aboutText != null) {
            var appVersion = Application.Properties.getValue("appVersion");
            if (appVersion == null) {
                appVersion = "Unknown";
            }
            var dynamicAboutText = "About the app\n\nAuthor: Adrián Moreno Peña\nVersion: " + appVersion + "\nCode: github.com/zetxek/garmin-qr";
            (aboutText as WatchUi.Text).setText(dynamicAboutText);
        }
        
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
    }
    function onKey(keyEvent) {
        var key = keyEvent.getKey();
        if (key == WatchUi.KEY_START || key == WatchUi.KEY_UP || key == WatchUi.KEY_DOWN) {
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