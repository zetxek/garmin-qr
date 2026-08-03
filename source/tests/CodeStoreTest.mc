import Toybox.Lang;
import Toybox.Test;
import Toybox.Application;
import Toybox.Application.Storage;

// ------------------------------------------------------------------ type normalisation

(:test)
function typeFromSettingsStringIsNormalised(logger as Test.Logger) as Boolean {
    TestSupport.assertStringEquals(CodeStore.normaliseType("0"), CodeStore.TYPE_QR, "\"0\"");
    TestSupport.assertStringEquals(CodeStore.normaliseType("1"), CodeStore.TYPE_BARCODE, "\"1\"");
    return true;
}

//! The settings editor can hand the list value back as a Number, and `Number.equals("1")` is
//! false — which is why a code saved as a barcode used to render as a QR code.
(:test)
function typeFromSettingsNumberIsNormalised(logger as Test.Logger) as Boolean {
    TestSupport.assertStringEquals(CodeStore.normaliseType(0), CodeStore.TYPE_QR, "Number 0");
    TestSupport.assertStringEquals(CodeStore.normaliseType(1), CodeStore.TYPE_BARCODE, "Number 1");
    return true;
}

(:test)
function typeFromLegacyWordsIsNormalised(logger as Test.Logger) as Boolean {
    TestSupport.assertStringEquals(CodeStore.normaliseType("barcode"), CodeStore.TYPE_BARCODE, "\"barcode\"");
    TestSupport.assertStringEquals(CodeStore.normaliseType("qr"), CodeStore.TYPE_QR, "\"qr\"");
    return true;
}

(:test)
function typeFromGarbageFallsBackToQr(logger as Test.Logger) as Boolean {
    TestSupport.assertStringEquals(CodeStore.normaliseType(null), CodeStore.TYPE_QR, "null");
    TestSupport.assertStringEquals(CodeStore.normaliseType("nonsense"), CodeStore.TYPE_QR, "garbage");
    return true;
}

// ------------------------------------------------------------------ cache invalidation

//! Regression test for the defect behind "codes never load".
//!
//! Cache validity used to be decided with `text != cachedText`. `!=` on Monkey C Strings is
//! reference inequality, so it was always true: every load discarded the whole image cache and
//! queued a fresh download for every code. This asserts that an unchanged code keeps its image.
(:test)
function cacheStaysValidWhenNothingChanged(logger as Test.Logger) as Boolean {
    TestSupport.reset();
    CodeStore.save(0, "Gym", "MEMBER-12345", CodeStore.TYPE_BARCODE);
    CodeStore.putImage(0, TestSupport.sampleBitmap());

    Test.assertMessage(CodeStore.isCacheValid(0), "cache should still be valid after a no-op reload");
    Test.assertMessage(CodeStore.cachedImage(0) != null, "cached image should be returned");
    return true;
}

(:test)
function cacheIsInvalidatedWhenTextChanges(logger as Test.Logger) as Boolean {
    TestSupport.reset();
    CodeStore.save(0, "Gym", "MEMBER-12345", CodeStore.TYPE_QR);
    CodeStore.putImage(0, TestSupport.sampleBitmap());
    Test.assertMessage(CodeStore.isCacheValid(0), "precondition: cache is valid");

    CodeStore.save(0, "Gym", "MEMBER-99999", CodeStore.TYPE_QR);

    Test.assertMessage(!CodeStore.isCacheValid(0), "changing the text must invalidate the image");
    Test.assertMessage(CodeStore.cachedImage(0) == null, "stale image must not be served");
    return true;
}

(:test)
function cacheIsInvalidatedWhenTypeChanges(logger as Test.Logger) as Boolean {
    TestSupport.reset();
    CodeStore.save(0, "Gym", "MEMBER-12345", CodeStore.TYPE_QR);
    CodeStore.putImage(0, TestSupport.sampleBitmap());

    CodeStore.save(0, "Gym", "MEMBER-12345", CodeStore.TYPE_BARCODE);

    Test.assertMessage(!CodeStore.isCacheValid(0), "switching QR -> barcode must refetch the image");
    return true;
}

(:test)
function changingTitleKeepsTheCachedImage(logger as Test.Logger) as Boolean {
    TestSupport.reset();
    CodeStore.save(0, "Gym", "MEMBER-12345", CodeStore.TYPE_QR);
    CodeStore.putImage(0, TestSupport.sampleBitmap());

    CodeStore.save(0, "Fitness club", "MEMBER-12345", CodeStore.TYPE_QR);

    Test.assertMessage(CodeStore.isCacheValid(0), "the title is not encoded, so the image still applies");
    return true;
}

// ------------------------------------------------------------------ slot lifecycle

