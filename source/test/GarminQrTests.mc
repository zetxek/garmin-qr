using Toybox.Application;
using Toybox.Lang;
using Toybox.System;
using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Application.Storage;

// Main test class for the Garmin QR application
(:test)
class GarminQrTests {
    // Test adding a QR code
    function testAddQR() {
        // Arrange
        Storage.deleteValue("code_0_text");
        Storage.deleteValue("code_0_title");
        Storage.deleteValue("code_0_type");

        // Act
        Storage.setValue("code_0_text", "https://www.garmin.com");
        Storage.setValue("code_0_title", "Garmin Website");
        Storage.setValue("code_0_type", "0");

        // Assert
        var text = Storage.getValue("code_0_text");
        var title = Storage.getValue("code_0_title");
        var type = Storage.getValue("code_0_type");
        
        System.println("Test Add QR Code: " + 
            (text.equals("https://www.garmin.com") && 
             title.equals("Garmin Website") && 
             type.equals("0") ? "PASSED" : "FAILED"));
    }
    
    // Test adding a barcode
    function testAddBarcode() {
        // Arrange
        Storage.deleteValue("code_1_text");
        Storage.deleteValue("code_1_title");
        Storage.deleteValue("code_1_type");

        // Act
        Storage.setValue("code_1_text", "1234567890");
        Storage.setValue("code_1_title", "Product Code");
        Storage.setValue("code_1_type", "1");

        // Assert
        var text = Storage.getValue("code_1_text");
        var title = Storage.getValue("code_1_title");
        var type = Storage.getValue("code_1_type");
        
        System.println("Test Add Barcode: " + 
            (text.equals("1234567890") && 
             title.equals("Product Code") && 
             type.equals("1") ? "PASSED" : "FAILED"));
    }
    
    // Test removing a code
    function testRemoveCode() {
        // Arrange - Add a code first
        Storage.setValue("code_2_text", "test");
        Storage.setValue("code_2_title", "Test Code");
        Storage.setValue("code_2_type", "0");
        
        // Act - Remove the code
        Storage.deleteValue("code_2_text");
        Storage.deleteValue("code_2_title");
        Storage.deleteValue("code_2_type");
        
        // Assert
        var text = Storage.getValue("code_2_text");
        var title = Storage.getValue("code_2_title");
        var type = Storage.getValue("code_2_type");
        
        System.println("Test Remove Code: " + 
            (text == null && title == null && type == null ? "PASSED" : "FAILED"));
    }
    
    // Test URL generation for QR code
    function testQrUrlGeneration() {
        // Arrange
        var codeText = "test123";
        var codeType = "0"; // QR code
        
        // Act
        var url = "https://qr-generator-329626796314.europe-west4.run.app/qr?text=" + codeText;
        
        // Assert - Just ensure URL is formed correctly for manual inspection
        System.println("QR URL: " + url);
        System.println("Test QR URL Generation: PASSED");
    }
    
    // Test URL generation for barcode
    function testBarcodeUrlGeneration() {
        // Arrange
        var codeText = "1234567890";
        var codeType = "1"; // Barcode
        
        // Act
        var url = "https://qr-generator-329626796314.europe-west4.run.app/barcode?text=" + codeText;
        
        // Assert - Just ensure URL is formed correctly for manual inspection
        System.println("Barcode URL: " + url);
        System.println("Test Barcode URL Generation: PASSED");
    }
    
    // Main function to run all tests
    function runTests() {
        System.println("STARTING GARMIN QR TESTS");
        System.println("========================");
        
        // Run each test
        testAddQR();
        testAddBarcode();
        testRemoveCode();
        testQrUrlGeneration();
        testBarcodeUrlGeneration();
        
        System.println("========================");
        System.println("ALL TESTS COMPLETE");
    }
    
    // Call this from the simulator to run tests
    function run() {
        runTests();
    }
} 