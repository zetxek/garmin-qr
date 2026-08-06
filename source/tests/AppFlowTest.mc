import Toybox.Lang;
import Toybox.Test;
import Toybox.Application;
import Toybox.Application.Storage;

//! Whole-app tests: they boot the real `AppView` inside the simulator and drive the real
//! `ImageService` queue, rather than poking modules in isolation.
//!
//! Only the radio itself is replaced (see `FakeImageService`). Everything either side of it —
//! queueing, dispatch order, callback routing, caching, recovery — is the production path.
//! This is where the "it doesn't work" defects lived, so this is where the regression tests are.

//! Booting the app dispatches the code the user is actually looking at before any prefetch.
(:test)
function appBootDispatchesTheVisibleCodeFirst(logger as Test.Logger) as Boolean {
    TestSupport.threeCodes();
    var service = TestSupport.fakeService();

    var view = new AppView();

    Test.assertEqualMessage(view.slots.size(), 3, "all three codes are listed");
    Test.assertEqualMessage(view.activeSlot(), 0, "the first code is the visible one");
    Test.assertEqualMessage(service.inFlight, 0, "the visible code is the one being fetched");
    Test.assertMessage(service.isQueued(1), "the other codes are queued behind it");
    Test.assertMessage(service.isQueued(2), "the other codes are queued behind it");
    Test.assertMessage(service.isQueued(service.GLANCE), "the glance image is queued too");
    Test.assertEqualMessage(service.requested.size(), 1, "exactly one request is outstanding");

    logger.debug("boot requested: " + service.requested[0]);
    return true;
}

//! The regression test for the defect behind most "it doesn't work" reports.
//!
//! The old code had a single `isDownloading` flag and no queue, so with three codes only one was
//! ever requested and the rest sat on "Loading image..." forever. Every response must hand off
//! to the next request.
(:test)
function everyCodeDownloadsNotJustTheFirst(logger as Test.Logger) as Boolean {
    TestSupport.threeCodes();
    var service = TestSupport.fakeService();

    new AppView();
    var served = service.drain();

    logger.debug("served in order: " + served);
    logger.debug("requested " + service.requested.size() + " urls");

    Test.assertMessage(CodeStore.isCacheValid(0), "code 1 was downloaded and cached");
    Test.assertMessage(CodeStore.isCacheValid(1), "code 2 was downloaded — not dropped behind code 1");
    Test.assertMessage(CodeStore.isCacheValid(2), "code 3 was downloaded — not dropped behind code 1");
    Test.assertMessage(CodeStore.isGlanceCacheValid(), "the glance image was downloaded");
    Test.assertEqualMessage(service.pendingCount(), 0, "nothing is left pending");
    Test.assertEqualMessage(served.size(), 4, "three codes plus the glance image");
    return true;
}

//! Each code is fetched from the endpoint its type selects, with its payload percent-encoded.
//! A barcode requested from the QR endpoint is what issue #9 reported.
(:test)
function eachCodeIsFetchedFromItsOwnEndpoint(logger as Test.Logger) as Boolean {
    TestSupport.reset();
    CodeStore.save(0, "Link", "a b&c", CodeStore.TYPE_QR);
    CodeStore.save(1, "Card", "MEMBER 1", CodeStore.TYPE_BARCODE);
    var service = TestSupport.fakeService();

    new AppView();
    service.drain();

    var qr = service.requested[0];
    var barcode = service.requested[1];
    logger.debug("qr      -> " + qr);
    logger.debug("barcode -> " + barcode);

    Test.assertMessage(qr.find("/qr?") != null, "the QR code used the qr endpoint");
    Test.assertMessage(barcode.find("/barcode?") != null, "the barcode used the barcode endpoint");
    Test.assertMessage(qr.find("a%20b%26c") != null,
        "the space and ampersand were percent-encoded, not passed through: " + qr);
    Test.assertMessage(qr.find("text=a b&c") == null, "the raw payload never reaches the URL");
    return true;
}

