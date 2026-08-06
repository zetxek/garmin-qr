import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.System;
import Toybox.Application;
import Toybox.Timer;

//! The main screen: one code at a time, up/down or swipe to move between them.
//!
//! Rendering only. `onUpdate` draws what the store already holds and never starts a download —
//! the previous version issued network requests from inside the draw path and then called
//! `requestUpdate()` from the callback, which could re-enter drawing.
(:app)
class AppView extends WatchUi.View {

    static var current as AppView?;

    var slots as Array<Number>;
    var position as Number;
    //! Only the visible code's bitmap is held in memory. Loading all ten at once was a large
    //! part of this app's memory footprint on smaller devices.
    var currentSlot as Number;
    var currentImage as WatchUi.BitmapResource?;
    //! Locally generated code for the visible slot. When either is set, nothing is downloaded.
    var currentMatrix as QrMatrix?;
    var currentBars as ByteArray?;
    //! Generation is deferred to a timer rather than run inline. Building a QR takes a few
    //! hundred milliseconds, and Connect IQ's watchdog kills a startup slice long before that --
    //! doing it in `initialize` crashed the app with "Code Executed Too Long". Off the startup
    //! path the screen appears immediately and the code fills in a frame later.
    var generateTimer as Timer.Timer?;
    var generateFor as Number = -1;
    var builder as QrBuilder?;
    var emptyLayoutShown as Boolean;

    function initialize() {
        View.initialize();
        AppView.current = self;
        slots = [] as Array<Number>;
        position = 0;
        currentSlot = -1;
        currentImage = null;
        emptyLayoutShown = false;
        onCodesChanged();
    }

    // ------------------------------------------------------------ lifecycle

    function onLayout(dc as Graphics.Dc) as Void {
    }

    function onShow() as Void {
        applyScreenTimeout();
        if (serviceIsInUse()) {
            Connectivity.get().start();
            ImageService.get().pump();
        }
    }

    function onHide() as Void {
        stopGeneration();
        var backlight = Application.getApp().backlight;
        if (backlight != null) {
            backlight.disable();
        }
    }

    //! Called whenever the set of codes may have changed: startup, settings sync, add, delete.
    function onCodesChanged() as Void {
        slots = CodeStore.occupiedSlots();
        if (position >= slots.size()) {
            position = slots.size() > 0 ? slots.size() - 1 : 0;
        }
        currentSlot = -1;
        currentImage = null;
        loadCurrent();

        // Only prefetch from the service when it is actually the source. With on-device
        // generation the codes never need downloading, and prefetching would spend battery on
        // requests whose results are thrown away.
        if (!CodeGeneration.enabled()) {
            var service = ImageService.get();
            service.enqueueAll();
            service.pump();
        }
        WatchUi.requestUpdate();
    }

    function activeSlot() as Number {
        if (position < 0 || position >= slots.size()) { return -1; }
        return slots[position];
    }

    function loadCurrent() as Void {
        var slot = activeSlot();
        if (slot == currentSlot && hasSomethingToDraw()) { return; }

        currentSlot = slot;
        currentMatrix = null;
        currentBars = null;
        currentImage = null;
        if (slot < 0) { return; }

        // Generating on the watch is the primary path: no network, no waiting, and immune to the
        // image-proxy failures that leave downloads returning 404.
        if (CodeGeneration.enabled() && CodeStore.getText(slot) != null) {
            // A code already generated is drawn on this very frame -- no intermediate screen.
            currentBars = CodeStore.cachedBars(slot);
            currentMatrix = CodeStore.cachedMatrix(slot);
            if (hasSomethingToDraw()) {
                prepareGlanceCode();
                return;
            }

            if (CodeStore.isBarcode(slot)) {
                // Code 128 is a table lookup and a checksum, fast enough to do inline.
                currentBars = Code128.encode(CodeStore.getText(slot) as String);
                if (currentBars != null) {
                    CodeStore.putBars(slot, currentBars as ByteArray);
                    prepareGlanceCode();
                    return;
                }
            } else {
                scheduleGeneration(slot);
                return;
            }
        }

        // Fall back to the service: either the payload is outside what the local encoders cover,
        // or on-device generation has been switched off.
        currentImage = CodeStore.cachedImage(slot);
        if (currentImage == null) {
            // The code the user is looking at jumps the queue.
            var service = ImageService.get();
            service.enqueueFirst(slot);
            service.pump();
        }
    }

    //! Only reach for the network when it is actually the source of codes.
    function serviceIsInUse() as Boolean {
        return !CodeGeneration.enabled();
    }

