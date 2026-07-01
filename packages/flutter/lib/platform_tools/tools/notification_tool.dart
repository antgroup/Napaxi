import 'dart:convert';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Platform tool that posts local notifications on the device.
class NotificationTool {
  static FlutterLocalNotificationsPlugin? _plugin;
  static bool _initialized = false;

  static Future<FlutterLocalNotificationsPlugin> ensureInit() async {
    if (_initialized && _plugin != null) return _plugin!;
    _plugin = FlutterLocalNotificationsPlugin();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestSoundPermission: false,
      requestBadgePermission: false,
      requestAlertPermission: false,
    );
    const settings = InitializationSettings(android: android, iOS: ios);
    await _plugin!.initialize(settings);
    _initialized = true;
    return _plugin!;
  }

  static Future<String> execute(String paramsJson) async {
    final params = jsonDecode(paramsJson) as Map<String, dynamic>;
    final title = params['title'] as String? ?? 'Notification';
    final body = params['body'] as String? ?? '';

    final plugin = await ensureInit();

    if (Platform.isIOS) {
      final granted = await plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      if (granted != true) {
        return jsonEncode({'error': 'Notification permission denied on iOS.'});
      }
    } else if (Platform.isAndroid) {
      final android = plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission();
      if (granted != true) {
        return jsonEncode(
            {'error': 'Notification permission denied on Android.'});
      }
    }

    const androidDetails = AndroidNotificationDetails(
      'napaxi_platform_tools',
      'Napaxi Notifications',
      channelDescription: 'Notifications from Napaxi AI agent',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    final id = DateTime.now().millisecondsSinceEpoch % 100000;
    await plugin.show(id, title, body, details);
    return jsonEncode({'success': true, 'notification_id': id});
  }
}
