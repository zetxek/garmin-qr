using Toybox.Application;
using Toybox.Lang;
using Toybox.System;
using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Application.Storage;

(:test)
class TestApp {
    private var testStorage;

    // Setup before each test
    function setUp() {
        // Setup test environment
        testStorage = new Lang.Dictionary();
        
        // Clear any existing codes from storage
        clearAllCodes();
    }

    // Clean up after each test
    function tearDown() {
        clearAllCodes();
    }

    // Helper function to clear all codes
    function clearAllCodes() {
        for(var i = 0; i < 10; i++) {
            Storage.deleteValue("code_" + i + "_text");
            Storage.deleteValue("code_" + i + "_title");
            Storage.deleteValue("code_" + i + "_type");
        }
    }

    // Test adding a QR code
    function testAddQRCode(logger) {
        var codeText = "https://www.garmin.com";
        var codeTitle = "Garmin Website";
        var codeType = "0"; // QR code
        
        // Add a code
        Storage.setValue("code_0_text", codeText);
        Storage.setValue("code_0_title", codeTitle);
        Storage.setValue("code_0_type", codeType);
        
        // Verify code was added successfully
        TestUtils.assertEqual(Storage.getValue("code_0_text"), codeText, "QR code text should match");
        TestUtils.assertEqual(Storage.getValue("code_0_title"), codeTitle, "QR code title should match");
        TestUtils.assertEqual(Storage.getValue("code_0_type"), codeType, "QR code type should match");
        
        return true;
    }
    
    // Test adding a Barcode
    function testAddBarcode(logger) {
        var codeText = "1234567890";
        var codeTitle = "Product Barcode";
        var codeType = "1"; // Barcode
        
        // Add a code
        Storage.setValue("code_0_text", codeText);
        Storage.setValue("code_0_title", codeTitle);
        Storage.setValue("code_0_type", codeType);
        
        // Verify code was added successfully
        TestUtils.assertEqual(Storage.getValue("code_0_text"), codeText, "Barcode text should match");
        TestUtils.assertEqual(Storage.getValue("code_0_title"), codeTitle, "Barcode title should match");
        TestUtils.assertEqual(Storage.getValue("code_0_type"), codeType, "Barcode type should match");
        
        return true;
    }
    
    // Test removing a code
    function testRemoveCode(logger) {
        // First add a code
        Storage.setValue("code_0_text", "Test code");
        Storage.setValue("code_0_title", "Test title");
        Storage.setValue("code_0_type", "0");
        
        // Verify code was added
        TestUtils.assertTrue(Storage.getValue("code_0_text") != null, "Code should be present");
        
        // Now remove it
        Storage.deleteValue("code_0_text");
        Storage.deleteValue("code_0_title");
        Storage.deleteValue("code_0_type");
        
        // Verify it was removed
        TestUtils.assertTrue(Storage.getValue("code_0_text") == null, "Code should be deleted");
        TestUtils.assertTrue(Storage.getValue("code_0_title") == null, "Title should be deleted");
        TestUtils.assertTrue(Storage.getValue("code_0_type") == null, "Type should be deleted");
        
        return true;
    }
    
    // Test adding multiple codes and verifying they're retrievable
    function testMultipleCodes(logger) {
        // Add several codes
        for(var i = 0; i < 3; i++) {
            Storage.setValue("code_" + i + "_text", "Test code " + i);
            Storage.setValue("code_" + i + "_title", "Test title " + i);
            Storage.setValue("code_" + i + "_type", (i % 2).toString()); // Alternate types
        }
        
        // Verify all codes were saved
        for(var i = 0; i < 3; i++) {
            TestUtils.assertEqual(Storage.getValue("code_" + i + "_text"), "Test code " + i, "Code " + i + " text should match");
            TestUtils.assertEqual(Storage.getValue("code_" + i + "_title"), "Test title " + i, "Code " + i + " title should match");
            TestUtils.assertEqual(Storage.getValue("code_" + i + "_type"), (i % 2).toString(), "Code " + i + " type should match");
        }
        
        return true;
    }
} 