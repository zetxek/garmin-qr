import Toybox.Lang;
import Toybox.System;
import Toybox.Communications;
import Toybox.Timer;
import Toybox.WatchUi;
import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Graphics;

const QR_SERVICE_URL = "https://qr-gen.adrianmoreno.info";
const BACKOFF_BASE_MS = 5000;
const BACKOFF_CAP_MS = 60000;

//! Fetches code images, one request at a time, and never gets stuck.
//!
//! The previous implementation used a single `isDownloading` boolean with no queue: with N
//! codes to fetch, N-1 requests were dropped on the floor, and if a callback never arrived the
//! flag stayed set for the rest of the session and nothing loaded again. This is a FIFO queue
//! with a watchdog, so every enqueued slot eventually resolves or fails explicitly.
(:app)
class ImageService {

    //! A request that has produced neither success nor failure by now is treated as failed.
    //! This is what guarantees the in-flight lock is always released.
    const REQUEST_TIMEOUT_MS = 20000;

    const MAX_ATTEMPTS = 4;

    //! Queue entry standing in for "the small image the glance view draws".
    const GLANCE = -2;
    const NONE = -1;

    const QUEUE_KEY = "pendingImageSlots";

    static var instance as ImageService? = null;

    static function get() as ImageService {
        // Returned via a local: `return instance;` leaves the type checker with
        // PolyType<Null or ImageService>, which is an error at -l 3.
        var existing = instance;
        if (existing == null) {
            existing = new ImageService();
            instance = existing;
        }
        return existing;
    }

    // ------------------------------------------------------------ URL building

    //! Percent-encode the payload before putting it in the query string.
    //!
    //! Without this, a code containing `&` was cut short at the first ampersand, and `+`,
    //! spaces, `#` and `%` silently produced the wrong code (issue #31).
    //! The service host, overridable from settings.
    //!
    //! Garmin's image proxy fails for some domains and not others, and the failure is outside
    //! this app's control. Making the host a setting means a working host can be pointed at
    //! without waiting on an app-store release.
    static function serviceUrl() as String {
        var configured = null;
        try {
            configured = Application.Properties.getValue("serviceUrl");
        } catch (e) {
            configured = null;
        }
        if (configured instanceof String && configured.length() > 0) {
            // Trailing slashes would produce "//qr" or, worse, a path the service 404s on.
            var trimmed = configured;
            while (trimmed.length() > 0 && trimmed.substring(trimmed.length() - 1, trimmed.length()).equals("/")) {
                trimmed = trimmed.substring(0, trimmed.length() - 1);
            }
            if (trimmed.length() > 0) { return trimmed; }
        }
        return $.QR_SERVICE_URL;
    }

    static function buildUrl(text as String, type as String, size as Number) as String {
        var encoded = Communications.encodeURL(text);
        var base = serviceUrl();
        if (type.equals(CodeStore.TYPE_BARCODE)) {
            return base + "/barcode?text=" + encoded + "&size=" + size + "&shape=rectangle";
        }
        return base + "/qr?text=" + encoded + "&size=" + size;
    }

    //! Request size for the full-screen view, scaled to the display.
    static function fullSize() as Number {
        var longest = longestScreenEdge();
        if (longest >= 454) { return 400; }
        if (longest >= 280) { return 300; }
        if (longest >= 240) { return 250; }
        return 200;
    }

    static function glanceSize() as Number {
        var longest = longestScreenEdge();
        if (longest >= 454) { return 120; }
        if (longest >= 280) { return 100; }
        return 80;
    }

    static function longestScreenEdge() as Number {
        var settings = System.getDeviceSettings();
        return settings.screenWidth > settings.screenHeight
            ? settings.screenWidth
            : settings.screenHeight;
    }

    // --------------------------------------------------------------- state

    var queue as Array<Number>;
    var inFlight as Number;
    var watchdog as Timer.Timer?;
    //! slot -> { :attempts, :readyAt, :code }
    var failures as Dictionary;

    function initialize() {
        queue = [] as Array<Number>;
        inFlight = NONE;
        watchdog = null;
        failures = {};
        restoreQueue();
    }

    // --------------------------------------------------------------- queue

    function isQueued(slot as Number) as Boolean {
        for (var i = 0; i < queue.size(); i++) {
            if (queue[i] == slot) { return true; }
        }
        return false;
    }

