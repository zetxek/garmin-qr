using Toybox.Application;
using Toybox.Lang;
using Toybox.System;
using Toybox.WatchUi;

(:test)
class TestRunner {
    // Entry point for tests
    function runAllTests() {
        System.println("Starting test execution");
        
        // Run storage tests
        System.println("=== Running Storage Tests ===");
        var storageTest = new TestApp();
        runStorageTests(storageTest);
        
        // Run AppView tests
        System.println("=== Running AppView Tests ===");
        var appViewTest = new TestAppView();
        runAppViewTests(appViewTest);
        
        // Run menu tests
        System.println("=== Running Menu Tests ===");
        var menuTest = new TestMenus();
        runMenuTests(menuTest);
        
        // Run image generation tests
        System.println("=== Running Image Generation Tests ===");
        var imageGenTest = new TestImageGeneration();
        imageGenTest.run();
        
        System.println("All tests complete");
    }
    
    // Run storage tests directly
    function runStorageTests(suite) {
        var logger = new TestLogger("Storage");
        
        // Setup
        suite.setUp();
        
        // Run individual tests directly
        System.println("Running test: testAddQRCode");
        suite.testAddQRCode(logger);
        
        System.println("Running test: testAddBarcode");
        suite.testAddBarcode(logger);
        
        System.println("Running test: testRemoveCode");
        suite.testRemoveCode(logger);
        
        System.println("Running test: testMultipleCodes");
        suite.testMultipleCodes(logger);
        
        // Teardown
        suite.tearDown();
    }
    
    // Run AppView tests directly
    function runAppViewTests(suite) {
        var logger = new TestLogger("AppView");
        
        // Setup
        suite.setUp();
        
        // Run individual tests directly
        System.println("Running test: testEmptyState");
        suite.testEmptyState(logger);
        
        System.println("Running test: testCodeNavigation");
        suite.testCodeNavigation(logger);
        
        System.println("Running test: testQrImageGeneration");
        suite.testQrImageGeneration(logger);
        
        System.println("Running test: testBarcodeImageGeneration");
        suite.testBarcodeImageGeneration(logger);
        
        // Teardown
        suite.tearDown();
    }
    
    // Run Menu tests directly
    function runMenuTests(suite) {
        var logger = new TestLogger("Menu");
        
        // Setup
        suite.setUp();
        
        // Run individual tests directly
        System.println("Running test: testAddCodeMenu");
        suite.testAddCodeMenu(logger);
        
        System.println("Running test: testDeleteConfirmation");
        suite.testDeleteConfirmation(logger);
        
        System.println("Running test: testAddCodeViaMenu");
        suite.testAddCodeViaMenu(logger);
        
        // Teardown
        suite.tearDown();
    }
} 