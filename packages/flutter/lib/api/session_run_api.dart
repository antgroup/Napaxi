import 'dart:convert';

import '../generated/bridge/session_runs.dart' as rust_session_runs;
import '../models/session_run.dart';

/// Session-run API: query the history of agent runs recorded by the engine.
class SessionRunApi {
  SessionRunApi(this._handle);

  final int Function() _handle;

  List<SessionRunRecord> list({
    String? agentId,
    String? threadId,
    SessionRunRecordStatus? status,
    int limit = 100,
    int offset = 0,
  }) {
    return decodeSessionRunRecords(
      rust_session_runs.listSessionRuns(
        handle: _handle(),
        filterJson: jsonEncode({
          if (agentId != null) 'agentId': agentId,
          if (threadId != null) 'threadId': threadId,
          if (status != null && status != SessionRunRecordStatus.unknown)
            'status': status.wireName,
        }),
        limit: limit,
        offset: offset,
      ),
    );
  }

  SessionRunRecord? get(String runId) {
    final raw = rust_session_runs.getSessionRun(
      handle: _handle(),
      runId: runId,
    );
    final decoded = jsonDecode(raw);
    if (decoded is! Map || decoded['error'] != null) return null;
    return SessionRunRecord.fromJson(Map<String, dynamic>.from(decoded));
  }

  List<SessionRunRecord> active() {
    return decodeSessionRunRecords(
      rust_session_runs.getActiveSessionRuns(handle: _handle()),
    );
  }
}
