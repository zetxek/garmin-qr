import Toybox.Lang;
import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.WatchUi;

//! The only place that knows how codes are persisted.
//!
//! Two stores are involved and they are not interchangeable:
//!
//!  * `Storage` is the app's own key/value store. It is fast, it survives restarts and it is
//!    the store the app reads from at runtime.
//!  * `Application.Properties["codesList"]` is the array behind the Connect IQ settings editor.
//!    Its shape is dictated by `resources/settings.xml`; writing anything that does not match
//!    that schema makes the phone-side editor fail to save (issue #30).
//!
//! Storage key names are unchanged from 0.0.22 so that upgrading does not lose a user's codes.
//!
//! Annotated `(:glance)` because the glance view reads codes too, and the glance process only
//! links symbols carrying that annotation.
(:glance)
module CodeStore {

    const MAX_CODES = 20;

    const TYPE_QR = "0";
    const TYPE_BARCODE = "1";

    //! Keys of a `codesList` entry. These must match `resources/settings.xml` exactly,
    //! and nothing else may be written into an entry.
    const PROP_CODES = "codesList";
    const PROP_TEXT = "code_$index_text";
    const PROP_TITLE = "code_$index_title";
    const PROP_TYPE = "code_$index_type";

    const GLANCE_IMAGE = "qr_image_glance_0";
    const GLANCE_META_TEXT = "qr_image_glance_meta_text_0";
    const GLANCE_META_TYPE = "qr_image_glance_meta_type_0";

    // ---------------------------------------------------------------- keys

    function textKey(slot as Number) as String { return "code_" + slot + "_text"; }
    function titleKey(slot as Number) as String { return "code_" + slot + "_title"; }
    function typeKey(slot as Number) as String { return "code_" + slot + "_type"; }
    function imageKey(slot as Number) as String { return "qr_image_" + slot; }
    function metaTextKey(slot as Number) as String { return "qr_image_meta_text_" + slot; }
    function metaTypeKey(slot as Number) as String { return "qr_image_meta_type_" + slot; }

    // ------------------------------------------------------------- reading

    function getText(slot as Number) as String? {
        if (slot < 0 || slot >= MAX_CODES) { return null; }
        var value = Storage.getValue(textKey(slot));
        if (value instanceof String && value.length() > 0) { return value; }
        return null;
    }

    function getTitle(slot as Number) as String {
        var value = Storage.getValue(titleKey(slot));
        if (value instanceof String) { return value; }
        return "";
    }

    //! Coerce whatever is in storage into "0" (QR) or "1" (barcode).
    //!
    //! The settings editor round-trips the `<listEntry value="1">` as either a String or a
    //! Number depending on the device and the Connect IQ version, and `Number.equals("1")` is
    //! false — which is why barcodes used to render as QR codes. Releases before 0.0.10 also
    //! wrote the words "qr" and "barcode". Everything is normalised here, once.
    function normaliseType(raw as Object?) as String {
        if (raw instanceof Number || raw instanceof Long) {
            return raw.toNumber() == 1 ? TYPE_BARCODE : TYPE_QR;
        }
        if (raw instanceof Float || raw instanceof Double) {
            return raw.toNumber() == 1 ? TYPE_BARCODE : TYPE_QR;
        }
        if (raw instanceof String) {
            if (raw.equals(TYPE_BARCODE) || raw.equals("barcode")) { return TYPE_BARCODE; }
            return TYPE_QR;
        }
        return TYPE_QR;
    }

    function getType(slot as Number) as String {
        return normaliseType(Storage.getValue(typeKey(slot)));
    }

    function isBarcode(slot as Number) as Boolean {
        return getType(slot).equals(TYPE_BARCODE);
    }

    //! Storage indices that hold a code, ascending. Slots may be sparse after a delete.
    function occupiedSlots() as Array<Number> {
        var slots = [] as Array<Number>;
        for (var i = 0; i < MAX_CODES; i++) {
            if (getText(i) != null) { slots.add(i); }
        }
        return slots;
    }

    function count() as Number {
        return occupiedSlots().size();
    }

