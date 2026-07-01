import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';

/// Host platform metadata passed into the Napaxi engine at startup.
///
/// Carries the writable data directory plus a JSON-encoded snapshot of the
/// host environment (platform, files dir, timezone, native library dir).
class NapaxiPlatformContext {
  /// Creates a platform context from already-resolved host values.
  NapaxiPlatformContext({
    required this.filesDir,
    required this.platformContextJson,
    this.userTimezone,
  });

  /// Absolute path to the writable application data directory on the host.
  final String filesDir;

  /// JSON-encoded platform context handed to the engine (platform, files dir,
  /// timezone, native library dir).
  final String platformContextJson;

  /// IANA timezone identifier reported by the host, if available.
  final String? userTimezone;
}

/// Resolves [NapaxiPlatformContext] from the native host over a method channel.
class NapaxiPlatformContextResolver {
  NapaxiPlatformContextResolver._();

  static const _channel = MethodChannel('com.napaxi.flutter/platform_context');

  /// Queries the native host for platform context, falling back to a temp
  /// directory on non-mobile platforms. Throws [StateError] if the mobile host
  /// returns no context or omits the files directory.
  static Future<NapaxiPlatformContext> resolve() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final map = await _channel.invokeMapMethod<String, dynamic>(
        'getPlatformContext',
      );
      if (map == null) {
        throw StateError('Napaxi platform context unavailable');
      }
      final filesDir = map['filesDir'] as String?;
      if (filesDir == null || filesDir.isEmpty) {
        throw StateError('Napaxi platform context missing filesDir');
      }
      final platformContext = <String, dynamic>{
        'platform': map['platform'] ?? (Platform.isAndroid ? 'android' : 'ios'),
        'files_dir': filesDir,
        if (map['userTimezone'] != null) 'user_timezone': map['userTimezone'],
        if (map['nativeLibraryDir'] != null)
          'native_library_dir': map['nativeLibraryDir'],
      };
      return NapaxiPlatformContext(
        filesDir: filesDir,
        platformContextJson: jsonEncode(platformContext),
        userTimezone: map['userTimezone'] as String?,
      );
    }

    final filesDir = '${Directory.systemTemp.path}/napaxi_data';
    return NapaxiPlatformContext(
      filesDir: filesDir,
      platformContextJson: jsonEncode({
        'platform': 'other',
        'files_dir': filesDir,
      }),
    );
  }
}
