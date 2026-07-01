import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'api/json_codec.dart';
import 'generated/bridge/file_bridge.dart' as rust_file_bridge;

/// Resolved file reference detected in Agent output text.
class ResolvedFile {
  final String sandboxPath;
  final String realPath;
  final String filename;
  final String mimeType;
  final bool isImage;
  final bool isDirectory;
  final bool exists;
  final int? sizeBytes;

  const ResolvedFile({
    required this.sandboxPath,
    required this.realPath,
    required this.filename,
    required this.mimeType,
    required this.isImage,
    this.isDirectory = false,
    required this.exists,
    this.sizeBytes,
  });

  factory ResolvedFile.fromMap(Map<String, dynamic> map) {
    return ResolvedFile(
      sandboxPath: map['sandbox_path'] as String? ?? '',
      realPath: map['real_path'] as String? ?? '',
      filename: map['filename'] as String? ?? '',
      mimeType: map['mime_type'] as String? ?? 'application/octet-stream',
      isImage: map['is_image'] as bool? ?? false,
      isDirectory: map['is_directory'] as bool? ?? false,
      exists: map['exists'] as bool? ?? false,
      sizeBytes: (map['size_bytes'] as num?)?.toInt(),
    );
  }
}

/// File info for workspace browsing.
class WorkspaceFileInfo {
  final String name;
  final String sandboxPath;
  final String realPath;
  final String mimeType;
  final bool isDirectory;
  final int sizeBytes;
  final DateTime modified;

  const WorkspaceFileInfo({
    required this.name,
    required this.sandboxPath,
    required this.realPath,
    required this.mimeType,
    required this.isDirectory,
    required this.sizeBytes,
    required this.modified,
  });

