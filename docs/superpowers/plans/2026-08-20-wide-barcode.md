# Wider Code 128 Barcodes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Fix [issue #35](https://github.com/zetxek/garmin-qr/issues/35) — barcodes rendering with bars too thin for some scanners — with an always-on layout correctness fix plus an opt-in "Wide Barcode" toggle.

**Architecture:** `CodeRenderer.barcodeLayout` currently requires the full 10-module quiet zone to fit before it will pick a larger integer bar scale, which wastes available width in borderline cases. It gains a `wide as Boolean` parameter: `false` (always, no setting) lowers the floor it insists on from the full ideal to a small 2-module minimum; `true` (opt-in, off by default) lowers it further to 1 module, and callers widen the screen fraction they allocate to the barcode box to match. A new `WideBarcode` settings module (mirroring the existing `CodeGeneration` module) reads the toggle; `AppView` and `GlanceView` read it once per frame and thread it through; a new on-watch Settings menu item flips it.

**Tech Stack:** Connect IQ / Monkey C, SDK 8.4.1+. Tests run via `Toybox.Test` inside the Connect IQ simulator (`scripts/run-tests.sh`), not a host-side test runner. `monkeyc` compiles all of `source/` as one program per `monkey.jungle` — there is no incremental/per-file compilation, so a function signature change and every one of its call sites must land in the same buildable task.

## Global Constraints

- Any module reachable from the glance process must carry the `(:glance)` annotation (see `source/CodeRenderer.mc:11`, `source/CodeGeneration.mc:9`). `WideBarcode` is read from `GlanceView`, so it needs this too.
- The new property is **not** added to `resources/settings.xml` — on-watch only, not phone-synced (see design doc rationale).
- Build/type-check at `-w -l 2` (the level every existing script and CI workflow uses); a task is not done if it introduces new warnings beyond the pre-existing ones already in this codebase.
- Target device for manual verification: `fenix843mm` (the device the issue was reported and reproduced on).
- Full unit suite: `./scripts/run-tests.sh fenix843mm` must print `==> Tests passed` before any task is considered complete.

---

### Task 1: `WideBarcode` settings module

**Files:**
- Create: `source/WideBarcode.mc`
- Modify: `resources/drawables/properties.xml`
- Modify: `source/tests/TestSupport.mc`
- Modify: `source/tests/AppFlowTest.mc`

**Interfaces:**
- Produces: `WideBarcode.SETTING as String` (the property key, `"wideBarcode"`), `WideBarcode.enabled() as Boolean`.

- [x] **Step 1: Write the failing test**

Add to `source/tests/AppFlowTest.mc`, immediately after `anImpossibleBarcodeIsReported` (the last of the three existing `barcodeLayout` tests, ending around line 528):

```monkeyc
//! `WideBarcode.enabled()` reflects whatever is in Properties, off by default.
(:test)
function wideBarcodeReflectsTheProperty(logger as Test.Logger) as Boolean {
    TestSupport.reset();
    Test.assertMessage(!WideBarcode.enabled(), "off by default after reset");

    Application.Properties.setValue(WideBarcode.SETTING, true);
    Test.assertMessage(WideBarcode.enabled(), "reflects a true property");

    Application.Properties.setValue(WideBarcode.SETTING, false);
    Test.assertMessage(!WideBarcode.enabled(), "reflects a false property");

    logger.debug("WideBarcode.enabled() tracks the wideBarcode property, off by default");
    return true;
}
```

- [x] **Step 2: Run it to confirm it fails to build**

Run: `./scripts/run-tests.sh fenix843mm`
Expected: build failure — `WideBarcode` is not yet defined.

- [x] **Step 3: Register the property**

In `resources/drawables/properties.xml`, add a line after `generateOnDevice` so the file reads:

```xml
<properties>
    <property id="appVersion" type="string">0.1.0</property>
    <property id="codesList" type="array"></property>
    <property id="keepScreenOn" type="boolean">true</property>

    <property id="serviceUrl" type="string">https://qr-gen.adrianmoreno.info</property>
    <property id="generateOnDevice" type="boolean">true</property>
    <property id="wideBarcode" type="boolean">false</property>
</properties>
```