//! A response that never arrives must not take the rest of the queue down with it. The watchdog
//! is what makes this true; without it the in-flight flag stayed set for the whole session.
(:test)
function aLostResponseDoesNotStallTheQueue(logger as Test.Logger) as Boolean {
    TestSupport.threeCodes();
    var service = TestSupport.fakeService();

    new AppView();
    Test.assertEqualMessage(service.inFlight, 0, "code 1 is in flight");

    // The radio never calls back; the watchdog fires instead.
    service.onTimeout();

    Test.assertMessage(service.inFlight != 0, "the stalled request released the lock");
    Test.assertMessage(service.inFlight != service.NONE, "the next code started immediately");

    service.drain();

    Test.assertMessage(CodeStore.isCacheValid(1), "the codes behind the stalled one still loaded");
    Test.assertMessage(CodeStore.isCacheValid(2), "the codes behind the stalled one still loaded");
    logger.debug("recovered from a lost response; slot 0 requeued for retry");
    return true;
}

//! A response must land on the code it was requested for, even if the list was rebuilt while it
//! was in flight. The old code kept an index into the view's array, so a settings sync mid
//! download wrote the bitmap onto a different code.
(:test)
function aResponseLandsOnTheRightCodeAfterTheListChanges(logger as Test.Logger) as Boolean {
    TestSupport.threeCodes();
    var service = TestSupport.fakeService();

    var view = new AppView();
    Test.assertEqualMessage(service.inFlight, 0, "code 1 is in flight");

    // The phone pushes a settings change that removes the first code while the request is out.
    CodeStore.deleteSlot(0);
    view.onCodesChanged();

    Test.assertMessage(service.inFlight != 1 && service.inFlight != 2,
        "rebuilding the list did not repoint the in-flight request at another code");

    service.respondOk();

    Test.assertMessage(!CodeStore.isCacheValid(1),
        "the response for the deleted code did not land on code 2");
    Test.assertMessage(!CodeStore.isCacheValid(2),
        "the response for the deleted code did not land on code 3");
    logger.debug("stale response discarded instead of corrupting another code");
    return true;
}

//! A warm start must not re-fetch anything. The old cache check compared strings with `!=`,
//! which is reference equality in Monkey C and therefore always true, so every launch threw the
//! cache away and re-downloaded every code.
(:test)
function aWarmStartDownloadsNothing(logger as Test.Logger) as Boolean {
    TestSupport.threeCodes();
    var first = TestSupport.fakeService();
    new AppView();
    first.drain();

    // Restart: fresh service, fresh view, same storage.
    var restarted = TestSupport.fakeService();
    new AppView();

    Test.assertEqualMessage(restarted.inFlight, restarted.NONE, "nothing was requested on restart");
    Test.assertEqualMessage(restarted.queue.size(), 0, "nothing was queued on restart");
    Test.assertEqualMessage(restarted.requested.size(), 0, "no URL was fetched on restart");
    logger.debug("warm start issued no requests");
    return true;
}

//! Moving to a code with no image yet must put it at the front of the queue, so the user is not
//! waiting on prefetches for codes they cannot see.
(:test)
function movingToACodePrioritisesIt(logger as Test.Logger) as Boolean {
    TestSupport.threeCodes();
    var service = TestSupport.fakeService();

    var view = new AppView();
    service.respondOk();  // finish code 1, leaving codes 2, 3 and the glance queued

    view.showNext();
    var visible = view.activeSlot();

    Test.assertMessage(service.inFlight == visible || service.queue[0] == visible,
        "the code the user moved to is being fetched or is next, not stuck behind the glance");
    logger.debug("moved to slot " + visible + ", inFlight=" + service.inFlight
        + " queue=" + service.queue);
    return true;
}

//! Offline, the app shows what it has and holds the rest — it must not drop the work.
(:test)
function goingOfflineHoldsTheQueueInsteadOfLosingIt(logger as Test.Logger) as Boolean {
    TestSupport.threeCodes();
    var service = TestSupport.fakeService();

    new AppView();
    service.respondOk();  // code 1 lands before the phone goes away

    Test.assertMessage(service.pendingCount() > 0, "there is still work queued");

    // -104 is what the radio reports when the phone is not reachable.
    service.respondWith(-104);

    Test.assertMessage(service.pendingCount() > 0,
        "work queued while offline is retained, not discarded");
    Test.assertMessage(CodeStore.isCacheValid(0),
        "the code that already downloaded is still displayable offline");
    logger.debug("offline: " + service.pendingCount() + " downloads retained");
    return true;
}

