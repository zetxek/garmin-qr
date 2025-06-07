using Toybox.Application;
using Toybox.WatchUi;
using Toybox.System;
using Toybox.Timer;
using Toybox.Communications;
using Toybox.Application.Storage;
using Toybox.Lang;

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
                    // Trigger UI update to show offline status
                    WatchUi.requestUpdate();
                }
            }
            
            // Update the last known state
            lastConnectionState = currentConnectionState;
            
            // Regular sync check for pending items
            if (currentConnectionState && pendingSyncQueue != null && pendingSyncQueue.size() > 0) {
                performSyncIfNeeded();
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
                                        System.println("[PerformSync] No cached image, downloading for storage index: " + storageIndex + ", images index: " + imagesIndex);
                                        AppView.current.downloadImage(text, imagesIndex);
                                        syncedCount++;
                                    }
                                } else {
                                    System.println("[PerformSync] Could not find images index for storage index: " + storageIndex);
                                }
                            }
                        }
                    } catch (syncError) {
                        System.println("[PerformSync] Error processing sync item " + i + ": " + syncError.getErrorMessage());
                        // Continue with next item
                    }
                }
                
                // Remove synced items from queue (rebuild queue to ensure correctness)
                try {
                    var remainingQueue = [];
                    for (var k = maxSyncItems; k < pendingSyncQueue.size(); k++) {
                        if (k < pendingSyncQueue.size() && pendingSyncQueue[k] != null) {
                            remainingQueue.add(pendingSyncQueue[k]);
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
        } catch (e) {
            System.println("[PerformSync] Error during sync: " + e.getErrorMessage());
            // Reset queue on error to prevent further issues
            pendingSyncQueue = [];
        }
    }

    function addToPendingSync(text as Lang.String, index as Lang.Number) {
        try {
            // Prevent duplicate entries
            if (pendingSyncQueue != null) {
                for (var i = 0; i < pendingSyncQueue.size(); i++) {
                    var existingItem = pendingSyncQueue[i];
                    if (existingItem != null) {
                        var existingText = existingItem.get("text");
                        var existingIndex = existingItem.get("index");
                        if (existingText != null && existingText.equals(text) && existingIndex == index) {
                            System.println("[AddToPendingSync] Item already in queue: " + text);
                            return;
                        }
                    }
                }
                
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
