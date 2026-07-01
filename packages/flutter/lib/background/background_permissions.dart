import 'dart:io';
import 'package:flutter/services.dart';

/// Helper for checking and requesting permissions needed for background execution.
class NapaxiBackgroundPermissions {
  static const _channel = MethodChannel('com.napaxi.flutter/background');

  /// Whether background execution is supported on this platform.
  static bool get isSupported => Platform.isAndroid;

  /// Check if the POST_NOTIFICATIONS permission is granted (Android 13+).
  ///
  /// Returns true on platforms that don't require this permission.
  static Future<bool> checkNotificationPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final result = await _channel.invokeMethod<bool>('checkNotificationPermission');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Request the POST_NOTIFICATIONS permission (Android 13+).
  ///
  /// Returns true if granted. On older Android versions, returns true immediately.
  /// On non-Android platforms, returns true.
  static Future<bool> requestNotificationPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final result = await _channel.invokeMethod<bool>('requestNotificationPermission');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Whether the app can run agents in the background on this device.
  ///
  /// Checks both platform support and notification permission.
  static Future<bool> canRunInBackground() async {
    if (!isSupported) return false;
    return checkNotificationPermission();
  }
}