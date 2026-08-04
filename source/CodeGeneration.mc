import Toybox.Lang;
import Toybox.Application;

//! Whether codes are generated on the watch or fetched from the service.
//!
//! On-device generation is the default and the intended path. The service remains available as
//! a fallback for one release: if a payload trips a bug in the local encoders, a user can switch
//! back from Garmin Express without waiting for an app-store update.
(:glance)
module CodeGeneration {

    const SETTING = "generateOnDevice";

    function enabled() as Boolean {
        var value = null;
        try {
            value = Application.Properties.getValue(SETTING);
        } catch (e) {
            value = null;
        }
        return value instanceof Boolean ? value : true;
    }
}
