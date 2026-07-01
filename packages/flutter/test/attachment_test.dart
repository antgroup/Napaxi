import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:napaxi_flutter/napaxi_flutter.dart';

void main() {
  test('McAttachment includes sandbox path metadata without dropping payload',
      () {
    final attachment = McAttachment(
      kind: 'image',
      mimeType: 'image/png',
      filename: 'out.png',
      sandboxPath: '/workspace/out.png',
      localPath: '/local/demo/out.png',
      data: Uint8List.fromList(utf8.encode('png-bytes')),
    );

    final map = attachment.toMap();

    expect(map['sandbox_path'], '/workspace/out.png');
    expect(map['path'], '/local/demo/out.png');
    expect(map['data_base64'], isA<String>());
  });

  test('ChatAttachment reads current and older metadata keys', () {
    final current = ChatAttachment.fromMap({
      'kind': 'document',
      'mime_type': 'text/plain',
      'filename': 'notes.txt',
      'sandbox_path': '/workspace/notes.txt',
    });
    final older = ChatAttachment.fromMap({
      'kind': 'document',
      'mime_type': 'text/plain',
      'name': 'old.txt',
      'path': '/workspace/old.txt',
    });
    final local = ChatAttachment.fromMap({
      'kind': 'document',
      'mime_type': 'text/plain',
      'filename': 'local.txt',
      'path': '/local/demo/local.txt',
    });

    expect(current.filename, 'notes.txt');
    expect(current.sandboxPath, '/workspace/notes.txt');
    expect(older.filename, 'old.txt');
    expect(older.sandboxPath, '/workspace/old.txt');
    expect(older.localPath, isNull);
    expect(local.filename, 'local.txt');
    expect(local.localPath, '/local/demo/local.txt');
    expect(local.sandboxPath, isNull);
  });
}