    //! `occupiedSlots()`, sorted by title when the "Order By Title" setting is on; otherwise the
    //! slot order, same as `occupiedSlots()`. The sort is case-insensitive and stable -- an
    //! insertion sort rather than `Array.sort()`, so that codes sharing a title (notably ones with
    //! no title at all) keep their existing relative order instead of shuffling on every reload.
    function orderedSlots() as Array<Number> {
        var slots = occupiedSlots();
        if (!OrderByTitle.enabled()) { return slots; }

        for (var i = 1; i < slots.size(); i++) {
            var slot = slots[i];
            var key = getTitle(slot).toLower();
            var j = i - 1;
            while (j >= 0 && getTitle(slots[j]).toLower().compareTo(key) > 0) {
                slots[j + 1] = slots[j];
                j--;
            }
            slots[j + 1] = slot;
        }
        return slots;
    }

    //! The slot the glance view shows, or -1 when there are no codes.
    function firstSlot() as Number {
        for (var i = 0; i < MAX_CODES; i++) {
            if (getText(i) != null) { return i; }
        }
        return -1;
    }

    function nextFreeSlot() as Number {
        for (var i = 0; i < MAX_CODES; i++) {
            if (getText(i) == null) { return i; }
        }
        return -1;
    }

    // ------------------------------------------------------------- writing

    //! Write a code. Drops the cached image when the encoded content changed, so a slot can
    //! never display the image of whatever used to live in it.
    //!
    //! Returns false if the Object Store is full (`Lang.StorageFullException` -- the platform's
    //! only way of reporting this, since remaining space cannot be queried ahead of time) or any
    //! other write failure occurs. The partial write is then rolled back by deleting the slot's
    //! keys outright, which is only safe because every caller passes a slot from `nextFreeSlot()`
    //! -- there is no edit path that overwrites an occupied slot, so rollback can never destroy a
    //! previously saved code.
    function save(slot as Number, title as String?, text as String, type as Object?) as Boolean {
        if (slot < 0 || slot >= MAX_CODES) { return false; }
        if (!(text instanceof String) || text.length() == 0) { return false; }

        var normalisedType = normaliseType(type);
        var previousText = getText(slot);
        var previousType = getType(slot);

        try {
            Storage.setValue(textKey(slot), text);
            Storage.setValue(titleKey(slot), title == null ? "" : title);
            Storage.setValue(typeKey(slot), normalisedType);
        } catch (e) {
            Log.warn("[CodeStore] could not save slot " + slot + ": " + e.getErrorMessage());
            Storage.deleteValue(textKey(slot));
            Storage.deleteValue(titleKey(slot));
            Storage.deleteValue(typeKey(slot));
            return false;
        }

        var contentChanged = previousText == null
            || !previousText.equals(text)
            || !previousType.equals(normalisedType);
        if (contentChanged) {
            clearImage(slot);
            clearGenerated(slot);
        }
        return true;
    }

    //! Remove a code and everything derived from it. The cached image in particular: leaving it
    //! behind meant the next code added reused the slot and showed the deleted code's image.
    function deleteSlot(slot as Number) as Void {
        if (slot < 0 || slot >= MAX_CODES) { return; }
        Storage.deleteValue(textKey(slot));
        Storage.deleteValue(titleKey(slot));
        Storage.deleteValue(typeKey(slot));
        Storage.deleteValue("code_" + slot + "_timestamp"); // written by releases <= 0.0.22
        Storage.deleteValue("img_error_" + slot);
        clearImage(slot);
        clearGenerated(slot);
    }

    //! The download queue's Storage key. ImageService owns the queue, but Storage keys live
    //! here so a rename cannot silently strand readers on a stale key.
    const PENDING_SLOTS = "pendingImageSlots";

    // --------------------------------------------------------- image cache

