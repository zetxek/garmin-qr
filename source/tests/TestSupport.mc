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

    //! Three codes — a QR, a barcode and a QR — with no images yet.
    function threeCodes() as Void {
        reset();
        CodeStore.save(0, "First", "code-one", CodeStore.TYPE_QR);
        CodeStore.save(1, "Second", "code-two", CodeStore.TYPE_BARCODE);
        CodeStore.save(2, "Third", "code-three", CodeStore.TYPE_QR);
    }

    //! Install a service that records requests instead of making them, and return it.
    //!
    //! Tests must not touch the radio. In the simulator `makeImageRequest` calls back
    //! *synchronously* with -101 when the phone data channel is unavailable, so a test using the
    //! real one would be driving the simulator's failures rather than its own.
    function fakeService() as FakeImageService {
        var service = new FakeImageService();
        ImageService.instance = service;
        return service;
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

//! `ImageService` with the radio replaced by a log of the URLs it would have fetched.
//! Everything else — the queue, dispatch order, callback routing, caching, backoff — is the
//! production code under test.
(:test)
class FakeImageService extends ImageService {

    var requested as Array<String>;

    function initialize() {
        ImageService.initialize();
        requested = [] as Array<String>;
    }

    function transmit(url as String, size as Number) as Void {
        requested.add(url);
    }

    //! Deliver a successful response for whatever is currently in flight.
    function respondOk() as Void {
        onResponse(200, TestSupport.sampleBitmap());
    }

    //! Deliver a failure for whatever is currently in flight.
    function respondWith(code as Number) as Void {
        onResponse(code, null);
    }

    //! Answer every request the queue makes, bounded so a stall fails rather than hangs.
    //! Returns the slots that were served, in order.
    function drain() as Array<Number> {
        var served = [] as Array<Number>;
        for (var step = 0; step < 20 && inFlight != NONE; step++) {
            served.add(inFlight);
            respondOk();
        }
        return served;
    }
}
