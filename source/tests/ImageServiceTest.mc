import Toybox.Lang;
import Toybox.Test;
import Toybox.Application;

// ------------------------------------------------------------------ URL building

//! Regression test for issue #31: a URL pasted into the settings was cut off at its first `&`
//! because the payload went into the query string unencoded.
(:test)
function ampersandInTextIsEncoded(logger as Test.Logger) as Boolean {
    var url = ImageService.buildUrl("http://abc.com?a=1&b=2", CodeStore.TYPE_QR, 300);
    logger.debug(url);

    Test.assertMessage(url.find("%26") != null, "the ampersand must be percent-encoded");
    Test.assertMessage(url.find("text=http://abc.com?a=1&b=2") == null,
        "the raw payload must not appear in the query string");
    // The only `&` left is the separator introducing the `size` parameter.
    Test.assertMessage(url.find("&size=") != null, "size must still be a separate parameter");
    return true;
}

(:test)
function reservedCharactersAreEncoded(logger as Test.Logger) as Boolean {
    var url = ImageService.buildUrl("a b+c#d%e=f", CodeStore.TYPE_QR, 200);
    logger.debug(url);

    Test.assertMessage(url.find(" ") == null, "spaces must be encoded");
    Test.assertMessage(url.find("#") == null, "fragments must be encoded");
    Test.assertMessage(url.find("%2B") != null, "plus must be encoded, not read as a space");
    return true;
}

(:test)
function barcodeAndQrUseDifferentEndpoints(logger as Test.Logger) as Boolean {
    var qr = ImageService.buildUrl("hello", CodeStore.TYPE_QR, 250);
    var barcode = ImageService.buildUrl("hello", CodeStore.TYPE_BARCODE, 250);

    Test.assertMessage(qr.find("/qr?") != null, "QR endpoint");
    Test.assertMessage(barcode.find("/barcode?") != null, "barcode endpoint");
    Test.assertMessage(barcode.find("shape=rectangle") != null, "barcodes are rendered as rectangles");
    return true;
}

// ------------------------------------------------------------------ queue behaviour

(:test)
function queueDeduplicates(logger as Test.Logger) as Boolean {
    TestSupport.reset();
    CodeStore.save(0, "A", "aaa", CodeStore.TYPE_QR);

    var service = ImageService.get();
    service.enqueue(0);
    service.enqueue(0);
    service.enqueue(0);

    Test.assertEqualMessage(service.queue.size(), 1, "the same slot is only queued once");
    return true;
}

(:test)
function cachedSlotsAreNotQueued(logger as Test.Logger) as Boolean {
    TestSupport.reset();
    CodeStore.save(0, "A", "aaa", CodeStore.TYPE_QR);
    CodeStore.putImage(0, TestSupport.sampleBitmap());

    var service = ImageService.get();
    service.enqueue(0);

    Test.assertEqualMessage(service.queue.size(), 0, "a slot with a valid cached image needs no download");
    return true;
}

//! The code on screen must not sit behind prefetches for codes the user cannot see.
(:test)
function visibleSlotJumpsTheQueue(logger as Test.Logger) as Boolean {
    TestSupport.reset();
    CodeStore.save(0, "A", "aaa", CodeStore.TYPE_QR);
    CodeStore.save(1, "B", "bbb", CodeStore.TYPE_QR);
    CodeStore.save(2, "C", "ccc", CodeStore.TYPE_QR);

    var service = ImageService.get();
    service.enqueue(0);
    service.enqueue(1);
    service.enqueue(2);
    service.enqueueFirst(2);

    Test.assertEqualMessage(service.queue[0], 2, "the visible slot moves to the head");
    Test.assertEqualMessage(service.queue.size(), 3, "and is not duplicated");
    return true;
}

(:test)
function forgettingASlotClearsItFromTheQueue(logger as Test.Logger) as Boolean {
    TestSupport.reset();
    CodeStore.save(0, "A", "aaa", CodeStore.TYPE_QR);
    CodeStore.save(1, "B", "bbb", CodeStore.TYPE_QR);

    var service = ImageService.get();
    service.enqueue(0);
    service.enqueue(1);
    service.forget(0);

    Test.assertEqualMessage(service.queue.size(), 1, "the forgotten slot is dropped");
    Test.assertEqualMessage(service.queue[0], 1, "the other slot is untouched");
    return true;
}

//! The queue is what makes offline codes load later, so it has to outlive a restart.
(:test)
function queueSurvivesARestart(logger as Test.Logger) as Boolean {
    TestSupport.reset();
    CodeStore.save(0, "A", "aaa", CodeStore.TYPE_QR);
    CodeStore.save(1, "B", "bbb", CodeStore.TYPE_QR);

    ImageService.get().enqueue(0);
    ImageService.get().enqueue(1);

    ImageService.instance = null; // simulate the app being closed and reopened
    var restored = ImageService.get();

    Test.assertEqualMessage(restored.queue.size(), 2, "queued downloads are restored from storage");
    return true;
}

