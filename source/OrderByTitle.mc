import Toybox.Lang;
import Toybox.Application;

//! Whether the codes list is sorted alphabetically by title instead of showing codes in the
//! order they were added. Off by default: slot order is what existing users already expect.
(:glance)
module OrderByTitle {

    const SETTING = "orderByTitle";

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
