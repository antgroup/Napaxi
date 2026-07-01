import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'capability_context.dart';
import 'platform_tool_provider.dart';
import 'tools/alarm_tool.dart';
import 'tools/audio_tool.dart';
import 'tools/calendar_tool.dart';
import 'tools/camera_tool.dart';
import 'tools/clipboard_tool.dart';
import 'tools/contacts_tool.dart';
import 'tools/device_info_tool.dart';
import 'tools/install_app_tool.dart';
import 'tools/location_tool.dart';
import 'tools/notification_tool.dart';
import 'tools/phone_tool.dart';
import 'tools/url_tool.dart';

/// Host-side executor that dispatches platform tool calls to the matching
/// device-capability tool implementation (camera, clipboard, location, etc.).
class FlutterCapabilityHost {
  final String? filesDir;

  FlutterCapabilityHost({this.filesDir});

  bool canHandle(String toolName) {
    return PlatformToolProvider.isPlatformTool(toolName);
  }

  Future<String> execute(
    String toolName,
    String paramsJson, {
    String? workspaceFilesDir,
  }) async {
    final context = CapabilityContext(
      filesDir: filesDir,
      workspaceFilesDir: workspaceFilesDir,
    );
    switch (toolName) {
      case 'open_url':
        return UrlTool.execute(paramsJson);
      case 'make_call':
        return PhoneTool.makeCall(paramsJson);
      case 'send_sms':
        return PhoneTool.sendSms(paramsJson);
      case 'get_clipboard':
        return ClipboardTool.getClipboard(paramsJson);
      case 'set_clipboard':
        return ClipboardTool.setClipboard(paramsJson);
      case 'get_device_info':
        return DeviceInfoTool.execute(paramsJson);
      case 'get_location':
        return LocationTool.execute(paramsJson);
      case 'send_notification':
        return NotificationTool.execute(paramsJson);
      case 'get_contacts':
        return ContactsTool.execute(paramsJson);
      case 'create_calendar_event':
        return CalendarTool.createEvent(paramsJson);
      case 'list_calendar_events':
        return CalendarTool.listEvents(paramsJson);
      case 'take_photo':
        return CameraTool.execute(paramsJson, context);
      case 'media_library':
        return _MediaLibraryTool.execute(paramsJson, context);
      case 'pick_media':
        return _MediaLibraryTool.executeLegacyPick(paramsJson, context);
      case 'record_audio':
        return AudioTool.execute(paramsJson, context);
      case 'set_alarm':
        return AlarmTool.execute(paramsJson);
      case 'install_apk':
        return InstallAppTool.execute(paramsJson, context);
      default:
        return jsonEncode({'error': 'Unknown platform tool: $toolName'});
    }
  }
}

class _MediaLibraryTool {
  static const _channel = MethodChannel('com.napaxi.flutter/media_library');
  static final _picker = ImagePicker();

  static Future<String> execute(
    String paramsJson,
    CapabilityContext context,
  ) async {
    final params = _decodeParams(paramsJson);
    final action = (params['action'] ?? 'pick').toString().trim().toLowerCase();
    if (action == 'status' || action == 'search') {
      return _nativeJson(action, params);
    }
    if (action == 'import') {
      return _import(params, context);
    }
    if (action == 'pick') {
      return _pick(params, context);
    }
    return jsonEncode({
      'success': false,
      'error': 'Unsupported media_library action: $action',
      'supportedActions': ['status', 'search', 'import', 'pick'],
    });
  }

  static Future<String> executeLegacyPick(
    String paramsJson,
    CapabilityContext context,
  ) {
    final params = _decodeParams(paramsJson);
    params['action'] = 'pick';
    return execute(jsonEncode(params), context);
  }

