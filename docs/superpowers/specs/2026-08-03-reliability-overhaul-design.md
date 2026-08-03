# Reliability overhaul — design

Date: 2026-08-03
Status: approved for implementation

## Problem

Users report the app "doesn't work": codes stay on `Loading image...`, barcodes render as QR
codes, URLs containing `&` are truncated, and editing settings from Connect IQ throws an error
after the app has been opened once.

All of the app (2071 lines) lives in `source/App.mc`, with data access, networking, sync,
rendering and menu handling interleaved. There are no tests and CI only compiles one device.

## Root causes (verified in the Connect IQ simulator, SDK 8.4.1)

A probe harness was compiled and run in the simulator to settle the semantics that the
diagnosis depends on. Results:

| Probe | Result |
|---|---|
| `storedString == equalLiteral` | **`false`** — `==` on `String` is reference equality |
| `Number(1).equals("1")` | **`false`** |
| `"abc".substring(0, 20)` | `"abc"` — out-of-range end is clamped, does not throw |
| `Communications.encodeURL("...?a=1&b=2 x+y#z")` | `...%3Fa%3D1%26b%3D2%20x%2By%23z` |

### C1 — Cache invalidation compares strings by reference

`refreshMissingImages()` decides whether a cached image is stale with:

```monkeyc
if (text != cachedText || currentType != cachedType || cachedText == null) { ... }
```

Both operands are separate `String` objects read from `Storage`, so `!=` is **always true**.
Every load therefore deletes every cached image and re-downloads every code. This is the
primary defect. It explains issue #13 (slow to display), defeats the offline support added for
issue #15, and — combined with C2 — is why codes get stuck on `Loading image...`.

### C2 — One global download lock, no queue, no timeout

`isDownloading` is a single boolean. `downloadImage()` returns immediately when it is set, and
the caller is not retried or queued. With N codes needing images, N-1 requests are silently
dropped; the remaining ones only get another chance if something happens to call `onUpdate`
again. If a callback never arrives (dropped BLE connection mid-request) the flag stays `true`
for the lifetime of the app and **no code ever loads again**. A 2-second global throttle drops
requests the same way.

### C3 — In-flight request is keyed by array position

`downloadingImageIdx` is an index into the `images` array. Any `loadAllCodes()` while a request
is in flight (settings change, refresh, add, delete) rebuilds that array, so the callback writes
the downloaded bitmap into a **different code's** slot, or out of range.

### C4 — Text is concatenated into the URL unencoded (issue #31)

```monkeyc
url = "https://qr-gen.adrianmoreno.info/qr?text=" + text;
```

`&`, `#`, `+`, space, `%` and `=` all corrupt the request. Confirmed against the live service:
the URL the old code built for `http://abc.com?a=1&b=2` returns a PNG **byte-identical** to the
one for `http://abc.com?a=1`, so the watch really was displaying a QR code of the truncated URL,
exactly as reported. The percent-encoded URL returns a different image.

### C5 — App writes keys into `codesList` that the settings schema does not declare (issue #30)

`resources/settings.xml` declares three keys per entry: `code_$index_type`, `code_$index_title`,
`code_$index_text`. The app writes a fourth, `code_$index_timestamp`, back into the array on
every startup, and `ConfirmDeleteDelegate` writes a literal `null` into the array on delete.
The Connect IQ settings editor then fails to save. The reproduction in issue #30 — install,
configure, **open the app**, edit settings again, error — matches the startup write exactly.

The timestamps are useless anyway: they come from `System.getTimer()`, which is milliseconds
since device power-on, so the "newer version wins" arbitration between Storage and Properties
compares two unrelated clocks.

### C6 — Code type is assumed to be a `String`

`codeType.equals("1")` is `false` when the settings editor round-trips the list value as a
`Number`, so the code renders as a QR instead of a barcode. This matches the follow-up report on
issue #9 ("code is always saved as a qr code - even if I choose a barcode option").

### C7 — Delete leaves the cached image behind

`ConfirmDeleteDelegate` removes `code_N_text/title/type` but not `qr_image_N`,
`qr_image_meta_*_N` or `code_N_timestamp`. `AddCodeMenu2InputDelegate` allocates the first free
slot, so the next code added reuses slot N and initially displays the **previous** code's image.

### C8 — Offline queue is wiped at every startup

