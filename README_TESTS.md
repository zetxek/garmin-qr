# Garmin QR Code App Tests

This document explains the test suite for the Garmin QR Code application.

## Test Structure

The test files are organized in the `source/test/` directory and include:

1. `GarminQrTests.mc` - Main test class with practical tests that can be run directly in the simulator
2. `TestApp.mc` - Tests for core storage and code handling functionality
3. `TestAppView.mc` - Tests for UI components and interaction
4. `TestMenus.mc` - Tests for menu functionality
5. `TestImageGeneration.mc` - Tests for image generation and network calls
6. `TestUtils.mc` - Utility functions for assertions and test helpers
7. `SimpleTestRunner.mc` - A runner to execute tests without try-catch blocks
8. `TestRunner.mc` - A more complex test runner (not fully compatible with all simulators)

## Running Tests

To run the tests in the Garmin Connect IQ simulator:

1. Open the Garmin Connect IQ IDE
2. Load the project
3. In the simulator console, execute:
   ```
   var tests = new GarminQrTests();
   tests.run();
   ```

## Features Tested

The test suite covers all the core functionality:

### 1. Adding a Code
- Adding QR codes with text and title
- Adding barcodes with text and title
- Testing different code types (QR and barcode)

### 2. Viewing Code Data
- Testing code data retrieval from storage
- Testing code navigation (previous/next)
- Testing correct display of code details

### 3. Removing a Code
- Testing code deletion
- Verifying storage cleanup
- Testing UI updates after deletion

### 4. Generating Images
- Testing QR code image URL generation
- Testing barcode image URL generation
- Testing image download functionality

### 5. Code Type Support
- Testing QR code specific functionality
- Testing barcode specific functionality
- Testing type-specific UI elements

## Mock Classes

Several mock classes are provided to simulate:
- Device context (DC) for drawing
- Key events for navigation
- Storage operations
- Network responses

## Known Limitations

1. The tests are primarily designed for simulator testing, not on-device testing
2. Some test classes may show linter errors due to the mocking approach
3. Full UI testing is limited due to the simulator environment

## Future Test Improvements

1. Add more comprehensive UI testing
2. Implement true unit test isolation
3. Add performance tests for larger numbers of codes
4. Add more edge case handling tests

For more information about Garmin Connect IQ testing, refer to the Garmin developer documentation. 