This is a Garmin application, using Monkey-C with SDK compatibility 5.0.0 or later.

The project uses Github to manage the codebase and issues.

Answer all questions taking into account the kind of application this is (Garmin SDK).

When possible, give code suggestions directly in the response.

## Project layout

- `source/App.mc` — entry point only: lifecycle and view wiring.
- `source/CodeStore.mc` — the only place that knows Storage keys and the `codesList` settings
  schema.
- `source/ImageService.mc` — URL building, the download queue, retry policy, image cache.
- `source/Connectivity.mc`, `source/Backlight.mc`, `source/Haptics.mc`, `source/Log.mc` —
  small single-purpose helpers.
- `source/views/`, `source/menus/` — UI.
- `source/tests/` — `(:test)` functions, run with `./scripts/run-tests.sh`.

## Rules that past bugs came from

- **Compare Strings with `.equals()`, never `==` or `!=`.** Monkey C compares String references,
  so two equal strings are never `==`. Using `!=` to detect a changed code invalidated the image
  cache on every single load.
- **The glance process only links symbols annotated `(:glance)`.** `GlanceView` and `CodeStore`
  have it. Anything else the glance touches needs it too, or the glance is blank at runtime with
  no compile error. Keep everything else out — the glance memory budget is a fraction of the
  app's. `App.initialize`/`onStart`/`onStop` run in the glance process too, so they must not
  reach app-only code.
- **Never write anything into `codesList` that `resources/settings.xml` does not declare**, and
  never leave `null` holes in it. Both make the phone-side settings editor fail to save.
- **Percent-encode code text before putting it in a URL** (`Communications.encodeURL`). A raw `&`
  truncates the payload.
- **`System.getTimer()` is milliseconds since power-on, not a clock.** It is fine for measuring a
  backoff inside one session and useless for deciding which of two saved copies is newer.
- **Guard optional hardware**: `Attention.vibrate` does not exist on Edge devices, and
  `Attention.backlight` throws once the display has been held on for about a minute.
- Build with `-w -l 2`. The type checker is what catches missing glance symbols.