    //! Queue a slot for download. Cheap and idempotent; safe to call from anywhere.
    function enqueue(slot as Number) as Void {
        if (!needsDownload(slot)) { return; }
        if (slot == inFlight || isQueued(slot)) { return; }
        queue.add(slot);
        persistQueue();
    }

    //! Queue a slot at the head — used for the code the user is actually looking at, so it is
    //! never stuck behind prefetches for codes further down the list.
    function enqueueFirst(slot as Number) as Void {
        if (!needsDownload(slot)) { return; }
        if (slot == inFlight) { return; }
        queue.remove(slot);
        var reordered = [slot] as Array<Number>;
        reordered.addAll(queue);
        queue = reordered;
        persistQueue();
    }

    function enqueueAll() as Void {
        var slots = CodeStore.occupiedSlots();
        for (var i = 0; i < slots.size(); i++) {
            enqueue(slots[i]);
        }
        enqueueGlance();
    }

    function enqueueGlance() as Void {
        if (CodeStore.firstSlot() < 0 || CodeStore.isGlanceCacheValid()) { return; }
        if (inFlight == GLANCE || isQueued(GLANCE)) { return; }
        queue.add(GLANCE);
        persistQueue();
    }

    //! A slot the service has given up on stays out of the queue, so "pending" stays honest and
    //! the syncing indicator clears.
    function dropPermanentFailures() as Void {
        var kept = [] as Array<Number>;
        for (var i = 0; i < queue.size(); i++) {
            if (!isPermanentlyFailed(queue[i])) { kept.add(queue[i]); }
        }
        if (kept.size() == queue.size()) { return; }
        queue = kept;
        persistQueue();
    }

    function needsDownload(slot as Number) as Boolean {
        if (slot == GLANCE) {
            return CodeStore.firstSlot() >= 0 && !CodeStore.isGlanceCacheValid();
        }
        if (slot < 0 || slot >= CodeStore.MAX_CODES) { return false; }
        if (CodeStore.getText(slot) == null) { return false; }
        return !CodeStore.isCacheValid(slot);
    }

    function forget(slot as Number) as Void {
        queue.remove(slot);
        clearFailure(slot);
        if (inFlight == slot) {
            // The response is no longer interesting, but the lock must still be released.
            inFlight = NONE;
            stopWatchdog();
        }
        persistQueue();
    }

    function clear() as Void {
        queue = [] as Array<Number>;
        failures = {};
        persistQueue();
    }

    //! The queue survives a restart so codes added while offline are still fetched later.
    //! Only slot numbers are persisted, so the stored value stays tiny.
    function persistQueue() as Void {
        try {
            if (queue.size() == 0) {
                Storage.deleteValue(QUEUE_KEY);
            } else {
                Storage.setValue(QUEUE_KEY, queue as Application.PropertyValueType);
            }
        } catch (e) {
            Log.warn("[ImageService] could not persist queue: " + e.getErrorMessage());
        }
    }

    function restoreQueue() as Void {
        var stored = null;
        try {
            stored = Storage.getValue(QUEUE_KEY);
        } catch (e) {
            stored = null;
        }
        if (!(stored instanceof Array)) { return; }
        for (var i = 0; i < stored.size(); i++) {
            var slot = stored[i];
            if (slot instanceof Number && needsDownload(slot) && !isQueued(slot)) {
                queue.add(slot);
            }
        }
        Log.debug("[ImageService] restored " + queue.size() + " queued downloads");
    }

    // ------------------------------------------------------------ requests

    //! Start the next eligible request if nothing is in flight. Idempotent.
    function pump() as Void {
        if (inFlight != NONE) { return; }
        dropPermanentFailures();
        if (queue.size() == 0) { return; }
        if (!Connectivity.isConnected()) {
            Log.debug("[ImageService] offline, holding " + queue.size() + " queued downloads");
            return;
        }

        var now = System.getTimer();
        while (queue.size() > 0) {
            var index = -1;
            for (var i = 0; i < queue.size(); i++) {
                if (readyAt(queue[i]) <= now) { index = i; break; }
            }
            if (index < 0) { return; } // everything left is still backing off

            var slot = queue[index];
            queue.remove(slot);
            persistQueue();

            if (!needsDownload(slot)) { continue; } // resolved or deleted while queued
            if (send(slot)) { return; }
        }
    }

