# ExifTool in FloFile Beta

## Issue
The bundled ExifTool (Perl script) doesn't work in the packaged DMG due to sandboxing restrictions and missing Perl dependencies.

## Solution
The app now includes improved error handling and fallback mechanisms:

### Automatic Fallback
- First tries the bundled exiftool
- If that fails, automatically falls back to system-installed exiftool
- Provides detailed debug output for troubleshooting

### User Installation
For the app to work properly, users need to install ExifTool system-wide:

```bash
brew install exiftool
```

### Error Handling
- Clear error messages when ExifTool is not available
- Graceful degradation when metadata cannot be read/written
- Debug logging to help diagnose issues

## Testing
1. Install exiftool: `brew install exiftool`
2. Open the DMG and run the app
3. Check console output for ExifTool debug messages
4. Verify that EXIF data loads in the picture preview panel

## Troubleshooting
If ExifTool still doesn't work:
1. Verify exiftool is installed: `which exiftool`
2. Check console output for detailed error messages
3. Ensure the app has necessary permissions to access files

## Future Improvements
- Consider bundling a standalone exiftool binary
- Add user-friendly error dialogs
- Implement alternative metadata reading methods
