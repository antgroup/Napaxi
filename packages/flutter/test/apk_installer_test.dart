import 'package:flutter_test/flutter_test.dart';
import 'package:napaxi_flutter/napaxi_flutter.dart';

void main() {
  test(
    'APK installer does not report opening the installer as installation',
    () {
      final result = NapaxiApkInstallResult.fromMap({
        'success': false,
        'installerOpened': true,
        'apkPath': '/tmp/app.apk',
        'code': 'installer_opened',
      });

      expect(result.success, isFalse);
      expect(result.installerOpened, isTrue);
      expect(result.code, 'installer_opened');
      expect(result.toMap(), {
        'success': false,
        'installerOpened': true,
        'permissionRequired': false,
        'installState': 'unknown',
        'apkPath': '/tmp/app.apk',
        'code': 'installer_opened',
        'canceled': false,
      });
    },
  );

  test(
    'APK installer reports unsupported platforms without a channel call',
    () async {
      final result = await NapaxiApkInstaller.installApk('/tmp/app.apk');

      expect(result.success, isFalse);
      expect(result.installerOpened, isFalse);
      expect(result.permissionRequired, isFalse);
      expect(result.error, 'APK installation is only supported on Android.');
    },
  );

  // DIMA 2026110400120316848 regression tests: model layer only, no channel
  // call. These cover the installState state machine, the
  // build_id/failureStage/installerStatusCode propagation, and the new
  // verifying/build_failed/gate_failed/update_succeeded states.

  test(
    'APK install result round-trips build_id, failureStage, installerStatusCode',
    () {
      final result = NapaxiApkInstallResult.fromMap({
        'success': false,
        'installerOpened': false,
        'apkPath': '/tmp/app.apk',
        'installState': 'failed',
        'code': 'signature_or_version_blocked',
        'buildId': 'abcdef0123456789',
        'failureStage': 'post_install',
        'installerStatusCode': 7,
      });
      expect(result.buildId, 'abcdef0123456789');
      expect(result.failureStage, 'post_install');
      expect(result.installerStatusCode, 7);
      expect(result.installState, NapaxiApkInstallState.failed);
      final map = result.toMap();
      expect(map['buildId'], 'abcdef0123456789');
      expect(map['failureStage'], 'post_install');
      expect(map['installerStatusCode'], 7);
    },
  );

  test('APK install state maps every extended wire name', () {
    const wires = <String, NapaxiApkInstallState>{
      'generated': NapaxiApkInstallState.generated,
      'verifying': NapaxiApkInstallState.verifying,
      'verified_installable': NapaxiApkInstallState.verifiedInstallable,
      'awaiting_confirmation': NapaxiApkInstallState.awaitingConfirmation,
      'installed': NapaxiApkInstallState.installed,
      'update_succeeded': NapaxiApkInstallState.updateSucceeded,
      'canceled': NapaxiApkInstallState.canceled,
      'failed': NapaxiApkInstallState.failed,
      'build_failed': NapaxiApkInstallState.buildFailed,
      'gate_failed': NapaxiApkInstallState.gateFailed,
      'already_installed_same_version':
          NapaxiApkInstallState.alreadyInstalledSameVersion,
      'unknown': NapaxiApkInstallState.unknown,
      'unsupported_ios': NapaxiApkInstallState.unsupportedIos,
    };
    for (final entry in wires.entries) {
      expect(
        NapaxiApkInstallState.fromString(entry.key),
        entry.value,
        reason: 'wire name ${entry.key} must round-trip',
      );
      expect(entry.value.wireName, entry.key);
    }
  });

  test(
    'artifact record round-trips new gated-artifact fields from build_apk.sh',
    () {
      final record = NapaxiApkArtifactRecord.fromJson({
        'gate': 'ok',
        'build_id': 'abcdef0123456789',
        'apk_abs_path': '/tmp/project/build/app.apk',
        'sha256': 'deadbeef',
        'size': 1234,
        'packageName': 'com.napaxi.example.test',
        'versionCode': '2',
        'versionName': '1.1',
        'target_sdk': 33,
        'arsc_uncompressed': true,
        'arsc_aligned': true,
        'signed_v1': true,
        'signed_v2': true,
        'signed_v3': false,
        'zip_ok': true,
        'signing_cert_fingerprint_sha256': 'AA:BB:CC',
        'build_tool_version': '33.0.2',
        'validation_rule_version': 'android-apk-build.gate.v1',
        'built_at_iso': '2026-11-05T00:00:00Z',
        'verified_at_iso': '2026-11-05T00:00:05Z',
        'builder': 'napaxi-bundled-android-apk-build',
        'gate_checks': [
          {'name': 'zip_integrity', 'result': 'pass'},
        ],
        'failure_stage': null,
        'failure_reason': null,
      });
      expect(record.gate, 'ok');
      expect(record.isGated, isTrue);
      expect(record.buildId, 'abcdef0123456789');
      expect(record.targetSdk, 33);
      expect(record.signedV3, isFalse);
      expect(record.signedV1, isTrue);
      expect(record.signedV2, isTrue);
      expect(record.signingCertFingerprintSha256, 'AA:BB:CC');
      expect(record.buildToolVersion, '33.0.2');
      expect(record.validationRuleVersion, 'android-apk-build.gate.v1');
      expect(record.gateChecks, isNotEmpty);
    },
  );

  test(
    'artifact record exposes gate=failed with build_id + failure_stage for UI',
    () {
      final record = NapaxiApkArtifactRecord.fromJson({
        'gate': 'failed',
        'build_id': 'abcdef0123456789',
        'failure_stage': 'post_sign_digest',
        'failure_reason': 'post_sign_content_mismatch',
        'validation_rule_version': 'android-apk-build.gate.v1',
        'built_at_iso': '2026-11-05T00:00:00Z',
      });
      expect(record.gate, 'failed');
      expect(record.isGated, isFalse);
      expect(record.buildId, 'abcdef0123456789');
      expect(record.failureStage, 'post_sign_digest');
      expect(record.failureReason, 'post_sign_content_mismatch');
    },
  );
}
