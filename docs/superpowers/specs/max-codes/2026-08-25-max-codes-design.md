# Raising MAX_CODES and guarding against storage exhaustion — design

Date: 2026-08-25
Status: approved for implementation

## Problem

A user asked whether the code limit could go from 10 (this repo's current value; they were
testing an older build still at 4) to 50. Investigation turned up two separate questions:

1. Is there headroom to raise the ceiling at all?
2. What happens when a device actually runs out of storage while adding a code?

For (1): the Connect IQ `watchApp` memory budget on the fenix 7 and fenix 8 families (per the
installed SDK's `compiler.json`) is 786,432 bytes (768 KB), shared by the whole running app. Each
saved code costs at most ~4.8 KB of `Application.Storage` (a 256-character payload pushed to QR
version 12, the largest this app's encoder builds: a 65×65 matrix stored as one byte per module,
plus the text/title/type/meta strings). 20 codes worst-case is under 100 KB — comfortable headroom
under the ceiling, and a smaller jump than 50 to validate before considering going further.

For (2): Garmin's own docs for `Storage.setValue` say plainly: *"There is a limit on the size of
the Object Store that can vary between devices. If you reach this limit, the value will not be
saved and an exception will be thrown"* (`Lang.StorageFullException`, a catchable `Lang.Exception`
subclass). The per-device limit is undocumented and not queryable ahead of time — so the only
reliable signal is the exception itself.

Auditing every `Storage.setValue` call in `CodeStore.mc` found that the generated-code caches
(`putMatrix`, `putBars`, `putImage`) already catch and log this failure, degrading gracefully (a
code that can't be cached just regenerates on next view instead of crashing). The one gap is
`save()` — the three writes that create a new code (text, title, type) are unguarded. A
`StorageFullException` there is an uncaught exception on the add-code path.

Separately, `AddCodeMenu.save()` already had one silent failure mode fixed before (commit
`dd0071c`: saving with empty text used to fail with only a `Log.debug`, invisible on a real
device, now shows a `WatchUi.Confirmation`). The "no free slot" case (`nextFreeSlot()` returns
`-1`) has the same bug today — `Log.warn` only, nothing on screen — and is fixed here as the same
class of issue.

## Design

### 1. Raise the ceiling

- `CodeStore.MAX_CODES`: 10 → 20 ([CodeStore.mc:23](../../../../source/CodeStore.mc)).
- `resources/settings.xml`: `<setting propertyKey="@Properties.codesList" ... maxLength="10">` →
  `maxLength="20"`. The existing comment above it ("Must stay in step with CodeStore.MAX_CODES")
  is the reason these two never drift independently.

### 2. Guard `CodeStore.save()` against storage exhaustion

`save()` changes from `Void` to `Boolean` (`true` on success). The three `Storage.setValue` calls
move into a `try`/`catch`. On any exception:

- Roll back by deleting whatever of `textKey(slot)`, `titleKey(slot)`, `typeKey(slot)` was
  written for that slot, so a failed save never leaves a slot half-populated (which would make
  `occupiedSlots()` count it as used with no readable title/type).
- Log the failure (matching the existing `Log.warn(... + e.getErrorMessage())` style used
  elsewhere in this file).
- Return `false`.

This is a narrow, mechanical change: the try/catch/rollback pattern already exists three times in
this file for the generated-code caches; `save()` gets the same treatment it was missing.

### 3. Surface both failures in `AddCodeMenu`

`AddCodeMenu.save()` gets two new visible failures, both using the `WatchUi.Confirmation` +
acknowledge-delegate pattern `dd0071c` established:

- `CodeStore.save(...)` returns `false` → `"Not enough space to save this code"`.
- `CodeStore.nextFreeSlot()` returns `-1` → `"All 20 code slots are full"`.

The existing `EmptyCodeDelegate` (a `ConfirmationDelegate` whose `onResponse` just returns `true`)
has no state and no logic specific to the empty-text case — it's reused for these too rather than
adding two near-identical classes.

### 4. Explicitly out of scope

No proactive "running low on space" estimate. There's no API to query remaining Object Store
size, and the per-device ceiling is undocumented, so an estimate would be a guess with nothing to
validate it against. `StorageFullException` is the actual ground truth the platform gives us, and
the design uses it directly rather than trying to predict it.

## Testing

- `source/tests/CodeStoreTest.mc` runs against the real `Storage` module (no mock/injection layer
  exists in this codebase for it — every existing test, including `TestSupport.mc`, writes through
  real `Storage`). That means the rollback branch itself (deleting partial keys after a caught
  exception) cannot be triggered from a unit test without a way to force `Storage.setValue` to
  throw, which nothing in this codebase currently provides. Adding a general Storage-mocking seam
  is out of scope for this change — over-engineering for a single failure path.
- What *is* unit-testable and will be covered: `save()`'s success path still returns `true` and
  behaves exactly as before; `MAX_CODES` moving to 20 is exercised by existing loop-based tests
  that already iterate `0 ..< MAX_CODES` (e.g. `TestSupport.mc`'s cleanup, `Migration.mc`'s
  loops) — these adapt automatically since they read the constant rather than hardcoding 10.
- The `AddCodeMenu` `Confirmation` UI paths are not unit-tested, matching how this file's existing
  empty-text `Confirmation` (`dd0071c`) and the rest of the menu layer (`AppSettingsMenu`,
  `CodeMenu`) have no test coverage — verified against the API contract instead.
- Manual simulator pass: fill 20 slots with max-length (256-char) text on the fenix7 and
  fenix843mm device profiles, confirm no crash, confirm the 21st add attempt shows the "all slots
  full" message.
