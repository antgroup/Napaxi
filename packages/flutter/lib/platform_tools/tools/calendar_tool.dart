import 'dart:convert';

import 'package:device_calendar/device_calendar.dart';

/// Platform tool that reads and creates device calendar events.
class CalendarTool {
  static final _plugin = DeviceCalendarPlugin();

  static Future<String> _ensurePermission() async {
    var result = await _plugin.hasPermissions();
    if (result.data != true) {
      result = await _plugin.requestPermissions();
      if (result.data != true) {
        return 'Calendar permission denied by user.';
      }
    }
    return '';
  }

  static Future<String?> _getDefaultCalendarId() async {
    final result = await _plugin.retrieveCalendars();
    final calendars = result.data;
    if (calendars == null || calendars.isEmpty) return null;
    final writable = calendars.where((c) => !c.isReadOnly!).toList();
    if (writable.isNotEmpty) return writable.first.id;
    return calendars.first.id;
  }

  static Future<String> createEvent(String paramsJson) async {
    final permError = await _ensurePermission();
    if (permError.isNotEmpty) return jsonEncode({'error': permError});

    final params = jsonDecode(paramsJson) as Map<String, dynamic>;
    final title = params['title'] as String? ?? '';
    final startStr = params['start'] as String? ?? '';
    final endStr = params['end'] as String? ?? '';
    final description = params['description'] as String?;

    final start = DateTime.tryParse(startStr);
    final end = DateTime.tryParse(endStr);
    if (start == null || end == null) {
      return jsonEncode({'error': 'Invalid date format. Use ISO 8601.'});
    }

    final calendarId = await _getDefaultCalendarId();
    if (calendarId == null) {
      return jsonEncode({'error': 'No calendar found on device.'});
    }

    final event = Event(calendarId);
    event.title = title;
    event.start = TZDateTime.from(start, local);
    event.end = TZDateTime.from(end, local);
    if (description != null) event.description = description;

    final result = await _plugin.createOrUpdateEvent(event);
    if (result?.isSuccess == true && result?.data != null) {
      return jsonEncode({
        'success': true,
        'event_id': result!.data,
        'title': title,
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
      });
    }
    final errors = result?.errors;
    return jsonEncode({
      'error': 'Failed to create event: ${errors?.join(', ') ?? 'unknown'}',
    });
  }

  static Future<String> listEvents(String paramsJson) async {
    final permError = await _ensurePermission();
    if (permError.isNotEmpty) return jsonEncode({'error': permError});

    final params = jsonDecode(paramsJson) as Map<String, dynamic>;
    final startStr = params['start'] as String? ?? '';
    final endStr = params['end'] as String? ?? '';

    final start = DateTime.tryParse(startStr);
    final end = DateTime.tryParse(endStr);
    if (start == null || end == null) {
      return jsonEncode({'error': 'Invalid date format. Use ISO 8601.'});
    }

    final calendarsResult = await _plugin.retrieveCalendars();
    final calendars = calendarsResult.data ?? [];
    final events = <Map<String, dynamic>>[];

    for (final calendar in calendars) {
      final result = await _plugin.retrieveEvents(
        calendar.id,
        RetrieveEventsParams(startDate: start, endDate: end),
      );
      if (result.data != null) {
        for (final event in result.data!) {
          events.add({
            'title': event.title ?? '',
            'start': event.start?.toIso8601String() ?? '',
            'end': event.end?.toIso8601String() ?? '',
            'description': event.description ?? '',
            'calendar': calendar.name ?? '',
            'all_day': event.allDay ?? false,
          });
        }
      }
    }

    events.sort((a, b) => (a['start'] as String).compareTo(b['start'] as String));

    return jsonEncode({'events': events, 'count': events.length});
  }
}