//! Deleting a code and adding a new one reuses the storage slot. The old code left the previous
//! image behind, so the new code briefly displayed the deleted code's QR.
(:test)
function reusingASlotNeverShowsTheOldCode(logger as Test.Logger) as Boolean {
    TestSupport.reset();
    CodeStore.save(0, "Old", "old-payload", CodeStore.TYPE_QR);
    var service = TestSupport.fakeService();

    var view = new AppView();
    service.drain();
    Test.assertMessage(CodeStore.isCacheValid(0), "the first code has an image");

    CodeStore.deleteSlot(0);
    Test.assertEqualMessage(CodeStore.nextFreeSlot(), 0, "the slot is reused");
    CodeStore.save(0, "New", "new-payload", CodeStore.TYPE_QR);

    view.onCodesChanged();

    Test.assertMessage(view.currentImage == null,
        "the new code shows no image until its own one arrives, not the deleted code's");
    Test.assertMessage(!CodeStore.isCacheValid(0), "the stale image was not reused");
    logger.debug("slot reuse starts from a clean cache");
    return true;
}

//! `GlanceView extends WatchUi.GlanceView` shadows its own superclass name, which makes the
//! initializer call look like infinite recursion. It resolves to the superclass, and this test
//! is what keeps that true — a stack overflow here would be a blank glance on a real watch.
(:test)
function glanceViewConstructsWithoutRecursing(logger as Test.Logger) as Boolean {
    TestSupport.threeCodes();
    var view = new GlanceView();
    Test.assertMessage(view != null, "the glance view constructed");
    logger.debug("GlanceView constructed without recursing");
    return true;
}

//! With on-device generation on -- the default -- opening a code must not touch the network at
//! all. This is the whole point of generating locally: no service, no proxy, no waiting.
(:test)
function generatedCodesNeverHitTheNetwork(logger as Test.Logger) as Boolean {
    TestSupport.threeCodes();
    Application.Properties.setValue(CodeGeneration.SETTING, true);
    var service = TestSupport.fakeService();

    var view = new AppView();

    Test.assertEqualMessage(service.requested.size(), 0, "nothing was requested");
    Test.assertEqualMessage(service.pendingCount(), 0, "nothing was even queued");
    Test.assertEqualMessage(service.inFlight, service.NONE, "no request is in flight");

    // The barcode is generated inline; the QR is handed to the incremental builder.
    view.position = 1;
    view.currentSlot = -1;
    view.loadCurrent();
    Test.assertMessage(view.currentBars != null, "the barcode was generated on the spot");
    Test.assertEqualMessage(service.requested.size(), 0, "still nothing requested");

    logger.debug("on-device generation issued zero requests");
    return true;
}

//! A QR is built across timer slices, so the builder must reach a finished matrix.
(:test)
function theIncrementalBuilderFinishesAQrCode(logger as Test.Logger) as Boolean {
    var builder = new QrBuilder("https://example.com/pass?id=42&type=member");
    var steps = 0;
    while (!builder.advance() && steps < 50) { steps++; }

    Test.assertMessage(!builder.failed, "the builder did not fail");
    Test.assertMessage(builder.matrix != null, "a matrix was produced");
    Test.assertEqualMessage(builder.matrix.size, 29, "version 3 for this payload");

    // It must agree with the one-shot encoder, which the reference tests pin down.
    var direct = Qr.encode("https://example.com/pass?id=42&type=member");
    for (var y = 0; y < direct.size; y++) {
        for (var x = 0; x < direct.size; x++) {
            Test.assertEqualMessage(builder.matrix.get(x, y), direct.get(x, y),
                "module " + x + "," + y + " differs from the one-shot encoder");
        }
    }
    logger.debug("builder finished in " + steps + " slices and matches Qr.encode");
    return true;
}

// ---------------------------------------------------------------- on-watch feedback
// Three things reported from a real fenix 8, each pinned here.

