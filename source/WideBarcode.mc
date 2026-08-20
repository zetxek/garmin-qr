import Toybox.Lang;
import Toybox.Application;

//! Whether barcodes render using nearly the full screen width and a thinner-than-ideal quiet
//! zone, for scanners that need thicker bars more than the standard 10-module margin. Off by
//! default: a smaller quiet zone is a real tradeoff, not a free improvement.
(:glance)
module WideBarcode {

    const SETTING = "wideBarcode";

    function enabled() as Boolean {
        var value = null;
        try {
            value = Application.Properties.getValue(SETTING);
        } catch (e) {
            value = null;
        }
        return value instanceof Boolean ? value : false;
    }
}