(:test)
function restoredQueueDropsSlotsThatNoLongerNeedDownloading(logger as Test.Logger) as Boolean {
    TestSupport.reset();
    CodeStore.save(0, "A", "aaa", CodeStore.TYPE_QR);
    CodeStore.save(1, "B", "bbb", CodeStore.TYPE_QR);
    ImageService.get().enqueue(0);
    ImageService.get().enqueue(1);

    CodeStore.deleteSlot(1);
    CodeStore.putImage(0, TestSupport.sampleBitmap());

    ImageService.instance = null;
    var restored = ImageService.get();

    Test.assertEqualMessage(restored.queue.size(), 0,
        "a deleted code and an already-cached code are both dropped on restore");
    return true;
}

// ------------------------------------------------------------------ failure handling

(:test)
function clientErrorsAreNotRetried(logger as Test.Logger) as Boolean {
    TestSupport.reset();
    CodeStore.save(0, "A", "aaa", CodeStore.TYPE_QR);

    var service = ImageService.get();
    service.recordFailure(0, 400);

    Test.assertMessage(service.isPermanentlyFailed(0), "a 4xx means the payload itself is wrong");
    Test.assertEqualMessage(service.queue.size(), 0, "and it is not queued for another attempt");
    Test.assertMessage(service.stateFor(0) == :failed, "the view is told it failed for good");
    return true;
}

(:test)
function transientErrorsAreRequeued(logger as Test.Logger) as Boolean {
    TestSupport.reset();
    CodeStore.save(0, "A", "aaa", CodeStore.TYPE_QR);

    var service = ImageService.get();
    service.recordFailure(0, 500);

    Test.assertMessage(!service.isPermanentlyFailed(0), "a server error is worth retrying");
    Test.assertEqualMessage(service.queue.size(), 1, "and the slot goes back in the queue");
    return true;
}

(:test)
function repeatedFailuresEventuallyGiveUp(logger as Test.Logger) as Boolean {
    TestSupport.reset();
    CodeStore.save(0, "A", "aaa", CodeStore.TYPE_QR);

    var service = ImageService.get();
    for (var i = 0; i < service.MAX_ATTEMPTS; i++) {
        service.recordFailure(0, 500);
    }

    Test.assertMessage(service.isPermanentlyFailed(0),
        "after MAX_ATTEMPTS the app stops hammering the service");
    return true;
}

(:test)
function backoffGrowsAndIsCapped(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(ImageService.backoffFor(1), 5000, "first retry");
    Test.assertEqualMessage(ImageService.backoffFor(2), 10000, "second retry");
    Test.assertEqualMessage(ImageService.backoffFor(3), 20000, "third retry");
    Test.assertEqualMessage(ImageService.backoffFor(10), 60000, "capped at a minute");
    return true;
}

(:test)
function permanentFailuresAreNeverSentAgain(logger as Test.Logger) as Boolean {
    TestSupport.reset();
    CodeStore.save(0, "A", "aaa", CodeStore.TYPE_QR);

    var service = ImageService.get();
    service.enqueue(0);
    service.recordFailure(0, 404);
    service.pump();

    Test.assertMessage(service.inFlight == service.NONE, "nothing should be in flight");
    Test.assertEqualMessage(service.queue.size(), 0, "and it is dropped from the queue");
    Test.assertEqualMessage(service.pendingCount(), 0, "so the syncing indicator clears");
    return true;
}

// ------------------------------------------------------------------ in-flight bookkeeping

//! The response used to be applied to `images[downloadingImageIdx]`, an index into an array
//! that any reload rebuilt — so a download could land on the wrong code. The in-flight identity
//! is now the storage slot, which is stable.
(:test)
function inFlightIsReleasedOnTimeout(logger as Test.Logger) as Boolean {
    TestSupport.reset();
    CodeStore.save(0, "A", "aaa", CodeStore.TYPE_QR);

    var service = ImageService.get();
    service.inFlight = 0;
    service.onTimeout();

    Test.assertMessage(service.inFlight == service.NONE,
        "a request that never called back must not hold the queue forever");
    Test.assertEqualMessage(service.queue.size(), 1, "the slot is queued for another attempt");
    return true;
}

(:test)
function pendingCountIncludesTheRequestInFlight(logger as Test.Logger) as Boolean {
    TestSupport.reset();
    CodeStore.save(0, "A", "aaa", CodeStore.TYPE_QR);
    CodeStore.save(1, "B", "bbb", CodeStore.TYPE_QR);

    var service = ImageService.get();
    service.enqueue(1);
    service.inFlight = 0;

    Test.assertEqualMessage(service.pendingCount(), 2, "one queued plus one in flight");
    return true;
}
