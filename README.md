# Garmin QR + Barcode Generator

⌚️ A Connect IQ watch app for Garmin devices that allows you to generate and display QR codes and barcodes directly on your watch.
Using https://github.com/zetxek/qr-generator to generate QR codes and barcodes ☁️

![2025-05-17 22 21 58](https://github.com/user-attachments/assets/e23133ed-530a-461c-838f-a75362b8f734)


## Features

- Generate QR codes and barcodes from text input
- Store multiple codes for quick access
- View codes in both full app and glance view
- Edit or remove existing codes
- Support for various Garmin devices (Fenix, Epix, Edge, etc.)

## Supported Devices

- Fenix 7 & 8 series
- Epix 2 series
- Edge series
- Approach series
- And more (see manifest.xml for full list)

## Usage

1. Edit the app settings from Garmin Connect IQ app or Garmin Express
2. Open the app on your watch
3. The code will be generated and displayed
4. Use up/down keys to navigate between stored codes
5. Press enter to access options

## Managing Codes

You can manage your QR and barcode entries using the Garmin Connect IQ app or Garmin Express on your phone or computer:

- **Add a Code:**
  1. Open the app settings from the Connect IQ app or Garmin Express.
  2. Tap 'Add' or the plus (+) button to create a new code entry.
  3. Choose the code type (QR or Barcode), enter a title, and the text to encode.
  4. Save your changes and sync with your device.

- **Edit a Code:**
  1. In the app settings, tap on an existing code entry.
  2. Change the title, type, or text as needed.
  3. Save and sync.

- **Remove a Code:**
  1. In the app settings, tap the delete (trash) icon or swipe to remove a code entry.
  2. Save and sync.

- **Refresh Codes on Device:**
  - On your watch, open the app and press the menu button (key 4) to access the code menu.
  - Select 'Refresh Codes' to reload the latest codes from storage.

- **Navigate Codes:**
  - Use the up/down keys to switch between your saved codes.

- **About Screen:**
  - In the code menu, select 'About the app' to view app info and toggle between about text and a QR code for the GitHub repository by tapping the screen or pressing the start button.

## Development

### Prerequisites

- Garmin Connect IQ SDK
- VS Code with Connect IQ plugin (recommended)

### Building

1. Clone the repository
2. Open the project in VS Code
3. Build using the Connect IQ SDK

Build with type checking on — `monkeyc -w -l 2` — and treat its output as part of the build.
Level 2 is what reports a symbol that is missing from the glance process; without it a broken
glance compiles cleanly and only shows up as a blank widget on a watch.

### Testing

```bash
./scripts/run-tests.sh fenix7pro
```

Compiles the `(:test)` functions under `source/tests/`, runs them in the Connect IQ simulator
and reports the result. `monkeydo` exits 1 whether tests pass or fail, so the script reads its
summary line rather than the exit code.

The same script runs in the CI container image, which is the most reliable way to reproduce a
CI result locally:

```bash
docker run --rm --entrypoint bash -v "$PWD:/src" -w /src \
  -e DEVELOPER_KEY=developer_key.der ghcr.io/zetxek/connectiq-tester:latest \
  -c './scripts/run-tests.sh fenix7pro'
```

CI runs the same script. One thing to know if you touch that workflow: the job must pin
`HOME`. Hosted runners override it per step, and the simulator keeps its state under `$HOME` —
with the overridden value it starts and listens on its port but never answers `monkeydo`, and
the job produces no output at all.

Two kinds of test live there:

- **Unit tests** for the pure logic — URL encoding, code-type normalisation, cache validity,
  slot lifecycle, the settings round-trip, queue backoff.
- **App-flow tests** (`AppFlowTest.mc`) that boot the real `AppView` and drive the real
  download queue. Only the radio call is stubbed, via the `ImageService.transmit()` seam, so
  queueing, dispatch order, callback routing and caching are all production code. Tests must
  not use the real radio: in the simulator `makeImageRequest` calls back *synchronously* with
  `-101` when the phone data channel is unavailable.

### End-to-end check against the live service

```bash
./scripts/simulator-test.sh fenix7pro
```

Seeds two codes, runs the real app so it downloads them over HTTP, then verifies what was
cached. This is the only layer that touches the network, so it is a manual pre-release check
rather than part of CI. Its fixtures live in `integration/` and are compiled only by
`monkey-integration.jungle`.

**The simulator will not carry app traffic until you sign it in to Garmin Connect.** Until you
do, it puts up a "Your Garmin Connect credentials are required" prompt for every outbound
request and the app sees `-101`. If the check fails with "the download never completed", run
the diagnostic and look at `lastError`:

```bash
monkeydo bin/integration.prg fenix7pro -t integrationDump
```

To inspect the screen without any network at all, seed codes that already have cached images:

```bash
monkeydo bin/integration.prg fenix7pro -t integrationSeedRendered
```

### Project Structure

| Path | Responsibility |
| --- | --- |
| `source/App.mc` | Entry point: lifecycle and view wiring, nothing else |
| `source/CodeStore.mc` | The only code that knows Storage keys and the settings schema |
| `source/ImageService.mc` | URL building, the download queue, retries, image cache |
| `source/Connectivity.mc` | Phone reachability, and the heartbeat that retries downloads |
| `source/Backlight.mc` | The "keep screen on" setting |
| `source/Haptics.mc` | Vibration, guarded for devices without a motor |
| `source/Log.mc` | Logging, compiled out of release builds |
| `source/views/` | `AppView`, `GlanceView`, `AboutView` |
| `source/menus/` | Menu construction and input delegates |
| `source/tests/` | Unit tests, excluded from normal builds |
| `resources/` | UI resources, strings and the settings schema |
| `manifest.xml` | App configuration and device support |

Two rules are worth knowing before changing anything:

- **Compare Strings with `.equals()`, never `==`.** In Monkey C `==` on Strings compares
  references, so two equal strings read from storage are never `==`. This caused the image cache
  to be discarded on every load.
- **The glance process only links `(:glance)` symbols.** `GlanceView` and `CodeStore` carry that
  annotation. Anything the glance needs must have it too, and anything it does not need should
  not, because the glance has a much smaller memory budget than the app.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change.

### Issues

If you find a bug or have a feature request, please open an issue in the [GitHub issue tracker](https://github.com/zetxek/garmin-qr/issues).
