import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

//! A coloured disc with a white plus or cross, used as a menu icon. Menu2 cannot colour a row's
//! text, so the colour rides on the icon: green for adding, red for deleting.
(:app)
class MenuIcon extends WatchUi.Drawable {

    static const PLUS = 0;
    static const CROSS = 1;

    var color as Number;
    var glyph as Number;

    function initialize(color as Number, glyph as Number) {
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
        var arm = r / 2;

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, cy, r);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(r / 4 > 1 ? r / 4 : 1);
        if (glyph == PLUS) {
            dc.drawLine(cx - arm, cy, cx + arm, cy);
            dc.drawLine(cx, cy - arm, cx, cy + arm);
        } else {
            dc.drawLine(cx - arm, cy - arm, cx + arm, cy + arm);
            dc.drawLine(cx - arm, cy + arm, cx + arm, cy - arm);
        }
    }
}