    //! True when a stored image exists and was generated from the code currently in the slot.
    //!
    //! The comparison uses `String.equals`. The previous implementation used `!=`, which on
    //! Monkey C Strings is reference inequality and therefore always true — so every load threw
    //! the whole cache away and re-downloaded everything.
    function isCacheValid(slot as Number) as Boolean {
        var text = getText(slot);
        if (text == null) { return false; }

        var metaText = Storage.getValue(metaTextKey(slot));
        if (!(metaText instanceof String) || !metaText.equals(text)) { return false; }

        var metaType = Storage.getValue(metaTypeKey(slot));
        if (!(metaType instanceof String) || !metaType.equals(getType(slot))) { return false; }

        return Storage.getValue(imageKey(slot)) != null;
    }

    function cachedImage(slot as Number) as WatchUi.BitmapResource? {
        if (!isCacheValid(slot)) { return null; }
        return Storage.getValue(imageKey(slot)) as WatchUi.BitmapResource?;
    }

    function putImage(slot as Number, image as WatchUi.BitmapResource?) as Void {
        if (image == null) { return; }
        var text = getText(slot);
        if (text == null) { return; }
        try {
            Storage.setValue(imageKey(slot), image);
            Storage.setValue(metaTextKey(slot), text);
            Storage.setValue(metaTypeKey(slot), getType(slot));
        } catch (e) {
            Log.warn("[CodeStore] could not cache image for slot " + slot + ": " + e.getErrorMessage());
            clearImage(slot);
        }
    }

    function clearImage(slot as Number) as Void {
        Storage.deleteValue(imageKey(slot));
        Storage.deleteValue(metaTextKey(slot));
        Storage.deleteValue(metaTypeKey(slot));
    }

    // --------------------------------------------------- glance image cache

    function isGlanceCacheValid() as Boolean {
        var slot = firstSlot();
        if (slot < 0) { return false; }

        var metaText = Storage.getValue(GLANCE_META_TEXT);
        var text = getText(slot);
        if (!(metaText instanceof String) || text == null || !metaText.equals(text)) { return false; }

        var metaType = Storage.getValue(GLANCE_META_TYPE);
        if (!(metaType instanceof String) || !metaType.equals(getType(slot))) { return false; }

        return Storage.getValue(GLANCE_IMAGE) != null;
    }

    function glanceImage() as WatchUi.BitmapResource? {
        if (!isGlanceCacheValid()) { return null; }
        return Storage.getValue(GLANCE_IMAGE) as WatchUi.BitmapResource?;
    }

    function putGlanceImage(image as WatchUi.BitmapResource?) as Void {
        var slot = firstSlot();
        if (image == null || slot < 0) { return; }
        try {
            Storage.setValue(GLANCE_IMAGE, image);
            Storage.setValue(GLANCE_META_TEXT, getText(slot));
            Storage.setValue(GLANCE_META_TYPE, getType(slot));
        } catch (e) {
            // The image may have been written before the metadata throw. Leaving it behind means
            // a cached glance image attributed to nothing, so drop the pair together.
            Log.warn("[CodeStore] could not cache glance image: " + e.getErrorMessage());
            Storage.deleteValue(GLANCE_IMAGE);
            Storage.deleteValue(GLANCE_META_TEXT);
            Storage.deleteValue(GLANCE_META_TYPE);
        }
    }

    // ------------------------------------------------- generated code cache

    //! Generated codes are cached so a code is built once, not rebuilt on every open.
    //!
    //! This is also what lets the glance show a code at all. The glance has a fraction of the
    //! app's memory and the same watchdog, so it can read and draw a matrix but must never build
    //! one. The app populates this cache; the glance only consumes it.
    function matrixKey(slot as Number) as String { return "qr_matrix_" + slot; }
    function matrixSizeKey(slot as Number) as String { return "qr_matrix_size_" + slot; }
    function barsKey(slot as Number) as String { return "code_bars_" + slot; }
    function generatedMetaTextKey(slot as Number) as String { return "gen_meta_text_" + slot; }
    function generatedMetaTypeKey(slot as Number) as String { return "gen_meta_type_" + slot; }

