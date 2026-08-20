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
        Storage.deleteValue(CodeStore.PENDING_SLOTS);
        Application.Properties.setValue(CodeStore.PROP_CODES, [] as Array<Application.PropertyValueType>);
        // Most of these tests are about the download path, so they opt out of on-device
        // generation explicitly. Tests that want generation turn it back on themselves.
        Application.Properties.setValue(CodeGeneration.SETTING, false);
        Application.Properties.setValue(WideBarcode.SETTING, false);
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
        // Build the message first. Concatenating a null throws UnexpectedTypeException, which
        // would crash the test before the assertion could report the null it was checking for.
        var got = actual == null ? "null" : actual;
        Test.assertMessage(
            actual != null && actual.equals(expected),
            context + ": expected '" + expected + "' but got '" + got + "'");
    }

    //! Assert an encoding matches the reference module-for-module. Lives in this module so the
    //! test runner does not mistake a helper for a test case.
    function assertCode128(logger as Test.Logger, text as String, expected as String) as Void {
        var modules = Code128.encode(text);
        Test.assertMessage(modules != null, "'" + text + "' should be encodable");

        var actual = "";
        for (var i = 0; i < modules.size(); i++) {
            actual += modules[i] == 1 ? "1" : "0";
        }
        Test.assertEqualMessage(actual.length(), expected.length(),
            "'" + text + "': expected " + expected.length() + " modules, got " + actual.length());
        Test.assertMessage(actual.equals(expected),
            "'" + text + "' differs from the reference:\n  expected " + expected + "\n  actual   " + actual);
        logger.debug("'" + text + "' -> " + actual.length() + " modules, matches reference");
    }

    //! Assert a generated QR matrix equals the reference row for row.
    function assertQrMatches(
        logger as Test.Logger, text as String, mask as Number, expected as Array<String>
    ) as Void {
        var matrix = Qr.encodeWithMask(text, mask);
        Test.assertMessage(matrix != null, "'" + text + "' should encode");
        Test.assertEqualMessage(matrix.size, expected.size(),
            "'" + text + "': expected a " + expected.size() + " module square, got " + matrix.size);

        for (var y = 0; y < matrix.size; y++) {
            var row = "";
            for (var x = 0; x < matrix.size; x++) {
                row += matrix.get(x, y) == 1 ? "1" : "0";
            }
            Test.assertMessage(row.equals(expected[y]),
                "'" + text + "' row " + y + " differs:\n  expected " + expected[y] + "\n  actual   " + row);
        }
        logger.debug("'" + text + "' -> " + matrix.size + "x" + matrix.size + " mask " + mask + ", matches reference");
    }

    //! Recreate the storage an older release would have left behind.
    function seedLegacyInstall() as Void {
        reset();
        Storage.deleteValue(Migration.SCHEMA_KEY);

        // Codes as the old release wrote them: the type as a word, not "0"/"1".
        Storage.setValue("code_0_text", "https://example.com/pass?id=42&type=member");
        Storage.setValue("code_0_title", "Gym card");
        Storage.setValue("code_0_type", "qr");
        Storage.setValue("code_0_timestamp", 123456);

        Storage.setValue("code_1_text", "MEMBER 12345");
        Storage.setValue("code_1_title", "Loyalty");
        Storage.setValue("code_1_type", "barcode");
        Storage.setValue("code_1_timestamp", 123457);

        // A settings-editor round trip could also leave the type as a Number.
        Storage.setValue("code_2_text", "PLAIN");
        Storage.setValue("code_2_title", "Numeric type");
        Storage.setValue("code_2_type", 1);

        // Debris from the old download path.
        Storage.setValue("pendingSyncImages", [0, 1] as Array<Application.PropertyValueType>);
        Storage.setValue("lastSyncTime", 998877);
        Storage.setValue("last_error_code_0", 404);

        // `codesList` with the undeclared timestamp key that broke the settings editor, plus a
        // null hole where a code had been deleted.
        var legacy = [
            {
                "code_$index_text" => "https://example.com/pass?id=42&type=member",
                "code_$index_title" => "Gym card",
                "code_$index_type" => "qr",
                "code_$index_timestamp" => 123456
            },
            null
        ] as Array<Application.PropertyValueType>;
        Application.Properties.setValue(CodeStore.PROP_CODES, legacy);
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
