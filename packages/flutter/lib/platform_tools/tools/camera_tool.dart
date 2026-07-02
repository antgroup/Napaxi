import 'dart:io';

import 'package:image_picker/image_picker.dart';

import '../capability_context.dart';

/// Platform tool that captures a photo with the device camera.
class CameraTool {
  static final _picker = ImagePicker();

  static Future<String> execute(
    String paramsJson,
    CapabilityContext context,
  ) async {
    final photoDir = await context.ensureAttachmentDir('camera');
    if (photoDir == null) {
      return context.errorJson('File storage not available.');
    }

    final image = await _picker.pickImage(source: ImageSource.camera);
    if (image == null) {
      return context.errorJson('Photo cancelled by user.');
    }

    final ext = image.path.endsWith('.png') ? '.png' : '.jpg';
    final filename = 'photo_${DateTime.now().millisecondsSinceEpoch}$ext';
    final sandboxPath = context.attachmentSandboxPath('camera', filename);
    final outFile = File('${photoDir.path}/$filename');
    final bytes = await image.readAsBytes();
    await outFile.writeAsBytes(bytes);
    final mimeType = ext == '.png' ? 'image/png' : 'image/jpeg';

    return context.attachmentResultJson(
      sandboxPath: sandboxPath,
      kind: 'image',
      filename: filename,
      mimeType: mimeType,
      sizeBytes: bytes.length,
    );
  }
}
