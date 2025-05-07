# Garmin QR + Barcode Generator

A Connect IQ watch app for Garmin devices that allows you to generate and display QR codes and barcodes directly on your watch.

## Features

- Generate QR codes and barcodes from text input
- Store multiple codes for quick access
- View codes in both full app and glance view
- Edit or remove existing codes
- Support for various Garmin devices (Fenix, Epix, Edge, etc.)

## Supported Devices

- Fenix 7 series
- Epix 2 series
- Edge series
- Approach series
- And more (see manifest.xml for full list)

## Usage

1. Open the app on your watch
2. Press any key to add a new code
3. Select code type (QR or Barcode)
4. Enter the text to encode
5. The code will be generated and displayed
6. Use up/down keys to navigate between stored codes
7. Press enter to access options (edit, remove, add new)

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

[Add contribution guidelines if applicable]