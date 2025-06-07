using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.System;
using Toybox.Application.Storage;
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

                    // Calculate image size first to determine actual space needed
                    var margin = 5;
                    var maxImageSize = (screenHeight < screenWidth ? screenHeight : screenWidth) - (margin * 4);
                    
                    var scale = 1.0;
                    if (bmpWidth > maxImageSize || bmpHeight > maxImageSize) {
                        var scaleX = maxImageSize.toFloat() / bmpWidth;
                        var scaleY = maxImageSize.toFloat() / bmpHeight;
                        scale = scaleX < scaleY ? scaleX : scaleY;
                    }
                    
                    var drawWidth = (bmpWidth * scale).toNumber();
                    var drawHeight = (bmpHeight * scale).toNumber();
                    
                    // Position image on the left with small margin
                    var imageX = margin;
                    var imageY = (screenHeight - drawHeight) / 2;  // Center vertically
                    
                    // Draw the QR code image
                    dc.drawScaledBitmap(imageX, imageY, drawWidth, drawHeight, bmp);
                    System.println("[GlanceView.onUpdate] Drew scaled image at " + imageX + "," + imageY + " size " + drawWidth + "x" + drawHeight);
                    
                    // Position text directly adjacent to the right edge of the image
                    var textX = imageX + drawWidth;  // No gap - text starts immediately after image
                    var remainingWidth = screenWidth - textX - margin;
                    
                    // Only draw text if there's enough space
                    if (remainingWidth > 20) {
                        var codeText = Storage.getValue("code_" + firstCodeIndex + "_text");
                        var displayText = "QR Code";
                        if (codeText != null && codeText.length() > 0) {
                            // Truncate text based on available space
                            var maxChars = remainingWidth > 60 ? 15 : 8;
                            displayText = codeText.length() > maxChars ? codeText.substring(0, maxChars - 3) + "..." : codeText;
                        }
                        
                        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
                        dc.drawText(
                            textX + (remainingWidth / 2),  // Center in remaining space
                            screenHeight / 2,  // Center vertically
                            Graphics.FONT_TINY,
                            displayText,
                            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
                        );
                        System.println("[GlanceView.onUpdate] Drew text: " + displayText);
                    }
                    
                } catch (e) {
                    System.println("[GlanceView.onUpdate] Error drawing image: " + e.getErrorMessage());
                    // On error, show text fallback
                    dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
                    dc.drawText(
                        dc.getWidth() / 2,
                        dc.getHeight() / 2,
                        Graphics.FONT_TINY,
                        "QR Code",
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
                    );
                }
            } else {
                System.println("[GlanceView.onUpdate] No image available, showing loading message");
                // No image available, show text
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
                dc.drawText(
                    dc.getWidth() / 2,
                    dc.getHeight() / 2,
                    Graphics.FONT_TINY,
                    "Loading...",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
                );
            }
        } else {
            System.println("[GlanceView.onUpdate] No codes configured");
            // No codes configured
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            dc.drawText(
                dc.getWidth() / 2,
                dc.getHeight() / 2,
                Graphics.FONT_TINY,
                "No codes",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
        }
        
        System.println("[GlanceView.onUpdate] Glance update complete");
    }
}