    function send(slot as Number) as Boolean {
        var text;
        var type;
        var size;
        if (slot == GLANCE) {
            var first = CodeStore.firstSlot();
            if (first < 0) { return false; }
            text = CodeStore.getText(first);
            type = CodeStore.getType(first);
            size = glanceSize();
        } else {
            text = CodeStore.getText(slot);
            type = CodeStore.getType(slot);
            size = fullSize();
        }
        if (text == null) { return false; }

        var url = buildUrl(text, type, size);
        Log.debug("[ImageService] requesting slot " + slot + ": " + url);

        try {
            inFlight = slot;
            startWatchdog();
            transmit(url, size);
            return true;
        } catch (e) {
            Log.warn("[ImageService] request failed to start for slot " + slot + ": " + e.getErrorMessage());
            stopWatchdog();
            inFlight = NONE;
            recordFailure(slot, -1);
            return false;
        }
    }

    //! The radio call, kept on its own so tests can drive the queue without a network.
    //!
    //! Note this can call `onResponse` back *synchronously* — the simulator does exactly that
    //! when the phone data channel is unavailable — so nothing may assume the callback is
    //! deferred. `inFlight` and the watchdog are both set before this runs for that reason.
    function transmit(url as String, size as Number) as Void {
        Communications.makeImageRequest(
            url,
            null,
            {
                :maxWidth => size,
                :maxHeight => size,
                // Codes are pure black and white; dithering only blurs the modules and makes
                // them harder for a scanner to read.
                :dithering => Communications.IMAGE_DITHERING_NONE
            },
            method(:onResponse)
        );
    }

    function onResponse(
        responseCode as Number,
        data as Null or Graphics.BitmapReference or WatchUi.BitmapResource
    ) as Void {
        stopWatchdog();
        var slot = inFlight;
        inFlight = NONE;

        if (slot == NONE) {
            Log.debug("[ImageService] response " + responseCode + " for a cancelled request");
            pump();
            return;
        }

        try {
            var bitmap = resolveBitmap(data);
            if (responseCode == 200 && bitmap != null) {
                if (slot == GLANCE) {
                    CodeStore.putGlanceImage(bitmap);
                } else {
                    CodeStore.putImage(slot, bitmap);
                }
                clearFailure(slot);
                Log.debug("[ImageService] slot " + slot + " downloaded");
            } else {
                recordFailure(slot, responseCode);
                Log.warn("[ImageService] slot " + slot + " failed with " + responseCode);
            }
        } catch (e) {
            Log.warn("[ImageService] error handling response: " + e.getErrorMessage());
            recordFailure(slot, responseCode);
        }

        WatchUi.requestUpdate();
        pump();
    }

    //! `makeImageRequest` hands back either a resource or a reference to one depending on the
    //! device; only the resource can be cached.
    static function resolveBitmap(
        data as Null or Graphics.BitmapReference or WatchUi.BitmapResource
    ) as WatchUi.BitmapResource? {
        if (data instanceof Graphics.BitmapReference) {
            var resolved = data.get();
            return resolved instanceof WatchUi.BitmapResource ? resolved : null;
        }
        if (data instanceof WatchUi.BitmapResource) { return data; }
        return null;
    }

    //! Fires when a request produced no callback at all. Without this the in-flight lock would
    //! be held forever and the app would sit on "Loading..." until it was restarted.
    function onTimeout() as Void {
        var slot = inFlight;
        watchdog = null;
        inFlight = NONE;
        if (slot == NONE) { return; }

        Log.warn("[ImageService] slot " + slot + " timed out after " + REQUEST_TIMEOUT_MS + "ms");
        recordFailure(slot, Communications.NETWORK_REQUEST_TIMED_OUT);
        WatchUi.requestUpdate();
        pump();
    }

    function startWatchdog() as Void {
        stopWatchdog();
        try {
            watchdog = new Timer.Timer();
            watchdog.start(method(:onTimeout), REQUEST_TIMEOUT_MS, false);
        } catch (e) {
            Log.warn("[ImageService] could not arm watchdog: " + e.getErrorMessage());
            watchdog = null;
        }
    }

