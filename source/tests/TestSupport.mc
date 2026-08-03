import Toybox.Lang;
import Toybox.Test;
import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.WatchUi;

//! Helpers shared by the test files. `(:test)` declarations are dropped from normal builds, so
//! none of this ships to a device.
(:test)
module TestSupport {

    //! Wipe every key the app owns so each test starts from a known state.
    function reset() as Void {
        for (var slot = 0; slot < CodeStore.MAX_CODES; slot++) {
            CodeStore.deleteSlot(slot);
        }
        Storage.deleteValue(CodeStore.GLANCE_IMAGE);
        Storage.deleteValue(CodeStore.GLANCE_META_TEXT);
        Storage.deleteValue(CodeStore.GLANCE_META_TYPE);
        Storage.deleteValue("pendingImageSlots");
        Application.Properties.setValue(CodeStore.PROP_CODES, [] as Array<Application.PropertyValueType>);
        ImageService.instance = null;
    }

    //! Any real BitmapResource will do; the tests only care that something was cached.
    function sampleBitmap() as WatchUi.BitmapResource {
        return WatchUi.loadResource(Rez.Drawables.LauncherIcon) as WatchUi.BitmapResource;
    }

    function assertStringEquals(actual as String?, expected as String, context as String) as Void {
        Test.assertMessage(
            actual != null && actual.equals(expected),
            context + ": expected '" + expected + "' but got '" + actual + "'");
    }

    function propertiesEntryCount() as Number {
        var raw = Application.Properties.getValue(CodeStore.PROP_CODES);
        return raw instanceof Array ? raw.size() : 0;
    }
}
