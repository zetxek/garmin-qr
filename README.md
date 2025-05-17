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

### Project Structure

- `source/App.mc`: Main application code
- `resources/`: UI resources and assets
- `manifest.xml`: App configuration and device support

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change.

### Issues

If you find a bug or have a feature request, please open an issue in the [GitHub issue tracker](https://github.com/zetxek/garmin-qr/issues).
