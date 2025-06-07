# Refactoring Plan for App.mc

The current `App.mc` file is over 2000 lines and contains multiple classes with different responsibilities. This refactoring plan proposes splitting it into logical, focused files.

## Current Issues:
- Single file with 2000+ lines
- Multiple classes mixed together
- Hard to maintain and navigate
- Violates Single Responsibility Principle

## Proposed File Structure:

### Core Application Files:
1. **`App.mc`** - Main application class only (~350 lines)
   - App class with connectivity and sync management
   - Application lifecycle methods
   - Settings synchronization

2. **`AppView.mc`** - Main view and UI handling (~600 lines)
   - AppView class
   - Image loading and display logic
   - Navigation and key handling
   - Screen timeout management

3. **`ImageManager.mc`** - Image download and caching (~400 lines)
   - Image downloading logic
   - Response callbacks
   - Retry mechanisms
   - Cache management

4. **`MenuDelegates.mc`** - Menu handling and delegates (~500 lines)
   - CodeInfoMenu2InputDelegate
   - AddCodeMenu2InputDelegate
   - TypeMenu2InputDelegate
   - AddCodeTextPickerDelegate
   - ConfirmDeleteDelegate

5. **`SettingsViews.mc`** - Settings UI and management (~300 lines)
   - SettingsView
   - SettingsDelegate
   - AppSettingsView
   - AppSettingsDelegate
   - AppSettingsMenuDelegate

6. **`GlanceView.mc`** - Glance view implementation (~200 lines)
   - GlanceView class
   - Glance image handling

7. **`AboutView.mc`** - About view and delegate (~100 lines)
   - AboutView class
   - AboutViewDelegate

8. **`AppDelegate.mc`** - Main app delegate (~50 lines)
   - AppDelegate class
   - Basic input handling

## Benefits:
- **Maintainability**: Easier to find and modify specific functionality
- **Readability**: Each file has a clear, single purpose
- **Testing**: Easier to test individual components
- **Collaboration**: Multiple developers can work on different files
- **Code Reuse**: Better separation of concerns allows for reusability

## Implementation Steps:
1. Create the new files with proper class definitions
2. Move imports and using statements to each file as needed
3. Ensure proper visibility (public/private) for cross-file access
4. Test compilation after each file move
5. Verify functionality remains intact

## File Responsibilities:

### App.mc
- Application initialization and lifecycle
- Connectivity monitoring
- Sync queue management
- Settings synchronization between Storage and Properties

### AppView.mc
- Main UI rendering and layout
- Image display logic
- Navigation (swipe, key handling)
- Empty state management
- Screen timeout settings

### ImageManager.mc
- Network image downloading
- Image caching to Storage
- Retry logic and failure handling
- Response callback processing
- Glance image generation

### MenuDelegates.mc
- All menu interaction logic
- Code addition workflows
- Deletion confirmation
- Type selection menus
- Text input handling

### SettingsViews.mc
- Settings UI presentation
- Settings menu creation
- Property toggling
- Settings synchronization UI

### GlanceView.mc
- Glance view rendering
- Compact code display
- Glance-specific image handling

### AboutView.mc
- About screen display
- QR code toggle for GitHub
- Simple interaction handling

### AppDelegate.mc
- Basic input delegation
- Bridge between views and input handling

## Notes:
- Each file will need appropriate `using` statements
- Some shared constants or utilities might need a separate `Constants.mc` file
- Static references like `AppView.current` will need careful handling
- Method visibility may need adjustment for cross-file access
