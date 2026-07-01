import 'dart:io';

/// Configuration for background agent execution (Android only).
///
/// When enabled, a Foreground Service keeps the agent alive when the app
/// goes to background. iOS and desktop platforms gracefully degrade — the
/// config is accepted but has no effect.
class BackgroundConfig {
  /// Whether to enable background execution.
  final bool enabled;

  /// Notification appearance and behavior.
  final NotificationConfig notificationConfig;

  /// Maximum duration to hold the WakeLock (prevents CPU sleep).
  /// Defaults to 30 minutes. After this, the WakeLock is released but
  /// the Foreground Service continues keeping the process alive.
  final Duration wakeLockTimeout;

  const BackgroundConfig({
    this.enabled = true,
    this.notificationConfig = const NotificationConfig(),
    this.wakeLockTimeout = const Duration(minutes: 30),
  });

  /// Returns the config as a map for MethodChannel communication.
  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'channelName': notificationConfig.channelName,
        'channelDescription': notificationConfig.channelDescription,
        'ongoingTitle': notificationConfig.ongoingTitle,
        'ongoingMessage': notificationConfig.ongoingMessage,
        'hitlTitle': notificationConfig.hitlTitle,
        'hitlChannelSuffix': notificationConfig.hitlChannelSuffix,
        'hitlChannelDescription': notificationConfig.hitlChannelDescription,
        'completionChannelSuffix': notificationConfig.completionChannelSuffix,
        'completionChannelDescription':
            notificationConfig.completionChannelDescription,
        'completionMessage': notificationConfig.completionMessage,
        'errorPrefix': notificationConfig.errorPrefix,
        'stopActionLabel': notificationConfig.stopActionLabel,
        'openActionLabel': notificationConfig.openActionLabel,
        'wakeLockTimeoutMs': wakeLockTimeout.inMilliseconds,
      };
}

/// Notification appearance configuration for the foreground service.
class NotificationConfig {
  /// Notification channel name (visible in Android settings).
  final String channelName;

  /// Notification channel description.
  final String channelDescription;

  /// Title shown on the ongoing notification while the agent is running.
  final String ongoingTitle;

  /// Message shown on the ongoing notification while the agent is running.
  final String ongoingMessage;

  /// Title shown when the agent asks for human confirmation.
  final String hitlTitle;

  /// Suffix appended to the HITL notification channel name.
  final String hitlChannelSuffix;

  /// Description for the HITL notification channel.
  final String hitlChannelDescription;

  /// Suffix appended to the completion notification channel name.
  final String completionChannelSuffix;

  /// Description for the completion notification channel.
  final String completionChannelDescription;

  /// Message shown when the task completes.
  final String completionMessage;

  /// Prefix used for stream errors.
  final String errorPrefix;

  /// Label for the stop action on the ongoing notification.
  final String stopActionLabel;

  /// Label for the open action when no HITL options are provided.
  final String openActionLabel;

  const NotificationConfig({
    this.channelName = 'Agent',
    this.channelDescription = 'Napaxi Agent is running',
    this.ongoingTitle = 'Napaxi Agent',
    this.ongoingMessage = 'Agent is running...',
    this.hitlTitle = 'Agent needs confirmation',
    this.hitlChannelSuffix = 'Confirmation',
    this.hitlChannelDescription = 'Notifications requiring your confirmation',
    this.completionChannelSuffix = 'Completed',
    this.completionChannelDescription = 'Task completion notifications',
    this.completionMessage = 'Task completed',
    this.errorPrefix = 'Error',
    this.stopActionLabel = 'Stop',
    this.openActionLabel = 'Open',
  });
}

/// Types of actions the user can take on background notifications.
enum BackgroundAction {
  /// User tapped "Stop" on the ongoing notification.
  stop,

  /// User approved a HITL request via notification button.
  hitlApprove,

  /// User denied a HITL request via notification button.
  hitlDeny,

  /// User tapped "View" on a completion notification.
  viewResult,

  /// A trusted Provider app submitted an App-to-Agent trigger.
  agentTrigger,

  /// A platform scheduler wake fired for a mobile automation job.
  automationWake,
}

/// An event emitted when the user interacts with a background notification.
class BackgroundActionEvent {
  /// The action the user took.
  final BackgroundAction action;

  /// The HITL request ID (only set for [BackgroundAction.hitlApprove] and
  /// [BackgroundAction.hitlDeny]).
  final String? requestId;

  /// Additional payload (e.g., the option text the user selected).
  final String? payload;

  const BackgroundActionEvent({
    required this.action,
    this.requestId,
    this.payload,
  });

  @override
  String toString() =>
      'BackgroundActionEvent(action: $action, requestId: $requestId, payload: $payload)';
}

/// Checks whether background execution is supported on the current platform.
bool isBackgroundExecutionSupported() => Platform.isAndroid;
