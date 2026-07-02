import '../generated/bridge/capability.dart' as rust_capability;
import '../models/capability.dart';

/// Capability API: list capability definitions and resolve their status
/// against a profile/selection.
class CapabilityApi {
  CapabilityApi(this._handle, {NapaxiCapabilityProfile? defaultProfile})
      : _defaultProfile = defaultProfile;

  final int Function() _handle;
  final NapaxiCapabilityProfile? _defaultProfile;

  List<NapaxiCapabilityDefinition> listDefinitions() {
    return decodeCapabilityDefinitions(
      rust_capability.listCapabilityDefinitionsJson(),
    );
  }

  List<NapaxiCapabilityStatus> listStatuses({
    NapaxiCapabilityProfile? profile,
    NapaxiCapabilitySelection? selection,
  }) {
    return decodeCapabilityStatuses(
      rust_capability.listCapabilityStatusJson(
        handle: _handle(),
        profileJson: (profile ?? _defaultProfile)?.toJsonString() ?? '{}',
        selectionJson: selection?.toJsonString() ?? '{}',
      ),
    );
  }

  List<NapaxiScenarioPack> listScenarioPacks() {
    return decodeScenarioPacks(
      rust_capability.listScenarioPacksJson(handle: _handle()),
    );
  }

  NapaxiScenarioPackInstallResult? installScenarioPack(
    NapaxiScenarioPack pack,
  ) {
    return installScenarioPackJson(pack.toJsonString());
  }

  NapaxiScenarioPackInstallResult? installScenarioPackJson(String packJson) {
    return decodeScenarioPackInstallResult(
      rust_capability.installScenarioPackJson(
        handle: _handle(),
        packJson: packJson,
      ),
    );
  }

  NapaxiScenarioPackRemovalResult? removeScenarioPack(String scenarioId) {
    return decodeScenarioPackRemovalResult(
      rust_capability.removeScenarioPackJson(
        handle: _handle(),
        scenarioId: scenarioId,
      ),
    );
  }

  List<NapaxiScenarioStatus> listScenarioStatuses({
    NapaxiCapabilityProfile? profile,
    NapaxiCapabilitySelection? selection,
  }) {
    return decodeScenarioStatuses(
      rust_capability.listScenarioStatusJson(
        handle: _handle(),
        profileJson: (profile ?? _defaultProfile)?.toJsonString() ?? '{}',
        selectionJson: selection?.toJsonString() ?? '{}',
      ),
    );
  }

  NapaxiScenarioResolution? resolveScenario(
    String scenarioId, {
    NapaxiCapabilityProfile? profile,
    NapaxiCapabilitySelection? selection,
  }) {
    return decodeScenarioResolution(
      rust_capability.resolveScenarioJson(
        handle: _handle(),
        profileJson: (profile ?? _defaultProfile)?.toJsonString() ?? '{}',
        selectionJson: selection?.toJsonString() ?? '{}',
        scenarioId: scenarioId,
      ),
    );
  }

  String providerCapabilityId(String provider) {
    return rust_capability.providerCapabilityId(provider: provider);
  }

  String agentEngineCapabilityId(String engineId) {
    return rust_capability.agentEngineCapabilityId(engineId: engineId);
  }

  String toolCapabilityId(String toolName) {
    return rust_capability.toolCapabilityId(toolName: toolName);
  }
}
