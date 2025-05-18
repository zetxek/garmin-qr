using Toybox.Lang;
using Toybox.System;
using Toybox.Application.Storage;

// Utility functions for tests
module TestUtils {
    // Assert that a condition is true
    function assertTrue(condition, message) {
        if (!condition) {
            if (message != null) {
                System.println("ASSERTION FAILED: " + message);
            } else {
                System.println("ASSERTION FAILED: Expected true, but got false");
            }
            return false;
        }
        return true;
    }
    
    // Assert that two values are equal
    function assertEqual(actual, expected, message) {
        if (actual != expected) {
            if (message != null) {
                System.println("ASSERTION FAILED: " + message + " (Expected: " + expected + ", Actual: " + actual + ")");
            } else {
                System.println("ASSERTION FAILED: Expected " + expected + ", but got " + actual);
            }
            return false;
        }
        return true;
    }
    
    // Assert that a value is not null
    function assertNotNull(value, message) {
        if (value == null) {
            if (message != null) {
                System.println("ASSERTION FAILED: " + message);
            } else {
                System.println("ASSERTION FAILED: Expected non-null value");
            }
            return false;
        }
        return true;
    }
    
    // Clear all test data
    function clearTestData() {
        for (var i = 0; i < 10; i++) {
            Storage.deleteValue("code_" + i + "_text");
            Storage.deleteValue("code_" + i + "_title");
            Storage.deleteValue("code_" + i + "_type");
        }
    }
    
    // Create test QR code
    function createTestQrCode(index, text, title) {
        Storage.setValue("code_" + index + "_text", text);
        Storage.setValue("code_" + index + "_title", title);
        Storage.setValue("code_" + index + "_type", "0");
    }
    
    // Create test barcode
    function createTestBarcode(index, text, title) {
        Storage.setValue("code_" + index + "_text", text);
        Storage.setValue("code_" + index + "_title", title);
        Storage.setValue("code_" + index + "_type", "1");
    }
} 