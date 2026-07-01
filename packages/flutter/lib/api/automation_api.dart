import 'dart:convert';

import '../generated/bridge/automation.dart' as rust_automation;
import '../models/automation.dart';

/// Automation API: create, update, and manage scheduled automation jobs.
class AutomationApi {
  AutomationApi(this._handle);

  final int Function() _handle;

  AutomationJob createAutomationJob(AutomationJob job) {
    return _decodeJob(
      rust_automation.createAutomationJob(
        handle: _handle(),
        jobJson: job.toJsonString(),
      ),
    );
  }

  AutomationJob updateAutomationJob(
    String jobId,
    Map<String, dynamic> patch,
  ) {
    return _decodeJob(
      rust_automation.updateAutomationJob(
        handle: _handle(),
        jobId: jobId,
        patchJson: jsonEncode(patch),
      ),
    );
  }

  bool deleteAutomationJob(String jobId) {
    return rust_automation.deleteAutomationJob(
      handle: _handle(),
      jobId: jobId,
    );
  }

  List<AutomationJob> listAutomationJobs({
    String? accountId,
    String? agentId,
    bool? enabled,
  }) {
    return decodeAutomationJobs(
      rust_automation.listAutomationJobs(
        handle: _handle(),
        filterJson: jsonEncode({
          if (accountId != null) 'accountId': accountId,
          if (agentId != null) 'agentId': agentId,
          if (enabled != null) 'enabled': enabled,
        }),
      ),
    );
  }

  AutomationJob? getAutomationJob(String jobId) {
    final raw = rust_automation.getAutomationJob(
      handle: _handle(),
      jobId: jobId,
    );
    final decoded = jsonDecode(raw);
    if (decoded is! Map || decoded['error'] != null) return null;
    return AutomationJob.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<AutomationRun> runAutomationJob(
    String jobId, {
    String mode = 'manual',
  }) async {
    return _decodeRun(
      await rust_automation.runAutomationJob(
        handle: _handle(),
        jobId: jobId,
        mode: mode,
      ),
    );
  }

  List<AutomationRun> listAutomationRuns({
    String? jobId,
    int limit = 200,
    int offset = 0,
  }) {
    return decodeAutomationRuns(
      rust_automation.listAutomationRuns(
        handle: _handle(),
        jobId: jobId,
        limit: limit,
        offset: offset,
      ),
    );
  }

  AutomationWake? getNextAutomationWake() {
    final raw = rust_automation.getNextAutomationWake(handle: _handle());
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    return AutomationWake.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<AutomationRun> recordAutomationWake(
      String jobId, String source) async {
    return _decodeRun(
      await rust_automation.recordAutomationWake(
        handle: _handle(),
        jobId: jobId,
        source: source,
      ),
    );
  }

  AutomationJob _decodeJob(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is Map && decoded['error'] != null) {
      throw StateError(decoded['error'].toString());
    }
    return AutomationJob.fromJson(Map<String, dynamic>.from(decoded as Map));
  }

  AutomationRun _decodeRun(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is Map && decoded['error'] != null) {
      throw StateError(decoded['error'].toString());
    }
    return AutomationRun.fromJson(Map<String, dynamic>.from(decoded as Map));
  }
}