  static Future<String> _nativeJson(
    String action,
    Map<String, dynamic> params, {
    CapabilityContext? context,
  }) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'mediaLibrary',
        _nativeArgs(action, params, context: context),
      );
      return jsonEncode(
          result ?? {'success': false, 'error': 'Empty media library result'});
    } on MissingPluginException {
      return jsonEncode({
        'success': false,
        'supported': false,
        'action': action,
        'code': 'media_library_native_unavailable',
        'error': action == 'pick'
            ? 'Native media library bridge is unavailable.'
            : 'Media library $action requires a host/native media library implementation. Use action=pick as a manual fallback when appropriate.',
      });
    } on PlatformException catch (error) {
      return jsonEncode({
        'success': false,
        'action': action,
        'code': error.code,
        'error': error.message ?? error.code,
        if (error.details != null) 'details': error.details,
      });
    } catch (error) {
      return jsonEncode({
        'success': false,
        'action': action,
        'error': error.toString(),
      });
    }
  }

  static Future<String> _import(
    Map<String, dynamic> params,
    CapabilityContext context,
  ) async {
    final mediaDir = await context.ensureAttachmentDir('media');
    if (mediaDir == null) {
      return context.errorJson('File storage not available.');
    }
    return _nativeJson('import', params, context: context);
  }

  static Future<String> _pick(
    Map<String, dynamic> params,
    CapabilityContext context,
  ) async {
    final mediaDir = await context.ensureAttachmentDir('media');
    if (mediaDir == null) {
      return context.errorJson('File storage not available.');
    }
    final mediaTypes =
        _mediaTypes(params['media_types'] ?? params['mediaTypes']);
    final maxCount =
        _int(params['limit'] ?? params['max_count'] ?? params['maxCount'])
                ?.clamp(1, 20) ??
            9;

    final picked = await _pickWithSystemPicker(mediaTypes, maxCount);
    if (picked.isEmpty) {
      return context.errorJson('Media selection cancelled by user.');
    }

    final attachments = <Map<String, dynamic>>[];
    for (final item in picked.take(maxCount)) {
      final bytes = await item.readAsBytes();
      final ext = _extensionFor(item.path, item.mimeType);
      final filename = 'media_${DateTime.now().microsecondsSinceEpoch}$ext';
      final sandboxPath = context.attachmentSandboxPath('media', filename);
      await File('${mediaDir.path}/$filename').writeAsBytes(bytes);
      final mimeType = item.mimeType ?? _mimeTypeForExtension(ext);
      final kind = mimeType.startsWith('image/') ? 'image' : 'document';
      attachments.add({
        'artifactId': filename,
        'kind': kind,
        'mimeType': mimeType,
        'mime_type': mimeType,
        'name': item.name.isEmpty ? filename : item.name,
        'filename': filename,
        'uri': sandboxPath,
        'sandbox_path': sandboxPath,
        'sizeBytes': bytes.length,
        'size_bytes': bytes.length,
        'metadata': {
          'source': 'system_picker',
          'original_name': item.name,
        },
      });
    }

    return context.successJson({
      'success': true,
      'action': 'pick',
      'artifacts': attachments,
      'attachments': attachments,
      'count': attachments.length,
    });
  }

  static Map<String, dynamic> _nativeArgs(
    String action,
    Map<String, dynamic> params, {
    CapabilityContext? context,
  }) {
    final args = Map<String, dynamic>.from(params);
    args['action'] = action;
    if ((action == 'search' || action == 'import') &&
        args['request_permission'] == null &&
        args['requestPermission'] == null) {
      args['request_permission'] = true;
    }
    if (context != null) {
      final workspaceDir = context.workspaceDir;
      if (workspaceDir != null) {
        args['outputDir'] = '$workspaceDir/attachments/media';
        args['sandboxPrefix'] = '/workspace/attachments/media';
      }
    }
    return args;
  }

  static Future<List<XFile>> _pickWithSystemPicker(
    Set<String> mediaTypes,
    int maxCount,
  ) async {
    final images = mediaTypes.contains('image');
    final videos = mediaTypes.contains('video');
    if (maxCount <= 1) {
      final single = videos && !images
          ? await _picker.pickVideo(source: ImageSource.gallery)
          : images && !videos
              ? await _picker.pickImage(source: ImageSource.gallery)
              : await _picker.pickMedia();
      return single == null ? const [] : [single];
    }
    if (videos && images) {
      return _picker.pickMultipleMedia(limit: maxCount);
    }
    if (videos) {
      return _picker.pickMultiVideo(limit: maxCount);
    }
    return _picker.pickMultiImage(limit: maxCount);
  }

  static Map<String, dynamic> _decodeParams(String paramsJson) {
    try {
      final decoded = jsonDecode(paramsJson.isEmpty ? '{}' : paramsJson);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return const {};
  }

  static Set<String> _mediaTypes(Object? value) {
    final raw = value is List
        ? value.map((item) => item.toString())
        : value is String
            ? value.split(',')
            : const <String>[];
    final normalized = raw
        .map((item) => item.trim().toLowerCase())
        .where((item) => item == 'image' || item == 'video')
        .toSet();
    return normalized.isEmpty ? {'image'} : normalized;
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  static String _extensionFor(String path, String? mimeType) {
    final lower = path.toLowerCase();
    for (final ext in [
      '.jpg',
      '.jpeg',
      '.png',
      '.heic',
      '.webp',
      '.gif',
      '.mp4',
      '.mov',
    ]) {
      if (lower.endsWith(ext)) return ext;
    }
    if (mimeType == 'image/png') return '.png';
    if (mimeType == 'image/heic') return '.heic';
    if (mimeType == 'image/webp') return '.webp';
    if (mimeType == 'video/quicktime') return '.mov';
    if (mimeType?.startsWith('video/') == true) return '.mp4';
    return '.jpg';
  }

  static String _mimeTypeForExtension(String ext) {
    return const {
          '.png': 'image/png',
          '.heic': 'image/heic',
          '.webp': 'image/webp',
          '.gif': 'image/gif',
          '.mp4': 'video/mp4',
          '.mov': 'video/quicktime',
          '.jpeg': 'image/jpeg',
          '.jpg': 'image/jpeg',
        }[ext.toLowerCase()] ??
        'image/jpeg';
  }
}
