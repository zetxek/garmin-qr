import Toybox.Lang;
import Toybox.System;

//! Logging that costs nothing in release builds.
//!
//! `monkeyc -r` drops declarations annotated `(:debug)` and keeps `(:release)` ones,
//! so `Log.debug(...)` calls compile away to an empty function in shipped builds.
(:glance)
module Log {

    (:debug)
    function debug(message as String) as Void {
        System.println(message);
    }

    (:release)
    function debug(message as String) as Void {
    }

    //! Unexpected conditions. Kept in release builds so field logs stay useful.
    function warn(message as String) as Void {
        System.println("WARN " + message);
    }
}
