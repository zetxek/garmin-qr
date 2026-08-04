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

Three layers, all runnable locally and in CI.

### 1. Unit tests — `source/tests/`

Connect IQ `(:test)` functions, run in the simulator by `monkeyc --unit-test` + `monkeydo -t`,
and excluded from normal builds. They cover the pure logic where the defects were: URL
encoding, type normalisation, cache validity, slot lifecycle, the Properties round-trip, and
the queue's dedupe/backoff/permanent-failure rules.

### 2. App-flow tests — `source/tests/AppFlowTest.mc`

These boot the real `AppView` in the simulator and drive the real `ImageService`. Only the
radio call is replaced: `ImageService.transmit()` is a one-line seam that `FakeImageService`
overrides to record URLs instead of sending them. Everything either side of it — queueing,
dispatch order, callback routing, caching, recovery — is production code.

The seam is necessary, not just convenient. In the simulator `makeImageRequest` calls back
**synchronously** with `-101` when the phone data channel is unavailable, so a test using the
real radio would be asserting against the simulator's failures rather than its own scenario.
That behaviour also forced a note in `transmit()`: nothing may assume the callback is deferred,
which is why `inFlight` and the watchdog are both set before the request goes out.

These are the regression tests for the reported defects, and they were mutation-checked:

| Reintroduced defect | Result |
|---|---|
| `metaText != text` instead of `.equals` (C1) | 11 tests fail |
| remove the hand-off to the next queued download (C2) | 4 tests fail |

### 3. Simulator end-to-end — `scripts/simulator-test.sh`

The only layer that makes real HTTP requests. Storage persists between simulator invocations,
so the script runs three of them: seed two codes (one QR containing `&`, one barcode containing
a space) with no images, run the real app so it drains its queue against the live service, then
verify what was cached — both images present, attributed to the right codes, the QR square and
the barcode wider than tall, and a warm start queuing nothing.

The fixtures live in `integration/`, which only `monkey-integration.jungle` compiles, so they
never run as part of the unit suite. Note the SDK's default `base.sourcePath` is `.\**.mc`,
which sweeps in every `.mc` file in the repository; `monkey.jungle` now pins it to `source`.

This layer is **not** in CI, because it needs a simulator that is signed in to Garmin Connect.
The simulator proxies app traffic through that account: until you sign in it shows a "Your
Garmin Connect credentials are required" prompt for every outbound request and the app sees
`-101`. The original code behaves identically there, so a CI failure would say nothing about
the app. It is a manual check to run before a release:

```
./scripts/simulator-test.sh fenix7pro
```

### Root cause of the download failures: Garmin bug CIQQA-3382

`makeImageRequest` does not fetch from the watch. It is proxied through Garmin's image service,
which fetches the URL itself and returns a transcoded bitmap. That proxy returns **404 for
domains it fails to fetch**, even when the URL is publicly reachable and returns 200 to every
normal client. Garmin acknowledged this as **CIQQA-3382** and it has been open for over a year;
`makeWebRequest` to the same host works, only `makeImageRequest` fails.

Measured in the simulator, signed in to Garmin Connect:

| Request | Result |
|---|---|
| `qr-gen.adrianmoreno.info/qr?text=HELLO&size=250` via `curl` | **200**, valid PNG |
| the same URL via `makeImageRequest` | **404** |
| the same URL, query passed as a params dictionary | **404** |
| a PNG on `raw.githubusercontent.com`, no query string | **200**, cached |
| the same PNG **with** a query string | **200**, cached |
| the original pre-refactor app, same seeded code | no image either |
| an `http://127.0.0.1` URL | 200 with an empty body — the proxy cannot reach localhost |

So the request path is correct, query strings are fine, and the behaviour is identical before
and after this change. The variable is the host: some domains the proxy can fetch, some it
cannot, and ours is currently in the second group.

Header negotiation was ruled out — `Accept`, `User-Agent`, HTTP version, and HEAD vs GET all
return 200 from a normal client. One difference worth trying on the service is caching: the
host that works sends `Cache-Control` and `ETag`, and `qr-gen` sends neither.

Two consequences for this app, both now fixed:

- **404 is no longer treated as permanent.** It was, so the first 404 stranded the code for the
  session and told the user "This code can't be generated. Check its text in settings." — which
  blamed them for a Garmin-side failure. 404 is now retried with backoff, and the message for it
  reads "Code service unavailable".
- **The service host is now a setting** (`serviceUrl`). Since the failure is domain-specific and
  outside this app's control, a working host can be pointed at from Garmin Express without
  waiting on an app-store release.

What this app cannot fix is the proxy itself. Worth trying on the `qr-generator` side: serving
from the Cloud Run `*.run.app` URL or another domain, and adding `Cache-Control`/`ETag` to
image responses.

### What the GUI pass confirmed

Driving the running app in the simulator, with codes seeded via `integrationSeedRendered`:

- the code screen draws the title, a centred code and `Code 1 of 2`;
- the down button moves to `Code 2 of 2` (issue #6 was codes not switching);
- the Code Info menu reports the right type and title;
- the glance draws its image and label in 12.6kB of the 59.8kB glance budget, which is the
  measurement behind C11;
- **restarting with every image cached produced no request at all** — the Connect login prompt
  never appeared. That is C1 fixed, visible end to end: previously every launch discarded the
  cache and re-fetched every code.

## CI

- Compile with type-check level 3.
- Build a device matrix covering the screen-size and input classes actually shipped:
  `fenix7pro`, `fenix847mm`, `venu3`, `vivoactive6`, `fr165`, `edge1040`,
  `instinct3amoled45mm`, `approachs50`.
- Run the unit and app-flow suites in the simulator on a virtual display.
- Keep the existing release job unchanged.

## Out of scope

- Changing the code-generation service or its API.
- Changing the app id in `manifest.xml` (would orphan installed users' settings).
- Redesigning the settings editor UX.
