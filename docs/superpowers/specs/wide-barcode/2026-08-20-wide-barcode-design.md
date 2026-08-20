# Wider Code 128 barcodes — design

Date: 2026-08-20
Status: approved for implementation

## Problem

[Issue #35](https://github.com/zetxek/garmin-qr/issues/35): a barcode for the text `FFCC12345`
won't scan on an older club barcode reader. The reporter's own suggestion: *"add an option to
fill the watch display width"*.

## Root cause (verified in the Connect IQ simulator, fenix843mm)

Barcodes are generated on-device by `Code128.encode` and laid out by
`CodeRenderer.barcodeLayout` (`source/CodeRenderer.mc:61`) — not downloaded images. The fenix843mm
screen is 416×416px (confirmed from the installed SDK's device config). `Code128.encode("FFCC12345")`
produces **134 modules**. `AppView.drawGeneratedCode` gives the barcode box 94% of the screen
width: `(416 * 0.94).toNumber() = 391`px.

`barcodeLayout` picks the largest whole-pixel scale such that *bars plus a full 10-module quiet
zone* fit in the available width:

```monkeyc
var scale = available / (moduleCount + (2 * quietModules));  // quietModules = 10
```

For this payload: `391 / (134 + 20) = 391 / 154 = 2` (integer division). The bars alone would fit
at scale 3 (`134 * 3 = 402 <= 416`, the full screen), but the formula charges the ideal quiet zone
*before* it will consider a bigger scale, so it never gets there — landing on 2px bars and using
only 308 of the 391px it was given. Confirmed by seeding this exact payload
(`integrationSeedIssue35Barcode` in `integration/SimulatorIntegrationTest.mc`) and screenshotting
the running simulator: a clearly under-filled white block, black margin visible on both sides
beyond the drawn quiet zone.

This is a real physical constraint, not just a rendering bug: getting from 2px to 3px bars for a
134-module payload on a 416px screen requires using ≥402 of 416px for bars alone, which leaves
room for at most a token quiet zone. There is no default that is both "safe for every existing
barcode" and "fixes this specific case" — the two are in tension, which is why the issue asks for
an *option* rather than a behavior change.

## Design

Two independent changes to `CodeRenderer.barcodeLayout`, gated by a new `wide as Boolean`
parameter:

1. **Always on** — stop requiring the full 10-module quiet zone before picking a larger scale.
   The scale is chosen against a small 2-module floor instead; the *drawn* quiet zone still caps
   at the ideal 10 modules whenever there's room (unchanged). This recovers scale in borderline
   cases within the existing width allocation, with no new setting and no behavior change for
   payloads that were already at their limit. Verified by hand against the three existing
   `barcodeLayout` tests in `source/tests/AppFlowTest.mc:474` — all three still pass unchanged,
   since none of them sit in the borderline this affects.

2. **Opt-in "Wide Barcode" toggle**, default off — the lever that actually fixes issue #35. When
   enabled: the width allocation goes from 94%→99% (AppView) / 96%→99% (GlanceView), and the
   layout floor drops to 1 module. For the issue's own payload this yields scale 3 (`134*3=402
   <= 411`), a 50% increase in bar width, at the cost of a ~4px (~1.3-module) quiet zone — well
   under the Code 128 spec's 10x recommendation. Likely fine for most modern scanners, a real
   departure from spec for stricter ones, which is exactly why this is opt-in rather than
   default.

   The toggle lives on-watch only (Settings menu, next to "Keep Screen On"), not synced from the
   phone: this is a "flip it right before I scan" control tied to a specific reader, not a
   standing preference.

### Files

- **`source/WideBarcode.mc`** (new) — settings-read module, mirrors `source/CodeGeneration.mc`
  exactly: `SETTING = "wideBarcode"`, `enabled()` reads `Application.Properties`, defaults to
  `false` on any error or unset value.
- **`resources/drawables/properties.xml`** — register `wideBarcode` as a `boolean` property,
  default `false`. Deliberately *not* added to `resources/settings.xml`, so it does not appear as
  a phone-side (Garmin Connect/Express) setting.
- **`source/CodeRenderer.mc`** — `barcodeLayout(moduleCount, available, wide)` and
  `drawBarcode(..., wide)` gain the new parameter; the floor is 2 modules when `wide` is `false`,
  1 when `true`. The ideal 10-module cap is unchanged in both cases.
- **`source/views/AppView.mc`** — `drawGeneratedCode()` reads `WideBarcode.enabled()` once per
  frame, picks the width fraction (0.94 / 0.99), and passes `wide` through to
  `CodeRenderer.drawBarcode`.
- **`source/views/GlanceView.mc`** — `drawGeneratedBarcode()` gets the same treatment (0.96 /
  0.99). Reads the property directly rather than through `App`, since the glance process never
  runs `App.loadSettings()`.
- **`source/menus/AppSettingsMenu.mc`** — new `WatchUi.MenuItem` and delegate case for
  `:toggle_wide_barcode`, following the existing `:toggle_keep_screen_on` pattern exactly
  (read current value, flip, persist via `Application.Properties.setValue`, update the sublabel,
  `WatchUi.requestUpdate()`).

## Testing

- **`source/tests/AppFlowTest.mc`** — update the three existing `CodeRenderer.barcodeLayout(...)`
  call sites to pass `false` (they test today's default behavior). Add a test asserting that for
  the issue's own "FFCC12345" payload, `wide=true` picks a strictly larger scale than
  `wide=false`, and that the wide layout still fits within the width it was given (no clipping).
- **`integration/SimulatorIntegrationTest.mc`** — `integrationSeedIssue35Barcode` (already added
  during exploration) seeds the exact reported payload for a live visual check in the simulator.
- Before opening the PR: capture matched before/after screenshots in the simulator (toggle off vs
  on) for the PR description, the way the exploration in this conversation did.

## Out of scope

- QR codes — square 2D codes don't have the same "thin line" scanning problem and are unaffected.
- A phone-side (Garmin Connect/Express) setting for the toggle — on-watch only, see above.
- Changing barcode *height* — the issue is specifically about bar width/thickness.
- Alternate symbologies or further Code 128 subset optimizations.
