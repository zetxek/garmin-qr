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

    //! The quiet zone actually drawn, whenever there is room for it.
    const IDEAL_QUIET_MODULES = 10;
    //! The minimum the scale search insists on before picking a bigger integer scale. Requiring
    //! the full IDEAL_QUIET_MODULES here (as this used to) double-charges the margin: once to
    //! pick the scale, again below when centering. A small floor instead lets a bigger scale win
    //! whenever the bars themselves have room, even if the *ideal* margin would not also fit.
    const DEFAULT_MIN_QUIET_MODULES = 2;
    //! Wide mode's floor: thinner still, so a scale step that only just does not fit at the
    //! default floor gets to happen anyway. See WideBarcode for what this trades away.
    const WIDE_MIN_QUIET_MODULES = 1;

    //! Bar width, quiet-zone width and total width for a barcode, or null when the payload
    //! cannot be drawn legibly in the space available.
    //!
    //! Separate from the drawing so the fit can be asserted without a Dc.
    function barcodeLayout(moduleCount as Number, available as Number, wide as Boolean) as Array<Number>? {
        if (moduleCount <= 0 || available <= 0) { return null; }

        var minQuietModules = wide ? WIDE_MIN_QUIET_MODULES : DEFAULT_MIN_QUIET_MODULES;
        var scale = available / (moduleCount + (2 * minQuietModules));
        if (scale < 1) {
            // No room for even the reduced floor. A bar must be at least one pixel wide to be
            // read, so that is the last resort -- below it the payload does not fit this screen.
            scale = 1;
            if (moduleCount > available) { return null; }
        }

        var barsWidth = moduleCount * scale;
        var quiet = (available - barsWidth) / 2;
        if (quiet > IDEAL_QUIET_MODULES * scale) { quiet = IDEAL_QUIET_MODULES * scale; }
        return [scale, quiet, barsWidth + (2 * quiet)] as Array<Number>;
    }

    //! Draw a Code 128 module row as vertical bars filling the given box.
    //!
    //! Returns false when the payload cannot be drawn legibly, so the caller can say so rather
    //! than show a symbol no reader will accept.
    //!
    //! The bars come first and the quiet zone gets what is left. Charging the full 10-module
    //! quiet zone either side before checking the fit pushed long payloads off both edges: a
    //! 20-character payload is 255 modules, which with 20 quiet modules wants 275px on a screen
    //! offering about 244px. The start and stop patterns were drawn past the edge, and a clipped
    //! Code 128 symbol does not scan.
    function drawBarcode(
        dc as Graphics.Dc, modules as ByteArray,
        centreX as Number, centreY as Number, available as Number, height as Number, wide as Boolean
    ) as Boolean {
        var layout = barcodeLayout(modules.size(), available, wide);
        if (layout == null) { return false; }
        var scale = layout[0];
        var quiet = layout[1];
        var totalWidth = layout[2];

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
        return true;
    }
}
