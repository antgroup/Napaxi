import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

/// Lifecycle phase reported by the native installer for an in-flight APK install.
///
/// Mirrors the Android `PackageInstaller` session status, plus carrier states for
/// "the build product has been generated / verified installable on disk" before
/// any native install is attempted, and for unsupporting platforms.
///
/// Keep this enum in sync with:
/// - `packages/flutter/lib/platform_tools/tools/install_app_tool.dart`
/// - `packages/android/src/main/kotlin/com/napaxi/android/Models.kt`
///   (`NapaxiApkInstallResult.installState`)
/// - `packages/flutter/android/src/main/kotlin/com/napaxi/flutter/NapaxiFlutterPlugin.kt`
/// - `packages/ios` (unsupported platform returns `unsupportedIos`)
enum NapaxiApkInstallState {
  generated,
  verifiedInstallable,
  awaitingConfirmation,
  installed,
  canceled,
  failed,
  alreadyInstalledSameVersion,
  unknown,
  unsupportedIos;

  static NapaxiApkInstallState fromString(String? raw) {
    switch (raw) {
      case 'generated':
        return NapaxiApkInstallState.generated;
      case 'verified_installable':
        return NapaxiApkInstallState.verifiedInstallable;
      case 'awaiting_confirmation':
        return NapaxiApkInstallState.awaitingConfirmation;
      case 'installed':
        return NapaxiApkInstallState.installed;
      case 'canceled':
        return NapaxiApkInstallState.canceled;
      case 'failed':
        return NapaxiApkInstallState.failed;
      case 'already_installed_same_version':
        return NapaxiApkInstallState.alreadyInstalledSameVersion;
      case 'unsupported_ios':
        return NapaxiApkInstallState.unsupportedIos;
      case 'unknown':
      default:
        return NapaxiApkInstallState.unknown;
    }
  }

  String get wireName {
    switch (this) {
      case NapaxiApkInstallState.generated:
        return 'generated';
      case NapaxiApkInstallState.verifiedInstallable:
        return 'verified_installable';
      case NapaxiApkInstallState.awaitingConfirmation:
        return 'awaiting_confirmation';
      case NapaxiApkInstallState.installed:
        return 'installed';
      case NapaxiApkInstallState.canceled:
        return 'canceled';
      case NapaxiApkInstallState.failed:
        return 'failed';
      case NapaxiApkInstallState.alreadyInstalledSameVersion:
        return 'already_installed_same_version';
      case NapaxiApkInstallState.unsupportedIos:
        return 'unsupported_ios';
      case NapaxiApkInstallState.unknown:
        return 'unknown';
    }
  }
}

/// An APK install-via-artifact-registry verification result.
class NapaxiArtifactVerification {
  const NapaxiArtifactVerification({
    required this.verified,
    required this.state,
    this.apkPath,
    this.expectedSha256,
    this.actualSha256,
    this.size,
    this.packageName,
    this.versionCode,
    this.versionName,
    this.reason,
  });

  /// True when an `artifact.json` with `gate=ok` was located and its `sha256`
  /// matches the file currently on disk.
  final bool verified;

  /// [verifiedInstallable] on success, [failed] otherwise.
  final NapaxiApkInstallState state;

  final String? apkPath;
  final String? expectedSha256;
  final String? actualSha256;
  final int? size;
  final String? packageName;
  final String? versionCode;
  final String? versionName;
  final String? reason;
}

/// Marker fields for the registered APK product written by
/// `crates/core/src/skills/bundled_seeds/android-apk-build/scripts/build_apk.sh`
/// under `<project>/.mobile/artifact.json`.
class NapaxiApkArtifactRecord {
  NapaxiApkArtifactRecord({
    required this.gate,
    required this.apkAbsPath,
    required this.sha256,
    required this.size,
    this.packageName,
    this.versionCode,
    this.versionName,
    this.arscUncompressed = false,
    this.arscAligned = false,
    this.signedV1 = false,
    this.signedV2 = false,
    this.zipOk = false,
    this.builtAtIso,
    this.builder,
    this.rawJson,
  });

