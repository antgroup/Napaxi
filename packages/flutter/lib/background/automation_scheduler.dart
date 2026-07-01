import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../api/automation_api.dart';
import '../models/automation.dart';

/// Bridges automation jobs to the host's platform scheduler, syncing job state
/// over the background method channel.
class NapaxiAutomationScheduler {
  NapaxiAutomationScheduler(
    this._automation, {
    MethodChannel? channel,
    bool? supported,
  })  : _channel = channel ?? _methodChannel,
        _supported = supported ?? Platform.isAndroid;

  static const _methodChannel = MethodChannel('com.napaxi.flutter/background');
  static const _eventChannel =
      EventChannel('com.napaxi.flutter/background_events');

  final AutomationApi _automation;
  final MethodChannel _channel;
  final bool _supported;
  StreamSubscription<dynamic>? _wakeSubscription;

  bool get isSupported => _supported;

  Future<AutomationSchedulerStatus> status() async {
    if (!_supported) {
      return const AutomationSchedulerStatus(
        supported: false,
        platform: 'unsupported',
        reason: 'platform scheduler is not available',
      );
    }
    final raw = await _invokeMap('getAutomationSchedulerStatus');
    if (raw == null) {
      return const AutomationSchedulerStatus(
        supported: false,
        platform: 'android',
        reason: 'native scheduler bridge is not available',
      );
    }
    return AutomationSchedulerStatus.fromJson(raw);
  }

  Future<AutomationWake?> rescheduleNextWake({bool exact = false}) async {
    final wake = _automation.getNextAutomationWake();
    if (!_supported) return wake;
    if (wake == null || wake.jobId.trim().isEmpty || wake.atMs <= 0) {
      await _invokeBool('cancelAutomationWake');
      return null;
    }
    final scheduled = await _invokeBool('scheduleAutomationWake', {
      'jobId': wake.jobId,
      'atMs': wake.atMs,
      'trigger': wake.trigger.toJson(),
      'exact': exact,
    });
    return scheduled ? wake : null;
  }

  Future<List<AutomationPendingWake>> pendingWakes() async {
    if (!_supported) return const [];
    final raw = await _invokeList('getPendingAutomationWakes');
    if (raw == null) return const [];
    return raw
        .whereType<Map>()
        .map(
          (item) =>
              AutomationPendingWake.fromJson(Map<String, dynamic>.from(item)),
        )
        .where((wake) => wake.jobId.trim().isNotEmpty)
        .toList(growable: false);
  }

  Future<List<AutomationRun>> drainPendingWakes() async {
    final wakes = await pendingWakes();
    final runs = <AutomationRun>[];
    for (final wake in wakes) {
      if (_automation.getAutomationJob(wake.jobId) == null) {
        await _invokeBool(
            'clearPendingAutomationWake', {'wakeId': wake.wakeId});
        continue;
      }
      try {
        runs.add(
          await _automation.recordAutomationWake(wake.jobId, wake.source),
        );
      } on StateError catch (error) {
        if (!_isMissingJobError(error)) rethrow;
      }
      await _invokeBool('clearPendingAutomationWake', {'wakeId': wake.wakeId});
    }
    return runs;
  }

  Future<List<AutomationRun>> catchUpDueJobs({
    int? nowMs,
    int limit = 5,
  }) async {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final jobs = _automation.listAutomationJobs(enabled: true);
    final due = jobs
        .where((job) {
          final next = job.state.nextRunAtMs;
          return next != null && next <= now;
        })
        .take(limit.clamp(0, 50))
        .toList(growable: false);
    final runs = <AutomationRun>[];
    for (final job in due) {
      runs.add(await _automation.recordAutomationWake(job.id, 'catch_up'));
    }
    return runs;
  }

  Future<AutomationSchedulerSyncResult> sync({
    bool exact = false,
    int catchUpLimit = 5,
  }) async {
    final runs = <AutomationRun>[
      ...await drainPendingWakes(),
      ...await catchUpDueJobs(limit: catchUpLimit),
    ];
    final wake = await rescheduleNextWake(exact: exact);
    return AutomationSchedulerSyncResult(
      runs: runs,
      scheduledWake: wake,
      platformWakeScheduled: wake != null && _supported,
    );
  }

  void startWakeListener({
    bool exact = false,
    int catchUpLimit = 10,
    bool notify = true,
  }) {
    if (!_supported || _wakeSubscription != null) return;
    _wakeSubscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is! Map<dynamic, dynamic>) return;
        if (event['action'] != 'automationWake') return;
        _handleAutomationWake(
          exact: exact,
          catchUpLimit: catchUpLimit,
          notify: notify,
        ).catchError((_) {});
      },
      onError: (_) {},
    );
  }

  void dispose() {
    _wakeSubscription?.cancel();
    _wakeSubscription = null;
  }

  Future<void> _handleAutomationWake({
    required bool exact,
    required int catchUpLimit,
    required bool notify,
  }) async {
    final result = await sync(exact: exact, catchUpLimit: catchUpLimit);
    if (!notify || result.runs.isEmpty) return;
    await _notifyRuns(result.runs);
  }

  Future<void> _notifyRuns(List<AutomationRun> runs) async {
    final failed = runs.where((run) => run.status == 'failed').toList();
    if (failed.isNotEmpty) {
      await _invokeBool('showErrorNotification', {
        'title': 'napaxi Scheduled Task',
        'message':
            _runMessage(failed.first, fallback: 'Scheduled task failed.'),
      });
      return;
    }
    await _invokeBool('showCompletionNotification', {
      'title': 'napaxi Scheduled Task',
      'message': _runMessage(runs.last, fallback: 'Scheduled task completed.'),
    });
  }

  String _runMessage(AutomationRun run, {required String fallback}) {
    final summary = run.summary?.trim();
    if (summary != null && summary.isNotEmpty) return summary;
    final error = run.error?.trim();
    if (error != null && error.isNotEmpty) return error;
    return fallback;
  }

  bool _isMissingJobError(StateError error) {
    final message = error.message;
    return message.startsWith('automation job ') &&
        message.endsWith(' not found');
  }

  Future<Map<String, dynamic>?> _invokeMap(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    try {
      final raw = await _channel.invokeMethod<Object?>(method, args);
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
    return null;
  }

  Future<List<Object?>?> _invokeList(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    try {
      final raw = await _channel.invokeMethod<Object?>(method, args);
      if (raw is List) return raw;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
    return null;
  }

  Future<bool> _invokeBool(String method, [Map<String, dynamic>? args]) async {
    try {
      return await _channel.invokeMethod<bool>(method, args) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
