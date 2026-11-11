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
  verifying,
  verifiedInstallable,
  awaitingConfirmation,
  installed,
  updateSucceeded,
  canceled,
  failed,
  buildFailed,
  gateFailed,
  alreadyInstalledSameVersion,
  unknown,
  unsupportedIos;

  static NapaxiApkInstallState fromString(String? raw) {
    switch (raw) {
      case 'generated':
        return NapaxiApkInstallState.generated;
      case 'verifying':
        return NapaxiApkInstallState.verifying;
      case 'verified_installable':
        return NapaxiApkInstallState.verifiedInstallable;
      case 'awaiting_confirmation':
        return NapaxiApkInstallState.awaitingConfirmation;
      case 'installed':
        return NapaxiApkInstallState.installed;
      case 'update_succeeded':
        return NapaxiApkInstallState.updateSucceeded;
      case 'canceled':
        return NapaxiApkInstallState.canceled;
      case 'failed':
        return NapaxiApkInstallState.failed;
      case 'build_failed':
        return NapaxiApkInstallState.buildFailed;
      case 'gate_failed':
        return NapaxiApkInstallState.gateFailed;
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
      case NapaxiApkInstallState.verifying:
        return 'verifying';
      case NapaxiApkInstallState.verifiedInstallable:
        return 'verified_installable';
      case NapaxiApkInstallState.awaitingConfirmation:
        return 'awaiting_confirmation';
      case NapaxiApkInstallState.installed:
        return 'installed';
      case NapaxiApkInstallState.updateSucceeded:
        return 'update_succeeded';
      case NapaxiApkInstallState.canceled:
        return 'canceled';
      case NapaxiApkInstallState.failed:
        return 'failed';
      case NapaxiApkInstallState.buildFailed:
        return 'build_failed';
      case NapaxiApkInstallState.gateFailed:
        return 'gate_failed';
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
    this.buildId,
    this.targetSdk,
    this.reason,
  });

  /// True when an `artifact.json` with `gate=ok` was located and its `sha256`
  /// matches the file currently on disk.
  final bool verified;

  /// [verifiedInstallable] on success, [failed] (or [gateFailed] /
  /// [buildFailed]) otherwise.
  final NapaxiApkInstallState state;

  final String? apkPath;
  final String? expectedSha256;
  final String? actualSha256;
  final int? size;
  final String? packageName;
  final String? versionCode;
  final String? versionName;
  // Distinct build attempt identifier from `artifact.json.build_id`. Two
  // rebuilds that produce identical APK bytes still get distinct build_ids,
  // so the install entry can distinguish "this exact build attempt" from
  // "another run that happened to land the same file."
  final String? buildId;
  final int? targetSdk;
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
    this.signedV3 = false,
    this.zipOk = false,
    this.builtAtIso,
    this.verifiedAtIso,
    this.builder,
    this.buildId,
    this.targetSdk,
    this.signingCertFingerprintSha256,
    this.buildToolVersion,
    this.validationRuleVersion,
    this.gateChecks,
    this.failureStage,
    this.failureReason,
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
      signedV3: json['signed_v3'] as bool? ?? false,
      zipOk: json['zip_ok'] as bool? ?? false,
      builtAtIso: json['built_at_iso'] as String?,
      verifiedAtIso: json['verified_at_iso'] as String?,
      builder: json['builder'] as String?,
      buildId: json['build_id'] as String?,
      targetSdk: (json['target_sdk'] as num?)?.toInt(),
      signingCertFingerprintSha256:
          json['signing_cert_fingerprint_sha256'] as String?,
      buildToolVersion: json['build_tool_version'] as String?,
      validationRuleVersion: json['validation_rule_version'] as String?,
      gateChecks: json['gate_checks'] as List<dynamic>?,
      failureStage: json['failure_stage'] as String?,
      failureReason: json['failure_reason'] as String?,
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
  final bool signedV3;
  final bool zipOk;
  final String? builtAtIso;
  final String? verifiedAtIso;
  final String? builder;
  final String? buildId;
  final int? targetSdk;
  final String? signingCertFingerprintSha256;
  final String? buildToolVersion;
  final String? validationRuleVersion;
  final List<dynamic>? gateChecks;
  final String? failureStage;
  final String? failureReason;
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
    this.buildId,
    this.failureStage,
    this.installerStatusCode,
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
      buildId: map['buildId'] as String?,
      failureStage: map['failureStage'] as String?,
      installerStatusCode: (map['installerStatusCode'] as num?)?.toInt(),
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

  /// Build attempt identifier from `artifact.json.build_id`, propagated by the
  /// native installer so a failure can attribute which exact build failed.
  final String? buildId;

  /// Stage the install died at, e.g. `pre_install`, `open_installer`,
  /// `post_install`. Lets the UI show "this build's install failed at stage X"
  /// instead of a generic failed state.
  final String? failureStage;

  /// Numeric installer status code from the native layer, when available.
  /// Mirrors Android `PackageInstaller.STATUS_*` codes so the caller can keep
  /// diagnostic context (sample K, L) beyond the wire-state enum.
  final int? installerStatusCode;

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
      if (buildId != null) 'buildId': buildId,
      if (failureStage != null) 'failureStage': failureStage,
      if (installerStatusCode != null) 'installerStatusCode': installerStatusCode,
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
        state: NapaxiApkInstallState.gateFailed,
        reason: 'no_artifact_json',
      );
    }
    late final Map<String, dynamic> json;
    try {
      json = jsonDecode(jsonFile.readAsStringSync()) as Map<String, dynamic>;
    } catch (error) {
      return NapaxiArtifactVerification(
        verified: false,
        state: NapaxiApkInstallState.gateFailed,
        reason: 'artifact_json_unreadable: $error',
      );
    }
    final record = NapaxiApkArtifactRecord.fromJson(json);
    if (!record.isGated) {
      // gate=failed carries build_id + failure_stage + failure_reason so the
      // UI can show "this build attempt failed at stage X (reason)" instead of
      // a generic gate_not_ok.
      final stageSuffix = record.failureStage == null
          ? ''
          : ':stage=${record.failureStage}';
      final reasonSuffix = record.failureReason == null
          ? ''
          : ':reason=${record.failureReason}';
      return NapaxiArtifactVerification(
        verified: false,
        state: NapaxiApkInstallState.gateFailed,
        buildId: record.buildId,
        targetSdk: record.targetSdk,
        reason: 'gate_not_ok:${record.gate}${stageSuffix}${reasonSuffix}',
      );
    }
    final apkPath = record.apkAbsPath;
    final expectedSha = record.sha256;
    final expectedSize = record.size;
    if (apkPath == null || expectedSha == null || expectedSize == null) {
      return NapaxiArtifactVerification(
        verified: false,
        state: NapaxiApkInstallState.gateFailed,
        buildId: record.buildId,
        targetSdk: record.targetSdk,
        reason:
            'artifact_missing_path_or_sha${record.buildId == null ? '' : ':build_id=${record.buildId}'}',
      );
    }
    final File apk = File(apkPath);
    if (!apk.existsSync()) {
      return NapaxiArtifactVerification(
        verified: false,
        state: NapaxiApkInstallState.failed,
        apkPath: apkPath,
        expectedSha256: expectedSha,
        size: expectedSize,
        packageName: record.packageName,
        versionCode: record.versionCode,
        versionName: record.versionName,
        buildId: record.buildId,
        targetSdk: record.targetSdk,
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
        size: expectedSize,
        packageName: record.packageName,
        versionCode: record.versionCode,
        versionName: record.versionName,
        buildId: record.buildId,
        targetSdk: record.targetSdk,
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
        size: expectedSize,
        packageName: record.packageName,
        versionCode: record.versionCode,
        versionName: record.versionName,
        buildId: record.buildId,
        targetSdk: record.targetSdk,
        reason:
            'sha256_mismatch${record.buildId == null ? '' : ':build_id=${record.buildId}'}',
      );
    }
    // G13: size check. The build script records the final APK size in
    // `artifact.json.size`; a replaced file whose sha256 collision-matches
    // (unlikely) but differs in size still fails the install gate.
    final actualSize = apk.lengthSync();
    if (actualSize != expectedSize) {
      return NapaxiArtifactVerification(
        verified: false,
        state: NapaxiApkInstallState.failed,
        apkPath: apkPath,
        expectedSha256: expectedSha,
        actualSha256: actualSha,
        size: actualSize,
        packageName: record.packageName,
        versionCode: record.versionCode,
        versionName: record.versionName,
        buildId: record.buildId,
        targetSdk: record.targetSdk,
        reason:
            'size_mismatch:expected=$expectedSize,actual=$actualSize${record.buildId == null ? '' : ':build_id=${record.buildId}'}',
      );
    }
    return NapaxiArtifactVerification(
      verified: true,
      state: NapaxiApkInstallState.verifiedInstallable,
      apkPath: apkPath,
      expectedSha256: expectedSha,
      actualSha256: actualSha,
      size: expectedSize,
      packageName: record.packageName,
      versionCode: record.versionCode,
      versionName: record.versionName,
      buildId: record.buildId,
      targetSdk: record.targetSdk,
    );
  }

  /// Requests installation of the APK at [apkPath] through the native host.
  ///
  /// When [expectedArtifactSha256] is provided, the native layer re-validates
  /// the file sha256 before opening the system installer, so a replaced file
  /// with the same path is rejected rather than installed. [buildId] is the
  /// build-attempt identifier from `artifact.json.build_id`; the native layer
  /// echoes it back in the install result so a failure can attribute which
  /// exact build attempt failed (samples D, E, H, K, L).
  ///
  /// Returns a failure result on non-Android platforms or when the native
  /// layer throws a [PlatformException].
  static Future<NapaxiApkInstallResult> installApk(
    String apkPath, {
    String? expectedArtifactSha256,
    String? buildId,
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
          if (buildId != null) 'buildId': buildId,
        },
      );
      final mapped = NapaxiApkInstallResult.fromMap(result ?? {'success': false});
      // If the native layer did not echo buildId (older plugin), fill it from
      // the caller so install-result attribution is preserved anyway.
      if (mapped.buildId == null && buildId != null) {
        return NapaxiApkInstallResult(
          success: mapped.success,
          installerOpened: mapped.installerOpened,
          permissionRequired: mapped.permissionRequired,
          apkPath: mapped.apkPath,
          error: mapped.error,
          code: mapped.code,
          installState: mapped.installState,
          artifactSha256: mapped.artifactSha256,
          artifactSize: mapped.artifactSize,
          versionCode: mapped.versionCode,
          versionName: mapped.versionName,
          packageName: mapped.packageName,
          canceled: mapped.canceled,
          failedReason: mapped.failedReason,
          buildId: buildId,
          failureStage: mapped.failureStage,
          installerStatusCode: mapped.installerStatusCode,
        );
      }
      return mapped;
    } on PlatformException catch (error) {
      return NapaxiApkInstallResult(
        success: false,
        error: error.message ?? error.code,
        code: error.code,
        installState: NapaxiApkInstallState.failed,
        failedReason: error.message,
        buildId: buildId,
      );
    }
  }

  /// Convenience: verify the artifact at [androidProjectRoot] and, only when
  /// the registry gate passed AND the on-disk file matches, dispatch to
  /// [installApk]. Returns the verification result alongside an install
  /// result when one was produced; install is null when the verification
  /// refused to open the installer. This is the entry point install UIs
  /// should call so that a gate-failed / replaced / sha256-mismatch artifact
  /// never reaches the system installer (samples A, E, F, G, H).
  static Future<NapaxiApkArtifactInstallAttempt> installVerified(
    String androidProjectRoot, {
    String? artifactJsonPath,
  }) async {
    final verification =
        await verifyArtifact(androidProjectRoot, artifactJsonPath: artifactJsonPath);
    if (!verification.verified ||
        verification.apkPath == null ||
        verification.expectedSha256 == null) {
      return NapaxiApkArtifactInstallAttempt(
        verification: verification,
        install: null,
      );
    }
    final install = await installApk(
      verification.apkPath!,
      expectedArtifactSha256: verification.expectedSha256,
      buildId: verification.buildId,
    );
    return NapaxiApkArtifactInstallAttempt(verification: verification, install: install);
  }
}

/// Pair returned by [NapaxiApkInstaller.installVerified]: the artifact
/// verification result plus the install result (or null when the gate refused
/// to open the installer). Lets the demo UI render the "this build failed at
/// stage X" message from the verification without ever opening the installer.
class NapaxiApkArtifactInstallAttempt {
  const NapaxiApkArtifactInstallAttempt({
    required this.verification,
    required this.install,
  });

  final NapaxiArtifactVerification verification;
  final NapaxiApkInstallResult? install;

  /// True only when the install was actually attempted (verification passed).
  bool get installAttempted => install != null;

  /// True only when the install reported [installed] or [updateSucceeded].
  bool get succeeded =>
      install != null &&
      (install!.installState == NapaxiApkInstallState.installed ||
          install!.installState == NapaxiApkInstallState.updateSucceeded);
}
