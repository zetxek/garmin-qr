using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.System;
using Toybox.Application.Storage;
using Toybox.Communications;
using Toybox.Lang;

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
                            if (textWidth > maxTextWidth) {
                                // Truncate and add ellipsis
                                var truncatedText = displayText;
                                while (truncatedText.length() > 3 && dc.getTextWidthInPixels(truncatedText + "...", Graphics.FONT_XTINY) > maxTextWidth) {
                                    truncatedText = truncatedText.substring(0, truncatedText.length() - 1);
                                }
                                displayText = truncatedText + "...";
                            }
                            
                            dc.drawText(
                                textX,
                                textY,
                                Graphics.FONT_XTINY,
                                displayText,
                                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER
                            );
                        }
                    }
                } catch (e) {
                    System.println("[GlanceView.onUpdate] Error drawing image: " + e.getErrorMessage());
                    dc.drawText(
                        dc.getWidth() / 2,
                        dc.getHeight() / 2,
                        Graphics.FONT_TINY,
                        "Error displaying code",
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
                    );
                }
            } else {
                System.println("[GlanceView.onUpdate] No image available, showing loading message");
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
