part of '../main.dart';

const String _demoAccountId = sdk.NapaxiEngine.defaultAccountId;
const DemoAgent _defaultDemoAgent = DemoAgent(
  id: sdk.NapaxiEngine.defaultAgentId,
  name: 'napaxi',
  icon: Icons.auto_awesome_rounded,
);

class DemoAgent {
  const DemoAgent({
    required this.id,
    required this.name,
    required this.icon,
    this.systemPrompt = '',
    this.modelProfileId,
  });

  final String id;
  final String name;
  final IconData icon;
  final String systemPrompt;
  final String? modelProfileId;

  String label(AppLanguage language) => name;

  bool get isDefault => id == sdk.NapaxiEngine.defaultAgentId;

  bool get inheritsModel => modelProfileId == null || modelProfileId!.isEmpty;

  factory DemoAgent.fromDefinition(sdk.AgentDefinition definition) {
    return DemoAgent(
      id: definition.id,
      name: definition.name.trim().isEmpty ? definition.id : definition.name,
      icon: _agentIconFromId(definition.id),
      systemPrompt: definition.systemPrompt,
      modelProfileId: definition.modelProfileId?.trim().isEmpty ?? true
          ? null
          : definition.modelProfileId!.trim(),
    );
  }
}

IconData _agentIconFromId(String agentId) {
  if (agentId == sdk.NapaxiEngine.defaultAgentId) {
    return Icons.auto_awesome_rounded;
  }
  if (agentId.startsWith('engine.')) return Icons.terminal_rounded;
  return Icons.person_search_rounded;
}

String _agentIdFromName(String name) {
  final lower = name.trim().toLowerCase();
  final slug = lower
      .replaceAll(RegExp(r'[^a-z0-9_-]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  if (slug.isNotEmpty) return slug;
  return 'agent-${DateTime.now().millisecondsSinceEpoch}';
}
