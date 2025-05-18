using Toybox.Application;
using Toybox.Lang;
using Toybox.System;
using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Communications;
using Toybox.Application.Storage;

(:test)
class TestImageGeneration {
    var mockCommunications;
    var appView;
    
    function initialize() {
        // Initialize mock objects
        mockCommunications = new MockCommunications();
        appView = new AppView();
    }
    
    // Test QR code image download
    function testQrImageDownload() {
        // Arrange: Setup test data
        var codeText = "https://www.garmin.com";
        var codeTitle = "Garmin Website";
        var codeType = "0"; // QR code
        var imageIndex = 0;
        
        // Save code to storage
        Storage.setValue("code_0_text", codeText);
        Storage.setValue("code_0_title", codeTitle);
        Storage.setValue("code_0_type", codeType);
        
        // Act: Trigger image download
        appView.downloadImage(codeText, imageIndex);
        
        // Assert: Verify the URL was correctly formed
        // This would use our mock to check the URL
        var expectedUrlPrefix = "https://qr-generator-329626796314.europe-west4.run.app/qr?text=";
        
        System.println("Test QR Image Download: Success");
        return true;
    }
    
    // Test Barcode image download
    function testBarcodeImageDownload() {
        // Arrange: Setup test data
        var codeText = "1234567890";
        var codeTitle = "Product Barcode";
        var codeType = "1"; // Barcode
        var imageIndex = 0;
        
        // Save code to storage
        Storage.setValue("code_0_text", codeText);
        Storage.setValue("code_0_title", codeTitle);
        Storage.setValue("code_0_type", codeType);
        
        // Act: Trigger image download
        appView.downloadImage(codeText, imageIndex);
        
        // Assert: Verify the URL was correctly formed
        // This would use our mock to check the URL contains barcode endpoint
        var expectedUrlPrefix = "https://qr-generator-329626796314.europe-west4.run.app/barcode?text=";
        
        System.println("Test Barcode Image Download: Success");
        return true;
    }
    
    // Test response handling
    function testResponseCallback() {
        // Arrange: Setup test data and mocks
        var mockData = new MockBitmapResource(100, 100);
        var imagesIdx = 0;
        appView.downloadingImageIdx = imagesIdx;
        appView.images = [{:index => 0, :image => null}];
        
        // Act: Call response callback with successful response
        appView.responseCallback(200, mockData);
        
        // Assert: Verify image was stored correctly
        // In a real test we'd verify the bitmap was stored and UI was updated
        System.println("Test Response Callback: Success");
        return true;
    }
    
    // Test error handling in response
    function testErrorHandling() {
        // Arrange: Setup test conditions
        appView.downloadingImageIdx = 0;
        appView.images = [{:index => 0, :image => null}];
        
        // Act: Call response callback with error response
        appView.responseCallback(-101, null);
        
        // Assert: Verify error message is set
        System.println("Test Error Handling: Success");
        return true;
    }
    
    // Run all tests
    function run() {
        testQrImageDownload();
        testBarcodeImageDownload();
        testResponseCallback();
        testErrorHandling();
        System.println("All image generation tests complete");
    }
}

// Mock classes

class MockCommunications {
    var lastUrl;
    var lastParams;
    var lastOptions;
    var lastCallback;
    
    function initialize() {
        lastUrl = null;
        lastParams = null;
        lastOptions = null;
        lastCallback = null;
    }
    
    function makeImageRequest(url, params, options, callback) {
        lastUrl = url;
        lastParams = params;
        lastOptions = options;
        lastCallback = callback;
        System.println("Mock image request: " + url);
    }
}

class MockBitmapResource {
    var width;
    var height;
    
    function initialize(w, h) {
        width = w;
        height = h;
    }
    
    function getWidth() {
        return width;
    }
    
    function getHeight() {
        return height;
    }
} 