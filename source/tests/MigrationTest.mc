import Toybox.Lang;
import Toybox.Test;
import Toybox.Application;
import Toybox.Application.Storage;

//! Upgrade tests.
//!
//! The thing that must never happen is an existing user opening the new release and finding
//! their codes gone, so each of these builds storage the way an older release actually wrote it
//! -- word type values, per-slot timestamps, an offline queue, `codesList` entries carrying an
//! undeclared timestamp key -- and checks what survives.

//! The codes themselves have to come through untouched.
(:test)
function upgradeKeepsExistingCodes(logger as Test.Logger) as Boolean {
    TestSupport.seedLegacyInstall();
    Test.assertMessage(Migration.run(), "an old install migrates");

    Test.assertEqualMessage(CodeStore.count(), 3, "all three codes survived");
    TestSupport.assertStringEquals(CodeStore.getText(0),
        "https://example.com/pass?id=42&type=member", "code 1 text");
    TestSupport.assertStringEquals(CodeStore.getTitle(0), "Gym card", "code 1 title");
    TestSupport.assertStringEquals(CodeStore.getText(1), "MEMBER 12345", "code 2 text");
    TestSupport.assertStringEquals(CodeStore.getTitle(1), "Loyalty", "code 2 title");
    TestSupport.assertStringEquals(CodeStore.getText(2), "PLAIN", "code 3 text");

    logger.debug("all codes preserved across the upgrade");
    return true;
}

//! Legacy type values are rewritten in canonical form, so a barcode stays a barcode.
(:test)
function upgradeNormalisesLegacyTypeValues(logger as Test.Logger) as Boolean {
    TestSupport.seedLegacyInstall();
    Migration.run();

    TestSupport.assertStringEquals(Storage.getValue(CodeStore.typeKey(0)) as String,
        CodeStore.TYPE_QR, "the word 'qr' became \"0\" on disk");
    TestSupport.assertStringEquals(Storage.getValue(CodeStore.typeKey(1)) as String,
        CodeStore.TYPE_BARCODE, "the word 'barcode' became \"1\" on disk");
    TestSupport.assertStringEquals(Storage.getValue(CodeStore.typeKey(2)) as String,
        CodeStore.TYPE_BARCODE, "the Number 1 became \"1\" on disk");

    Test.assertMessage(!CodeStore.isBarcode(0), "code 1 still reads as a QR code");
    Test.assertMessage(CodeStore.isBarcode(1), "code 2 still reads as a barcode");
    logger.debug("legacy type values normalised without changing meaning");
    return true;
}

//! The settings editor could not save while `codesList` carried an undeclared key or a null
//! hole. Republishing from Storage is what unbreaks issue #30 for an existing install.
(:test)
function upgradeRepublishesSettingsTheEditorCanSave(logger as Test.Logger) as Boolean {
    TestSupport.seedLegacyInstall();
    Migration.run();

    var raw = Application.Properties.getValue(CodeStore.PROP_CODES) as Array;
    Test.assertEqualMessage(raw.size(), 3, "one entry per code, no null holes");

    for (var i = 0; i < raw.size(); i++) {
        var entry = raw[i];
        Test.assertMessage(entry instanceof Dictionary, "entry " + i + " is a dictionary");
        var keys = (entry as Dictionary).keys();
        Test.assertEqualMessage(keys.size(), 3, "entry " + i + " has only the declared keys");
        Test.assertMessage((entry as Dictionary).get("code_$index_timestamp") == null,
            "entry " + i + " no longer carries a timestamp");
    }
    logger.debug("codesList republished with only the three declared keys");
    return true;
}

//! Debris from the old download path is cleared so it does not sit in storage forever.
(:test)
function upgradeClearsObsoleteKeys(logger as Test.Logger) as Boolean {
    TestSupport.seedLegacyInstall();
    Migration.run();

    Test.assertMessage(Storage.getValue("pendingSyncImages") == null, "old sync queue removed");
    Test.assertMessage(Storage.getValue("lastSyncTime") == null, "old sync timestamp removed");
    Test.assertMessage(Storage.getValue("code_0_timestamp") == null, "per-slot timestamp removed");
    Test.assertMessage(Storage.getValue("last_error_code_0") == null, "old error record removed");
    logger.debug("obsolete keys cleared");
    return true;
}

//! A cached image is the download fallback's cache. Someone who has to switch generation off
//! should not then face a re-download against a service that may still be failing.
(:test)
function upgradeKeepsCachedImagesForTheFallback(logger as Test.Logger) as Boolean {
    TestSupport.seedLegacyInstall();
    CodeStore.putImage(0, TestSupport.sampleBitmap());
    Test.assertMessage(CodeStore.isCacheValid(0), "precondition: slot 0 has a cached image");

    Migration.run();

    Test.assertMessage(CodeStore.isCacheValid(0), "the cached image is still there afterwards");
    logger.debug("cached images preserved for the fallback path");
    return true;
}

//! Running twice must not repeat the work, and a fresh install must not be treated as an
//! upgrade at all.
(:test)
function upgradeRunsOnceAndIsSafeOnAFreshInstall(logger as Test.Logger) as Boolean {
    TestSupport.seedLegacyInstall();
    Test.assertMessage(Migration.run(), "the first run migrates");
    Test.assertMessage(!Migration.run(), "the second run is a no-op");
    Test.assertEqualMessage(Migration.storedSchema(), Migration.CURRENT, "schema recorded");

    TestSupport.reset();
    Storage.deleteValue(Migration.SCHEMA_KEY);
    Test.assertMessage(Migration.run(), "a fresh install still stamps the schema");
    Test.assertEqualMessage(CodeStore.count(), 0, "and has no codes to lose");
    Test.assertMessage(!Migration.run(), "and does not migrate again");

    logger.debug("migration is idempotent and safe with no data");
    return true;
}
