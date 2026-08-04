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
        'apkPath': '/tmp/app.apk',
        'code': 'installer_opened',
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
}
