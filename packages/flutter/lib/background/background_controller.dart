import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import '../models/background.dart';
import 'background_permissions.dart';

/// Platform-agnostic controller for the Napaxi background agent service.
///
/// On Android, this communicates with `NapaxiAgentService` via MethodChannel.
/// On other platforms, all methods are no-ops and [isRunning] is always false.
class NapaxiBackgroundController {
  static const _methodChannel = MethodChannel('com.napaxi.flutter/background');
  static const _eventChannel =
      EventChannel('com.napaxi.flutter/background_events');

  MethodChannel? _channel;
  StreamSubscription<dynamic>? _eventSubscription;
  final StreamController<BackgroundActionEvent> _actionController =
      StreamController<BackgroundActionEvent>.broadcast();

  bool _isRunning = false;
  BackgroundConfig? _currentConfig;

  /// Constructor accepts optional initial config.
  NapaxiBackgroundController([BackgroundConfig? initialConfig])
      : _currentConfig = initialConfig;

  /// Whether the foreground service is currently running.
  bool get isRunning => _isRunning;

  /// The current background configuration, or null if not started.
  BackgroundConfig? get currentConfig => _currentConfig;

  /// Update the current configuration for future notification updates.
  void updateConfig(BackgroundConfig config) {
    _currentConfig = config;
  }

  /// Stream of user actions from background notifications.
  ///
  /// Listen to this to handle:
  /// - [BackgroundAction.stop]: User wants to stop the agent
  /// - [BackgroundAction.hitlApprove]: User approved a HITL request
  /// - [BackgroundAction.hitlDeny]: User denied a HITL request
  /// - [BackgroundAction.viewResult]: User wants to view the result
  Stream<BackgroundActionEvent> get onAction => _actionController.stream;

  /// Start the foreground service with the given configuration.
  ///
  /// On non-Android platforms, this is a no-op.
  Future<void> start(BackgroundConfig config) async {
    if (!Platform.isAndroid || !config.enabled) return;

    _channel = _channel ?? _methodChannel;
    _currentConfig = config;

    final hasNotificationPermission =
        await NapaxiBackgroundPermissions.requestNotificationPermission();
    if (!hasNotificationPermission) {
      throw PlatformException(
        code: 'NOTIFICATION_PERMISSION_DENIED',
        message: 'Notification permission is required for background execution',
      );
    }

    // Listen for action events from the native side
    _eventSubscription?.cancel();
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is! Map<dynamic, dynamic>) return;
        final actionStr = event['action'] as String?;
        if (actionStr == null) return;
        final action = switch (actionStr) {
          'stop' => BackgroundAction.stop,
          'hitlApprove' => BackgroundAction.hitlApprove,
          'hitlDeny' => BackgroundAction.hitlDeny,
          'viewResult' => BackgroundAction.viewResult,
          'agentTrigger' => BackgroundAction.agentTrigger,
          'automationWake' => BackgroundAction.automationWake,
          _ => null,
        };
        if (action == null) return;
        _actionController.add(BackgroundActionEvent(
          action: action,
          requestId: event['requestId'] as String?,
          payload: event['payload'] as String?,
        ));
      },
      onError: (Object e) {
        // EventChannel error — log and continue
      },
    );

    await _channel!
        .invokeMethod<bool>('startForegroundService', config.toMap());
    _isRunning = true;
  }

  /// Stop the foreground service.
  Future<void> stop() async {
    if (!Platform.isAndroid || _channel == null) return;

    await _channel!.invokeMethod<bool>('stopForegroundService');
    _isRunning = false;
    _currentConfig = null;
  }

  /// Update the ongoing notification with current progress.
  ///
  /// [message] — status text (e.g., "Searching files...")
  /// [progress] — 0-100, or null for indeterminate
  Future<void> updateNotification({String? message, int? progress}) async {
    if (!Platform.isAndroid || _channel == null || !_isRunning) return;

    await _channel!.invokeMethod<bool>('updateNotification', {
      'message': message,
      'progress': progress,
    });
  }

  /// Show a HITL confirmation notification.
  ///
  /// [requestId] — the ID from [AskingHumanEvent.requestId]
  /// [question] — the question text
  /// [options] — button labels (e.g., `["Allow", "Deny"]`)
  Future<void> showHitlNotification({
    required String requestId,
    required String question,
    List<String>? options,
  }) async {
    if (!Platform.isAndroid || _channel == null || !_isRunning) return;

    await _channel!.invokeMethod<bool>('showHitlNotification', {
      'requestId': requestId,
      'question': question,
      'options': options,
    });
  }

  /// Show a task completion notification.
  Future<void> showCompletionNotification({
    String title = 'Napaxi Agent',
    String message = 'Task completed',
  }) async {
    if (!Platform.isAndroid || _channel == null || !_isRunning) return;

    await _channel!.invokeMethod<bool>('showCompletionNotification', {
      'title': title,
      'message': message,
    });
  }

  /// Show an error notification.
  Future<void> showErrorNotification({
    String title = 'Napaxi Agent',
    String message = 'An error occurred',
  }) async {
    if (!Platform.isAndroid || _channel == null || !_isRunning) return;

    await _channel!.invokeMethod<bool>('showErrorNotification', {
      'title': title,
      'message': message,
    });
  }

  /// Cancel a specific notification by ID, or all notifications if null.
  Future<void> cancelNotification({int? notificationId}) async {
    if (!Platform.isAndroid || _channel == null) return;

    await _channel!.invokeMethod<bool>('cancelNotification', {
      'notificationId': notificationId,
    });
  }

  /// Release resources.
  void dispose() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
    _actionController.close();
    _isRunning = false;
    _currentConfig = null;
    _channel = null;
  }
}
