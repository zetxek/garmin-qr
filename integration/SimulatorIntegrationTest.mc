import Toybox.Lang;
import Toybox.Test;
import Toybox.System;
import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.WatchUi;

//! End-to-end check that runs inside the Connect IQ simulator, driven by
//! `scripts/simulator-test.sh` in three steps:
//!
//!   1. `integrationSeed`   — writes two codes and clears their image cache.
//!   2. the real app runs   — reconciles settings, drains the download queue, makes live HTTP
//!                            requests to the code service and caches what comes back.
//!   3. `integrationVerify` — asserts the images really arrived and are attributed to the right
//!                            codes.
//!
//! The unit suite cannot cover this: `makeImageRequest` only completes on the event loop, which
//! a synchronous test function never reaches. Splitting it across three simulator invocations —
//! simulator storage persists between them — exercises the queue, the URL, the callback routing
//! and the cache the way a watch does.
//!
//! These live in `integration/`, which only `monkey-integration.jungle` compiles, so they never
//! run as part of the normal unit suite.

const SEED_QR_TEXT = "https://example.com/pass?id=42&type=member";  // the `&` is the point
const SEED_QR_TITLE = "Ampersand QR";
const SEED_BARCODE_TEXT = "MEMBER 12345";                          // the space is the point
const SEED_BARCODE_TITLE = "Gym card";

(:test)
function integrationSeed(logger as Test.Logger) as Boolean {
    for (var slot = 0; slot < CodeStore.MAX_CODES; slot++) {
        CodeStore.deleteSlot(slot);
    }
    Storage.deleteValue("pendingImageSlots");
    Storage.deleteValue(CodeStore.GLANCE_IMAGE);
    Application.Properties.setValue(
        CodeStore.PROP_CODES, [] as Array<Application.PropertyValueType>);
    // Match a real install. The simulator persists properties between runs, so without this the
    // fixture inherits whatever the last unit-test run left behind -- and the unit tests turn
    // generation off, which quietly puts the app back on the dead download path.
    Application.Properties.setValue(CodeGeneration.SETTING, true);

    CodeStore.save(0, $.SEED_QR_TITLE, $.SEED_QR_TEXT, CodeStore.TYPE_QR);
    CodeStore.save(1, $.SEED_BARCODE_TITLE, $.SEED_BARCODE_TEXT, CodeStore.TYPE_BARCODE);
    CodeStore.publishProperties();

    Test.assertEqualMessage(CodeStore.count(), 2, "two codes seeded");
    Test.assertMessage(!CodeStore.isCacheValid(0), "slot 0 starts with no image");
    Test.assertMessage(!CodeStore.isCacheValid(1), "slot 1 starts with no image");
    Test.assertMessage(CodeGeneration.enabled(), "codes are generated on the watch, as shipped");

    logger.debug("SEEDED 2 codes, no cached images");
    return true;
}

(:test)
function integrationVerify(logger as Test.Logger) as Boolean {
    // Both codes downloaded, not just the first one. Before the queue existed, a single
    // in-flight flag meant every code after the first was silently dropped.
    Test.assertMessage(CodeStore.isCacheValid(0),
        "slot 0 has no valid cached image after running the app — the download never completed");
    Test.assertMessage(CodeStore.isCacheValid(1),
        "slot 1 has no valid cached image after running the app — only the first code loaded");

    // The image is attributed to the code it was generated from, so a response cannot have
    // landed on the wrong slot.
    var meta0 = Storage.getValue(CodeStore.metaTextKey(0));
    var meta1 = Storage.getValue(CodeStore.metaTextKey(1));
    // Assert presence first: calling equals on a missing key throws, and the test then reports
    // an exception rather than the failure it was written to describe.
    Test.assertMessage(meta0 instanceof String && meta1 instanceof String,
        "both slots must have cached image metadata");
    Test.assertMessage(meta0.equals($.SEED_QR_TEXT), "slot 0 image is attributed to slot 0's text");
    Test.assertMessage(meta1.equals($.SEED_BARCODE_TEXT), "slot 1 image is attributed to slot 1's text");

    var type0 = Storage.getValue(CodeStore.metaTypeKey(0)) as String;
    var type1 = Storage.getValue(CodeStore.metaTypeKey(1)) as String;
    Test.assertMessage(type0.equals(CodeStore.TYPE_QR), "slot 0 was fetched as a QR code");
    Test.assertMessage(type1.equals(CodeStore.TYPE_BARCODE), "slot 1 was fetched as a barcode");

    // A QR is square; a rectangular barcode is not. This is what actually proves the barcode
    // endpoint was used — the bug where a barcode rendered as a QR code would fail here.
    var qr = CodeStore.cachedImage(0);
    var barcode = CodeStore.cachedImage(1);
    Test.assertMessage(qr != null && barcode != null, "both bitmaps load back out of storage");

    logger.debug("QR      " + qr.getWidth() + "x" + qr.getHeight());
    logger.debug("BARCODE " + barcode.getWidth() + "x" + barcode.getHeight());

    Test.assertMessage(qr.getWidth() > 0 && qr.getHeight() > 0, "the QR bitmap has real pixels");
    Test.assertMessage(
        qr.getWidth() == qr.getHeight(),
        "a QR code should come back square, got " + qr.getWidth() + "x" + qr.getHeight());
    Test.assertMessage(
        barcode.getWidth() > barcode.getHeight(),
        "a barcode should come back wider than it is tall, got "
            + barcode.getWidth() + "x" + barcode.getHeight());

    // The glance draws from its own smaller image; it should have been fetched too.
    Test.assertMessage(CodeStore.isGlanceCacheValid(), "the glance image was fetched and cached");

    logger.debug("VERIFIED both codes downloaded, cached and correctly attributed");
    return true;
}

