import 'dart:convert';
import 'dart:io';

import 'package:record/record.dart';

import '../capability_context.dart';

/// Platform tool that records audio from the microphone for a bounded duration.
class AudioTool {
  static Future<String> execute(
    String paramsJson,
    CapabilityContext context,
  ) async {
    final recDir = await context.ensureAttachmentDir('audio');
    if (recDir == null) {
      return context.errorJson('File storage not available.');
    }

    final params = jsonDecode(paramsJson) as Map<String, dynamic>;
    final duration = ((params['duration_seconds'] as int?) ?? 10).clamp(1, 60);

    final recorder = AudioRecorder();

    final hasPermission = await recorder.hasPermission();
    if (!hasPermission) {
      await recorder.dispose();
      return context.errorJson('Microphone permission denied by user.');
    }

    final filename = 'rec_${DateTime.now().millisecondsSinceEpoch}.wav';
    final outPath = '${recDir.path}/$filename';

    await recorder.start(
      const RecordConfig(encoder: AudioEncoder.wav),
      path: outPath,
    );

    await Future<void>.delayed(Duration(seconds: duration));

    final actualPath = await recorder.stop();
    await recorder.dispose();

    final savedFile = File(actualPath ?? outPath);
    if (!savedFile.existsSync()) {
      return context.errorJson('Recording failed.');
    }

    final sizeBytes = savedFile.lengthSync();
    final savedName = savedFile.uri.pathSegments.last;
    final sandboxPath = context.attachmentSandboxPath('audio', savedName);

    return context.attachmentResultJson(
      sandboxPath: sandboxPath,
      kind: 'audio',
      filename: savedName,
      mimeType: 'audio/wav',
      sizeBytes: sizeBytes,
      extra: {
        'duration_seconds': duration,
        'duration_secs': duration,
      },
    );
  }
}
