import 'dart:io';

import 'package:flutter/services.dart';

/// Outcome of an Android APK install request.
///
/// Reports whether the install succeeded or whether the system installer UI was
/// merely opened, along with any required permission prompt and error details.
class NapaxiApkInstallResult {
  /// Creates an install result with explicit field values.
  const NapaxiApkInstallResult({
    required this.success,
    this.installerOpened = false,
    this.permissionRequired = false,
    this.apkPath,
    this.error,
    this.code,
  });

  /// Builds a result from the native method-channel response map.
  factory NapaxiApkInstallResult.fromMap(Map<String, dynamic> map) {
    return NapaxiApkInstallResult(
      success: map['success'] as bool? ?? false,
      installerOpened: map['installerOpened'] as bool? ?? false,
      permissionRequired: map['permissionRequired'] as bool? ?? false,
      apkPath: map['apkPath'] as String?,
      error: map['error'] as String?,
      code: map['code'] as String?,
    );
  }

  /// Whether the APK was installed (or the install flow completed) successfully.
  final bool success;

  /// Whether the system package-installer UI was launched for the user.
  final bool installerOpened;

  /// Whether an install permission (e.g. install-from-unknown-sources) is needed.
  final bool permissionRequired;

  /// Filesystem path of the APK that was targeted, if reported.
  final String? apkPath;

  /// Human-readable error message when the install failed.
  final String? error;

  /// Machine-readable error code from the native layer.
  final String? code;

  /// Serializes this result back to a map mirroring the native channel shape.
  Map<String, dynamic> toMap() {
    return {
      'success': success,
      'installerOpened': installerOpened,
      'permissionRequired': permissionRequired,
      if (apkPath != null) 'apkPath': apkPath,
      if (error != null) 'error': error,
      if (code != null) 'code': code,
    };
  }
}

/// Triggers Android APK installation via the native host method channel.
class NapaxiApkInstaller {
  NapaxiApkInstaller._();

  static const MethodChannel _channel = MethodChannel(
    'com.napaxi.flutter/background',
  );

  /// Whether APK installation is available on the current platform (Android only).
  static bool get isSupported => Platform.isAndroid;

  /// Requests installation of the APK at [apkPath] through the native host.
  ///
  /// Returns a failure result on non-Android platforms or when the native
  /// layer throws a [PlatformException].
  static Future<NapaxiApkInstallResult> installApk(String apkPath) async {
    if (!Platform.isAndroid) {
      return const NapaxiApkInstallResult(
        success: false,
        error: 'APK installation is only supported on Android.',
      );
    }
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'installApk',
        {'apkPath': apkPath},
      );
      return NapaxiApkInstallResult.fromMap(result ?? {'success': false});
    } on PlatformException catch (error) {
      return NapaxiApkInstallResult(
        success: false,
        error: error.message ?? error.code,
        code: error.code,
      );
    }
  }
}
