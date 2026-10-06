import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

/// Picks an image from the camera or gallery and extracts Latin text via ML Kit.
class TextRecognitionPage extends StatefulWidget {
  const TextRecognitionPage({super.key});

  @override
  State<TextRecognitionPage> createState() => _TextRecognitionPageState();
}

class _TextRecognitionPageState extends State<TextRecognitionPage> {
  final ImagePicker _imagePicker = ImagePicker();
  final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  File? _imageFile;
  String _recognizedText = '';
  String? _errorMessage;
  bool _isProcessing = false;

  @override
  void dispose() {
    _textRecognizer.close();
    super.dispose();
  }

  Future<void> _pickAndRecognize(ImageSource source) async {
    if (_isProcessing) return;

    setState(() {
      _errorMessage = null;
    });

    late final XFile? pickedFile;
    try {
      pickedFile = await _imagePicker.pickImage(source: source);
    } catch (error, stackTrace) {
      debugPrint('Image pick failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to pick image: $error';
      });
      return;
    }

    if (pickedFile == null) return;

    final imageFile = File(pickedFile.path);

    setState(() {
      _imageFile = imageFile;
      _recognizedText = '';
      _errorMessage = null;
      _isProcessing = true;
    });

    try {
      final inputImage = InputImage.fromFile(imageFile);
      final recognizedText = await _textRecognizer.processImage(inputImage);
      final extracted = recognizedText.text.trim();

      if (!mounted) return;
      setState(() {
        _recognizedText =
            extracted.isEmpty ? 'No text detected.' : extracted;
      });
    } catch (error, stackTrace) {
      debugPrint('Text recognition failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _recognizedText = '';
        _errorMessage = 'Failed to process image: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Text Recognition'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _isProcessing
                          ? null
                          : () => _pickAndRecognize(ImageSource.camera),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Camera'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _isProcessing
                          ? null
                          : () => _pickAndRecognize(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Gallery'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                flex: 3,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _buildImagePreview(theme),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Extracted text',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Expanded(
                flex: 2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
                  child: _buildTextResult(theme),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImagePreview(ThemeData theme) {
    if (_isProcessing) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Processing image…'),
          ],
        ),
      );
    }

    if (_imageFile != null) {
      return InteractiveViewer(
        child: Image.file(
          _imageFile!,
          fit: BoxFit.contain,
          width: double.infinity,
          height: double.infinity,
        ),
      );
    }

    return Center(
      child: Text(
        'Select an image from the camera or gallery.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildTextResult(ThemeData theme) {
    if (_errorMessage != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Text(
          _errorMessage!,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      );
    }

    if (_recognizedText.isEmpty) {
      return Center(
        child: Text(
          'Recognized text will appear here.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SelectableText(
        _recognizedText,
        style: theme.textTheme.bodyLarge,
      ),
    );
  }
}