//! Deleting used to leave `qr_image_N` behind, so the next code added reused slot N and came up
//! showing the deleted code's image.
(:test)
function deletingASlotAlsoDropsItsImage(logger as Test.Logger) as Boolean {
    TestSupport.reset();
    CodeStore.save(0, "Gym", "MEMBER-12345", CodeStore.TYPE_QR);
    CodeStore.putImage(0, TestSupport.sampleBitmap());

    CodeStore.deleteSlot(0);
    Test.assertMessage(Storage.getValue(CodeStore.imageKey(0)) == null, "cached image must be deleted too");

    CodeStore.save(0, "Library", "CARD-77", CodeStore.TYPE_QR);
    Test.assertMessage(!CodeStore.isCacheValid(0), "a reused slot must not inherit the old image");
    Test.assertMessage(CodeStore.cachedImage(0) == null, "a reused slot must not serve the old image");
    return true;
}

(:test)
function occupiedSlotsSkipsHoles(logger as Test.Logger) as Boolean {
    TestSupport.reset();
    CodeStore.save(0, "A", "aaa", CodeStore.TYPE_QR);
    CodeStore.save(1, "B", "bbb", CodeStore.TYPE_QR);
    CodeStore.save(2, "C", "ccc", CodeStore.TYPE_QR);
    CodeStore.deleteSlot(1);

    var slots = CodeStore.occupiedSlots();
    Test.assertEqualMessage(slots.size(), 2, "two codes should remain");
    Test.assertEqualMessage(slots[0], 0, "first remaining slot");
    Test.assertEqualMessage(slots[1], 2, "hole at 1 should be skipped");
    Test.assertEqualMessage(CodeStore.nextFreeSlot(), 1, "the hole should be reused first");
    Test.assertEqualMessage(CodeStore.firstSlot(), 0, "glance shows the first code");
    return true;
}

(:test)
function emptyTextIsNotSaved(logger as Test.Logger) as Boolean {
    TestSupport.reset();
    CodeStore.save(0, "Nothing", "", CodeStore.TYPE_QR);
    Test.assertMessage(CodeStore.getText(0) == null, "an empty code is not a code");
    Test.assertEqualMessage(CodeStore.count(), 0, "nothing should have been stored");
    return true;
}

// ------------------------------------------------------------------ settings editor

//! Regression test for issue #30. Writing anything the settings schema does not declare — the
//! app used to add `code_$index_timestamp` on every startup — makes the phone-side editor fail
//! to save.
(:test)
function publishedEntriesOnlyContainDeclaredKeys(logger as Test.Logger) as Boolean {
    TestSupport.reset();
    CodeStore.save(0, "Gym", "MEMBER-12345", CodeStore.TYPE_BARCODE);
    CodeStore.publishProperties();

    var raw = Application.Properties.getValue(CodeStore.PROP_CODES) as Array;
    Test.assertEqualMessage(raw.size(), 1, "one code published");

    var entry = raw[0] as Dictionary;
    Test.assertEqualMessage(entry.keys().size(), 3, "exactly the three declared keys");
    Test.assertMessage(entry.hasKey(CodeStore.PROP_TEXT), "text key present");
    Test.assertMessage(entry.hasKey(CodeStore.PROP_TITLE), "title key present");
    Test.assertMessage(entry.hasKey(CodeStore.PROP_TYPE), "type key present");
    Test.assertMessage(!entry.hasKey("code_$index_timestamp"), "no undeclared timestamp key");
    return true;
}

//! Older releases wrote a literal `null` into the array when a code was deleted, which the
//! settings editor cannot parse.
(:test)
function publishedListIsCompactedWithoutNullHoles(logger as Test.Logger) as Boolean {
    TestSupport.reset();
    CodeStore.save(0, "A", "aaa", CodeStore.TYPE_QR);
    CodeStore.save(1, "B", "bbb", CodeStore.TYPE_QR);
    CodeStore.save(2, "C", "ccc", CodeStore.TYPE_QR);
    CodeStore.deleteSlot(1);
    CodeStore.publishProperties();

    var raw = Application.Properties.getValue(CodeStore.PROP_CODES) as Array;
    Test.assertEqualMessage(raw.size(), 2, "the deleted entry is removed, not nulled");
    for (var i = 0; i < raw.size(); i++) {
        Test.assertMessage(raw[i] instanceof Dictionary ? true : false, "no null entries");
    }
    return true;
}

(:test)
function publishSkipsTheWriteWhenNothingChanged(logger as Test.Logger) as Boolean {
    TestSupport.reset();
    CodeStore.save(0, "Gym", "MEMBER-12345", CodeStore.TYPE_QR);
    CodeStore.publishProperties();

    var list = [] as Array<Dictionary>;
    var entry = {};
    entry.put(CodeStore.PROP_TYPE, CodeStore.TYPE_QR);
    entry.put(CodeStore.PROP_TITLE, "Gym");
    entry.put(CodeStore.PROP_TEXT, "MEMBER-12345");
    list.add(entry);

    Test.assertMessage(CodeStore.propertiesMatch(list), "an identical list should be recognised as a no-op");
    return true;
}

