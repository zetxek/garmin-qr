import Toybox.Lang;
import Toybox.Application;

//! How the codes list is ordered. `DATE` is the order codes were added (their slot order), which is
//! what existing users already expect, so it is the default. The codes carry no timestamp, so
//! "date" cannot mean anything finer than that.
(:glance)
module SortOrder {

    const SETTING = "sortBy";

    const DATE = 0;
    const TITLE = 1;
    const CODE = 2;

    function current() as Number {
        var value = null;
        try {
            value = Application.Properties.getValue(SETTING);
        } catch (e) {
            value = null;
        }
        if (value instanceof Number && value >= DATE && value <= CODE) { return value; }
        return DATE;
    }

    function label(order as Number) as String {
        if (order == TITLE) { return "Title"; }
        if (order == CODE) { return "Code"; }
        return "Date added";
    }
}