`checkPendingSync()` deletes `pendingSyncImages` and resets the queue on every launch, so the
queue promised by issue #15 never survives a restart.

### C9 — `onSettingsChanged` clears every cached image

Even codes that did not change lose their image. Changing one code while offline leaves the
user with no codes at all.

### C10 — Downloads are triggered from `onUpdate`

Rendering performs network I/O and calls `requestUpdate()`, which can re-enter the draw path.

### C11 — The whole app is linked into the glance process

The compiler reports: `The entry point '$.App' was implicitly added to the glance process`.
The 5-second connectivity timer, the sync queue and the Storage/Properties arbitration are all
loaded in the memory-constrained glance context.

### C12 — `keepScreenOn` does nothing

`setAttentionMode()` calls `WatchUi.requestUpdate()` and nothing else. The feature shipped for
issue #24 is a no-op.

### C13 — Slot count disagrees with the settings schema

The code loops over 10 slots; `settings.xml` sets `maxLength="4"`.

### C14 — The glance links only `(:glance)` symbols

Found while refactoring, and it constrains the design. The glance process contains the entry
point plus whatever carries the `(:glance)` annotation, and *nothing else*. Anything the glance
view calls has to be annotated too, or it is missing at runtime — a blank glance with no
compile error at the default type-check level. `monkeyc -l 2` reports it as
"Value 'X' not available in all function scopes", which is why the type checker belongs in CI.

## Design

### Module structure

`source/App.mc` is split along the seams that the defects fall on. Each unit owns one concern
and can be reasoned about — and tested — on its own.

```
source/
  App.mc              AppBase only: lifecycle, view wiring, onSettingsChanged
  Log.mc              logging, compiled out of release builds via (:debug)
  CodeStore.mc        the only code that knows Storage keys and the Properties schema
  ImageService.mc     URL building, download queue, retry policy, image cache
  Connectivity.mc     phone connection state and change notification
  views/
    AppView.mc        rendering and input for the code screen
    GlanceView.mc     glance rendering, reads Storage only
    AboutView.mc      about screen
  menus/
    CodeMenu.mc       code info / actions menu
    AddCodeMenu.mc    add-code flow
    AppSettingsMenu.mc on-watch settings
  tests/
    *Test.mc          (:test) functions, excluded from normal builds
```

`CodeStore` and `ImageService` are modules with no UI dependency, which is what makes the
regression tests possible.

### CodeStore

Owns every `Storage` key and the `codesList` property. Storage key names are unchanged, so
existing installs keep their data.

```
MAX_CODES = 10

count()                         number of populated slots
occupiedSlots()                 array of storage indices, ascending
getText/getTitle/getType(slot)  getType normalises Number|String -> "0"|"1"
save(slot, title, text, type)   writes Storage, then republishes Properties
deleteSlot(slot)                deletes every key for the slot, including the image cache
nextFreeSlot()
cachedImage(slot)               null when absent or stale
putImage(slot, bitmap)          stores image plus the text/type it was generated from
clearImage(slot)
isCacheValid(slot)              String.equals comparison against stored metadata
adoptProperties()               Properties -> Storage, invalidating only changed slots
publishProperties()             Storage -> Properties, no-op when already identical
```

Fixes C1 (`.equals`), C5 (only schema keys are written, array is compacted, no `null` entries,
no timestamps), C6 (normalisation at the boundary), C7 (`deleteSlot` clears the image), C9
(`adoptProperties` invalidates per slot), C13 (one constant, `settings.xml` raised to match).

Storage/Properties arbitration replaces the meaningless timestamp comparison with a rule that
follows the data flow: Properties is what the phone last pushed, so **Properties wins whenever
it is non-empty**; when it is empty and Storage is not — codes added on the watch that have not
been published yet — Storage is published to Properties. Both directions write only the three
declared keys.

### ImageService

A FIFO queue with exactly one request in flight.

```
enqueue(slot)     ignored when already queued, in flight, or validly cached
pump()            starts the next request when nothing is in flight
onResponse()      resolves against the in-flight *storage* index, caches, pumps the next
onTimeout()       watchdog: releases the lock, applies backoff, pumps the next
```

- The in-flight identity is the storage slot, not an array position, so a concurrent
  `loadAllCodes()` cannot misroute a response (C3).