(:test)
function adoptingSettingsOverwritesStorage(logger as Test.Logger) as Boolean {
    TestSupport.reset();
    CodeStore.save(0, "Old", "old-value", CodeStore.TYPE_QR);
    CodeStore.putImage(0, TestSupport.sampleBitmap());

    var list = [] as Array<Dictionary>;
    var entry = {};
    entry.put(CodeStore.PROP_TYPE, 1); // as a Number, the way the editor may send it
    entry.put(CodeStore.PROP_TITLE, "New");
    entry.put(CodeStore.PROP_TEXT, "new-value");
    list.add(entry);
    Application.Properties.setValue(CodeStore.PROP_CODES, list as Application.PropertyValueType);

    Test.assertMessage(CodeStore.adoptProperties(), "adopting a different code reports a change");
    TestSupport.assertStringEquals(CodeStore.getText(0), "new-value", "text");
    TestSupport.assertStringEquals(CodeStore.getTitle(0), "New", "title");
    TestSupport.assertStringEquals(CodeStore.getType(0), CodeStore.TYPE_BARCODE, "type");
    Test.assertMessage(!CodeStore.isCacheValid(0), "the old image must not survive");
    return true;
}

//! Editing one code should not cost every other code its image — offline, that used to leave
//! the user with nothing at all.
(:test)
function adoptingSettingsKeepsUnchangedImages(logger as Test.Logger) as Boolean {
    TestSupport.reset();
    CodeStore.save(0, "A", "aaa", CodeStore.TYPE_QR);
    CodeStore.save(1, "B", "bbb", CodeStore.TYPE_QR);
    CodeStore.putImage(0, TestSupport.sampleBitmap());
    CodeStore.putImage(1, TestSupport.sampleBitmap());
    CodeStore.publishProperties();

    // The phone edits only the second code.
    var list = CodeStore.readProperties();
    (list[1] as Dictionary).put(CodeStore.PROP_TEXT, "bbb-edited");
    Application.Properties.setValue(CodeStore.PROP_CODES, list as Application.PropertyValueType);

    CodeStore.adoptProperties();

    Test.assertMessage(CodeStore.isCacheValid(0), "the untouched code keeps its image");
    Test.assertMessage(!CodeStore.isCacheValid(1), "the edited code loses its image");
    return true;
}

(:test)
function adoptingSettingsRemovesCodesDeletedOnThePhone(logger as Test.Logger) as Boolean {
    TestSupport.reset();
    CodeStore.save(0, "A", "aaa", CodeStore.TYPE_QR);
    CodeStore.save(1, "B", "bbb", CodeStore.TYPE_QR);

    var list = [] as Array<Dictionary>;
    var entry = {};
    entry.put(CodeStore.PROP_TYPE, CodeStore.TYPE_QR);
    entry.put(CodeStore.PROP_TITLE, "A");
    entry.put(CodeStore.PROP_TEXT, "aaa");
    list.add(entry);
    Application.Properties.setValue(CodeStore.PROP_CODES, list as Application.PropertyValueType);

    CodeStore.adoptProperties();

    Test.assertEqualMessage(CodeStore.count(), 1, "the removed code is gone from Storage too");
    Test.assertMessage(CodeStore.getText(1) == null, "slot 1 is empty");
    return true;
}

(:test)
function malformedSettingsEntriesAreIgnored(logger as Test.Logger) as Boolean {
    TestSupport.reset();

    var good = {};
    good.put(CodeStore.PROP_TYPE, CodeStore.TYPE_QR);
    good.put(CodeStore.PROP_TITLE, "A");
    good.put(CodeStore.PROP_TEXT, "aaa");

    var blank = {};
    blank.put(CodeStore.PROP_TEXT, "");

    var list = [null, blank, good] as Array;
    Application.Properties.setValue(CodeStore.PROP_CODES, list as Application.PropertyValueType);

    var parsed = CodeStore.readProperties();
    Test.assertEqualMessage(parsed.size(), 1, "only the well-formed entry survives");
    return true;
}

//! Codes added on the watch when the settings editor has never been used must reach the phone.
(:test)
function reconcilePublishesWatchOnlyCodes(logger as Test.Logger) as Boolean {
    TestSupport.reset();
    CodeStore.save(0, "Watch", "added-on-watch", CodeStore.TYPE_QR);
    Application.Properties.setValue(CodeStore.PROP_CODES, [] as Array<Application.PropertyValueType>);

    CodeStore.reconcile();

    Test.assertEqualMessage(TestSupport.propertiesEntryCount(), 1, "the watch code is published");
    return true;
}
