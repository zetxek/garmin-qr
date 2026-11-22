import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.WatchUi;

//! The icon on the left of a menu row, drawn in code so it needs no image files and scales with
//! the screen. With a colour it is a disc holding a white glyph (green plus, red cross); with
//! `null` it is a plain white glyph, like the icons in Garmin's own menus.
(:app)
class MenuIcon extends WatchUi.Drawable {

    static const PLUS = 0;
    static const CROSS = 1;
    static const TYPE = 2;
    static const TITLE = 3;
    static const TEXT = 4;
    static const REFRESH = 5;
    static const SETTINGS = 6;
    static const ABOUT = 7;

    var color as Number?;
    var glyph as Number;

    function initialize(color as Number?, glyph as Number) {
        Drawable.initialize({});
        self.color = color;
        self.glyph = glyph;
    }

    function draw(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;
        var r = (w < h ? w : h) / 2;

        var disc = color;
        if (disc != null) {
            dc.setColor(disc, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(cx, cy, r);
        }

        // A plain glyph may use the whole box; inside a disc it stays well clear of the edge.
        var g = disc != null ? r / 2 : r * 3 / 4;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(r / 5 > 1 ? r / 5 : 1);

        if (glyph == PLUS) {
            dc.drawLine(cx - g, cy, cx + g, cy);
            dc.drawLine(cx, cy - g, cx, cy + g);
        } else if (glyph == CROSS) {
            dc.drawLine(cx - g, cy - g, cx + g, cy + g);
            dc.drawLine(cx - g, cy + g, cx + g, cy - g);
        } else if (glyph == TYPE) {
            // Three finder squares and a dot: the shape of a QR code.
            var s = g * 2 / 3;
            dc.drawRectangle(cx - g, cy - g, s, s);
            dc.drawRectangle(cx + g - s, cy - g, s, s);
            dc.drawRectangle(cx - g, cy + g - s, s, s);
            dc.fillRectangle(cx + g - s / 2, cy + g - s / 2, s / 2, s / 2);
        } else if (glyph == TITLE) {
            dc.drawLine(cx - g, cy - g, cx + g, cy - g);
            dc.drawLine(cx, cy - g, cx, cy + g);
        } else if (glyph == TEXT) {
            dc.drawLine(cx - g, cy - g, cx + g, cy - g);
            dc.drawLine(cx - g, cy, cx + g, cy);
            dc.drawLine(cx - g, cy + g, cx, cy + g);
        } else if (glyph == REFRESH) {
            drawRefresh(dc, cx, cy, g);
        } else if (glyph == SETTINGS) {
            drawGear(dc, cx, cy, g);
        } else {
            dc.drawCircle(cx, cy, g);
            dc.fillCircle(cx, cy - g / 2, r / 8 > 1 ? r / 8 : 1);
            dc.drawLine(cx, cy - g / 8, cx, cy + g / 2);
        }
    }

    //! An open circle with an arrowhead at the gap.
    function drawRefresh(dc as Graphics.Dc, cx as Number, cy as Number, g as Number) as Void {
        dc.drawArc(cx, cy, g, Graphics.ARC_COUNTER_CLOCKWISE, 60, 330);
        var a = Math.toRadians(60);
        var px = cx + (g * Math.cos(a)).toNumber();
        var py = cy - (g * Math.sin(a)).toNumber();
        var k = g / 2;
        dc.fillPolygon([[px - k, py - k / 2], [px + k, py - k / 2], [px, py + k]]);
    }

    //! A ring with teeth.
    function drawGear(dc as Graphics.Dc, cx as Number, cy as Number, g as Number) as Void {
        dc.drawCircle(cx, cy, g * 2 / 3);
        for (var i = 0; i < 8; i++) {
            var a = Math.toRadians(i * 45);
            var c = Math.cos(a);
            var s = Math.sin(a);
            dc.drawLine(
                cx + (g * 2 / 3 * c).toNumber(), cy - (g * 2 / 3 * s).toNumber(),
                cx + (g * c).toNumber(), cy - (g * s).toNumber());
        }
    }
}