- [x] **Step 4: Create the settings module**

Create `source/WideBarcode.mc`:

```monkeyc
import Toybox.Lang;
import Toybox.Application;

//! Whether barcodes render using nearly the full screen width and a thinner-than-ideal quiet
//! zone, for scanners that need thicker bars more than the standard 10-module margin. Off by
//! default: a smaller quiet zone is a real tradeoff, not a free improvement.
(:glance)
module WideBarcode {

    const SETTING = "wideBarcode";

    function enabled() as Boolean {
        var value = null;
        try {
            value = Application.Properties.getValue(SETTING);
        } catch (e) {
            value = null;
        }
        return value instanceof Boolean ? value : false;
    }
}
```

- [x] **Step 5: Reset the property between tests**

In `source/tests/TestSupport.mc`, in `reset()`, add a line next to the existing `CodeGeneration.SETTING` reset so both read together:

```monkeyc
        // Most of these tests are about the download path, so they opt out of on-device
        // generation explicitly. Tests that want generation turn it back on themselves.
        Application.Properties.setValue(CodeGeneration.SETTING, false);
        Application.Properties.setValue(WideBarcode.SETTING, false);
        ImageService.instance = null;
```

- [x] **Step 6: Run the test to verify it passes**

Run: `./scripts/run-tests.sh fenix843mm`
Expected: `==> Tests passed`, including `wideBarcodeReflectsTheProperty`.

- [x] **Step 7: Commit**

```bash
git add source/WideBarcode.mc resources/drawables/properties.xml source/tests/TestSupport.mc source/tests/AppFlowTest.mc
git commit -m "Add the wideBarcode setting, off by default"
```

---

### Task 2: Wide-mode layout math, wired into `AppView` and `GlanceView`

This is one task, not three: `barcodeLayout`/`drawBarcode` gaining a parameter and every call site
that uses them are not independently buildable — `monkeyc` compiles all of `source/` together, so
the tree does not build again until all of it lands.

**Files:**
- Modify: `source/CodeRenderer.mc`
- Modify: `source/views/AppView.mc`
- Modify: `source/views/GlanceView.mc`
- Modify: `source/tests/AppFlowTest.mc`

**Interfaces:**
- Consumes: `WideBarcode.enabled() as Boolean` (Task 1).
- Produces: `CodeRenderer.barcodeLayout(moduleCount as Number, available as Number, wide as Boolean) as Array<Number>?`, `CodeRenderer.drawBarcode(dc as Graphics.Dc, modules as ByteArray, centreX as Number, centreY as Number, available as Number, height as Number, wide as Boolean) as Boolean`.

- [x] **Step 1: Update the three existing `barcodeLayout` tests for the new signature**

