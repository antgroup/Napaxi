import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

/// Platform tool that resolves the device's current geographic location.
class LocationTool {
  static const _channel = MethodChannel('com.napaxi.flutter/background');
  static const _locationSettings = LocationSettings(
    accuracy: LocationAccuracy.high,
    timeLimit: Duration(seconds: 15),
  );
  static const _locationRetrySettings = LocationSettings(
    accuracy: LocationAccuracy.high,
    timeLimit: Duration(seconds: 45),
  );

  static Future<String> execute(String paramsJson) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return jsonEncode({
        'error':
            'Location services are disabled. Please enable them in Settings.',
      });
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      if (Platform.isAndroid) {
        await _requestAndroidLocationPermission();
        permission = await Geolocator.checkPermission();
      } else {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        return jsonEncode({'error': 'Location permission denied by user.'});
      }
    }
    if (permission == LocationPermission.deniedForever) {
      return jsonEncode({
        'error':
            'Location permission permanently denied. Please enable in app settings.',
      });
    }

    final position = await _getCurrentPosition();

    return jsonEncode({
      'latitude': position.latitude,
      'longitude': position.longitude,
      'altitude': position.altitude,
      'accuracy': position.accuracy,
      'speed': position.speed,
      'timestamp': position.timestamp.toIso8601String(),
    });
  }

  static Future<void> _requestAndroidLocationPermission() async {
    try {
      await _channel.invokeMethod<bool>('requestLocationPermission');
    } on PlatformException {
      return;
    }
  }

  static Future<Position> _getCurrentPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: _locationSettings,
      );
    } on TimeoutException {
      return Geolocator.getCurrentPosition(
        locationSettings: _locationRetrySettings,
      );
    }
  }
}