//! "When adding a code it says SYNCING. Where to?"
//!
//! Saving a code queued a download even though the code is generated locally, so the banner
//! claimed to be syncing and the request then failed with the proxy's 404.
(:test)
function addingACodeDoesNotStartADownload(logger as Test.Logger) as Boolean {
    TestSupport.reset();
    Application.Properties.setValue(CodeGeneration.SETTING, true);
    var service = TestSupport.fakeService();

    var menu = new AddCodeMenu(new AppView());
    menu.codeTitle = "Gym";
    menu.codeText = "MEMBER 12345";
    menu.codeType = CodeStore.TYPE_BARCODE;
    menu.save();

    Test.assertEqualMessage(CodeStore.count(), 1, "the code was saved");
    Test.assertEqualMessage(service.requested.size(), 0, "saving requested nothing");
    Test.assertEqualMessage(service.pendingCount(), 0, "and queued nothing, so no SYNCING banner");
    logger.debug("saving a code stays entirely local");
    return true;
}

//! "I go to the glance and see 'failed to load code' / 'open to load code'."
//!
//! The glance only ever read downloaded images, so with generation on it had nothing to show and
//! fell through to an error. It now draws what the app cached.
(:test)
function theGlanceDrawsGeneratedCodes(logger as Test.Logger) as Boolean {
    TestSupport.reset();
    Application.Properties.setValue(CodeGeneration.SETTING, true);
    CodeStore.save(0, "Gym card", "MEMBER 12345", CodeStore.TYPE_BARCODE);

    Test.assertMessage(CodeStore.cachedBars(0) == null, "nothing cached before the app runs");

    TestSupport.fakeService();
    new AppView();   // opening the code generates and caches it

    Test.assertMessage(CodeStore.cachedBars(0) != null,
        "the app cached the generated barcode for the glance to draw");
    Test.assertMessage(CodeStore.isGeneratedValid(0), "and the cache is valid for this slot");
    logger.debug("glance has a generated code to draw without any download");
    return true;
}

//! "There is an intermediate screen that shouldn't be there."
//!
//! A QR is built across timer slices, so the first open shows a brief 'generating' state. Once
//! cached it must be drawn on the very first frame, with no intermediate state at all.
(:test)
function aCachedCodeIsDrawnOnTheFirstFrame(logger as Test.Logger) as Boolean {
    TestSupport.reset();
    Application.Properties.setValue(CodeGeneration.SETTING, true);
    CodeStore.save(0, "Pass", "https://example.com/pass?id=42&type=member", CodeStore.TYPE_QR);

    // Generate it the way the app does, then cache it.
    var builder = new QrBuilder("https://example.com/pass?id=42&type=member");
    for (var i = 0; i < 50 && !builder.advance(); i++) {}
    CodeStore.putMatrix(0, builder.matrix as QrMatrix);

    TestSupport.fakeService();
    var view = new AppView();

    Test.assertMessage(view.currentMatrix != null,
        "the cached matrix is loaded immediately, not built again");
    Test.assertMessage(view.hasSomethingToDraw(), "so the first frame has a code to draw");
    Test.assertEqualMessage(view.currentMatrix.size, 29, "and it is the right symbol");
    logger.debug("a cached code needs no intermediate screen");
    return true;
}

//! Changing a code must invalidate what was generated from the old text, or the watch would show
//! the previous code.
(:test)
function editingACodeDropsTheGeneratedCache(logger as Test.Logger) as Boolean {
    TestSupport.reset();
    Application.Properties.setValue(CodeGeneration.SETTING, true);
    CodeStore.save(0, "One", "FIRST", CodeStore.TYPE_BARCODE);

    TestSupport.fakeService();
    new AppView();
    Test.assertMessage(CodeStore.cachedBars(0) != null, "precondition: generated and cached");

    CodeStore.save(0, "One", "SECOND", CodeStore.TYPE_BARCODE);
    Test.assertMessage(CodeStore.cachedBars(0) == null, "the old barcode was dropped");
    Test.assertMessage(!CodeStore.isGeneratedValid(0), "and the cache reads as stale");
    logger.debug("editing a code invalidates what was generated from it");
    return true;
}

