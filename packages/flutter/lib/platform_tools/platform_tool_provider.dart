import 'dart:io';

import '../api/json_codec.dart';
import '../generated/bridge/init.dart' as rust_init;
import '../models/custom_tool.dart';

/// Static registry of the built-in platform (device-capability) tool
/// definitions available on the current platform.
class PlatformToolProvider {
  PlatformToolProvider._();

  static List<CustomToolDef>? _cachedToolDefinitions;
  static Set<String>? _cachedToolNames;

  static bool get isSupported {
    try {
      return Platform.isAndroid || Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  static Set<String> get platformToolNames {
    return _cachedToolNames ??=
        getToolDefinitions().map((tool) => tool.name).toSet();
  }

  static bool isPlatformTool(String name) {
    try {
      return rust_init.isPlatformTool(name: name);
    } catch (_) {
      return _cachedToolNames?.contains(name) ?? false;
    }
  }

  static List<CustomToolDef> getToolDefinitions() {
    return _cachedToolDefinitions ??= _loadToolDefinitions();
  }

  static List<CustomToolDef> _loadToolDefinitions() {
    try {
      return decodeJsonObjectList(
        rust_init.platformToolDescriptorsJson(),
        CustomToolDef.fromJson,
      ).where((tool) => tool.name.isNotEmpty).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }
}
