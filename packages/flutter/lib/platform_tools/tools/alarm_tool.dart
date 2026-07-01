import 'dart:convert';
import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';

/// Platform tool that sets a device alarm (Android only) via a system intent.
class AlarmTool {
  static Future<String> execute(String paramsJson) async {
    if (!Platform.isAndroid) {
      return jsonEncode({
        'error':
            'Setting alarms is not supported on iOS due to system restrictions.',
      });
    }

    final Map<String, dynamic> intentArguments;
    try {
      intentArguments = buildIntentArguments(paramsJson);
    } on FormatException catch (error) {
      return jsonEncode({'error': error.message});
    }

    final intent = AndroidIntent(
      action: 'android.intent.action.SET_ALARM',
      arguments: intentArguments,
    );
    await intent.launch();

    return jsonEncode({
      'success': true,
      'hour': intentArguments['android.intent.extra.alarm.HOUR'],
      'minute': intentArguments['android.intent.extra.alarm.MINUTES'],
      'message': intentArguments['android.intent.extra.alarm.MESSAGE'],
      if (intentArguments.containsKey('android.intent.extra.alarm.DAYS'))
        'repeat_days': intentArguments['android.intent.extra.alarm.DAYS'],
    });
  }

  static Map<String, dynamic> buildIntentArguments(String paramsJson) {
    final decoded = jsonDecode(paramsJson);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Alarm parameters must be a JSON object.');
    }

    final timeStr = decoded['time'] as String? ?? '';
    final message = decoded['message'] as String? ?? 'Alarm';
    final time = _parseAlarmTime(timeStr);
    final repeatDays = _parseRepeatDays(
      decoded['repeat_days'] ?? decoded['repeatDays'] ?? decoded['days'],
    );

    return <String, dynamic>{
      'android.intent.extra.alarm.HOUR': time.$1,
      'android.intent.extra.alarm.MINUTES': time.$2,
      'android.intent.extra.alarm.MESSAGE': message,
      'android.intent.extra.alarm.SKIP_UI': true,
      if (repeatDays != null) 'android.intent.extra.alarm.DAYS': repeatDays,
    };
  }

  static (int, int) _parseAlarmTime(String timeStr) {
    int? hour;
    int? minute;

    final hhmmMatch = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(timeStr);
    if (hhmmMatch != null) {
      hour = int.parse(hhmmMatch.group(1)!);
      minute = int.parse(hhmmMatch.group(2)!);
    } else {
      final dt = DateTime.tryParse(timeStr);
      if (dt != null) {
        hour = dt.hour;
        minute = dt.minute;
      }
    }

    if (hour == null || minute == null) {
      throw const FormatException(
        'Invalid time format. Use HH:mm (e.g. "07:30") or ISO 8601.',
      );
    }

    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      throw const FormatException(
        'Invalid alarm time. Hour must be 0-23 and minute must be 0-59.',
      );
    }

    return (hour, minute);
  }

  static List<int>? _parseRepeatDays(Object? rawDays) {
    if (rawDays == null) return null;

    final days = <int>[];
    final seen = <int>{};

    void addDay(int day) {
      if (seen.add(day)) days.add(day);
    }

    void addAll(Iterable<int> values) {
      for (final value in values) {
        addDay(value);
      }
    }

    void parseOne(Object? rawDay) {
      if (rawDay is int) {
        if (rawDay < 1 || rawDay > 7) {
          throw FormatException('Invalid repeat day: $rawDay.');
        }
        addDay(rawDay);
        return;
      }

      if (rawDay is! String) {
        throw FormatException('Invalid repeat day: $rawDay.');
      }

      final normalized = rawDay.trim().toLowerCase();
      if (normalized.isEmpty) return;

      final preset = _repeatDayPresets[normalized];
      if (preset != null) {
        addAll(preset);
        return;
      }

      if (normalized.contains(',')) {
        for (final part in normalized.split(',')) {
          parseOne(part);
        }
        return;
      }

      final day = _repeatDayAliases[normalized];
      if (day == null) {
        throw FormatException('Invalid repeat day: $rawDay.');
      }
      addDay(day);
    }

    if (rawDays is List) {
      for (final rawDay in rawDays) {
        parseOne(rawDay);
      }
    } else {
      parseOne(rawDays);
    }

    return days.isEmpty ? null : days;
  }
}

const _allDays = <int>[1, 2, 3, 4, 5, 6, 7];
const _weekdays = <int>[2, 3, 4, 5, 6];
const _weekends = <int>[1, 7];

const _repeatDayPresets = <String, List<int>>{
  'daily': _allDays,
  'everyday': _allDays,
  'every day': _allDays,
  'all': _allDays,
  '每天': _allDays,
  '每日': _allDays,
  'weekdays': _weekdays,
  'weekday': _weekdays,
  'workdays': _weekdays,
  'workday': _weekdays,
  '工作日': _weekdays,
  'weekends': _weekends,
  'weekend': _weekends,
  '周末': _weekends,
};

const _repeatDayAliases = <String, int>{
  'sunday': 1,
  'sun': 1,
  '周日': 1,
  '星期日': 1,
  '礼拜日': 1,
  '周天': 1,
  '星期天': 1,
  '礼拜天': 1,
  'monday': 2,
  'mon': 2,
  '周一': 2,
  '星期一': 2,
  '礼拜一': 2,
  'tuesday': 3,
  'tue': 3,
  'tues': 3,
  '周二': 3,
  '星期二': 3,
  '礼拜二': 3,
  'wednesday': 4,
  'wed': 4,
  '周三': 4,
  '星期三': 4,
  '礼拜三': 4,
  'thursday': 5,
  'thu': 5,
  'thur': 5,
  'thurs': 5,
  '周四': 5,
  '星期四': 5,
  '礼拜四': 5,
  'friday': 6,
  'fri': 6,
  '周五': 6,
  '星期五': 6,
  '礼拜五': 6,
  'saturday': 7,
  'sat': 7,
  '周六': 7,
  '星期六': 7,
  '礼拜六': 7,
};
