import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../apk_installer.dart';
import '../capability_context.dart';

/// Platform tool that installs an APK package (Android only).
///
/// The tool gates installation on a registered, sha256-verified final product:
/// callers MAY pass `apk_path` plus the build script's `expected_sha256`. When
/// `expected_sha256` is provided, the native layer re-validates the file
/// digest before opening the system installer; a replaced file with the same
/// path yields [NapaxiApkInstallState.failed] rather than opening the installer.
///
/// When `expected_sha256` is omitted the tool still runs, but demo install UIs
/// should always pass it (see `examples/flutter` install entry points).
class InstallAppTool {
  static const _channel = MethodChannel('com.napaxi.flutter/background');

  static Future<String> execute(
    String paramsJson,
    CapabilityContext context,
  ) async {
    if (!Platform.isAndroid) {
      return jsonEncode({
        'success': false,
        'error': 'install_apk is only supported on Android.',
        'installState': NapaxiApkInstallState.unsupportedIos.wireName,
      });
    }

    final params = jsonDecode(paramsJson) as Map<String, dynamic>;
    final apkPath = params['apk_path'] as String? ?? '';
    if (apkPath.isEmpty) {
      return jsonEncode({
        'success': false,
        'error': 'apk_path is required.',
        'installState': NapaxiApkInstallState.failed.wireName,
      });
    }
    final expectedSha256 = params['expected_sha256'] as String?;

    final resolvedApkPath = context.resolveSandboxOrLocalPath(apkPath);
    final apkFile = File(resolvedApkPath);
    if (!apkFile.existsSync()) {
      return jsonEncode({
        'success': false,
        'error': 'APK file does not exist: $apkPath',
        'installState': NapaxiApkInstallState.failed.wireName,
        if (resolvedApkPath != apkPath) 'resolved_path': resolvedApkPath,
      });
    }

    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'installApk',
        {
          'apkPath': resolvedApkPath,
          if (expectedSha256 != null) 'expectedArtifactSha256': expectedSha256,
        },
      );
      // Ensure installState is present in the outgoing wire shape so demo side
      // can rely on it even when the native layer omits it for compatibility.
      final withState = Map<String, dynamic>.from(result ?? {'success': false});
      if (withState['installState'] == null) {
        final fallback = NapaxiApkInstallState.fromString(
          withState['code'] as String?,
        );
        withState['installState'] = fallback.wireName;
      }
      return jsonEncode(withState);
    } on PlatformException catch (e) {
      return jsonEncode({
        'success': false,
        'error': e.message ?? e.code,
        'code': e.code,
        'installState': NapaxiApkInstallState.failed.wireName,
      });
    }
  }
}