- A 20-second watchdog timer guarantees the lock is always released (C2).
- The queue drains itself on every completion, so N codes produce N downloads (C2).
- Retry uses exponential backoff (5s, 10s, 20s, 40s, capped at 60s, max 4 attempts). HTTP 4xx is
  permanent and is not retried. Failures are recorded per slot with the response code so the UI
  can distinguish "offline" from "server error" from "bad data".
- URLs are built as `base + "?text=" + Communications.encodeURL(text)` (C4).

### Connectivity

Wraps `System.getDeviceSettings().phoneConnected`, keeps the last state, and notifies a listener
on transition. Polling drops from 5s to 15s — the app is foreground-only and a code screen does
not need 5-second granularity — and the timer is only started once the main view exists, never
in the glance process (C11).

### Views

`AppView.onUpdate` becomes pure rendering: it draws whatever `CodeStore`/`ImageService` currently
hold and never starts a download (C10). Loads are kicked off from `initialize`, `onShow`,
navigation, and connectivity-restored callbacks.

`GlanceView` moves to its own file and only reads Storage. It and `CodeStore` carry
`(:glance)`; everything else — the queue, the connectivity timer, the backlight holder, the
full-screen views and the menus — does not, so none of it is linked into the glance process
(C14). `App`'s own hooks are the exception, because the entry point is always in both processes:
`initialize` and `onStart` do no work at all, and `onStop` is gated on a `started` flag that only
`getInitialView` sets, so the glance never reaches app-only code.

`keepScreenOn` is implemented with `Attention.backlight(true)`, re-armed on a 25-second timer,
stopped after two minutes, and wrapped in try/catch for `BacklightOnTooLongException` (C12).

### Offline behaviour

`ImageService`'s queue is persisted as a compact array of slot indices and restored at startup
(C8). When offline, `AppView` shows the cached image if there is one and an explicit
`Offline — will sync` state if there is not. Reconnection triggers a pump.

## Testing

Connect IQ `(:test)` functions run in the simulator via `monkeyc --unit-test` + `monkeydo -t`;
they are excluded from normal builds. Coverage targets the pure logic where the defects were:

- URL encoding: `&`, spaces, `+`, `#`, `%`, unicode; QR vs barcode endpoint selection.
- Type normalisation: `"0"`, `"1"`, `0`, `1`, `null`, garbage.
- Cache validity: matching metadata, changed text, changed type, missing metadata — the
  regression test for C1, which fails against `!=`.
- Slot lifecycle: save, allocate, delete clears the image, slot reuse does not resurrect the old
  image (C7).
- Properties round-trip: only declared keys, compacted, no nulls (C5).
- Queue behaviour: dedupe, one in flight, drain on completion, watchdog release, backoff, 4xx is
  permanent (C2, C3).

## CI

- Compile with `-l 2` (type checking on) and fail the build on any `ERROR` line. Level 2 is the
  level that reports missing glance symbols; level 3 additionally demands full type annotations
  on the Toybox callback surface and is not worth the churn here.
- Build a device matrix covering the screen and input classes actually shipped: `fenix7pro`,
  `fenix847mm`, `venu3`, `vivoactive6`, `fr165`, `edge1040`, `instinct3amoled45mm`,
  `approachs50`.
- Run the unit tests in the simulator via `scripts/run-tests.sh`. `monkeydo` exits 1 whatever
  happens, so the script parses its summary line instead of trusting the exit code.
- Keep the existing release job unchanged.

## Result

Measured on `vivoactive6`, release build, before and after:

| | before | after |
|---|---:|---:|
| Glance data | 4989 B | 1584 B |
| Glance code | 6510 B | 4342 B |
| Foreground data | 11652 B | 5359 B |
| Foreground code | 19542 B | 14725 B |
| Total PRG | 58620 B | 40940 B |

(The PRG figure also reflects dropping four bitmap resources and two layouts that nothing
referenced any more.)

35 unit tests pass. Reintroducing the original `!=` cache comparison, the unencoded URL and the
delete-without-clearing-the-image behaviour makes 9 of them fail, so they are regression tests
for the reported defects rather than descriptions of the new code.

## Out of scope

- Changing the code-generation service or its API.
- Changing the app id in `manifest.xml` (would orphan installed users' settings).
- Redesigning the settings editor UX.