//! "I leave the glance, go back, and it says 'open to load code' again."
//!
//! The glance can only draw what is already cached, and only the visible code was ever built.
//! Opening the app must also prepare the code the glance shows, even when that is a different
//! slot from the one on screen.
(:test)
function openingTheAppPreparesTheGlanceCode(logger as Test.Logger) as Boolean {
    TestSupport.reset();
    Application.Properties.setValue(CodeGeneration.SETTING, true);
    CodeStore.save(0, "Gym card", "MEMBER 12345", CodeStore.TYPE_BARCODE);
    CodeStore.save(1, "Second", "ANOTHER", CodeStore.TYPE_BARCODE);
    TestSupport.fakeService();

    var view = new AppView();
    view.showNext();          // look at slot 1, not the one the glance draws
    Test.assertEqualMessage(view.activeSlot(), 1, "the second code is on screen");

    Test.assertMessage(CodeStore.isGeneratedValid(0),
        "the glance's code (slot 0) was prepared even though slot 1 is on screen");
    Test.assertMessage(CodeStore.cachedBars(0) != null, "and the glance can read it back");
    logger.debug("glance code prepared regardless of which code is on screen");
    return true;
}

//! Opening the app must not switch the backlight off.
//!
//! `applyScreenTimeout` runs on every show, and with "keep screen on" off it called
//! `Backlight.disable()`. That did not just release a hold, it drove `Attention.backlight(false)`
//! and blacked out the display as soon as the app opened.
(:test)
function openingTheAppDoesNotDarkenTheScreen(logger as Test.Logger) as Boolean {
    var backlight = new Backlight();

    // Never enabled, so there is no hold to release and nothing to switch off.
    backlight.disable();
    Test.assertMessage(!backlight.isHolding(), "not holding the backlight after a bare disable");

    // A hold that was actually taken is still released.
    backlight.enable();
    if (Backlight.isSupported()) {
        Test.assertMessage(backlight.isHolding(), "enable() takes the hold");
    }
    backlight.disable();
    Test.assertMessage(!backlight.isHolding(), "disable() releases it again");
    logger.debug("backlight is only switched off when it was switched on");
    return true;
}

//! The user's choice of screen behaviour is honoured in both directions.
//!
//! The shipped default is `true`, set on the `keepScreenOn` property in
//! resources/drawables/properties.xml -- a code that dims while you hold your wrist up to a
//! scanner is not much use. That default cannot be asserted here: the simulator persists
//! properties between runs, so "nothing stored yet" is not a reachable state in a test.
(:test)
function theScreenSettingIsHonoured(logger as Test.Logger) as Boolean {
    TestSupport.reset();
    var app = Application.getApp();

    Application.Properties.setValue("keepScreenOn", false);
    app.loadSettings();
    Test.assertMessage(!app.keepScreenOn, "an explicit off is honoured");

    Application.Properties.setValue("keepScreenOn", true);
    app.loadSettings();
    Test.assertMessage(app.keepScreenOn, "and an explicit on");
    logger.debug("screen-on setting round-trips in both directions");
    return true;
}

//! While the watch is building a code it must not claim to be loading one.
//!
//! Nothing is fetched when codes are generated on the device, so "Loading code..." described
//! work that was not happening. The download wording still applies when the service is the
//! source.
(:test)
function theWaitMessageSaysWhatIsActuallyHappening(logger as Test.Logger) as Boolean {
    TestSupport.reset();
    Application.Properties.setValue(CodeGeneration.SETTING, true);
    CodeStore.save(0, "Pass", "https://example.com/pass?id=42&type=member", CodeStore.TYPE_QR);
    TestSupport.fakeService();

    var view = new AppView();
    Test.assertEqualMessage(view.placeholderMessage(), "Generating code...",
        "the watch says it is generating, not loading");

    // With generation off the service is the source again, and so is its wording.
    Application.Properties.setValue(CodeGeneration.SETTING, false);
    Test.assertEqualMessage(view.placeholderMessage(), "Loading code...",
        "the download path still says loading");
    logger.debug("wait message matches where the code is coming from");
    return true;
}
