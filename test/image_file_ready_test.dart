import 'dart:io';
import 'dart:typed_data';

import 'package:quick_cap/utils/image_file_ready.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('complete JPEG is accepted and a truncated JPEG is not', () async {
    final dir = await Directory.systemTemp.createTemp('image-ready');
    addTearDown(() => dir.delete(recursive: true));

    final complete = File('${dir.path}/done.jpg');
    await complete.writeAsBytes(_jpeg(truncated: false));
    final partial = File('${dir.path}/partial.jpg');
    await partial.writeAsBytes(_jpeg(truncated: true));

    expect(await isImageFileComplete(complete.path), isTrue);
    expect(await isImageFileComplete(partial.path), isFalse);
    expect(
      await waitForImageFileReady(
        partial.path,
        pollInterval: const Duration(milliseconds: 20),
        timeout: const Duration(milliseconds: 80),
        stablePollsRequired: 2,
      ),
      isFalse,
    );
  });
}

Uint8List _jpeg({required bool truncated}) {
  final bytes = <int>[
    0xFF, 0xD8,
    ...List<int>.filled(40, 0),
  ];
  if (!truncated) {
    bytes.addAll(const [0xFF, 0xD9]);
  }
  return Uint8List.fromList(bytes);
}