In `source/tests/AppFlowTest.mc`, the three calls around line 474-528 each gain a trailing `, false` (they test today's default, non-wide behavior):

```monkeyc
    var layout = CodeRenderer.barcodeLayout(moduleCount, available, false);
```
```monkeyc
    var layout = CodeRenderer.barcodeLayout((bars as ByteArray).size(), available, false);
```
```monkeyc
    var layout = CodeRenderer.barcodeLayout((bars as ByteArray).size(), 100, false);
```

- [x] **Step 2: Write the new failing test**

Add to `source/tests/AppFlowTest.mc`, after `wideBarcodeReflectsTheProperty` from Task 1:

```monkeyc
//! Wide mode trades quiet zone for scale when the default is too conservative to use it -- the
//! exact case from issue #35: a barcode readable on a plastic card but too thin on the watch.
(:test)
function wideModePicksABiggerScaleThanDefault(logger as Test.Logger) as Boolean {
    var bars = Code128.encode("FFCC12345");
    Test.assertMessage(bars != null, "the payload encodes");
    var moduleCount = (bars as ByteArray).size();

    // The fenix843mm from the issue: a 416px round display, 94% given to the barcode box
    // normally, 99% in wide mode (see AppView.drawGeneratedCode / GlanceView.drawGeneratedBarcode).
    var normalAvailable = (416 * 0.94).toNumber();
    var wideAvailable = (416 * 0.99).toNumber();

    var normal = CodeRenderer.barcodeLayout(moduleCount, normalAvailable, false);
    var wide = CodeRenderer.barcodeLayout(moduleCount, wideAvailable, true);

    Test.assertMessage(normal != null, "the default layout fits");
    Test.assertMessage(wide != null, "the wide layout fits");
    Test.assertMessage(wide[0] > normal[0],
        "wide mode should pick a bigger scale: " + wide[0] + " vs default " + normal[0]);
    Test.assertMessage(wide[2] <= wideAvailable,
        "the wide layout must still fit: " + wide[2] + " <= " + wideAvailable);
    Test.assertMessage(wide[1] > 0, "wide mode still keeps some quiet zone, however thin");

    logger.debug(moduleCount + " modules: default scale " + normal[0] + " (" + normal[2]
        + "px), wide scale " + wide[0] + " (" + wide[2] + "px)");
    return true;
}
```

- [x] **Step 3: Run tests to confirm the build fails**

Run: `./scripts/run-tests.sh fenix843mm`
Expected: build failure — `barcodeLayout` does not take 3 arguments yet.

- [x] **Step 4: Update `barcodeLayout` and `drawBarcode`**

In `source/CodeRenderer.mc`, replace:

```monkeyc
    //! Bar width, quiet-zone width and total width for a barcode, or null when the payload
    //! cannot be drawn legibly in the space available.
    //!
    //! Separate from the drawing so the fit can be asserted without a Dc.
    function barcodeLayout(moduleCount as Number, available as Number) as Array<Number>? {
        if (moduleCount <= 0 || available <= 0) { return null; }

        var quietModules = 10;
        var scale = available / (moduleCount + (2 * quietModules));
        if (scale < 1) {
            // No room for a full quiet zone. A bar must be at least one pixel wide to be read,
            // so that is the floor -- below it the payload does not fit this screen at all.
            scale = 1;
            if (moduleCount > available) { return null; }
        }

        var barsWidth = moduleCount * scale;
        var quiet = (available - barsWidth) / 2;
        if (quiet > quietModules * scale) { quiet = quietModules * scale; }
        return [scale, quiet, barsWidth + (2 * quiet)] as Array<Number>;
    }
```

with:

```monkeyc
    //! The quiet zone actually drawn, whenever there is room for it.
    const IDEAL_QUIET_MODULES = 10;
    //! The minimum the scale search insists on before picking a bigger integer scale. Requiring
    //! the full IDEAL_QUIET_MODULES here (as this used to) double-charges the margin: once to
    //! pick the scale, again below when centering. A small floor instead lets a bigger scale win
    //! whenever the bars themselves have room, even if the *ideal* margin would not also fit.
    const DEFAULT_MIN_QUIET_MODULES = 2;
    //! Wide mode's floor: thinner still, so a scale step that only just does not fit at the
    //! default floor gets to happen anyway. See WideBarcode for what this trades away.
    const WIDE_MIN_QUIET_MODULES = 1;

    //! Bar width, quiet-zone width and total width for a barcode, or null when the payload
    //! cannot be drawn legibly in the space available.
    //!
    //! Separate from the drawing so the fit can be asserted without a Dc.
    function barcodeLayout(moduleCount as Number, available as Number, wide as Boolean) as Array<Number>? {
        if (moduleCount <= 0 || available <= 0) { return null; }

        var minQuietModules = wide ? WIDE_MIN_QUIET_MODULES : DEFAULT_MIN_QUIET_MODULES;
        var scale = available / (moduleCount + (2 * minQuietModules));
        if (scale < 1) {
            // No room for even the reduced floor. A bar must be at least one pixel wide to be
            // read, so that is the last resort -- below it the payload does not fit this screen.
            scale = 1;
            if (moduleCount > available) { return null; }
        }

        var barsWidth = moduleCount * scale;
        var quiet = (available - barsWidth) / 2;
        if (quiet > IDEAL_QUIET_MODULES * scale) { quiet = IDEAL_QUIET_MODULES * scale; }
        return [scale, quiet, barsWidth + (2 * quiet)] as Array<Number>;
    }
```

Then replace the `drawBarcode` signature and its call into `barcodeLayout`:

```monkeyc
    function drawBarcode(
        dc as Graphics.Dc, modules as ByteArray,
        centreX as Number, centreY as Number, available as Number, height as Number
    ) as Boolean {
        var layout = barcodeLayout(modules.size(), available);
        if (layout == null) { return false; }
```

with:

```monkeyc
    function drawBarcode(
        dc as Graphics.Dc, modules as ByteArray,
        centreX as Number, centreY as Number, available as Number, height as Number, wide as Boolean
    ) as Boolean {
        var layout = barcodeLayout(modules.size(), available, wide);
        if (layout == null) { return false; }
```

- [x] **Step 5: Update `AppView.drawGeneratedCode`**

In `source/views/AppView.mc`, replace:

```monkeyc
        if (currentBars != null) {
            // Barcodes want width; the height only has to be enough for a scanner to find a row.
            var barLimit = (height * 0.45).toNumber();
            var barHeight = boxHeight < barLimit ? boxHeight : barLimit;
            var drawn = CodeRenderer.drawBarcode(
                dc, currentBars as ByteArray, width / 2, centreY,
                (width * 0.94).toNumber(), barHeight);
            if (!drawn) {
```

with:

```monkeyc
        if (currentBars != null) {
            // Barcodes want width; the height only has to be enough for a scanner to find a row.
            var barLimit = (height * 0.45).toNumber();
            var barHeight = boxHeight < barLimit ? boxHeight : barLimit;
            var wide = WideBarcode.enabled();
            var widthFraction = wide ? 0.99 : 0.94;
            var drawn = CodeRenderer.drawBarcode(
                dc, currentBars as ByteArray, width / 2, centreY,
                (width * widthFraction).toNumber(), barHeight, wide);
            if (!drawn) {
```

- [x] **Step 6: Update `GlanceView.drawGeneratedBarcode`**

In `source/views/GlanceView.mc`, replace:

```monkeyc
    //! A generated barcode: bars across most of the width, label underneath if it fits.
    function drawGeneratedBarcode(dc as Graphics.Dc, bars as ByteArray) as Void {
        var height = (dc.getHeight() * 0.72).toNumber();
        var drawn = CodeRenderer.drawBarcode(
            dc, bars, dc.getWidth() / 2, dc.getHeight() / 2,
            (dc.getWidth() * 0.96).toNumber(), height);
        if (!drawn) { drawMessage(dc, "Code too long"); }
    }
```

with:

```monkeyc
    //! A generated barcode: bars across most of the width, label underneath if it fits.
    function drawGeneratedBarcode(dc as Graphics.Dc, bars as ByteArray) as Void {
        var height = (dc.getHeight() * 0.72).toNumber();
        var wide = WideBarcode.enabled();
        var widthFraction = wide ? 0.99 : 0.96;
        var drawn = CodeRenderer.drawBarcode(
            dc, bars, dc.getWidth() / 2, dc.getHeight() / 2,
            (dc.getWidth() * widthFraction).toNumber(), height, wide);
        if (!drawn) { drawMessage(dc, "Code too long"); }
    }
```

- [x] **Step 7: Run the full unit suite**

Run: `./scripts/run-tests.sh fenix843mm`
Expected: `==> Tests passed`, including `wideModePicksABiggerScaleThanDefault` (log line should read `134 modules: default scale 2 (308px), wide scale 3 (410px)`).

- [x] **Step 8: Commit**

```bash
git add source/CodeRenderer.mc source/tests/AppFlowTest.mc source/views/AppView.mc source/views/GlanceView.mc
git commit -m "Thread a wide-mode flag through barcode layout, AppView and GlanceView"
```

---

### Task 3: On-watch "Wide Barcode" toggle

**Files:**
- Modify: `source/menus/AppSettingsMenu.mc`

**Interfaces:**
- Consumes: `WideBarcode.SETTING as String`, `WideBarcode.enabled() as Boolean` (Task 1).

- [x] **Step 1: Replace the whole file**

`source/menus/AppSettingsMenu.mc` currently:

```monkeyc
import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Application;

//! On-watch settings, for the handful of options that make sense without the phone.
(:app)
module AppSettingsMenu {

    function build() as WatchUi.Menu2 {
        var menu = new WatchUi.Menu2({:title => "Settings"});
        var enabled = (Application.getApp() as App).keepScreenOn;
        menu.addItem(new WatchUi.MenuItem(
            "Keep Screen On", enabled ? "Enabled" : "Disabled", :toggle_keep_screen_on, {}));
        return menu;
    }
}

(:app)
class AppSettingsMenuDelegate extends WatchUi.Menu2InputDelegate {
    var view as AppView;

    function initialize(view as AppView) {
        Menu2InputDelegate.initialize();
        self.view = view;
    }

    function onSelect(item) as Void {
        if (item.getId() != :toggle_keep_screen_on) { return; }

        var app = Application.getApp() as App;
        app.keepScreenOn = !app.keepScreenOn;
        try {
            Application.Properties.setValue("keepScreenOn", app.keepScreenOn);
        } catch (e) {
            Log.warn("[AppSettingsMenu] could not persist keepScreenOn: " + e.getErrorMessage());
        }

        item.setSubLabel(app.keepScreenOn ? "Enabled" : "Disabled");
        view.applyScreenTimeout();
        WatchUi.requestUpdate();
    }
}
```

Replace its full contents with:

```monkeyc
import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Application;

//! On-watch settings, for the handful of options that make sense without the phone.
(:app)
module AppSettingsMenu {

    function build() as WatchUi.Menu2 {
        var menu = new WatchUi.Menu2({:title => "Settings"});
        var enabled = (Application.getApp() as App).keepScreenOn;
        menu.addItem(new WatchUi.MenuItem(
            "Keep Screen On", enabled ? "Enabled" : "Disabled", :toggle_keep_screen_on, {}));
        menu.addItem(new WatchUi.MenuItem(
            "Wide Barcode", WideBarcode.enabled() ? "Enabled" : "Disabled", :toggle_wide_barcode, {}));
        return menu;
    }
}

(:app)
class AppSettingsMenuDelegate extends WatchUi.Menu2InputDelegate {
    var view as AppView;

    function initialize(view as AppView) {
        Menu2InputDelegate.initialize();
        self.view = view;
    }

    function onSelect(item) as Void {
        if (item.getId() == :toggle_keep_screen_on) {
            toggleKeepScreenOn(item);
        } else if (item.getId() == :toggle_wide_barcode) {
            toggleWideBarcode(item);
        }
    }

    function toggleKeepScreenOn(item) as Void {
        var app = Application.getApp() as App;
        app.keepScreenOn = !app.keepScreenOn;
        try {
            Application.Properties.setValue("keepScreenOn", app.keepScreenOn);
        } catch (e) {
            Log.warn("[AppSettingsMenu] could not persist keepScreenOn: " + e.getErrorMessage());
        }

        item.setSubLabel(app.keepScreenOn ? "Enabled" : "Disabled");
        view.applyScreenTimeout();
        WatchUi.requestUpdate();
    }

    function toggleWideBarcode(item) as Void {
        var next = !WideBarcode.enabled();
        try {
            Application.Properties.setValue(WideBarcode.SETTING, next);
        } catch (e) {
            Log.warn("[AppSettingsMenu] could not persist wideBarcode: " + e.getErrorMessage());
        }

        item.setSubLabel(next ? "Enabled" : "Disabled");
        WatchUi.requestUpdate();
    }
}
```

- [x] **Step 2: Run the full unit suite**

Run: `./scripts/run-tests.sh fenix843mm`
Expected: `==> Tests passed`.

- [x] **Step 3: Commit**

```bash
git add source/menus/AppSettingsMenu.mc
git commit -m "Add an on-watch Wide Barcode toggle"
```

---

### Task 4: Simulator verification and PR screenshots

**Files:**
- Modify: `integration/SimulatorIntegrationTest.mc`

**Interfaces:**
- Consumes: the built app from Tasks 1-3, and the `integrationSeedIssue35Barcode` fixture already committed in `integration/SimulatorIntegrationTest.mc`.

- [x] **Step 1: Add a second fixture that also turns wide mode on**

There is no scriptable way to drive the on-watch menu from `monkeydo`, so add a fixture that seeds
the same payload with the property already flipped — mechanical and reproducible, matching how
every other fixture in this file sets up state. In `integration/SimulatorIntegrationTest.mc`, after
`integrationSeedIssue35Barcode`, add:

```monkeyc
//! Same payload as integrationSeedIssue35Barcode, with wide mode already on -- for a matched
//! before/after screenshot pair.
//!
//!     monkeydo bin/integration.prg fenix843mm -t integrationSeedIssue35BarcodeWide
(:test)
function integrationSeedIssue35BarcodeWide(logger as Test.Logger) as Boolean {
    for (var slot = 0; slot < CodeStore.MAX_CODES; slot++) {
        CodeStore.deleteSlot(slot);
    }
    Storage.deleteValue(CodeStore.PENDING_SLOTS);
    Application.Properties.setValue(
        CodeStore.PROP_CODES, [] as Array<Application.PropertyValueType>);
    Application.Properties.setValue(CodeGeneration.SETTING, true);
    Application.Properties.setValue(WideBarcode.SETTING, true);

    CodeStore.save(0, "Club card", "FFCC12345", CodeStore.TYPE_BARCODE);
    CodeStore.publishProperties();

    Test.assertMessage(WideBarcode.enabled(), "wide mode is on for this fixture");
    Test.assertEqualMessage(CodeStore.count(), 1, "one code seeded");
    logger.debug("SEEDED issue #35 barcode with wide mode on");
    return true;
}
```

- [x] **Step 2: Build app and integration binaries**

```bash
SDK_BIN="$(dirname "$(command -v monkeyc)")"
DEVELOPER_KEY="$HOME/Documents/garmin-sdk/developer_key"
"$SDK_BIN/monkeyc" -o bin/app.prg -y "$DEVELOPER_KEY" -d fenix843mm -f monkey.jungle -w -l 2
"$SDK_BIN/monkeyc" -o bin/integration.prg -y "$DEVELOPER_KEY" -d fenix843mm -f monkey-integration.jungle -w -l 2 --unit-test
```
Expected: both `BUILD SUCCESSFUL`.

- [x] **Step 3: Screenshot with the toggle off (default)**

Ensure a simulator is running (`pgrep -x simulator`; if empty, start
`"$SDK_BIN/ConnectIQ.app/Contents/MacOS/simulator"` in the background and wait for port 1234 to
accept a connection), then:

```bash
"$SDK_BIN/monkeydo" bin/integration.prg fenix843mm -t integrationSeedIssue35Barcode
"$SDK_BIN/monkeydo" bin/app.prg fenix843mm &
sleep 6
```
Find the simulator window's position and size (System Events `position`/`size` of its window, as
done during exploration) and capture it:
```bash
screencapture -x -R<x>,<y>,<w>,<h> /tmp/issue35-after-default.png
```
Expected: same 2px-scale bars as the pre-fix screenshot from exploration — the always-on fix alone
does not change this specific payload (see design doc) — but confirm nothing regressed: still
centered, still legible, title and counter still drawn.

- [x] **Step 4: Screenshot with the toggle on**

Kill the running `app.prg`, reseed with the wide fixture, relaunch, and capture the same way:

```bash
kill %1 2>/dev/null
"$SDK_BIN/monkeydo" bin/integration.prg fenix843mm -t integrationSeedIssue35BarcodeWide
"$SDK_BIN/monkeydo" bin/app.prg fenix843mm &
sleep 6
screencapture -x -R<x>,<y>,<w>,<h> /tmp/issue35-after-wide.png
```
Expected: visibly thicker bars filling nearly the full screen width, matching the design doc's
predicted 410px/scale-3 result.

- [x] **Step 5: Commit the new fixture**

```bash
git add integration/SimulatorIntegrationTest.mc
git commit -m "Add a simulator fixture for wide-mode barcode screenshots"
```

- [x] **Step 6: Attach both screenshots to the PR description** when opening the PR for this change (per the user's request to include screenshots the way this conversation's exploration did).