    //! True when the cached generated code still matches the slot's text and type.
    function isGeneratedValid(slot as Number) as Boolean {
        var text = getText(slot);
        if (text == null) { return false; }

        var metaText = Storage.getValue(generatedMetaTextKey(slot));
        if (!(metaText instanceof String) || !metaText.equals(text)) { return false; }

        var metaType = Storage.getValue(generatedMetaTypeKey(slot));
        if (!(metaType instanceof String) || !metaType.equals(getType(slot))) { return false; }

        return isBarcode(slot)
            ? Storage.getValue(barsKey(slot)) != null
            : Storage.getValue(matrixKey(slot)) != null;
    }

    function cachedMatrix(slot as Number) as QrMatrix? {
        if (isBarcode(slot) || !isGeneratedValid(slot)) { return null; }
        var modules = Storage.getValue(matrixKey(slot));
        var side = Storage.getValue(matrixSizeKey(slot));
        if (!(modules instanceof ByteArray) || !(side instanceof Number)) { return null; }
        if (modules.size() != side * side) { return null; }

        var matrix = new QrMatrix(side);
        matrix.modules = modules;
        return matrix;
    }

    function cachedBars(slot as Number) as ByteArray? {
        if (!isBarcode(slot) || !isGeneratedValid(slot)) { return null; }
        var bars = Storage.getValue(barsKey(slot));
        return bars instanceof ByteArray ? bars : null;
    }

    function putMatrix(slot as Number, matrix as QrMatrix) as Void {
        var text = getText(slot);
        if (text == null) { return; }
        try {
            Storage.setValue(matrixKey(slot), matrix.modules as Application.PropertyValueType);
            Storage.setValue(matrixSizeKey(slot), matrix.size);
            Storage.deleteValue(barsKey(slot));
            stampGeneratedMeta(slot, text);
        } catch (e) {
            Log.warn("[CodeStore] could not cache the generated code: " + e.getErrorMessage());
            clearGenerated(slot);
        }
    }

    function putBars(slot as Number, bars as ByteArray) as Void {
        var text = getText(slot);
        if (text == null) { return; }
        try {
            Storage.setValue(barsKey(slot), bars as Application.PropertyValueType);
            Storage.deleteValue(matrixKey(slot));
            Storage.deleteValue(matrixSizeKey(slot));
            stampGeneratedMeta(slot, text);
        } catch (e) {
            Log.warn("[CodeStore] could not cache the generated code: " + e.getErrorMessage());
            clearGenerated(slot);
        }
    }

    function stampGeneratedMeta(slot as Number, text as String) as Void {
        Storage.setValue(generatedMetaTextKey(slot), text);
        Storage.setValue(generatedMetaTypeKey(slot), getType(slot));
    }

    function clearGenerated(slot as Number) as Void {
        Storage.deleteValue(matrixKey(slot));
        Storage.deleteValue(matrixSizeKey(slot));
        Storage.deleteValue(barsKey(slot));
        Storage.deleteValue(generatedMetaTextKey(slot));
        Storage.deleteValue(generatedMetaTypeKey(slot));
    }

    // ------------------------------------------------------ settings editor

    //! Read `codesList` and return only entries that are well formed, in order.
    //! Malformed entries — including the `null` holes written by older releases on delete —
    //! are skipped rather than propagated.
    function readProperties() as Array<Dictionary> {
        var raw = null;
        try {
            raw = Application.Properties.getValue(PROP_CODES);
        } catch (e) {
            Log.warn("[CodeStore] could not read codesList: " + e.getErrorMessage());
            return [] as Array<Dictionary>;
        }
        if (!(raw instanceof Array)) { return [] as Array<Dictionary>; }

        var entries = [] as Array<Dictionary>;
        for (var i = 0; i < raw.size() && entries.size() < MAX_CODES; i++) {
            // `Properties.ValueType` (raw's element type) does not include Dictionary, even
            // though a `codesList` entry always is one -- the settings editor's per-entry
            // group widget produces Dictionaries that the property-value type union just never
            // documents. Cast to Object? so `instanceof Dictionary` narrows normally instead of
            // being seen as statically impossible, which is what made the 9.x checker flag the
            // rest of this block as unreachable and its declarations as uninitialized.
            var entry = raw[i] as Object?;
            if (!(entry instanceof Dictionary)) { continue; }
            var text = entry.get(PROP_TEXT);
            if (!(text instanceof String) || text.length() == 0) { continue; }

            var title = entry.get(PROP_TITLE);
            var clean = {};
            clean.put(PROP_TYPE, normaliseType(entry.get(PROP_TYPE)));
            clean.put(PROP_TITLE, title instanceof String ? title : "");
            clean.put(PROP_TEXT, text);
            entries.add(clean);
        }
        return entries;
    }

