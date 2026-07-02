import 'dart:convert';

import '../generated/bridge/evolution.dart' as rust_evolution;
import '../models/evolution.dart';
import 'json_codec.dart';

/// Evolution API: inspect and act on the agent's self-evolution suggestions,
/// runs, and diagnostics.
///
/// Owns its logic and calls the core bridge directly (handle supplied by the
/// engine as a closure), mirroring the native adapters' `EvolutionApi`
/// (Android `Apis.kt`, iOS `NapaxiEvolutionAPI`). `NapaxiEngine`'s flat evolution
/// methods forward to this facade. Method names match the Android facade.
class EvolutionApi {
  EvolutionApi(this._handle);

  final int Function() _handle;

  /// List pending self-evolution suggestions awaiting apply/reject.
  List<Map<String, dynamic>> listPending() {
    final json = rust_evolution.listPendingEvolution(handle: _handle());
    return decodeJsonArray(json)
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  /// Apply a pending self-evolution suggestion by ID.
  Future<Map<String, dynamic>> applyPending(String pendingId) async {
    final json = rust_evolution.applyPendingEvolution(
      handle: _handle(),
      pendingId: pendingId,
    );
    try {
      return decodeJsonObject(json);
    } on FormatException {
      // Keep the previous soft-failure behavior for malformed core responses.
    }
    return {'error': 'unexpected apply response'};
  }

  /// Reject a pending self-evolution suggestion by ID.
  Future<Map<String, dynamic>> rejectPending(String pendingId) async {
    final json = rust_evolution.rejectPendingEvolution(
      handle: _handle(),
      pendingId: pendingId,
    );
    try {
      return decodeJsonObject(json);
    } on FormatException {
      // Keep the previous soft-failure behavior for malformed core responses.
    }
    return {'error': 'unexpected reject response'};
  }

  /// List self-evolution review runs, optionally filtered by run IDs.
  List<EvolutionRun> runs({List<String>? runIds}) {
    final json = rust_evolution.listEvolutionRuns(
      handle: _handle(),
      runIdsJson: jsonEncode(runIds ?? const <String>[]),
    );
    return decodeJsonObjectList(json, EvolutionRun.fromMap);
  }

  /// List persisted self-evolution diagnostics.
  List<EvolutionDiagnostic> diagnostics() {
    final json = rust_evolution.listEvolutionDiagnostics(handle: _handle());
    return decodeJsonObjectList(json, EvolutionDiagnostic.fromMap);
  }
}
