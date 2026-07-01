import 'package:flutter_test/flutter_test.dart';
import 'package:napaxi_flutter/napaxi_flutter.dart';

void main() {
  test('APK installer reports unsupported platforms without a channel call',
      () async {
    final result = await NapaxiApkInstaller.installApk('/tmp/app.apk');

    expect(result.success, isFalse);
    expect(result.installerOpened, isFalse);
    expect(result.permissionRequired, isFalse);
    expect(result.error, 'APK installation is only supported on Android.');
  });
}
