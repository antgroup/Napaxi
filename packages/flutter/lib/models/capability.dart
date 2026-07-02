import 'dart:convert';

/// Declares a single capability the host can register: its identity,
/// supported platforms, configuration schema, risk level, and the
/// requirements/activation rules that gate admission.
class NapaxiCapabilityDefinition {
  final String id;
  final String kind;
  final String version;
  final List<String> platforms;
  final Map<String, dynamic> configSchema;
  final String risk;
  final List<String> requirements;
  final bool defaultEnabled;
  final String activation;

  const NapaxiCapabilityDefinition({
    required this.id,
    required this.kind,
    required this.version,
    required this.platforms,
    required this.configSchema,
    required this.risk,
    required this.requirements,
    required this.defaultEnabled,
    required this.activation,
  });

  factory NapaxiCapabilityDefinition.fromJson(Map<String, dynamic> json) {
    return NapaxiCapabilityDefinition(
      id: json['id'] as String? ?? '',
      kind: json['kind'] as String? ?? '',
      version: json['version'] as String? ?? '',
      platforms: (json['platforms'] as List? ?? const [])
          .map((item) => item.toString())
          .toList(growable: false),
      configSchema: json['config_schema'] is Map
          ? Map<String, dynamic>.from(json['config_schema'] as Map)
          : const <String, dynamic>{},
      risk: json['risk'] as String? ?? '',
      requirements: (json['requirements'] as List? ?? const [])
          .map((item) => item.toString())
          .toList(growable: false),
      defaultEnabled: json['default_enabled'] as bool? ?? false,
      activation: json['activation'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'version': version,
        'platforms': platforms,
        'config_schema': configSchema,
        'risk': risk,
        'requirements': requirements,
        'default_enabled': defaultEnabled,
        'activation': activation,
      };
}

/// Runtime status of a capability: its definition plus whether it is
/// registered, available, and enabled, with a reason when unavailable.
class NapaxiCapabilityStatus {
  final NapaxiCapabilityDefinition definition;
  final bool registered;
  final bool available;
  final bool enabled;
  final String? unavailableReason;

  const NapaxiCapabilityStatus({
    required this.definition,
    required this.registered,
    required this.available,
    required this.enabled,
    this.unavailableReason,
  });

  factory NapaxiCapabilityStatus.fromJson(Map<String, dynamic> json) {
    return NapaxiCapabilityStatus(
      definition: NapaxiCapabilityDefinition.fromJson(
        Map<String, dynamic>.from(json['definition'] as Map? ?? const {}),
      ),
      registered: json['registered'] as bool? ?? false,
      available: json['available'] as bool? ?? false,
      enabled: json['enabled'] as bool? ?? false,
      unavailableReason: json['unavailable_reason'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'definition': definition.toJson(),
        'registered': registered,
        'available': available,
        'enabled': enabled,
        if (unavailableReason != null) 'unavailable_reason': unavailableReason,
      };
}

/// A platform's capability profile: which capabilities it supports and
/// which are explicitly disabled.
class NapaxiCapabilityProfile {
  final String? platform;
  final List<String> supportedCapabilities;
  final List<String> disabledCapabilities;

  const NapaxiCapabilityProfile({
    this.platform,
    this.supportedCapabilities = const [],
    this.disabledCapabilities = const [],
  });

  Map<String, dynamic> toJson() => {
        if (platform != null) 'platform': platform,
        'supported_capabilities': supportedCapabilities,
        'disabled_capabilities': disabledCapabilities,
      };

  String toJsonString() => jsonEncode(toJson());
}

/// A caller's requested capability selection: capabilities to enable or
/// disable, plus per-capability configuration overrides.
class NapaxiCapabilitySelection {
  final List<String> enabledCapabilities;
  final List<String> disabledCapabilities;
  final Map<String, dynamic> config;

  const NapaxiCapabilitySelection({
    this.enabledCapabilities = const [],
    this.disabledCapabilities = const [],
    this.config = const {},
  });

  Map<String, dynamic> toJson() => {
        'enabled_capabilities': enabledCapabilities,
        'disabled_capabilities': disabledCapabilities,
        'config': config,
      };

  String toJsonString() => jsonEncode(toJson());

  factory NapaxiCapabilitySelection.fromJson(Map<String, dynamic> json) {
    return NapaxiCapabilitySelection(
      enabledCapabilities: _stringList(json['enabled_capabilities']),
      disabledCapabilities: _stringList(json['disabled_capabilities']),
      config: Map<String, dynamic>.from(json['config'] as Map? ?? const {}),
    );
  }
}

/// A bundle of capabilities, UI/settings contributions, and metadata that
/// together activate a higher-level scenario (use case) on the host.
class NapaxiScenarioPack {
  final String id;
  final String version;
  final String label;
  final String description;
  final String risk;
  final String activation;
  final List<String> executionPlanes;
  final List<String> requiredCapabilities;
  final List<String> recommendedCapabilities;
  final List<String> optionalCapabilities;
  final List<String> uiSurfaces;
  final List<NapaxiScenarioSettingsContribution> settingsContributions;
  final List<NapaxiScenarioUiContribution> uiContributions;
  final List<String> memoryScopes;
  final List<String> tags;

  const NapaxiScenarioPack({
    required this.id,
    required this.version,
    required this.label,
    required this.description,
    required this.risk,
    required this.activation,
    this.executionPlanes = const [],
    this.requiredCapabilities = const [],
    this.recommendedCapabilities = const [],
    this.optionalCapabilities = const [],
    this.uiSurfaces = const [],
    this.settingsContributions = const [],
    this.uiContributions = const [],
    this.memoryScopes = const [],
    this.tags = const [],
  });

  factory NapaxiScenarioPack.fromJson(Map<String, dynamic> json) {
    return NapaxiScenarioPack(
      id: json['id'] as String? ?? '',
      version: json['version'] as String? ?? '',
      label: json['label'] as String? ?? '',
      description: json['description'] as String? ?? '',
      risk: json['risk'] as String? ?? '',
      activation: json['activation'] as String? ?? '',
      executionPlanes: _stringList(json['execution_planes']),
      requiredCapabilities: _stringList(json['required_capabilities']),
      recommendedCapabilities: _stringList(json['recommended_capabilities']),
      optionalCapabilities: _stringList(json['optional_capabilities']),
      uiSurfaces: _stringList(json['ui_surfaces']),
      settingsContributions: _settingsContributionList(
        json['settings_contributions'],
      ),
      uiContributions: _uiContributionList(json['ui_contributions']),
      memoryScopes: _stringList(json['memory_scopes']),
      tags: _stringList(json['tags']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'version': version,
        'label': label,
        'description': description,
        'risk': risk,
        'activation': activation,
        'execution_planes': executionPlanes,
        'required_capabilities': requiredCapabilities,
        'recommended_capabilities': recommendedCapabilities,
        'optional_capabilities': optionalCapabilities,
        'ui_surfaces': uiSurfaces,
        'settings_contributions': settingsContributions
            .map((contribution) => contribution.toJson())
            .toList(growable: false),
        'ui_contributions': uiContributions
            .map((contribution) => contribution.toJson())
            .toList(growable: false),
        'memory_scopes': memoryScopes,
        'tags': tags,
      };

  String toJsonString() => jsonEncode(toJson());
}

/// A settings panel a scenario pack contributes for one of its capabilities,
/// described by placement, title, JSON schema, and available actions.
class NapaxiScenarioSettingsContribution {
  final String id;
  final String capabilityId;
  final String placement;
  final String title;
  final String description;
  final Map<String, dynamic> schema;
  final List<String> actions;

  const NapaxiScenarioSettingsContribution({
    required this.id,
    required this.capabilityId,
    this.placement = '',
    this.title = '',
    this.description = '',
    this.schema = const {},
    this.actions = const [],
  });

  factory NapaxiScenarioSettingsContribution.fromJson(
    Map<String, dynamic> json,
  ) {
    return NapaxiScenarioSettingsContribution(
      id: json['id'] as String? ?? '',
      capabilityId: json['capability_id'] as String? ?? '',
      placement: json['placement'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      schema: json['schema'] is Map
          ? Map<String, dynamic>.from(json['schema'] as Map)
          : const <String, dynamic>{},
      actions: _stringList(json['actions']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'capability_id': capabilityId,
        'placement': placement,
        'title': title,
        'description': description,
        'schema': schema,
        'actions': actions,
      };
}

/// A UI surface a scenario pack contributes for one of its capabilities,
/// described by placement, renderer, data sources, and available actions.
class NapaxiScenarioUiContribution {
  final String id;
  final String capabilityId;
  final String placement;
  final String title;
  final String description;
  final String icon;
  final String renderer;
  final Map<String, dynamic> dataSources;
  final List<String> actions;

  const NapaxiScenarioUiContribution({
    required this.id,
    required this.capabilityId,
    required this.renderer,
    this.placement = '',
    this.title = '',
    this.description = '',
    this.icon = '',
    this.dataSources = const {},
    this.actions = const [],
  });

  factory NapaxiScenarioUiContribution.fromJson(Map<String, dynamic> json) {
    return NapaxiScenarioUiContribution(
      id: json['id'] as String? ?? '',
      capabilityId: json['capability_id'] as String? ?? '',
      placement: json['placement'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      icon: json['icon'] as String? ?? '',
      renderer: json['renderer'] as String? ?? '',
      dataSources: json['data_sources'] is Map
          ? Map<String, dynamic>.from(json['data_sources'] as Map)
          : const <String, dynamic>{},
      actions: _stringList(json['actions']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'capability_id': capabilityId,
        'placement': placement,
        'title': title,
        'description': description,
        'icon': icon,
        'renderer': renderer,
        'data_sources': dataSources,
        'actions': actions,
      };
}

/// Runtime status of a scenario pack: whether it is registered, available,
/// and enabled, plus any missing or disabled required capabilities.
class NapaxiScenarioStatus {
  final NapaxiScenarioPack definition;
  final bool registered;
  final bool available;
  final bool enabled;
  final List<String> missingRequiredCapabilities;
  final List<String> disabledRequiredCapabilities;
  final List<String> unavailableReasons;

  const NapaxiScenarioStatus({
    required this.definition,
    required this.registered,
    required this.available,
    required this.enabled,
    this.missingRequiredCapabilities = const [],
    this.disabledRequiredCapabilities = const [],
    this.unavailableReasons = const [],
  });

  factory NapaxiScenarioStatus.fromJson(Map<String, dynamic> json) {
    return NapaxiScenarioStatus(
      definition: NapaxiScenarioPack.fromJson(
        Map<String, dynamic>.from(json['definition'] as Map? ?? const {}),
      ),
      registered: json['registered'] as bool? ?? false,
      available: json['available'] as bool? ?? false,
      enabled: json['enabled'] as bool? ?? false,
      missingRequiredCapabilities: _stringList(
        json['missing_required_capabilities'],
      ),
      disabledRequiredCapabilities: _stringList(
        json['disabled_required_capabilities'],
      ),
      unavailableReasons: _stringList(json['unavailable_reasons']),
    );
  }

  Map<String, dynamic> toJson() => {
        'definition': definition.toJson(),
        'registered': registered,
        'available': available,
        'enabled': enabled,
        'missing_required_capabilities': missingRequiredCapabilities,
        'disabled_required_capabilities': disabledRequiredCapabilities,
        'unavailable_reasons': unavailableReasons,
      };
}

/// The computed plan for activating a scenario: which capabilities to
/// enable/disable and which are required by host, remote, or policy.
class NapaxiScenarioActivationPlan {
  final List<String> supportedCapabilities;
  final List<String> enabledCapabilities;
  final List<String> disabledCapabilities;
  final List<String> hostRequiredCapabilities;
  final List<String> remoteRequiredCapabilities;
  final List<String> policyRequiredCapabilities;
  final List<String> warnings;

  const NapaxiScenarioActivationPlan({
    this.supportedCapabilities = const [],
    this.enabledCapabilities = const [],
    this.disabledCapabilities = const [],
    this.hostRequiredCapabilities = const [],
    this.remoteRequiredCapabilities = const [],
    this.policyRequiredCapabilities = const [],
    this.warnings = const [],
  });

  factory NapaxiScenarioActivationPlan.fromJson(Map<String, dynamic> json) {
    return NapaxiScenarioActivationPlan(
      supportedCapabilities: _stringList(json['supported_capabilities']),
      enabledCapabilities: _stringList(json['enabled_capabilities']),
      disabledCapabilities: _stringList(json['disabled_capabilities']),
      hostRequiredCapabilities: _stringList(json['host_required_capabilities']),
      remoteRequiredCapabilities: _stringList(
        json['remote_required_capabilities'],
      ),
      policyRequiredCapabilities: _stringList(
        json['policy_required_capabilities'],
      ),
      warnings: _stringList(json['warnings']),
    );
  }

  Map<String, dynamic> toJson() => {
        'supported_capabilities': supportedCapabilities,
        'enabled_capabilities': enabledCapabilities,
        'disabled_capabilities': disabledCapabilities,
        'host_required_capabilities': hostRequiredCapabilities,
        'remote_required_capabilities': remoteRequiredCapabilities,
        'policy_required_capabilities': policyRequiredCapabilities,
        'warnings': warnings,
      };
}

/// Result of resolving a scenario: its current status paired with the
/// activation plan needed to enable it.
class NapaxiScenarioResolution {
  final NapaxiScenarioStatus status;
  final NapaxiScenarioActivationPlan activationPlan;

  const NapaxiScenarioResolution({
    required this.status,
    required this.activationPlan,
  });

  factory NapaxiScenarioResolution.fromJson(Map<String, dynamic> json) {
    return NapaxiScenarioResolution(
      status: NapaxiScenarioStatus.fromJson(
        Map<String, dynamic>.from(json['status'] as Map? ?? const {}),
      ),
      activationPlan: NapaxiScenarioActivationPlan.fromJson(
        Map<String, dynamic>.from(json['activation_plan'] as Map? ?? const {}),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'status': status.toJson(),
        'activation_plan': activationPlan.toJson(),
      };
}

/// Outcome of installing a scenario pack: the definition installed, whether
/// it replaced an existing pack, and any warnings raised.
class NapaxiScenarioPackInstallResult {
  final NapaxiScenarioPack definition;
  final bool installed;
  final bool replaced;
  final List<String> warnings;

  const NapaxiScenarioPackInstallResult({
    required this.definition,
    required this.installed,
    required this.replaced,
    this.warnings = const [],
  });

  factory NapaxiScenarioPackInstallResult.fromJson(Map<String, dynamic> json) {
    return NapaxiScenarioPackInstallResult(
      definition: NapaxiScenarioPack.fromJson(
        Map<String, dynamic>.from(json['definition'] as Map? ?? const {}),
      ),
      installed: json['installed'] as bool? ?? false,
      replaced: json['replaced'] as bool? ?? false,
      warnings: _stringList(json['warnings']),
    );
  }

  Map<String, dynamic> toJson() => {
        'definition': definition.toJson(),
        'installed': installed,
        'replaced': replaced,
        'warnings': warnings,
      };
}

/// Outcome of removing a scenario pack: its id and whether removal occurred.
class NapaxiScenarioPackRemovalResult {
  final String scenarioId;
  final bool removed;

  const NapaxiScenarioPackRemovalResult({
    required this.scenarioId,
    required this.removed,
  });

  factory NapaxiScenarioPackRemovalResult.fromJson(Map<String, dynamic> json) {
    return NapaxiScenarioPackRemovalResult(
      scenarioId: json['scenario_id'] as String? ?? '',
      removed: json['removed'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'scenario_id': scenarioId,
        'removed': removed,
      };
}

/// Decodes a JSON array string into a list of capability definitions.
List<NapaxiCapabilityDefinition> decodeCapabilityDefinitions(String jsonStr) {
  final decoded = jsonDecode(jsonStr);
  if (decoded is! List) return const [];
  return decoded
      .whereType<Map>()
      .map(
        (item) =>
            NapaxiCapabilityDefinition.fromJson(Map<String, dynamic>.from(item)),
      )
      .toList(growable: false);
}

/// Decodes a JSON array string into a list of capability statuses.
List<NapaxiCapabilityStatus> decodeCapabilityStatuses(String jsonStr) {
  final decoded = jsonDecode(jsonStr);
  if (decoded is! List) return const [];
  return decoded
      .whereType<Map>()
      .map(
        (item) =>
            NapaxiCapabilityStatus.fromJson(Map<String, dynamic>.from(item)),
      )
      .toList(growable: false);
}

/// Decodes a JSON array string into a list of scenario packs.
List<NapaxiScenarioPack> decodeScenarioPacks(String jsonStr) {
  final decoded = jsonDecode(jsonStr);
  if (decoded is! List) return const [];
  return decoded
      .whereType<Map>()
      .map(
        (item) => NapaxiScenarioPack.fromJson(Map<String, dynamic>.from(item)),
      )
      .toList(growable: false);
}

/// Decodes a JSON array string into a list of scenario statuses.
List<NapaxiScenarioStatus> decodeScenarioStatuses(String jsonStr) {
  final decoded = jsonDecode(jsonStr);
  if (decoded is! List) return const [];
  return decoded
      .whereType<Map>()
      .map(
        (item) => NapaxiScenarioStatus.fromJson(Map<String, dynamic>.from(item)),
      )
      .toList(growable: false);
}

/// Decodes a scenario resolution object, or null on error/non-object JSON.
NapaxiScenarioResolution? decodeScenarioResolution(String jsonStr) {
  final decoded = jsonDecode(jsonStr);
  if (decoded is! Map || decoded.containsKey('error')) return null;
  return NapaxiScenarioResolution.fromJson(Map<String, dynamic>.from(decoded));
}

/// Decodes a scenario pack install result, or null on error/non-object JSON.
NapaxiScenarioPackInstallResult? decodeScenarioPackInstallResult(
  String jsonStr,
) {
  final decoded = jsonDecode(jsonStr);
  if (decoded is! Map || decoded.containsKey('error')) return null;
  return NapaxiScenarioPackInstallResult.fromJson(
    Map<String, dynamic>.from(decoded),
  );
}

/// Decodes a scenario pack removal result, or null on error/non-object JSON.
NapaxiScenarioPackRemovalResult? decodeScenarioPackRemovalResult(
  String jsonStr,
) {
  final decoded = jsonDecode(jsonStr);
  if (decoded is! Map || decoded.containsKey('error')) return null;
  return NapaxiScenarioPackRemovalResult.fromJson(
    Map<String, dynamic>.from(decoded),
  );
}

List<String> _stringList(Object? value) {
  return (value as List? ?? const [])
      .map((item) => item.toString())
      .toList(growable: false);
}

List<NapaxiScenarioSettingsContribution> _settingsContributionList(
  Object? value,
) {
  return (value as List? ?? const [])
      .whereType<Map>()
      .map(
        (item) => NapaxiScenarioSettingsContribution.fromJson(
          Map<String, dynamic>.from(item),
        ),
      )
      .toList(growable: false);
}

List<NapaxiScenarioUiContribution> _uiContributionList(Object? value) {
  return (value as List? ?? const [])
      .whereType<Map>()
      .map(
        (item) => NapaxiScenarioUiContribution.fromJson(
          Map<String, dynamic>.from(item),
        ),
      )
      .toList(growable: false);
}
