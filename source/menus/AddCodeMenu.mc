import Toybox.Lang;
import Toybox.WatchUi;

//! Add a code from the watch: title, text, type, save.
(:app)
class AddCodeMenu {

    var view as AppView;
    var codeTitle as String;
    var codeText as String;
    var codeType as String;
    var menu as WatchUi.Menu2?;

    function initialize(view as AppView) {
        self.view = view;
        codeTitle = "";
        codeText = "";
        codeType = CodeStore.TYPE_QR;
        menu = null;
    }

    function show() as Void {
        var typeLabel = codeType.equals(CodeStore.TYPE_BARCODE) ? "Barcode" : "QR Code";
        var existing = menu;

        if (existing == null) {
            var created = new WatchUi.Menu2({:title => "Add Code"});
            created.addItem(titleItem());
            created.addItem(textItem());
            created.addItem(new WatchUi.MenuItem("Type", typeLabel, :input_type, {}));
            created.addItem(new WatchUi.MenuItem("Save", null, :save_code, {}));
            menu = created;
            WatchUi.pushView(created, new AddCodeMenuDelegate(self), WatchUi.SLIDE_UP);
        } else {
            existing.updateItem(titleItem(), 0);
            existing.updateItem(textItem(), 1);
            existing.updateItem(new WatchUi.MenuItem("Type", typeLabel, :input_type, {}), 2);
            WatchUi.requestUpdate();
        }
    }

    function titleItem() as WatchUi.MenuItem {
        return new WatchUi.MenuItem(
            "Title", codeTitle.length() > 0 ? codeTitle : "<enter>", :input_title, {});
    }

    function textItem() as WatchUi.MenuItem {
        return new WatchUi.MenuItem(
            "Code", codeText.length() > 0 ? codeText : "<enter>", :input_text, {});
    }

    function save() as Void {
        if (codeText.length() == 0) {
            Log.debug("[AddCodeMenu] refusing to save an empty code");
            WatchUi.pushView(
                new WatchUi.Confirmation("Code text is required"),
                new AddCodeConfirmationDelegate(),
                WatchUi.SLIDE_UP);
            return;
        }

        var slot = CodeStore.nextFreeSlot();
        if (slot < 0) {
            Log.warn("[AddCodeMenu] no free slot, all " + CodeStore.MAX_CODES + " are in use");
            WatchUi.pushView(
                new WatchUi.Confirmation("All " + CodeStore.MAX_CODES + " code slots are full"),
                new AddCodeConfirmationDelegate(),
                WatchUi.SLIDE_UP);
            return;
        }

        if (!CodeStore.save(slot, codeTitle, codeText, codeType)) {
            WatchUi.pushView(
                new WatchUi.Confirmation("Not enough space to save this code"),
                new AddCodeConfirmationDelegate(),
                WatchUi.SLIDE_UP);
            return;
        }
        CodeStore.publishProperties();
        Log.debug("[AddCodeMenu] saved new code in slot " + slot);

        WatchUi.popView(WatchUi.SLIDE_DOWN); // add menu
        WatchUi.popView(WatchUi.SLIDE_DOWN); // code menu

        view.onCodesChanged();

        // Show the code that was just added.
        for (var i = 0; i < view.slots.size(); i++) {
            if (view.slots[i] == slot) {
                view.position = i;
                view.loadCurrent();
                break;
            }
        }
        // Only fetch when the service is actually the source. With on-device generation this
        // used to queue a download the moment a code was saved, which is why adding a code
        // flashed "SYNCING..." and then failed with a 404.
        if (!CodeGeneration.enabled()) {
            ImageService.get().enqueueFirst(slot);
            ImageService.get().pump();
        }
        WatchUi.requestUpdate();
    }
}

(:app)
class AddCodeMenuDelegate extends WatchUi.Menu2InputDelegate {
    var owner as AddCodeMenu;

    function initialize(owner as AddCodeMenu) {
        Menu2InputDelegate.initialize();
        self.owner = owner;
    }

    function onSelect(item) as Void {
        var id = item.getId();

        if (id == :input_title) {
            WatchUi.pushView(
                new WatchUi.TextPicker(owner.codeTitle),
                new CodeTextPickerDelegate(owner, :input_title),
                WatchUi.SLIDE_UP);

        } else if (id == :input_text) {
            WatchUi.pushView(
                new WatchUi.TextPicker(owner.codeText),
                new CodeTextPickerDelegate(owner, :input_text),
                WatchUi.SLIDE_UP);

        } else if (id == :input_type) {
            var typeMenu = new WatchUi.Menu2({:title => "Select Type"});
            typeMenu.addItem(new WatchUi.MenuItem("QR Code", null, :type_qr, {}));
            typeMenu.addItem(new WatchUi.MenuItem("Barcode", null, :type_barcode, {}));
            WatchUi.pushView(typeMenu, new CodeTypeMenuDelegate(owner), WatchUi.SLIDE_UP);

        } else if (id == :save_code) {
            owner.save();
        }
    }
}

(:app)
class CodeTextPickerDelegate extends WatchUi.TextPickerDelegate {
    var owner as AddCodeMenu;
    var field as Symbol;

    function initialize(owner as AddCodeMenu, field as Symbol) {
        TextPickerDelegate.initialize();
        self.owner = owner;
        self.field = field;
    }

    function onTextEntered(text as String, changed as Boolean) as Boolean {
        if (text != null) {
            if (field == :input_title) {
                owner.codeTitle = text;
            } else if (field == :input_text) {
                owner.codeText = text;
            }
        }
        owner.show();
        return true;
    }
}

//! Confirmation pops itself on response, the same way TextPicker does above -- this only needs
//! to acknowledge it, not manage the view stack. Shared by every validation/failure message this
//! menu shows (empty text, no free slot, storage full): none of them carry state to act on.
(:app)
class AddCodeConfirmationDelegate extends WatchUi.ConfirmationDelegate {
    function initialize() {
        ConfirmationDelegate.initialize();
    }

    function onResponse(response) as Boolean {
        return true;
    }
}

(:app)
class CodeTypeMenuDelegate extends WatchUi.Menu2InputDelegate {
    var owner as AddCodeMenu;

    function initialize(owner as AddCodeMenu) {
        Menu2InputDelegate.initialize();
        self.owner = owner;
    }

    function onSelect(item) as Void {
        owner.codeType = item.getId() == :type_barcode
            ? CodeStore.TYPE_BARCODE
            : CodeStore.TYPE_QR;
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        owner.show();
    }
}
