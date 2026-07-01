import 'dart:convert';

/// Agent 句柄（标识一个已创建的 Agent 实例）
class AgentHandle {
  final String agentId;

  const AgentHandle({required this.agentId});

  @override
  String toString() => 'AgentHandle($agentId)';
}

/// Agent 定义（用于 CRUD 管理）
class AgentDefinition {
  final String id;
  final String name;
  final String description;
  final String systemPrompt;
  final String? provider;
  final String? model;
  final String? modelProfileId;
  final String engineId;
  final String engineProfileId;
  final Map<String, dynamic> engineConfig;
  final ToolFilter toolFilter;
  final List<String>? toolList;
  final String? icon;

  const AgentDefinition({
    required this.id,
    required this.name,
    this.description = '',
    this.systemPrompt = '',
    this.provider,
    this.model,
    this.modelProfileId,
    this.engineId = 'napaxi_core',
    this.engineProfileId = '',
    this.engineConfig = const {},
    this.toolFilter = ToolFilter.all,
    this.toolList,
    this.icon,
  });

  factory AgentDefinition.fromJson(String jsonStr) {
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    return AgentDefinition.fromMap(map);
  }

  factory AgentDefinition.fromMap(Map<String, dynamic> map) {
    final filterMap = map['tool_filter'] as Map<String, dynamic>?;
    ToolFilter filter = ToolFilter.all;
    List<String>? toolList;

    if (filterMap != null) {
      final type = filterMap['type'] as String? ?? 'AllTools';
      toolList = (filterMap['tools'] as List?)?.cast<String>();
      filter = switch (type) {
        'Allowlist' => ToolFilter.allowlist,
        'Denylist' => ToolFilter.denylist,
        _ => ToolFilter.all,
      };
    }
    final rawEngineConfig = map['engine_config'];

    return AgentDefinition(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      description: map['description'] as String? ?? '',
      systemPrompt: map['system_prompt'] as String? ?? '',
      provider: map['provider'] as String?,
      model: map['model'] as String?,
      modelProfileId: map['model_profile_id'] as String?,
      engineId: map['engine_id'] as String? ?? 'napaxi_core',
      engineProfileId: map['engine_profile_id'] as String? ?? '',
      engineConfig: rawEngineConfig is Map
          ? Map<String, dynamic>.from(rawEngineConfig)
          : const <String, dynamic>{},
      toolFilter: filter,
      toolList: toolList,
      icon: map['icon'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'description': description,
        'system_prompt': systemPrompt,
        if (provider != null && provider!.trim().isNotEmpty)
          'provider': provider,
        if (model != null && model!.trim().isNotEmpty) 'model': model,
        if (modelProfileId != null && modelProfileId!.trim().isNotEmpty)
          'model_profile_id': modelProfileId,
        'engine_id': engineId.trim().isEmpty ? 'napaxi_core' : engineId,
        if (engineProfileId.trim().isNotEmpty)
          'engine_profile_id': engineProfileId,
        if (engineConfig.isNotEmpty) 'engine_config': engineConfig,
        'tool_filter': {
          'type': toolFilter.name == 'all'
              ? 'AllTools'
              : toolFilter.name == 'allowlist'
                  ? 'Allowlist'
                  : 'Denylist',
          if (toolList != null) 'tools': toolList,
        },
        if (icon != null && icon!.trim().isNotEmpty) 'icon': icon,
      };

  String toJson() => jsonEncode(toMap());
}

/// 工具过滤模式
enum ToolFilter { all, allowlist, denylist }
