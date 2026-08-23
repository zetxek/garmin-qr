# Code screen UX: setting name and the counter — design

Date: 2026-08-22
Status: approved for implementation

## Problem

Two things surfaced while using the [wide-barcode](../wide-barcode/2026-08-20-wide-barcode-design.md)
build on a real fenix 8S 43mm:

1. The setting was called **"Wide Barcode"**, which names the mechanism. Someone opens that menu
   because a code will not scan, not because they want a wider one.
2. The code screen always drew **"Code 1 of 1"** — the common case for a user with a single code,
   and it states the obvious.

This also raised a broader question: should the setting generalise to a "reduced margin" mode
covering QR codes too, or become a code *type*?

## Why it does not generalise (the load-bearing finding)

A barcode and a QR are limited by **different** things, so one "use more of the screen" setting
cannot serve both honestly. Measured on a fenix 8S 43mm (416×416, round):

| | ceiling | today | gain from reclaiming layout chrome | gain from a thinner quiet zone |
|---|---|---|---|---|
| **Barcode** (134 modules) | 416px — a horizontal strip crosses the full diameter | 391px box | — (chrome costs height, not width) | **2px → 3px bars (+50%)** |
| **QR** (29×29, a typical URL) | **294px** — the largest square a round screen can show (416/√2) | 276px box | **0%** — the integer scale stays at 7 | +14% |

The QR is already within ~6% of its geometric ceiling. Reclaiming the counter's height buys a
typical URL QR *exactly zero* extra module size, because the scale is integer and 294/37 still
truncates to 7.

Two further asymmetries:

- Code 128's 10-module quiet zone is a **recommendation**; QR's 4-module one is **mandatory** and
  is how a scanner isolates the finder patterns. Cutting it is a worse trade.
- The reported problem (issue #35) was barcode-only. No QR complaint exists.

So "reduced margin for both" would add surface area to deliver ~0–25% on codes nobody has
complained about. Rejected.

**"Wide barcode" as a code type** was also rejected: type means *symbology* (what the code is),
while wide means *how to draw it*. Merging them needs four types the moment a wide QR is wanted,
and puts a non-symbology value into `code_$index_type` — the per-entry schema whose undeclared
keys broke the Connect IQ settings editor in issue #30. Its instinct (the need is per-code, not
per-watch) is right, but is deferred until someone reports wide mode breaking a *different* card.

## Design

### 1. Rename the setting

`AppSettingsMenu` shows **"Thicker bars"** instead of "Wide Barcode". At 12 characters it is
shorter than the already-shipping "Keep Screen On" (14), so it cannot truncate.

The property key stays `wideBarcode`. Renaming it would orphan the value on watches that already
have it set. The module keeps its `WideBarcode` name for the same reason; only the user-facing
string changes.

Rejected: "Thicker bars (old scanners)" — 26 characters, nearly double the longest shipping label,
and very likely to truncate.

### 2. Draw the counter only when there is something to count

`AppView.showsCounter()` returns `slots.size() > 1`; `drawCounter` returns early otherwise.

**This is decluttering, not a size win, deliberately.** The counter's height stays reserved in
`drawGeneratedCode`, so the code neither moves nor grows. Reclaiming it was considered and
rejected for two concrete reasons:

- It would push the code **down**, not centre it. The box is `[top, height - counterHeight]`;
  with `counterHeight = 0` and a title still pushing `top` to 82, the centre moves from 220 to
  249 — further from the screen centre (208) than it is now.
- It would let a QR exceed the 294px inscribed square, clipping the corners its finder patterns
  sit in. `drawQr` currently bounds by `width` (416), which is wrong for a round screen and would
  need an inscribed-square cap first.

Both belong to a separate layout/geometry change.

## Testing

`AppView.showsCounter()` exists as a seam so the rule is unit-testable without a `Dc`:
`aLoneCodeGetsNoCounter` asserts no counter with one code, and that it returns with two.

The rename has no seam worth testing — it is a display string. Its only risk is truncation, ruled
out by length comparison against shipping labels.

Both verified on the simulator with matched before/after captures of the same seeded payload,
committed under `screenshots/`.

## Out of scope

- Reclaiming the counter's height, and the round-screen inscribed-square cap for QR (above).
- Per-code scoping of the thicker-bars setting (above).
- Rotating a barcode along the screen diagonal (~588px vs 416px, ~41% longer at a full quiet
  zone). It is the only way to make a barcode meaningfully wider *without* trading quiet zone,
  but rendering rotated bars is far harder than `fillRectangle`.
