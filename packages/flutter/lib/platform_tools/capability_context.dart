import 'dart:convert';
import 'dart:io';

/// Runtime context passed to platform tools, resolving the file/workspace
/// directories they use for attachments and output.
class CapabilityContext {
  const CapabilityContext({
    required this.filesDir,
    required this.workspaceFilesDir,
  });

  final String? filesDir;
  final String? workspaceFilesDir;

  String? get workspaceDir {
    final base =
        workspaceFilesDir?.isNotEmpty == true ? workspaceFilesDir : filesDir;
    if (base == null || base.isEmpty) return null;
    return '$base/linux-env/workspace';
  }

  String? get rootfsDir {
    final base = filesDir;
    if (base == null || base.isEmpty) return null;
    return '$base/linux-env/rootfs';
  }

  String? get skillsDir {
    final base = filesDir;
    if (base == null || base.isEmpty) return null;
    return '$base/prompt_skills';
  }

  Future<Directory?> ensureAttachmentDir(String category) async {
    final workspace = workspaceDir;
    if (workspace == null) return null;
    final dir = Directory('$workspace/attachments/$category');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String attachmentSandboxPath(String category, String filename) {
    return '/workspace/attachments/$category/$filename';
  }

  String attachmentResultJson({
    required String sandboxPath,
    required String kind,
    required String filename,
    required String mimeType,
    required int sizeBytes,
    Map<String, dynamic> extra = const {},
  }) {
    return successJson({
      'sandbox_path': sandboxPath,
      'file_path': sandboxPath,
      'kind': kind,
      'filename': filename,
      'mime_type': mimeType,
      'mimeType': mimeType,
      'size_bytes': sizeBytes,
      'sizeBytes': sizeBytes,
      ...extra,
    });
  }

  String successJson(Map<String, dynamic> value) => jsonEncode(value);

  String errorJson(String message, {bool includeSuccess = false}) {
    return jsonEncode({
      if (includeSuccess) 'success': false,
      'error': message,
    });
  }

  String resolveSandboxOrLocalPath(String path) {
    final workspace = workspaceDir;
    final rootfs = rootfsDir;
    final skills = skillsDir;

    if (path == '/workspace' && workspace != null) {
      return workspace;
    }
    if (path.startsWith('/workspace/') && workspace != null) {
      return '$workspace/${path.substring('/workspace/'.length)}';
    }
    if (path == '/skills' && skills != null) {
      return skills;
    }
    if (path.startsWith('/skills/') && skills != null) {
      return '$skills/${path.substring('/skills/'.length)}';
    }
    if (_rootfsPrefixes
            .any((prefix) => path == prefix || path.startsWith('$prefix/')) &&
        rootfs != null) {
      return '$rootfs/${path.substring(1)}';
    }
    return path;
  }

  static const _rootfsPrefixes = [
    '/tmp',
    '/root',
    '/home',
    '/var',
    '/usr',
    '/opt',
    '/etc',
    '/srv',
    '/run',
  ];
}
