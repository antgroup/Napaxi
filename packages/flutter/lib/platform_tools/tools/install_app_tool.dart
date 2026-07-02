import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../capability_context.dart';

/// Platform tool that installs an APK package (Android only).
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
      });
    }

    final params = jsonDecode(paramsJson) as Map<String, dynamic>;
    final apkPath = params['apk_path'] as String? ?? '';
    if (apkPath.isEmpty) {
      return jsonEncode({'success': false, 'error': 'apk_path is required.'});
    }

    final resolvedApkPath = context.resolveSandboxOrLocalPath(apkPath);
    final apkFile = File(resolvedApkPath);
    if (!apkFile.existsSync()) {
      return jsonEncode({
        'success': false,
        'error': 'APK file does not exist: $apkPath',
        if (resolvedApkPath != apkPath) 'resolved_path': resolvedApkPath,
      });
    }

    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'installApk',
        {'apkPath': resolvedApkPath},
      );
      return jsonEncode(result ?? {'success': false});
    } on PlatformException catch (e) {
      return jsonEncode({
        'success': false,
        'error': e.message ?? e.code,
        'code': e.code,
      });
    }
  }
}