//! Re-running the app must not re-download anything. This is the check for the defect that made
//! every load discard the cache: run the app a second time and the queue should stay empty.
(:test)
function integrationVerifyNoRedownload(logger as Test.Logger) as Boolean {
    Test.assertMessage(CodeStore.isCacheValid(0), "precondition: slot 0 is cached");
    Test.assertMessage(CodeStore.isCacheValid(1), "precondition: slot 1 is cached");

    var service = ImageService.get();
    service.enqueueAll();

    Test.assertEqualMessage(service.queue.size(), 0,
        "nothing should be queued when every code already has a valid cached image");

    logger.debug("VERIFIED warm start queues no downloads");
    return true;
}

//! Diagnostic, not an assertion. Run it on its own when the end-to-end check fails, to see what
//! the app actually left behind:
//!
//!     monkeydo bin/integration.prg fenix7pro -t integrationDump
//!
//! A `lastError` of -101 means the simulator's phone data channel is not carrying traffic, so
//! no request could have succeeded regardless of the app.
(:test)
function integrationDump(logger as Test.Logger) as Boolean {
    logger.debug("count=" + CodeStore.count());
    for (var i = 0; i < 3; i++) {
        logger.debug("slot " + i
            + " text=" + CodeStore.getText(i)
            + " type=" + CodeStore.getType(i)
            + " cacheValid=" + CodeStore.isCacheValid(i)
            + " img=" + (Storage.getValue(CodeStore.imageKey(i)) != null)
            + " metaText=" + Storage.getValue(CodeStore.metaTextKey(i)));
    }
    logger.debug("persistedQueue=" + Storage.getValue("pendingImageSlots"));
    for (var i = 0; i < 3; i++) {
        logger.debug("slot " + i + " lastError=" + Storage.getValue(ImageService.errorKey(i)));
    }
    logger.debug("glanceError=" + Storage.getValue(ImageService.errorKey(-2)));
    logger.debug("glanceValid=" + CodeStore.isGlanceCacheValid());
    logger.debug("phoneConnected=" + System.getDeviceSettings().phoneConnected);
    return true;
}

//! Seeds two codes *with* cached images so the app renders immediately and makes no network
//! request at all. Used for visual checks of the draw path in the simulator, and it doubles as a
//! demonstration of the cache fix: a warm start shows codes with the radio never touched.
//!
//!     monkeydo bin/integration.prg fenix7pro -t integrationSeedRendered
(:test)
function integrationSeedRendered(logger as Test.Logger) as Boolean {
    for (var slot = 0; slot < CodeStore.MAX_CODES; slot++) {
        CodeStore.deleteSlot(slot);
    }
    Storage.deleteValue("pendingImageSlots");

    CodeStore.save(0, "Gym card", $.SEED_QR_TEXT, CodeStore.TYPE_QR);
    CodeStore.save(1, "Loyalty", $.SEED_BARCODE_TEXT, CodeStore.TYPE_BARCODE);

    var bitmap = WatchUi.loadResource(Rez.Drawables.LauncherIcon) as WatchUi.BitmapResource;
    CodeStore.putImage(0, bitmap);
    CodeStore.putImage(1, bitmap);
    CodeStore.putGlanceImage(bitmap);

    Test.assertMessage(CodeStore.isCacheValid(0), "slot 0 is cached");
    Test.assertMessage(CodeStore.isCacheValid(1), "slot 1 is cached");
    Test.assertMessage(CodeStore.isGlanceCacheValid(), "the glance is cached");

    logger.debug("SEEDED 2 codes with cached images; the app should need no network");
    return true;
}
