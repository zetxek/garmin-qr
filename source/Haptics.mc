import Toybox.Lang;
import Toybox.System;
import Toybox.Attention;

//! Vibration feedback, guarded.
//!
//! `Attention.vibrate` was previously called unconditionally when switching codes. Devices
//! without a vibration motor — Edge units are in the supported product list — do not have the
//! method at all, so the call threw and navigation appeared broken.
(:app)
module Haptics {

    function tick() as Void {
        if (!(Toybox has :Attention) || !(Attention has :vibrate)) { return; }
        try {
            var settings = System.getDeviceSettings();
            if ((settings has :vibrateOn) && settings.vibrateOn == false) { return; }
            Attention.vibrate([new Attention.VibeProfile(50, 100)]);
        } catch (e) {
            Log.debug("[Haptics] vibrate unavailable: " + e.getErrorMessage());
        }
    }
}
