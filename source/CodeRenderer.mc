import Toybox.Lang;
import Toybox.Graphics;

//! Draws locally generated codes straight onto the display.
//!
//! Modules are snapped to whole pixels. A QR drawn at a fractional module size gets uneven
//! rows, which is exactly what a scanner struggles with; better to leave a slightly wider quiet
//! margin than to smear the modules. This is also why a generated code reads more reliably than
//! the downloaded bitmap it replaces, which arrived at a fixed pixel size and was then scaled to
//! whatever the screen happened to be.
(:glance)
module CodeRenderer {

    //! QR codes carry a mandatory 4-module quiet zone. Anything less and many scanners refuse.
    const QUIET_MODULES = 4;

    //! Largest whole-pixel module size that fits `available` pixels, including the quiet zone.
    function moduleSize(matrixSize as Number, available as Number) as Number {
        var scale = available / (matrixSize + (2 * QUIET_MODULES));
        return scale < 1 ? 1 : scale;
    }

    //! Draw a QR matrix centred in the box, on a white field wide enough to act as the quiet
    //! zone. Returns the side length actually used, so the caller can lay out around it.
    function drawQr(
        dc as Graphics.Dc, matrix as QrMatrix, centreX as Number, centreY as Number, available as Number
    ) as Number {
        var scale = moduleSize(matrix.size, available);
        var codePixels = matrix.size * scale;
        var quiet = QUIET_MODULES * scale;
        var side = codePixels + (2 * quiet);

        var left = centreX - (side / 2);
        var top = centreY - (side / 2);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_WHITE);
        dc.fillRectangle(left, top, side, side);

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
        var originX = left + quiet;
        var originY = top + quiet;
        for (var y = 0; y < matrix.size; y++) {
            // Coalesce horizontal runs into one rectangle: far fewer draw calls than one per
            // module, which matters on the slower devices.
            var x = 0;
            while (x < matrix.size) {
                if (matrix.get(x, y) == 0) { x++; continue; }
                var run = 1;
                while (x + run < matrix.size && matrix.get(x + run, y) == 1) { run++; }
                dc.fillRectangle(originX + (x * scale), originY + (y * scale), run * scale, scale);
                x += run;
            }
        }
        return side;
    }

    //! Draw a Code 128 module row as vertical bars filling the given box.
    function drawBarcode(
        dc as Graphics.Dc, modules as ByteArray,
        centreX as Number, centreY as Number, available as Number, height as Number
    ) as Void {
        // A barcode's quiet zone is 10 modules either side; clamp the bar width so it fits.
        var quietModules = 10;
        var scale = available / (modules.size() + (2 * quietModules));
        if (scale < 1) { scale = 1; }

        var barsWidth = modules.size() * scale;
        var quiet = quietModules * scale;
        var totalWidth = barsWidth + (2 * quiet);

        var left = centreX - (totalWidth / 2);
        var top = centreY - (height / 2);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_WHITE);
        dc.fillRectangle(left, top, totalWidth, height);

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
        var originX = left + quiet;
        var i = 0;
        while (i < modules.size()) {
            if (modules[i] == 0) { i++; continue; }
            var run = 1;
            while (i + run < modules.size() && modules[i + run] == 1) { run++; }
            dc.fillRectangle(originX + (i * scale), top, run * scale, height);
            i += run;
        }
    }
}
