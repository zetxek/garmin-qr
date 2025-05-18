using Toybox.Application;
using Toybox.Lang;
using Toybox.System;
using Toybox.WatchUi;

(:test)
class SimpleTestRunner {
    // Entry point for tests
    function runAllTests() {
        System.println("Starting test execution");
        
        // Create test instances
        var storageTest = new TestApp();
        var imageGenTest = new TestImageGeneration();
        
        // Setup and run individual tests
        System.println("=== Running QR Code Tests ===");
        runQrCodeTests(storageTest);
        
        System.println("=== Running Barcode Tests ===");
        runBarcodeTests(storageTest);
        
        System.println("=== Running Image Generation Tests ===");
        imageGenTest.run();
        
        System.println("All tests complete");
    }
    
    // Run QR code specific tests
    function runQrCodeTests(testApp) {
        // Setup
        testApp.setUp();
        
        // Run tests
        System.println("Running test: testAddQRCode");
        testApp.testAddQRCode(new TestLogger("testAddQRCode"));
        
        System.println("Running test: testRemoveCode");
        testApp.testRemoveCode(new TestLogger("testRemoveCode"));
        
        // Teardown
        testApp.tearDown();
    }
    
    // Run barcode specific tests
    function runBarcodeTests(testApp) {
        // Setup
        testApp.setUp();
        
        // Run tests
        System.println("Running test: testAddBarcode");
        testApp.testAddBarcode(new TestLogger("testAddBarcode"));
        
        System.println("Running test: testMultipleCodes");
        testApp.testMultipleCodes(new TestLogger("testMultipleCodes"));
        
        // Teardown
        testApp.tearDown();
    }
}

// Simple logger class for tests
class TestLogger {
    var testName;
    
    function initialize(name) {
        testName = name;
    }
    
    function log(message) {
        System.println("[" + testName + "] " + message);
    }
} 