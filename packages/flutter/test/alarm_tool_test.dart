import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:napaxi_flutter/platform_tools/tools/alarm_tool.dart';

void main() {
  test('builds one-time alarm arguments when repeat days are omitted', () {
    final arguments = AlarmTool.buildIntentArguments(jsonEncode({
      'time': '07:30',
      'message': 'Standup',
    }));

    expect(arguments['android.intent.extra.alarm.HOUR'], 7);
    expect(arguments['android.intent.extra.alarm.MINUTES'], 30);
    expect(arguments['android.intent.extra.alarm.MESSAGE'], 'Standup');
    expect(arguments['android.intent.extra.alarm.SKIP_UI'], isTrue);
    expect(arguments.containsKey('android.intent.extra.alarm.DAYS'), isFalse);
  });

  test('builds repeating alarm arguments from weekday names', () {
    final arguments = AlarmTool.buildIntentArguments(jsonEncode({
      'time': '08:00',
      'message': 'Workout',
      'repeat_days': ['monday', 'wednesday', 'friday'],
    }));

    expect(arguments['android.intent.extra.alarm.DAYS'], [2, 4, 6]);
  });

  test('accepts repeat presets and localized aliases for compatibility', () {
    final daily = AlarmTool.buildIntentArguments(jsonEncode({
      'time': '08:00',
      'message': 'Daily check',
      'repeat_days': 'daily',
    }));
    final workdays = AlarmTool.buildIntentArguments(jsonEncode({
      'time': '09:00',
      'message': 'Work',
      'repeatDays': '工作日',
    }));
    final weekend = AlarmTool.buildIntentArguments(jsonEncode({
      'time': '10:00',
      'message': 'Weekend',
      'days': ['周六', '周日'],
    }));

    expect(daily['android.intent.extra.alarm.DAYS'], [1, 2, 3, 4, 5, 6, 7]);
    expect(workdays['android.intent.extra.alarm.DAYS'], [2, 3, 4, 5, 6]);
    expect(weekend['android.intent.extra.alarm.DAYS'], [7, 1]);
  });

  test('rejects invalid time and repeat day values', () {
    expect(
      () => AlarmTool.buildIntentArguments(jsonEncode({
        'time': '25:00',
        'message': 'Invalid',
      })),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => AlarmTool.buildIntentArguments(jsonEncode({
        'time': '07:30',
        'message': 'Invalid',
        'repeat_days': ['funday'],
      })),
      throwsA(isA<FormatException>()),
    );
  });
}
