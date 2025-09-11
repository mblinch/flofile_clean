import 'package:flutter/material.dart';
import '../utils/native_file_picker.dart';
import '../services/ftpclient_service.dart';

class FtpUploadWidget extends StatefulWidget {
  const FtpUploadWidget({super.key});

  @override
  State<FtpUploadWidget> createState() => _FtpUploadWidgetState();
}

class _FtpUploadWidgetState extends State<FtpUploadWidget> {
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  final TextEditingController _remotePathController = TextEditingController();
  final TextEditingController _localPathController = TextEditingController();

  bool _isUploading = false;
  double _uploadProgress = 0.0;
  String _statusText = '';
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _hostController.text = 'ftp.photoshelter.com';
    _usernameController.text = 'mb1';
    _passwordController.text = '';
    _portController.text = '21';
    _remotePathController.text = '';
  }

  @override
  void dispose() {
    _hostController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _portController.dispose();
    _remotePathController.dispose();
    _localPathController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final String? result = await NativeFilePicker.pickFile();
    if (result != null) {
      setState(() {
        _localPathController.text = result;
      });
    }
  }

  Future<void> _uploadFile() async {
    if (_localPathController.text.isEmpty) {
      setState(() {
        _errorText = 'Please select a file to upload';
      });
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
      _statusText = '';
      _errorText = null;
    });

    try {
      final result = await FtpClientService.uploadFile(
        host: _hostController.text,
        username: _usernameController.text,
        password: _passwordController.text,
        localFilePath: _localPathController.text,
        remoteFilePath: _remotePathController.text.isEmpty
            ? _localPathController.text.split('/').last
            : _remotePathController.text,
        port: int.tryParse(_portController.text) ?? 21,
        passiveMode: true,
        onProgress: (status, progress, error) {
          setState(() {
            _statusText = status;
            _uploadProgress = progress;
            if (error != null) {
              _errorText = error;
            }
          });
        },
      );

      setState(() {
        _isUploading = false;
        if (result.success) {
          _statusText = 'Upload completed successfully!';
          _uploadProgress = 1.0;
        } else {
          _errorText = result.error ?? 'Upload failed';
          _uploadProgress = 0.0;
        }
      });

      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload successful: ${result.details}'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: ${result.error}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isUploading = false;
        _errorText = e.toString();
        _uploadProgress = 0.0;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FTP Upload Test'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _hostController,
              decoration: const InputDecoration(
                labelText: 'FTP Host',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Username',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _portController,
              decoration: const InputDecoration(
                labelText: 'Port',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _localPathController,
                    decoration: const InputDecoration(
                      labelText: 'Local File Path',
                      border: OutlineInputBorder(),
                    ),
                    readOnly: true,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _pickFile,
                  child: const Text('Pick File'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _remotePathController,
              decoration: const InputDecoration(
                labelText: 'Remote Path (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isUploading ? null : _uploadFile,
              child: Text(_isUploading ? 'Uploading...' : 'Upload File'),
            ),
            const SizedBox(height: 16),
            if (_isUploading || _statusText.isNotEmpty)
              Column(
                children: [
                  LinearProgressIndicator(value: _uploadProgress),
                  const SizedBox(height: 8),
                  Text(_statusText),
                  if (_errorText != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        border: Border.all(color: Colors.red),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _errorText!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}
