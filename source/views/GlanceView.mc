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

        try {
            // Generated codes first. The glance never builds one -- it has a fraction of the
            // app's memory and the same watchdog -- it only draws what the app already cached.
            var bars = CodeStore.cachedBars(slot);
            if (bars != null) {
                drawGeneratedBarcode(dc, bars);
                return;
            }
            var matrix = CodeStore.cachedMatrix(slot);
            if (matrix != null) {
                drawGeneratedQr(dc, matrix, slot);
                return;
            }

            // Nothing generated yet: fall back to a downloaded image if one happens to exist.
            var bmp = CodeStore.glanceImage();
            if (bmp == null) { bmp = CodeStore.cachedImage(slot); }
            if (bmp != null) {
                if (CodeStore.isBarcode(slot)) { drawBarcode(dc, bmp); } else { drawQr(dc, bmp, slot); }
                return;
            }
        } catch (e) {
            drawMessage(dc, "Error displaying code");
            return;
        }

        drawMessage(dc, "Open the app once");
    }

    //! A generated barcode: bars across most of the width, label underneath if it fits.
    function drawGeneratedBarcode(dc as Graphics.Dc, bars as ByteArray) as Void {
        var height = (dc.getHeight() * 0.72).toNumber();
        var drawn = CodeRenderer.drawBarcode(
            dc, bars, dc.getWidth() / 2, dc.getHeight() / 2,
            (dc.getWidth() * 0.96).toNumber(), height);
        if (!drawn) { drawMessage(dc, "Code too long"); }
    }

    //! A generated QR sits left of the title.
    //!
    //! The glance is a chord across a round display, so the far left and right of the band are
    //! cut off by the bezel. Everything is inset from the edges rather than run to them, which
    //! is what clipped the quiet zone and the end of the title.
    function drawGeneratedQr(dc as Graphics.Dc, matrix as QrMatrix, slot as Number) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();

        var available = (height * 0.88).toNumber();
        var widthCap = (width * 0.34).toNumber();
        if (available > widthCap) { available = widthCap; }

        var centreX = (width * 0.30).toNumber();
        var side = CodeRenderer.drawQr(dc, matrix, centreX, height / 2, available);

        var label = CodeStore.getTitle(slot);
        if (label.length() == 0) {
            var text = CodeStore.getText(slot);
            label = text == null ? "" : text;
        }
        if (label.length() == 0) { return; }

        var textX = centreX + (side / 2) + 10;
        // Leave a margin on the right for the same reason: the bezel eats the last few pixels.
        var maxTextWidth = (width * 0.94).toNumber() - textX;
        if (maxTextWidth <= 20) { return; }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            textX, height / 2, Graphics.FONT_XTINY,
            truncate(dc, label, maxTextWidth),
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER
        );
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
        // Both dimensions matter: the ratio is the divisor, so a zero width divides by zero.
        if (bmp.getHeight() > 0 && bmp.getWidth() > 0) {
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