  factory WorkspaceFileInfo.fromMap(Map<String, dynamic> map) {
    return WorkspaceFileInfo(
      name: map['name'] as String? ?? '',
      sandboxPath: map['sandbox_path'] as String? ?? '',
      realPath: map['real_path'] as String? ?? '',
      mimeType: map['mime_type'] as String? ?? 'application/octet-stream',
      isDirectory: map['is_directory'] as bool? ?? false,
      sizeBytes: (map['size_bytes'] as num?)?.toInt() ?? 0,
      modified: DateTime.fromMillisecondsSinceEpoch(
        (map['modified'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}

/// Bridges the Napaxi sandbox filesystem and the App's real filesystem.
///
/// Mirrors Rust `LinuxAwareFileTool.map_path()` path-mapping logic so that
/// the Dart/Flutter side can resolve sandbox paths (e.g. `/workspace/out.png`)
/// to their real on-device location, and vice versa.
class NapaxiFileBridge {
  NapaxiFileBridge._({required this.filesDir, required int handle})
      : _handle = handle;

  static const MethodChannel _platformChannel = MethodChannel(
    'com.napaxi.flutter/background',
  );

  static NapaxiFileBridge? _instance;
  static NapaxiFileBridge get instance => _instance!;
  static bool get isInitialized => _instance != null;

  /// Initialize the file bridge. Called by [NapaxiEngine] after engine creation.
  static void init({required String filesDir, int? handle}) {
    final effectiveHandle = handle ?? _instance?._handle;
    if (effectiveHandle == null) {
      return;
    }
    _instance = NapaxiFileBridge._(filesDir: filesDir, handle: effectiveHandle);
    rust_file_bridge.initFileBridge(handle: effectiveHandle);
  }

  final String filesDir;
  final int _handle;

  Directory get workspaceDir =>
      Directory(rust_file_bridge.workspaceDir(handle: _handle));
  Directory get rootfsDir =>
      Directory(rust_file_bridge.rootfsDir(handle: _handle));
  Directory get skillsDir =>
      Directory(rust_file_bridge.skillsDir(handle: _handle));

  // ── Git commit identity (sandbox rootfs ~/.gitconfig) ──

  /// Write the Git commit identity (`user.name` / `user.email`) into the sandbox
  /// rootfs `~/.gitconfig` so the agent's `git commit` authors commits with this
  /// identity. Returns `true` on success.
  bool configureGitIdentity({required String name, required String email}) {
    return rust_file_bridge.configureGitIdentity(
      handle: _handle,
      name: name,
      email: email,
    );
  }

  /// Read the Git commit identity from the sandbox rootfs `~/.gitconfig`.
  ///
  /// Returns a record `(name, email)` when both are set, otherwise `null`.
  ({String name, String email})? readGitIdentity() {
    final raw = rust_file_bridge.readGitIdentity(handle: _handle);
    if (raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final name = decoded['name'];
        final email = decoded['email'];
        if (name is String && email is String &&
            name.trim().isNotEmpty && email.trim().isNotEmpty) {
          return (name: name, email: email);
        }
      }
    } catch (_) {
      // Malformed payload — treat as no identity configured.
    }
    return null;
  }

  /// Ask the host OS to open a local file with an installed app.
  ///
  /// Android uses the SDK FileProvider and a `content://` URI because raw
  /// `file://` URIs are rejected by modern Android apps.
  static Future<Map<String, dynamic>> openLocalFile(
    String path, {
    String mimeType = 'application/octet-stream',
  }) async {
    if (!Platform.isAndroid) {
      return {
        'success': false,
        'error': 'Opening local files is only implemented on Android.',
      };
    }
    try {
      final result = await _platformChannel.invokeMapMethod<String, dynamic>(
        'openFile',
        {'path': path, 'mimeType': mimeType},
      );
      return result ?? {'success': false};
    } on PlatformException catch (error) {
      return {
        'success': false,
        'error': error.message ?? error.code,
        'code': error.code,
      };
    }
  }

  Directory workspaceDirScoped({
    required String accountId,
    required String agentId,
  }) {
    return Directory(
      rust_file_bridge.workspaceDirScoped(
        handle: _handle,
        accountId: accountId,
        agentId: agentId,
      ),
    );
  }

  // ── Path mapping (mirrors Rust linux_file_tools.rs:59-83) ──

  /// Map a sandbox Linux-style path to the real filesystem path.
  /// Returns null if the path doesn't match any known sandbox prefix.
  String? sandboxToReal(String sandboxPath) {
    return rust_file_bridge.sandboxToReal(
      handle: _handle,
      sandboxPath: sandboxPath,
    );
  }

  String? sandboxToRealScoped(
    String sandboxPath, {
    required String accountId,
    required String agentId,
  }) {
    return rust_file_bridge.sandboxToRealScoped(
      handle: _handle,
      accountId: accountId,
      agentId: agentId,
      sandboxPath: sandboxPath,
    );
  }

  /// Map a real filesystem path back to the sandbox Linux-style path.
  /// Returns null if the path isn't within any mapped sandbox directory.
  String? realToSandbox(String realPath) {
    return rust_file_bridge.realToSandbox(handle: _handle, realPath: realPath);
  }

  String? realToSandboxScoped(
    String realPath, {
    required String accountId,
    required String agentId,
  }) {
    return rust_file_bridge.realToSandboxScoped(
      handle: _handle,
      accountId: accountId,
      agentId: agentId,
      realPath: realPath,
    );
  }

  // ── File operations ──

  /// Resolve a sandbox path to a real [File], returning null if it doesn't exist.
  Future<File?> resolveFile(String sandboxPath) async {
    final real = sandboxToReal(sandboxPath);
    if (real == null) return null;
    final file = File(real);
    return await file.exists() ? file : null;
  }

  /// Delete a file by its sandbox path.
  Future<void> deleteFile(String sandboxPath) async {
    await rust_file_bridge.deleteSandboxFile(
      handle: _handle,
      sandboxPath: sandboxPath,
    );
  }

  Future<void> deleteFileScoped(
    String sandboxPath, {
    required String accountId,
    required String agentId,
  }) async {
    await rust_file_bridge.deleteSandboxFileScoped(
      handle: _handle,
      accountId: accountId,
      agentId: agentId,
      sandboxPath: sandboxPath,
    );
  }

  /// Detect file references in text and resolve them.
  ///
  /// Returns a list of [ResolvedFile] for paths that map to existing files.
  List<ResolvedFile> detectFileReferences(String text) {
    final json = rust_file_bridge.detectFileReferences(
      handle: _handle,
      text: text,
    );
    return decodeJsonObjectList(json, ResolvedFile.fromMap);
  }

  List<ResolvedFile> detectFileReferencesScoped(
    String text, {
    required String accountId,
    required String agentId,
  }) {
    final json = rust_file_bridge.detectFileReferencesScoped(
      handle: _handle,
      accountId: accountId,
      agentId: agentId,
      text: text,
    );
    return decodeJsonObjectList(json, ResolvedFile.fromMap);
  }

  // ── Workspace browsing ──

  /// List files in the workspace directory.
  ///
  /// [subdir] is relative to workspace root.
  /// When [recursive] is true, lists all files recursively.
  Future<List<WorkspaceFileInfo>> listFiles({
    String? subdir,
    bool recursive = false,
  }) async {
    final json = await rust_file_bridge.listWorkspaceFilesystem(
      handle: _handle,
      subdir: subdir,
      recursive: recursive,
    );
    return decodeJsonObjectList(json, WorkspaceFileInfo.fromMap);
  }

  Future<List<WorkspaceFileInfo>> listFilesScoped({
    required String accountId,
    required String agentId,
    String? subdir,
    bool recursive = false,
  }) async {
    rust_file_bridge.initFileBridgeScoped(
      handle: _handle,
      accountId: accountId,
      agentId: agentId,
    );
    final json = await rust_file_bridge.listWorkspaceFilesystemScoped(
      handle: _handle,
      accountId: accountId,
      agentId: agentId,
      subdir: subdir,
      recursive: recursive,
    );
    return decodeJsonObjectList(json, WorkspaceFileInfo.fromMap);
  }

  /// Get total size of all files in the workspace.
  Future<int> workspaceSize() async {
    return rust_file_bridge.workspaceSize(handle: _handle).toInt();
  }

  Future<int> workspaceSizeScoped({
    required String accountId,
    required String agentId,
  }) async {
    return rust_file_bridge
        .workspaceSizeScoped(
          handle: _handle,
          accountId: accountId,
          agentId: agentId,
        )
        .toInt();
  }
}
