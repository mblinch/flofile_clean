# FTP File Transfer Integration

This Flutter app now includes comprehensive FTP file transfer capabilities using the `ftpconnect` package.

## Features

✅ **Upload files to FTP server**  
✅ **Download files from FTP server**  
✅ **List files in FTP directories**  
✅ **Retry logic with automatic reconnection**  
✅ **Modern Flutter UI with progress indication**  
✅ **SnackBar notifications for success/error feedback**  
✅ **File picker integration**  

## Files Added

### Core Service
- `lib/services/ftp_service.dart` - Main FTP service with retry logic and reconnection handling

### UI Components  
- `lib/widgets/ftp_upload_widget.dart` - Complete Flutter UI for FTP operations

### Example Usage
- `example_ftp_usage.dart` - Standalone example showing how to use the FTP service

## Quick Start

### 1. Enable the FTP Interface

In `lib/main.dart`, uncomment this line to show the FTP interface:

```dart
home: const FtpUploadWidget(), // Show FTP test interface
```

### 2. Basic API Usage

```dart
import 'package:your_app/services/ftp_service.dart';

// Upload a file
final success = await FtpService.uploadFile(
  host: 'ftp.example.com',
  username: 'user',
  password: 'pass',
  localFilePath: '/path/to/local/file.txt',
  remoteFilePath: '/remote/file.txt',
);

// Download a file
final success = await FtpService.downloadFile(
  host: 'ftp.example.com',
  username: 'user',
  password: 'pass',
  remoteFilePath: '/remote/file.txt',
  localFilePath: '/path/to/local/file.txt',
);

// List files in directory
final files = await FtpService.listFiles(
  host: 'ftp.example.com',
  username: 'user',
  password: 'pass',
  directory: '/remote/path/',
);
```

## Flutter UI Features

The `FtpUploadWidget` provides a complete interface with:

- **Connection Settings**: Host, username, password, port configuration
- **File Selection**: Integrated file picker for choosing local files
- **Upload/Download Buttons**: With state management and loading indicators
- **Progress Indication**: Visual feedback during file transfers
- **File Listing**: Browse remote directories and select files
- **SnackBar Notifications**: Success/error feedback with colored messages

## Configuration

### Dependencies

The following dependency has been added to `pubspec.yaml`:

```yaml
dependencies:
  ftpconnect: ^2.0.5
```

### FTP Service Configuration

Default settings in `FtpService`:

- **Max Retries**: 3 attempts
- **Retry Delay**: 2 seconds between attempts
- **Connection Timeout**: 30 seconds
- **Default Port**: 21

## Error Handling

The FTP service includes comprehensive error handling:

- **Automatic retry logic** with configurable attempts
- **Connection cleanup** on failures
- **Detailed logging** for debugging
- **Graceful error recovery** with user feedback

## Example Scenarios

### Upload a Photo
1. Open the FTP interface
2. Enter your FTP server details
3. Click "Pick File" to select a photo
4. Enter the remote path where you want to store it
5. Click "Upload"

### Download a File
1. Enter FTP connection details
2. Enter the remote file path
3. Enter where you want to save it locally
4. Click "Download"

### Browse Remote Directory
1. Enter FTP connection details
2. Enter a directory path (or leave empty for root)
3. Click "List Files"
4. Click on any file to auto-fill the remote path field

## Testing

### Test with Example File

Run the standalone example:

```bash
dart run example_ftp_usage.dart
```

### Test with UI

1. Set `home: const FtpUploadWidget()` in `main.dart`
2. Run the app: `flutter run`
3. Use the UI to test FTP operations

## Production Usage

### Remove Debug Prints

For production, you may want to remove or redirect the debug print statements in `ftp_service.dart`:

```dart
// Replace with proper logging
// print('FTP: Connected to $host');
logger.info('FTP: Connected to $host');
```

### Security Considerations

- **Never hardcode credentials** in your source code
- Store FTP credentials securely (using Flutter Secure Storage or similar)
- Use FTPS (FTP over SSL/TLS) for sensitive data
- Validate user inputs for security

### Error Handling in Production

```dart
try {
  final success = await FtpService.uploadFile(/* ... */);
  if (success) {
    // Handle success
  } else {
    // Handle failure
  }
} catch (e) {
  // Handle exceptions
  logger.error('FTP operation failed: $e');
}
```

## Troubleshooting

### Common Issues

1. **Connection Timeout**
   - Check firewall settings
   - Verify FTP server is accessible
   - Try different port numbers

2. **Authentication Failed**
   - Verify username/password
   - Check if anonymous login is disabled

3. **Upload/Download Failures**
   - Check file permissions
   - Verify remote directory exists
   - Ensure sufficient disk space

### Debug Mode

Enable detailed logging by checking the console output when running the app. All FTP operations log their progress and any errors encountered.

## Advanced Usage

### Custom Retry Logic

```dart
class CustomFtpService extends FtpService {
  static const int _customMaxRetries = 5;
  static const Duration _customDelay = Duration(seconds: 3);
  
  // Override retry logic as needed
}
```

### Progress Callbacks

The current implementation logs progress to console. You can extend it to provide progress callbacks to your UI for real-time progress bars.

## License

This FTP integration uses the `ftpconnect` package which is licensed under MIT License. 