    function stopWatchdog() as Void {
        if (watchdog != null) {
            watchdog.stop();
            watchdog = null;
        }
    }

    // ------------------------------------------------------------ failures

    //! 4xx means the server understood us and refused: the payload is the problem, so retrying
    //! it verbatim will never work. Everything else — offline, timeout, 5xx — is transient.
    //! 404 is deliberately *not* permanent.
    //!
    //! `makeImageRequest` does not fetch from the watch: it is proxied through Garmin's image
    //! service, which returns 404 both for genuinely missing images and for its own failures to
    //! fetch a perfectly reachable URL (Garmin bug CIQQA-3382, acknowledged, still open). Our
    //! own service answers the identical URL with 200 to any normal client while the proxy
    //! reports 404. Treating that as permanent stranded every code on the first attempt and
    //! told the user their text was wrong, which it was not.
    static function isPermanent(responseCode as Number) as Boolean {
        if (responseCode == 404) { return false; }
        return responseCode >= 400 && responseCode < 500;
    }

    static function errorKey(slot as Number) as String {
        return "img_error_" + slot;
    }

    function recordFailure(slot as Number, responseCode as Number) as Void {
        var record = failures.get(slot);
        var attempts = 1;
        if (record instanceof Dictionary) {
            attempts = (record.get(:attempts) as Number) + 1;
        }

        var permanent = isPermanent(responseCode) || attempts >= MAX_ATTEMPTS;

        failures.put(slot, {
            :attempts => attempts,
            :readyAt => System.getTimer() + backoffFor(attempts),
            :code => responseCode,
            :permanent => permanent
        });

        // Persisted so the reason survives a restart. Without it the app reopens knowing only
        // that it has no image, and tells the user "loading" forever instead of why.
        try {
            Storage.setValue(errorKey(slot), responseCode);
        } catch (e) {
            // Diagnostics are not worth failing a download over.
        }

        if (!permanent && !isQueued(slot)) {
            queue.add(slot);
            persistQueue();
        }
    }

    function clearFailure(slot as Number) as Void {
        failures.remove(slot);
        Storage.deleteValue(errorKey(slot));
    }

    //! 5s, 10s, 20s, 40s, capped at a minute.
    static function backoffFor(attempts as Number) as Number {
        var delay = $.BACKOFF_BASE_MS;
        for (var i = 1; i < attempts && delay < $.BACKOFF_CAP_MS; i++) {
            delay *= 2;
        }
        return delay > $.BACKOFF_CAP_MS ? $.BACKOFF_CAP_MS : delay;
    }

    function isPermanentlyFailed(slot as Number) as Boolean {
        var record = failures.get(slot);
        if (!(record instanceof Dictionary)) { return false; }
        var permanent = record.get(:permanent);
        return permanent instanceof Boolean && permanent;
    }

    function readyAt(slot as Number) as Number {
        var record = failures.get(slot);
        if (!(record instanceof Dictionary)) { return 0; }
        return record.get(:readyAt) as Number;
    }

    //! Falls back to the persisted code so the view can still explain a failure that happened
    //! before the app was last closed.
    function lastErrorCode(slot as Number) as Number? {
        var record = failures.get(slot);
        if (record instanceof Dictionary) { return record.get(:code) as Number; }
        var stored = Storage.getValue(errorKey(slot));
        return stored instanceof Number ? stored : null;
    }

    // ------------------------------------------------------------ UI state

    //! What the view should tell the user about this slot.
    //! One of :ready, :downloading, :queued, :offline, :retrying, :failed.
    function stateFor(slot as Number) as Symbol {
        if (CodeStore.isCacheValid(slot)) { return :ready; }
        if (slot == inFlight) { return :downloading; }

        if (isPermanentlyFailed(slot)) { return :failed; }
        if (!Connectivity.isConnected()) { return :offline; }
        if (failures.get(slot) instanceof Dictionary) { return :retrying; }
        return :queued;
    }

    //! Seconds until the next retry, or 0 when there is nothing to wait for.
    function retryInSeconds(slot as Number) as Number {
        var remaining = readyAt(slot) - System.getTimer();
        if (remaining <= 0) { return 0; }
        return (remaining / 1000).toNumber() + 1;
    }

    function pendingCount() as Number {
        return queue.size() + (inFlight == NONE ? 0 : 1);
    }
}
