import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Graphics;

//! The glance: first code, drawn from cache.
//!
//! The glance process gets a fraction of the app's memory, so this reads Storage and draws.
//! It never downloads and never touches the queue, the connectivity timer or the settings sync.
(:glance)
class GlanceView extends WatchUi.GlanceView {

    //! Qualified deliberately: this class shadows `WatchUi.GlanceView`, so an unqualified
    //! `GlanceView.initialize()` reads like self-recursion. It is not — Monkey C resolves it to
    //! the superclass — but `glanceViewConstructsWithoutRecursing` pins that down.
    function initialize() {
        WatchUi.GlanceView.initialize();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var slot = CodeStore.firstSlot();
        if (slot < 0) {
            drawMessage(dc, "No codes configured");
            return;
        }

        var bmp = CodeStore.glanceImage();
        if (bmp == null) {
            bmp = CodeStore.cachedImage(slot);
        }
        if (bmp == null) {
            drawMessage(dc, "Open to load code");
            return;
        }

        try {
            if (CodeStore.isBarcode(slot)) {
                drawBarcode(dc, bmp);
            } else {
                drawQr(dc, bmp, slot);
            }
        } catch (e) {
            drawMessage(dc, "Error displaying code");
        }
    }

    function drawMessage(dc as Graphics.Dc, message as String) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            dc.getWidth() / 2, dc.getHeight() / 2, Graphics.FONT_TINY, message,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );
    }

    function drawBarcode(dc as Graphics.Dc, bmp as WatchUi.BitmapResource) as Void {
        var screenWidth = dc.getWidth();
        var screenHeight = dc.getHeight();
        var margin = screenWidth * 0.05;

        var width = screenWidth - (margin * 2);
        var height = screenHeight * 0.7;
        if (bmp.getHeight() > 0) {
            var proportional = width / (bmp.getWidth().toFloat() / bmp.getHeight());
            if (proportional < height) { height = proportional; }
        }

        dc.drawScaledBitmap(margin, (screenHeight - height) / 2, width, height, bmp);
    }

    function drawQr(dc as Graphics.Dc, bmp as WatchUi.BitmapResource, slot as Number) as Void {
        var screenWidth = dc.getWidth();
        var screenHeight = dc.getHeight();

        var maxSize = screenWidth * 0.4;
        if (maxSize > screenHeight * 0.7) { maxSize = screenHeight * 0.7; }

        var longestEdge = bmp.getWidth() > bmp.getHeight() ? bmp.getWidth() : bmp.getHeight();
        if (longestEdge <= 0) { return; }
        var scale = maxSize / longestEdge;
        var width = bmp.getWidth() * scale;
        var height = bmp.getHeight() * scale;

        var x = 10;
        dc.drawScaledBitmap(x, (screenHeight - height) / 2, width, height, bmp);

        var label = CodeStore.getTitle(slot);
        if (label.length() == 0) {
            var text = CodeStore.getText(slot);
            label = text == null ? "" : text;
        }
        if (label.length() == 0) { return; }

        var textX = (x + width + 10).toNumber();
        var maxTextWidth = (screenWidth - textX - 5).toNumber();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            textX, screenHeight / 2, Graphics.FONT_XTINY,
            truncate(dc, label, maxTextWidth),
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER
        );
    }

    function truncate(dc as Graphics.Dc, text as String, maxWidth as Number) as String {
        var result = text;
        while (result.length() > 3 && dc.getTextWidthInPixels(result, Graphics.FONT_XTINY) > maxWidth) {
            result = result.substring(0, result.length() - 4) + "...";
        }
        return result;
    }
}