    function hasSomethingToDraw() as Boolean {
        return currentMatrix != null || currentBars != null || currentImage != null;
    }

    //! The glance draws the first code, and it cannot build one itself. If that code is not
    //! cached, build it here in the background so the glance has something to show without the
    //! user having to open it in the app first.
    function prepareGlanceCode() as Void {
        if (!CodeGeneration.enabled() || builder != null) { return; }

        var slot = CodeStore.firstSlot();
        if (slot < 0 || CodeStore.isGeneratedValid(slot)) { return; }

        var text = CodeStore.getText(slot);
        if (text == null) { return; }

        if (CodeStore.isBarcode(slot)) {
            var bars = Code128.encode(text);
            if (bars != null) { CodeStore.putBars(slot, bars as ByteArray); }
            return;
        }
        scheduleGeneration(slot);
    }

    //! Start building a QR in the background, one slice per timer tick.
    function scheduleGeneration(slot as Number) as Void {
        var text = CodeStore.getText(slot);
        if (text == null) { return; }

        generateFor = slot;
        builder = new QrBuilder(text);
        if (generateTimer == null) { generateTimer = new Timer.Timer(); }
        generateTimer.start(method(:onGenerateTick), 20, true);
    }

    //! One slice of generation. The watchdog kills any slice that runs too long, so the work is
    //! spread over ticks rather than done in one call.
    //!
    //! The slot being built is not always the one on screen: once the visible code is ready the
    //! glance's code is built the same way, so the glance has something to draw without the user
    //! opening it first.
    function onGenerateTick() as Void {
        var work = builder;
        if (work == null || generateFor < 0) {
            stopGeneration();
            return;
        }
        if (!work.advance()) { return; }

        stopGeneration();
        var slot = generateFor;
        var succeeded = !work.failed && work.matrix != null;
        builder = null;
        generateFor = -1;

        if (succeeded) {
            CodeStore.putMatrix(slot, work.matrix as QrMatrix);
            if (slot == currentSlot) { currentMatrix = work.matrix; }
            prepareGlanceCode();
            WatchUi.requestUpdate();
            return;
        }

        if (slot != currentSlot) {
            // A background build for the glance failed; nothing on screen depends on it.
            return;
        }

        // The visible code is outside what the local encoder covers; let the service try.
        currentImage = CodeStore.cachedImage(slot);
        if (currentImage == null) {
            var service = ImageService.get();
            service.enqueueFirst(slot);
            service.pump();
        }
        WatchUi.requestUpdate();
    }

    function stopGeneration() as Void {
        if (generateTimer != null) { generateTimer.stop(); }
    }

    function applyScreenTimeout() as Void {
        var app = Application.getApp();
        var backlight = app.backlight;
        if (backlight == null) { return; }
        if (app.keepScreenOn) {
            backlight.enable();
        } else {
            backlight.disable();
        }
    }

    // ------------------------------------------------------------- drawing

    function onUpdate(dc as Graphics.Dc) as Void {
        if (slots.size() == 0) {
            drawEmptyState(dc);
            return;
        }

        if (emptyLayoutShown) {
            setLayout(null);
            emptyLayoutShown = false;
        }

        // Cheap re-check: a download may have completed since the last frame.
        if (!hasSomethingToDraw() && currentSlot >= 0) {
            currentImage = CodeStore.cachedImage(currentSlot);
        }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        drawStatusBanner(dc);

        if (currentMatrix != null || currentBars != null) {
            drawGeneratedCode(dc);
            drawCounter(dc);
        } else if (currentImage != null) {
            drawCode(dc, currentImage, currentSlot);
            drawCounter(dc);
        } else {
            drawPlaceholder(dc);
        }
    }

    //! Draw a locally generated code, leaving room for the title above and the counter below.
    function drawGeneratedCode(dc as Graphics.Dc) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var title = CodeStore.getTitle(currentSlot);
        var titleHeight = title.length() > 0 ? (height * 0.12).toNumber() : 0;
        var counterHeight = (height * 0.14).toNumber();

        var top = (height * 0.08).toNumber() + titleHeight;
        var boxHeight = height - top - counterHeight;
        var centreY = top + (boxHeight / 2);