  factory NapaxiApkArtifactRecord.fromJson(Map<String, dynamic> json) {
    return NapaxiApkArtifactRecord(
      gate: json['gate'] as String? ?? '',
      apkAbsPath: json['apk_abs_path'] as String?,
      sha256: json['sha256'] as String?,
      size: (json['size'] as num?)?.toInt(),
      packageName: json['packageName'] as String?,
      versionCode: json['versionCode']?.toString(),
      versionName: json['versionName']?.toString(),
      arscUncompressed: json['arsc_uncompressed'] as bool? ?? false,
      arscAligned: json['arsc_aligned'] as bool? ?? false,
      signedV1: json['signed_v1'] as bool? ?? false,
      signedV2: json['signed_v2'] as bool? ?? false,
      zipOk: json['zip_ok'] as bool? ?? false,
      builtAtIso: json['built_at_iso'] as String?,
      builder: json['builder'] as String?,
      rawJson: json,
    );
  }

  /// `'ok'` for a gated product; any other value (e.g. `'failed'`) is not
  /// installable.
  final String gate;
  final String? apkAbsPath;
  final String? sha256;
  final int? size;
  final String? packageName;
  final String? versionCode;
  final String? versionName;
  final bool arscUncompressed;
  final bool arscAligned;
  final bool signedV1;
  final bool signedV2;
  final bool zipOk;
  final String? builtAtIso;
  final String? builder;
  final Map<String, dynamic>? rawJson;

  bool get isGated => gate == 'ok';
}

/// Outcome of an Android APK install request.
///
/// Reports whether the install succeeded or whether the system installer UI was
/// merely opened, along with any required permission prompt and error details.
/// `installState` distinguishes the install lifecycle phases mandated by the
/// Agent App product gate: a generated artifact that has not been verified
/// installable, an install pending user confirmation, an install that the
/// user canceled, a failed install blocked by signature/version mismatch, and
/// the same-package/same-version-already-installed case.
class NapaxiApkInstallResult {
  /// Creates an install result with explicit field values.
  const NapaxiApkInstallResult({
    required this.success,
    this.installerOpened = false,
    this.permissionRequired = false,
    this.apkPath,
    this.error,
    this.code,
    this.installState = NapaxiApkInstallState.unknown,
    this.artifactSha256,
    this.artifactSize,
    this.versionCode,
    this.versionName,
    this.packageName,
    this.canceled = false,
    this.failedReason,
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
      installState: NapaxiApkInstallState.fromString(
        map['installState'] as String? ?? map['install_state'] as String?,
      ),
      artifactSha256: map['artifactSha256'] as String?,
      artifactSize: (map['artifactSize'] as num?)?.toInt(),
      versionCode: map['versionCode']?.toString(),
      versionName: map['versionName'] as String?,
      packageName: map['packageName'] as String?,
      canceled: map['canceled'] as bool? ?? false,
      failedReason: map['failedReason'] as String?,
    );
  }

  /// Whether APK installation completed successfully.
  ///
  /// Opening the installer alone does not count as installation. In that case
  /// [installerOpened] is true and Android still awaits the user's decision.
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

  /// Phase of the install lifecycle reported by the native layer. Anything
  /// other than [NapaxiApkInstallState.installed] is not a completed install.
  final NapaxiApkInstallState installState;

  /// sha256 of the gated product recorded by the build script. When provided
  /// to [NapaxiApkInstaller.installApk], the native layer rechecks this digest
  /// against the on-disk file before opening the system installer.
  final String? artifactSha256;

  /// Size in bytes of the gated artifact, when known.
  final int? artifactSize;

  final String? versionCode;
  final String? versionName;
  final String? packageName;

  /// True when the user actively canceled the system install confirmation.
  final bool canceled;

  /// Human-readable failure cause when [installState] is [failed].
  final String? failedReason;

