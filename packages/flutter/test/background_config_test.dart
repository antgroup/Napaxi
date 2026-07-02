import 'package:flutter_test/flutter_test.dart';
import 'package:napaxi_flutter/napaxi_flutter.dart';

/// `BackgroundConfig.toMap()` is the payload contract for the Android
/// foreground-service MethodChannel: the Kotlin side reads these exact keys to
/// configure the notification channels and wake-lock. A renamed key would
/// silently drop a notification field on the native side, so this test pins the
/// flattened key set and the duration-to-millis conversion. `BackgroundAction`
/// is the inbound counterpart (user taps on the notification).
void main() {
  group('BackgroundConfig.toMap', () {
    test('flattens notification config with default values', () {
      final map = const BackgroundConfig().toMap();

      // Top-level flags and the wake-lock conversion.
      expect(map['enabled'], isTrue);
      expect(map['wakeLockTimeoutMs'], const Duration(minutes: 30).inMilliseconds);

      // Notification channel keys the Kotlin side reads.
      expect(map['channelName'], 'Agent');
      expect(map['ongoingTitle'], 'Napaxi Agent');
      expect(map['ongoingMessage'], 'Agent is running...');
      expect(map['hitlTitle'], 'Agent needs confirmation');
      expect(map['hitlChannelSuffix'], 'Confirmation');
      expect(map['completionChannelSuffix'], 'Completed');
      expect(map['completionMessage'], 'Task completed');
      expect(map['errorPrefix'], 'Error');
      expect(map['stopActionLabel'], 'Stop');
      expect(map['openActionLabel'], 'Open');
    });

    test('propagates custom notification config and wake-lock timeout', () {
      final map = const BackgroundConfig(
        enabled: false,
        wakeLockTimeout: Duration(minutes: 5),
        notificationConfig: NotificationConfig(
          channelName: 'Worker',
          ongoingTitle: 'Busy',
          stopActionLabel: 'Halt',
        ),
      ).toMap();

      expect(map['enabled'], isFalse);
      expect(map['wakeLockTimeoutMs'], 5 * 60 * 1000);
      expect(map['channelName'], 'Worker');
      expect(map['ongoingTitle'], 'Busy');
      expect(map['stopActionLabel'], 'Halt');
    });

    test('exposes every key the native side expects', () {
      final keys = const BackgroundConfig().toMap().keys.toSet();
      expect(
        keys,
        containsAll(<String>[
          'enabled',
          'channelName',
          'channelDescription',
          'ongoingTitle',
          'ongoingMessage',
          'hitlTitle',
          'hitlChannelSuffix',
          'hitlChannelDescription',
          'completionChannelSuffix',
          'completionChannelDescription',
          'completionMessage',
          'errorPrefix',
          'stopActionLabel',
          'openActionLabel',
          'wakeLockTimeoutMs',
        ]),
      );
    });
  });

  group('BackgroundActionEvent', () {
    test('carries the action with optional request id and payload', () {
      const event = BackgroundActionEvent(
        action: BackgroundAction.hitlApprove,
        requestId: 'req-1',
        payload: 'Approve',
      );
      expect(event.action, BackgroundAction.hitlApprove);
      expect(event.requestId, 'req-1');
      expect(event.payload, 'Approve');
    });

    test('allows a bare stop action with no request id', () {
      const event = BackgroundActionEvent(action: BackgroundAction.stop);
      expect(event.action, BackgroundAction.stop);
      expect(event.requestId, isNull);
      expect(event.payload, isNull);
    });
  });
}
