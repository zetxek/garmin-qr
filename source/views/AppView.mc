import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.System;
import Toybox.Application;

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
        Connectivity.get().start();
        applyScreenTimeout();
        ImageService.get().pump();
    }

    function onHide() as Void {
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

        var service = ImageService.get();
        service.enqueueAll();
        service.pump();
        WatchUi.requestUpdate();
    }

    function activeSlot() as Number {
        if (position < 0 || position >= slots.size()) { return -1; }
        return slots[position];
    }

    function loadCurrent() as Void {
        var slot = activeSlot();
        if (slot == currentSlot && currentImage != null) { return; }

        currentSlot = slot;
        currentImage = slot < 0 ? null : CodeStore.cachedImage(slot);

        if (slot >= 0 && currentImage == null) {
            // The code the user is looking at jumps the queue.
            var service = ImageService.get();
            service.enqueueFirst(slot);
            service.pump();
        }
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
        if (currentImage == null && currentSlot >= 0) {
            currentImage = CodeStore.cachedImage(currentSlot);
        }

        var image = currentImage;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        drawStatusBanner(dc);

        if (image != null) {
            drawCode(dc, image, currentSlot);
            drawCounter(dc);
        } else {
            drawPlaceholder(dc);
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
    function drawPlaceholder(dc as Graphics.Dc) as Void {
        var state = ImageService.get().stateFor(currentSlot);
        var message = "Loading code...";
        var color = Graphics.COLOR_WHITE;

        if (state == :offline) {
            message = "Offline\nWill load when your\nphone is back";
            color = Graphics.COLOR_YELLOW;
        } else if (state == :retrying) {
            var code = ImageService.get().lastErrorCode(currentSlot);
            message = "Couldn't load\nRetrying...";
            if (code != null) { message = "Couldn't load (" + code + ")\nRetrying..."; }
            color = Graphics.COLOR_YELLOW;
        } else if (state == :failed) {
            var failCode = ImageService.get().lastErrorCode(currentSlot);
            message = failCode != null && ImageService.isPermanent(failCode)
                ? "This code can't be\ngenerated. Check its\ntext in settings."
                : "Couldn't load this code.\nUse Refresh to try again.";
            color = Graphics.COLOR_RED;
        }

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
