# Connect IQ store assets

Upload these in the developer portal (Edit App Details). All were checked against the portal's limits.

| File | Portal field | Limit |
| --- | --- | --- |
| `hero-1440x720.png` | Hero Image | 1440×720, ≤ 2048 KB |
| `cover-500.png` | Cover Image (Web/Mobile). This is also the icon shown in store lists. | 500×500, < 300 KB |
| `icon-128-24bit.png` | On-device icon, 24-bit (AMOLED) | 128×128 |
| `icon-128-64color.png` | On-device icon, 64-colour (MIP) | 128×128, 64-colour palette |
| `screen-1…5-*.jpg` | Screen Images (up to 5, in this order) | < 150 KB each |
| `preview-1080p.mp4` | Preview Video. Upload to YouTube or Vimeo, then paste the link. | link only |

The cover/icon follows Garmin's brand guidelines: solid non-black background, 10 px or more of padding,
no text, no Garmin marks.

## Regenerating

Everything is built by `scripts/make-store-assets.py` from simulator captures of the fenix 8 43mm
(`fenix843mm`, the model in `source/`).

```bash
python3 scripts/make-store-assets.py prep <dir-with-simulator-window-captures>   # refresh source/
python3 scripts/make-store-assets.py build [hero|icons|screens|video|all]
```

`prep` expects full-window captures named `qr`, `bar`, `wifi`, `info`, `settings`, `sortby` and `glance`.
Capturing them takes some tricks:

- Take the capture with `screencapture -x -o -l <window id>`. The simulator's own File > Save Screen
  Capture writes to `~/Documents` and turns `/` in a typed path into `:`.
- The glance only appears if `Glance=1` is set in
  `~/Library/Application Support/Garmin/ConnectIQ/simulator.ini` while the simulator is closed.
  Set it back to `0` afterwards.
- The sample codes (Concert ticket, Gym card, Home Wi-Fi, ...) are seeded with a throwaway
  `(:test)` function that calls `CodeStore.save`, the way `integration/` does.