    //! Bring the two stores into agreement.
    //!
    //! Releases up to 0.0.22 arbitrated with a `System.getTimer()` "timestamp" — milliseconds
    //! since the device powered on — so "whichever side is newer wins" compared two unrelated
    //! clocks and picked essentially at random. The rule now follows the data flow instead:
    //! `codesList` is what the phone last pushed, so it wins whenever it has anything in it.
    //! It is only empty on a fresh install or when every code was added on the watch, and in
    //! that case Storage is published to it.
    function reconcile() as Void {
        if (readProperties().size() > 0) {
            adoptProperties();
        } else {
            publishProperties();
        }
    }

    //! Copy the settings-editor contents into Storage. Returns true when anything changed.
    //!
    //! Called when the phone pushes new settings, and at startup. Only slots whose encoded
    //! content actually changed lose their cached image, so editing one code no longer forces
    //! every other code to be downloaded again.
    function adoptProperties() as Boolean {
        var entries = readProperties();
        if (entries.size() == 0) { return false; }

        var changed = false;
        for (var slot = 0; slot < MAX_CODES; slot++) {
            if (slot < entries.size()) {
                var entry = entries[slot];
                var text = entry.get(PROP_TEXT) as String;
                var type = entry.get(PROP_TYPE);
                var previousText = getText(slot);
                var previousType = getType(slot);
                if (previousText == null || !previousText.equals(text) || !previousType.equals(type)) {
                    changed = true;
                }
                save(slot, entry.get(PROP_TITLE) as String, text, type);
            } else if (getText(slot) != null) {
                deleteSlot(slot);
                changed = true;
            }
        }
        return changed;
    }

    //! Publish Storage into the settings editor, compacted, using only the declared keys.
    //!
    //! Writes nothing when the property already matches. Every write to `codesList` is a chance
    //! to corrupt what the phone-side editor reads, so the app makes as few as possible.
    function publishProperties() as Void {
        var slots = occupiedSlots();
        var list = [] as Array<Dictionary>;
        for (var i = 0; i < slots.size(); i++) {
            var slot = slots[i];
            var entry = {};
            entry.put(PROP_TYPE, getType(slot));
            entry.put(PROP_TITLE, getTitle(slot));
            entry.put(PROP_TEXT, getText(slot));
            list.add(entry);
        }

        if (propertiesMatch(list)) {
            Log.debug("[CodeStore] codesList already up to date, skipping write");
            return;
        }
        try {
            Application.Properties.setValue(PROP_CODES, list as Application.PropertyValueType);
            Log.debug("[CodeStore] published " + list.size() + " codes to codesList");
        } catch (e) {
            Log.warn("[CodeStore] could not write codesList: " + e.getErrorMessage());
        }
    }

    function propertiesMatch(list as Array<Dictionary>) as Boolean {
        var current = readProperties();
        if (current.size() != list.size()) { return false; }
        for (var i = 0; i < list.size(); i++) {
            var a = current[i];
            var b = list[i];
            if (!stringsEqual(a.get(PROP_TEXT), b.get(PROP_TEXT))) { return false; }
            if (!stringsEqual(a.get(PROP_TITLE), b.get(PROP_TITLE))) { return false; }
            if (!stringsEqual(a.get(PROP_TYPE), b.get(PROP_TYPE))) { return false; }
        }
        return true;
    }

    //! `==` on Monkey C Strings compares references, so value comparison always goes through
    //! `equals`. Wrapped here because both sides can be null.
    function stringsEqual(a as Object?, b as Object?) as Boolean {
        if (a == null && b == null) { return true; }
        if (!(a instanceof String) || !(b instanceof String)) { return false; }
        return a.equals(b);
    }
}
