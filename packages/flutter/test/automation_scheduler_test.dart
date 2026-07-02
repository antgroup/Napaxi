import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napaxi_flutter/api/automation_api.dart';
import 'package:napaxi_flutter/background/automation_scheduler.dart';
import 'package:napaxi_flutter/models/automation.dart';

void main() {
  const channel = MethodChannel('com.napaxi.flutter/background');

  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('status decodes native scheduler bridge payload', () async {
    final scheduler = NapaxiAutomationScheduler(
      AutomationApi(() => 0),
      channel: channel,
      supported: true,
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getAutomationSchedulerStatus');
      return {
        'supported': true,
        'platform': 'android',
        'pendingWakeCount': 1,
        'nextPendingWake': {
          'wakeId': 'job-1:10',
          'jobId': 'job-1',
          'atMs': 10,
          'firedAtMs': 11,
          'source': 'platform_wake',
        },
      };
    });

    final status = await scheduler.status();

    expect(status.supported, true);
    expect(status.pendingWakeCount, 1);
    expect(status.nextPendingWake?.jobId, 'job-1');
  });

  test('pendingWakes filters native rows without a job id', () async {
    final scheduler = NapaxiAutomationScheduler(
      AutomationApi(() => 0),
      channel: channel,
      supported: true,
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getPendingAutomationWakes');
      return [
        {'wakeId': 'bad', 'jobId': '', 'atMs': 1, 'firedAtMs': 2},
        {'wakeId': 'ok', 'jobId': 'job-2', 'atMs': 3, 'firedAtMs': 4},
      ];
    });

    final wakes = await scheduler.pendingWakes();

    expect(wakes, hasLength(1));
    expect(wakes.single.wakeId, 'ok');
  });

  test('drainPendingWakes clears stale wakes for deleted one-shot jobs',
      () async {
    final scheduler = NapaxiAutomationScheduler(
      _FakeAutomationApi(),
      channel: channel,
      supported: true,
    );
    final calls = <String>[];

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return switch (call.method) {
        'getPendingAutomationWakes' => [
            {
              'wakeId': 'stale',
              'jobId': 'job-missing',
              'atMs': 1,
              'firedAtMs': 2
            },
          ],
        'clearPendingAutomationWake' => true,
        _ => null,
      };
    });

    final runs = await scheduler.drainPendingWakes();

    expect(runs, isEmpty);
    expect(calls, ['getPendingAutomationWakes', 'clearPendingAutomationWake']);
  });
}

class _FakeAutomationApi extends AutomationApi {
  _FakeAutomationApi() : super(() => 0);

  @override
  AutomationJob? getAutomationJob(String jobId) => null;

  @override
  Future<AutomationRun> recordAutomationWake(String jobId, String source) {
    throw StateError('recordAutomationWake should not be called');
  }
}
