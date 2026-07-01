import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

/// Platform tool that reports device information (platform, model, OS version).
class DeviceInfoTool {
  static final _plugin = DeviceInfoPlugin();

  static Future<String> execute(String paramsJson) async {
    if (Platform.isAndroid) {
      final info = await _plugin.androidInfo;
      return jsonEncode({
        'platform': 'android',
        'brand': info.brand,
        'model': info.model,
        'device': info.device,
        'android_version': info.version.release,
        'sdk_int': info.version.sdkInt,
        'manufacturer': info.manufacturer,
        'is_physical_device': info.isPhysicalDevice,
      });
    } else if (Platform.isIOS) {
      final info = await _plugin.iosInfo;
      return jsonEncode({
        'platform': 'ios',
        'name': info.name,
        'model': info.model,
        'system_name': info.systemName,
        'system_version': info.systemVersion,
        'is_physical_device': info.isPhysicalDevice,
      });
    }
    return jsonEncode({'error': 'Unsupported platform'});
  }
}