        if (title.length() > 0) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                width / 2, top - (titleHeight / 2), Graphics.FONT_TINY, title,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
        }

        if (currentBars != null) {
            // Barcodes want width; the height only has to be enough for a scanner to find a row.
            var barLimit = (height * 0.45).toNumber();
            var barHeight = boxHeight < barLimit ? boxHeight : barLimit;
            CodeRenderer.drawBarcode(
                dc, currentBars as ByteArray, width / 2, centreY,
                (width * 0.94).toNumber(), barHeight);
        } else {
            var available = boxHeight < width ? boxHeight : width;
            CodeRenderer.drawQr(dc, currentMatrix as QrMatrix, width / 2, centreY, available);
        }
    }

    function drawEmptyState(dc as Graphics.Dc) as Void {
        try {
            if (!emptyLayoutShown) {
                setLayout(Rez.Layouts.EmptyStateLayout(dc));
                emptyLayoutShown = true;
            }
            View.onUpdate(dc);
        } catch (e) {
            Log.warn("[AppView] empty state layout failed: " + e.getErrorMessage());
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            dc.clear();
            dc.drawText(
                dc.getWidth() / 2, dc.getHeight() / 2, Graphics.FONT_TINY,
                "No codes configured",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
        }
    }

    function drawStatusBanner(dc as Graphics.Dc) as Void {
        var label = null;
        var color = Graphics.COLOR_YELLOW;

        if (!serviceIsInUse()) {
            // Codes are generated here; there is nothing to be offline from or to sync.
            return;
        }
        if (!Connectivity.isConnected()) {
            label = "OFFLINE";
        } else if (ImageService.get().pendingCount() > 0) {
            label = "SYNCING...";
            color = Graphics.COLOR_BLUE;
        }
        if (label == null) { return; }

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(dc.getWidth() / 2, 8, Graphics.FONT_XTINY, label, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function drawCounter(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            dc.getWidth() / 2, dc.getHeight() - 40, Graphics.FONT_XTINY,
            "Code " + (position + 1) + " of " + slots.size(),
            Graphics.TEXT_JUSTIFY_CENTER
        );
    }

    //! What the user sees while there is no image: always an explanation, never a bare spinner
    //! that hides the fact that nothing is happening.
    //! What to say when there is no code to draw yet.
    //!
    //! When codes are generated on the watch nothing is being fetched, so the download states
    //! below cannot apply and "Loading" would be a plain lie -- the watch is building the code.
    function placeholderMessage() as String {
        if (!serviceIsInUse()) { return "Generating code..."; }

        var state = ImageService.get().stateFor(currentSlot);
        if (state == :offline) {
            return "Offline\nWill load when your\nphone is back";
        }
        if (state == :retrying) {
            var code = ImageService.get().lastErrorCode(currentSlot);
            return code == null
                ? "Couldn't load\nRetrying..."
                : "Couldn't load (" + code + ")\nRetrying...";
        }
        if (state == :failed) {
            var failCode = ImageService.get().lastErrorCode(currentSlot);
            if (failCode != null && failCode == 404) {
                // Not the user's fault: Garmin's image proxy reports 404 for its own fetch
                // failures too, so do not send them off to edit text that is already correct.
                return "Code service\nunavailable.\nUse Refresh to retry.";
            }
            if (failCode != null && ImageService.isPermanent(failCode)) {
                return "This code can't be\ngenerated. Check its\ntext in settings.";
            }
            return "Couldn't load this code.\nUse Refresh to try again.";
        }
        return "Loading code...";
    }

    function drawPlaceholder(dc as Graphics.Dc) as Void {
        var color = Graphics.COLOR_WHITE;
        if (serviceIsInUse()) {
            var state = ImageService.get().stateFor(currentSlot);
            if (state == :offline || state == :retrying) {
                color = Graphics.COLOR_YELLOW;
            } else if (state == :failed) {
                color = Graphics.COLOR_RED;
            }
        }
        drawPlaceholderText(dc, placeholderMessage(), color);
    }

    function drawPlaceholderText(dc as Graphics.Dc, message as String, color as Graphics.ColorType) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            dc.getWidth() / 2, dc.getHeight() / 2, Graphics.FONT_XTINY,
            message,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );
    }

    //! Scale the code into the space left between the status banner, the title and the counter.
    function drawCode(dc as Graphics.Dc, bmp as WatchUi.BitmapResource, slot as Number) as Void {
        var screenWidth = dc.getWidth();
        var screenHeight = dc.getHeight();
        var bmpWidth = bmp.getWidth();
        var bmpHeight = bmp.getHeight();
        if (bmpWidth <= 0 || bmpHeight <= 0) { return; }

        var title = CodeStore.getTitle(slot);
        var titleHeight = title.length() > 0 ? screenHeight * 0.1 : 0;
        var topStatusHeight = screenHeight * 0.12;
        var bottomCounterHeight = screenHeight * 0.15;

        var availableHeight = screenHeight - topStatusHeight - bottomCounterHeight - titleHeight;
        var availableWidth = screenWidth * 0.9;

        var finalWidth;
        var finalHeight;

        if (CodeStore.isBarcode(slot)) {
            // Barcodes are read across their width, so width is the dimension that matters.
            var scaleX = availableWidth / bmpWidth;
            var scaleY = (availableHeight * 0.8) / bmpHeight;
            var scale = scaleX < scaleY ? scaleX : scaleY;

            finalWidth = bmpWidth * scale;
            finalHeight = bmpHeight * scale;

            var minWidth = screenWidth * 0.7;
            if (finalWidth < minWidth) {
                scale = minWidth / bmpWidth;
                finalWidth = minWidth;
                finalHeight = bmpHeight * scale;
                if (finalHeight > availableHeight * 0.8) {
                    scale = (availableHeight * 0.8) / bmpHeight;
                    finalWidth = bmpWidth * scale;
                    finalHeight = bmpHeight * scale;
                }
            }
        } else {
            var limit = availableHeight * 0.85;
            var widthLimit = availableWidth * 0.85;
            if (widthLimit < limit) { limit = widthLimit; }

            var longestEdge = bmpWidth > bmpHeight ? bmpWidth : bmpHeight;
            var qrScale = limit / longestEdge;
            // Upscaling past 4x turns the modules into mush.
            if (qrScale > 4.0) { qrScale = 4.0; }

            finalWidth = bmpWidth * qrScale;
            finalHeight = bmpHeight * qrScale;
        }

        var y = topStatusHeight;
        if (title.length() > 0) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                screenWidth / 2, y + (titleHeight / 2), Graphics.FONT_TINY, title,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
            y += titleHeight;
        }

        dc.drawScaledBitmap(
            (screenWidth - finalWidth) / 2,
            y + (availableHeight - finalHeight) / 2,
            finalWidth,
            finalHeight,
            bmp
        );
    }

    // --------------------------------------------------------------- input

    function showNext() as Boolean {
        if (slots.size() < 2) { return true; }
        position = (position + 1) % slots.size();
        loadCurrent();
        Haptics.tick();
        WatchUi.requestUpdate();
        return true;
    }

    function showPrevious() as Boolean {
        if (slots.size() < 2) { return true; }
        position = (position - 1 + slots.size()) % slots.size();
        loadCurrent();
        Haptics.tick();
        WatchUi.requestUpdate();
        return true;
    }

    function onKey(keyEvent as WatchUi.KeyEvent) as Boolean {
        var key = keyEvent.getKey();
        if (key == WatchUi.KEY_UP) { return showPrevious(); }
        if (key == WatchUi.KEY_DOWN) { return showNext(); }
        if (key == WatchUi.KEY_MENU || key == WatchUi.KEY_ENTER || key == WatchUi.KEY_START) {
            showMenu();
            return true;
        }
        return false;
    }

    function onSwipe(swipeEvent as WatchUi.SwipeEvent) as Boolean {
        var direction = swipeEvent.getDirection();
        if (direction == WatchUi.SWIPE_DOWN) { return showNext(); }
        if (direction == WatchUi.SWIPE_UP) { return showPrevious(); }
        return false;
    }

    function showMenu() as Void {
        WatchUi.pushView(CodeMenu.build(self), new CodeMenuDelegate(self), WatchUi.SLIDE_UP);
    }

    //! Reload the visible code from scratch, e.g. after "Refresh codes".
    function forceReload() as Void {
        var slot = activeSlot();
        if (slot >= 0) {
            CodeStore.clearImage(slot);
            ImageService.get().forget(slot);
        }
        onCodesChanged();
    }
}

(:app)
class AppDelegate extends WatchUi.BehaviorDelegate {
    var view as AppView;

    function initialize(view as AppView) {
        BehaviorDelegate.initialize();
        self.view = view;
    }

    function onKey(keyEvent as WatchUi.KeyEvent) as Boolean { return view.onKey(keyEvent); }
    function onSwipe(swipeEvent as WatchUi.SwipeEvent) as Boolean { return view.onSwipe(swipeEvent); }
    function onMenu() as Boolean { view.showMenu(); return true; }
    function onSelect() as Boolean { view.showMenu(); return true; }
    function onNextPage() as Boolean { return view.showNext(); }
    function onPreviousPage() as Boolean { return view.showPrevious(); }
}
