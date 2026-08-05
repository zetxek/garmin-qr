import Toybox.Lang;
import Toybox.Application;
import Toybox.Application.Storage;

//! Brings storage written by an older release up to what this one expects.
//!
//! Existing users must not lose their codes, so the code slots themselves keep the same keys
//! they always had (`code_N_text`, `code_N_title`, `code_N_type`) and are never rewritten
//! except to normalise the type value. What this does clean up is the debris earlier releases
//! left behind, and the `codesList` entries that broke the settings editor.
//!
//! Runs once, guarded by a stored schema version, and is cheap enough for the startup slice:
//! a handful of Storage operations over at most ten slots.
(:app)
module Migration {

    const SCHEMA_KEY = "schemaVersion";

    //! 1 is any release before on-device generation; those installs have no marker at all.
    const SCHEMA_ON_DEVICE_CODES = 2;
    const CURRENT = SCHEMA_ON_DEVICE_CODES;

    function storedSchema() as Number {
        var value = null;
        try {
            value = Storage.getValue(SCHEMA_KEY);
        } catch (e) {
            value = null;
        }
        return value instanceof Number ? value : 1;
    }

    //! Returns true when it actually migrated something, which is only useful for the tests.
    function run() as Boolean {
        var from = storedSchema();
        if (from >= CURRENT) { return false; }

        Log.debug("[Migration] upgrading storage from schema " + from + " to " + CURRENT);
        if (from < SCHEMA_ON_DEVICE_CODES) {
            toOnDeviceCodes();
        }

        try {
            Storage.setValue(SCHEMA_KEY, CURRENT);
        } catch (e) {
            Log.warn("[Migration] could not record the schema version: " + e.getErrorMessage());
        }
        return true;
    }

    //! Everything that changed between the download-only releases and this one.
    function toOnDeviceCodes() as Void {
        normaliseTypes();
        dropObsoleteKeys();

        // Republish `codesList` from Storage. Older releases wrote a `code_$index_timestamp`
        // key into every entry, and a literal null for a deleted code; neither is in the
        // settings schema, and together they are what made the Connect IQ settings editor fail
        // to save (issue #30). Rewriting from Storage leaves only the three declared keys.
        try {
            CodeStore.publishProperties();
        } catch (e) {
            Log.warn("[Migration] could not republish settings: " + e.getErrorMessage());
        }
    }

    //! Older releases stored the code type in whatever form the settings editor handed over:
    //! the words "qr" and "barcode", or a Number. Reading normalises it anyway, but writing the
    //! canonical value back means the stored data matches the schema from here on.
    function normaliseTypes() as Void {
        for (var slot = 0; slot < CodeStore.MAX_CODES; slot++) {
            if (CodeStore.getText(slot) == null) { continue; }

            var raw = Storage.getValue(CodeStore.typeKey(slot));
            var normalised = CodeStore.normaliseType(raw);
            if (!(raw instanceof String) || !normalised.equals(raw)) {
                Storage.setValue(CodeStore.typeKey(slot), normalised);
                Log.debug("[Migration] slot " + slot + " type " + raw + " -> " + normalised);
            }
        }
    }

    //! Keys earlier releases wrote and nothing reads any more.
    //!
    //! Cached images are deliberately *not* removed. They are the download fallback's cache, and
    //! a user who has to switch generation off should not then face a re-download against a
    //! service that may still be refusing Garmin's image proxy.
    function dropObsoleteKeys() as Void {
        Storage.deleteValue("pendingSyncImages");   // the old offline queue
        Storage.deleteValue("lastSyncTime");

        for (var slot = 0; slot < CodeStore.MAX_CODES; slot++) {
            Storage.deleteValue("code_" + slot + "_timestamp");
            Storage.deleteValue("last_error_code_" + slot);
        }
    }
}
