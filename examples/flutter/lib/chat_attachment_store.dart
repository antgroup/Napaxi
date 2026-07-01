import 'dart:convert';
import 'dart:io';

import 'package:napaxi/main.dart' show ChatAttachment, ChatAttachmentType;

class _StoredChatAttachment {
  const _StoredChatAttachment({
    required this.name,
    required this.path,
    required this.type,
    this.sandboxPath,
  });

  final String name;
  final String path;
  final ChatAttachmentType type;
  final String? sandboxPath;

  Map<String, Object?> toMap() => {
        'name': name,
        'path': path,
        'type': type.name,
        if (sandboxPath != null && sandboxPath!.trim().isNotEmpty)
          'sandbox_path': sandboxPath,
      };

  factory _StoredChatAttachment.fromMap(Map<String, Object?> map) {
    final rawType = map['type'] as String? ?? ChatAttachmentType.file.name;
    return _StoredChatAttachment(
      name: map['name'] as String? ?? 'Attachment',
      path: map['path'] as String? ?? '',
      type: rawType == ChatAttachmentType.image.name
          ? ChatAttachmentType.image
          : ChatAttachmentType.file,
      sandboxPath: map['sandbox_path'] as String?,
    );
  }

  ChatAttachment toChatAttachment() => ChatAttachment(
        name: name,
        path: path,
        type: type,
        sandboxPath: sandboxPath,
      );
}

class ChatAttachmentStore {
  ChatAttachmentStore({required String filesDir})
      : _baseDir = Directory('$filesDir/chat_attachments');

  final Directory _baseDir;

  Directory _threadDir(String threadId) => Directory('${_baseDir.path}/$threadId');

  File _manifestFile(String threadId) => File('${_threadDir(threadId).path}/manifest.json');

  Future<List<ChatAttachment>> persistAttachments(
    String threadId,
    int userMsgIndex,
    List<ChatAttachment> attachments,
  ) async {
    if (attachments.isEmpty) {
      return const [];
    }

    final dir = _threadDir(threadId);
    await dir.create(recursive: true);

    final persisted = <ChatAttachment>[];
    final records = <_StoredChatAttachment>[];
    for (var i = 0; i < attachments.length; i++) {
      final attachment = attachments[i];
      final source = File(attachment.path);
      if (!await source.exists()) continue;

      final targetName = _uniqueFilename(
        dir,
        _storedFilename(attachment, index: i),
      );
      final target = File('${dir.path}/$targetName');
      await source.copy(target.path);

      final stored = _StoredChatAttachment(
        name: attachment.name,
        path: target.path,
        type: attachment.type,
      );
      persisted.add(
        ChatAttachment(
          name: attachment.name,
          path: target.path,
          type: attachment.type,
        ),
      );
      records.add(stored);
    }

    final manifest = await _readManifest(threadId);
    manifest[userMsgIndex.toString()] = [
      for (final attachment in records) attachment.toMap(),
    ];
    await _writeManifest(threadId, manifest);
    return List.unmodifiable(persisted);
  }

  Future<List<ChatAttachment>> loadMessageAttachments(
    String threadId,
    int userMsgIndex,
  ) async {
    final manifest = await _readManifest(threadId);
    final entries = manifest[userMsgIndex.toString()];
    if (entries is! List) return const [];
    return entries
        .whereType<Map>()
        .map((entry) => _StoredChatAttachment.fromMap(
              Map<String, Object?>.from(entry),
            ))
        .where((entry) => entry.path.trim().isNotEmpty)
        .map((entry) => entry.toChatAttachment())
        .toList(growable: false);
  }

  Future<void> deleteThread(String threadId) async {
    final dir = _threadDir(threadId);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  Future<Map<String, Object?>> _readManifest(String threadId) async {
    final file = _manifestFile(threadId);
    if (!await file.exists()) return <String, Object?>{};
    final raw = await file.readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      return Map<String, Object?>.from(decoded);
    }
    return <String, Object?>{};
  }

  Future<void> _writeManifest(
    String threadId,
    Map<String, Object?> manifest,
  ) async {
    final file = _manifestFile(threadId);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(manifest));
  }

  String _storedFilename(ChatAttachment attachment, {required int index}) {
    final extension = attachment.extension;
    final suffix = extension.isEmpty ? '' : '.$extension';
    return '${DateTime.now().millisecondsSinceEpoch}_${index + 1}$suffix';
  }

  String _uniqueFilename(Directory dir, String name) {
    final candidate = File('${dir.path}/$name');
    if (!candidate.existsSync()) return name;
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    return '${stem}_${DateTime.now().microsecondsSinceEpoch}$ext';
  }
}
