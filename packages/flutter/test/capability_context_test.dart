import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:napaxi_flutter/platform_tools/capability_context.dart';

void main() {
  test('attachment result includes canonical and legacy file fields', () {
    const context = CapabilityContext(
      filesDir: '/app/files',
      workspaceFilesDir: '/app/scopes/account/agent',
    );

    final result = jsonDecode(context.attachmentResultJson(
      sandboxPath: '/workspace/tmp/attachments/camera/photo.jpg',
      kind: 'image',
      filename: 'photo.jpg',
      mimeType: 'image/jpeg',
      sizeBytes: 42,
    )) as Map<String, dynamic>;

    expect(
        result['sandbox_path'], '/workspace/tmp/attachments/camera/photo.jpg');
    expect(result['file_path'], result['sandbox_path']);
    expect(result['mime_type'], 'image/jpeg');
    expect(result['mimeType'], 'image/jpeg');
    expect(result['size_bytes'], 42);
    expect(result['sizeBytes'], 42);
  });

  test('resolves sandbox paths through scoped workspace and shared roots', () {
    const context = CapabilityContext(
      filesDir: '/app/files',
      workspaceFilesDir: '/app/scopes/account/agent',
    );

    expect(
      context.resolveSandboxOrLocalPath('/workspace/app.apk'),
      '/app/scopes/account/agent/linux-env/workspace/app.apk',
    );
    expect(
      context.resolveSandboxOrLocalPath('/skills/demo/SKILL.md'),
      '/app/files/prompt_skills/demo/SKILL.md',
    );
    expect(
      context.resolveSandboxOrLocalPath('/tmp/out.txt'),
      '/app/files/linux-env/rootfs/tmp/out.txt',
    );
  });
}