  /// Serializes this result back to a map mirroring the native channel shape.
  Map<String, dynamic> toMap() {
    return {
      'success': success,
      'installerOpened': installerOpened,
      'permissionRequired': permissionRequired,
      'installState': installState.wireName,
      if (apkPath != null) 'apkPath': apkPath,
      if (error != null) 'error': error,
      if (code != null) 'code': code,
      if (artifactSha256 != null) 'artifactSha256': artifactSha256,
      if (artifactSize != null) 'artifactSize': artifactSize,
      if (versionCode != null) 'versionCode': versionCode,
      if (versionName != null) 'versionName': versionName,
      if (packageName != null) 'packageName': packageName,
      'canceled': canceled,
      if (failedReason != null) 'failedReason': failedReason,
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

  /// Reads `<androidProjectRoot>/.mobile/artifact.json`, locates the registered
  /// APK by absolute path, recomputes the on-disk sha256, and returns a
  /// [NapaxiArtifactVerification] with [verifiedInstallable] when the digest
  /// matches `gate=ok`, [failed] otherwise.
  ///
  /// [androidProjectRoot] is the project directory whose `build/<APP_NAME>.apk`
  /// was produced by the build skill; this is where `.mobile/artifact.json`
  /// lives. When [artifactJsonPath] is provided directly it takes precedence.
  /// When no record is found, returns [failed] with `reason='no_artifact_json'`
  /// so callers can hide the install entry.
  static Future<NapaxiArtifactVerification> verifyArtifact(
    String androidProjectRoot, {
    String? artifactJsonPath,
  }) async {
    final File jsonFile = File(
      artifactJsonPath ?? '$androidProjectRoot/.mobile/artifact.json',
    );
    if (!jsonFile.existsSync()) {
      return NapaxiArtifactVerification(
        verified: false,
        state: NapaxiApkInstallState.failed,
        reason: 'no_artifact_json',
      );
    }
    late final Map<String, dynamic> json;
    try {
      json = jsonDecode(jsonFile.readAsStringSync()) as Map<String, dynamic>;
    } catch (error) {
      return NapaxiArtifactVerification(
        verified: false,
        state: NapaxiApkInstallState.failed,
        reason: 'artifact_json_unreadable: $error',
      );
    }
    final record = NapaxiApkArtifactRecord.fromJson(json);
    if (!record.isGated) {
      return NapaxiArtifactVerification(
        verified: false,
        state: NapaxiApkInstallState.failed,
        reason: 'gate_not_ok:${record.gate}',
      );
    }
    final apkPath = record.apkAbsPath;
    final expectedSha = record.sha256;
    if (apkPath == null || expectedSha == null) {
      return NapaxiArtifactVerification(
        verified: false,
        state: NapaxiApkInstallState.failed,
        reason: 'artifact_missing_path_or_sha',
      );
    }
    final File apk = File(apkPath);
    if (!apk.existsSync()) {
      return NapaxiArtifactVerification(
        verified: false,
        state: NapaxiApkInstallState.failed,
        apkPath: apkPath,
        expectedSha256: expectedSha,
        reason: 'apk_file_missing',
      );
    }
    final String actualSha;
    try {
      final digest = sha256.convert(await apk.readAsBytes());
      actualSha = digest.toString();
    } catch (error) {
      return NapaxiArtifactVerification(
        verified: false,
        state: NapaxiApkInstallState.failed,
        apkPath: apkPath,
        expectedSha256: expectedSha,
        reason: 'sha_compute_failed: $error',
      );
    }
    if (actualSha != expectedSha) {
      return NapaxiArtifactVerification(
        verified: false,
        state: NapaxiApkInstallState.failed,
        apkPath: apkPath,
        expectedSha256: expectedSha,
        actualSha256: actualSha,
        size: record.size,
        packageName: record.packageName,
        versionCode: record.versionCode,
        versionName: record.versionName,
        reason: 'sha256_mismatch',
      );
    }
    return NapaxiArtifactVerification(
      verified: true,
      state: NapaxiApkInstallState.verifiedInstallable,
      apkPath: apkPath,
      expectedSha256: expectedSha,
      actualSha256: actualSha,
      size: record.size ?? apk.lengthSync(),
      packageName: record.packageName,
      versionCode: record.versionCode,
      versionName: record.versionName,
    );
  }

  /// Requests installation of the APK at [apkPath] through the native host.
  ///
  /// When [expectedArtifactSha256] is provided, the native layer re-validates
  /// the file sha256 before opening the system installer, so a replaced file
  /// with the same path is rejected rather than installed.
  ///
  /// Returns a failure result on non-Android platforms or when the native
  /// layer throws a [PlatformException].
  static Future<NapaxiApkInstallResult> installApk(
    String apkPath, {
    String? expectedArtifactSha256,
  }) async {
    if (!Platform.isAndroid) {
      return NapaxiApkInstallResult(
        success: false,
        error: 'APK installation is only supported on Android.',
        code: 'unsupported_platform',
        installState: NapaxiApkInstallState.unsupportedIos,
      );
    }
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'installApk',
        {
          'apkPath': apkPath,
          if (expectedArtifactSha256 != null)
            'expectedArtifactSha256': expectedArtifactSha256,
        },
      );
      return NapaxiApkInstallResult.fromMap(result ?? {'success': false});
    } on PlatformException catch (error) {
      return NapaxiApkInstallResult(
        success: false,
        error: error.message ?? error.code,
        code: error.code,
        installState: NapaxiApkInstallState.failed,
        failedReason: error.message,
      );
    }
  }
}
