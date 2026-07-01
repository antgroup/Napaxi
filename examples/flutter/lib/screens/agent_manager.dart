part of '../main.dart';

class _AgentManagerPage extends StatefulWidget {
  const _AgentManagerPage({
    required this.client,
    required this.initialAgents,
    required this.activeAgentId,
    required this.profiles,
    required this.managementProfile,
  });

  final NapaxiChatClient client;
  final List<DemoAgent> initialAgents;
  final String activeAgentId;
  final List<LlmModelProfile> profiles;
  final LlmModelProfile? managementProfile;

  @override
  State<_AgentManagerPage> createState() => _AgentManagerPageState();
}

class _AgentManagerPageState extends State<_AgentManagerPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _promptController = TextEditingController();
  late List<DemoAgent> _agents = widget.initialAgents;
  String? _selectedModelProfileId;
  bool _isPreparing = false;
  bool _isSaving = false;
  bool _isInstallingProvider = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_prepareForManagement());
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _reloadAgents() async {
    final agents = await widget.client.listAgents();
    if (!mounted) return;
    setState(
      () => _agents = agents.isEmpty ? const [_defaultDemoAgent] : agents,
    );
  }

  Future<void> _prepareForManagement() async {
    if (_isPreparing) return;
    setState(() => _isPreparing = true);
    try {
      final profile = widget.managementProfile;
      if (profile != null &&
          profile.hasModel &&
          profile.apiKey.trim().isNotEmpty) {
        await widget.client.configure(profile);
      } else {
        await widget.client.configureForManagement();
      }
    } catch (error) {
      try {
        await widget.client.configureForManagement();
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Agent manager failed to start: $error')),
        );
        return;
      }
    } finally {
      if (mounted) setState(() => _isPreparing = false);
    }
    await _reloadAgents();
    if (mounted) unawaited(_installPendingProviderAgent());
  }

  Future<void> _createAgent() async {
    final strings = AppStrings.of(context);
    final name = _nameController.text.trim();
    if (name.isEmpty || _isSaving) return;
    setState(() => _isSaving = true);
    try {
      final agent = await widget.client.createAgent(
        name: name,
        systemPrompt: _promptController.text,
        modelProfileId: _selectedModelProfileId,
      );
      _nameController.clear();
      _promptController.clear();
      setState(() => _selectedModelProfileId = null);
      await _reloadAgents();
      if (mounted) Navigator.of(context).pop(agent.id);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.sdkError(error.toString()))),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _editAgent(DemoAgent agent) async {
    if (agent.isDefault) return;
    final updated = await Navigator.of(context).push<DemoAgent>(
      MaterialPageRoute(
        builder: (context) => _AgentEditPage(
          client: widget.client,
          agent: agent,
          profiles: widget.profiles,
        ),
      ),
    );
    if (updated == null) return;
    await _reloadAgents();
    if (mounted) Navigator.of(context).pop(updated.id);
  }

  Future<void> _deleteAgent(DemoAgent agent) async {
    final strings = AppStrings.of(context);
    if (agent.isDefault) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.defaultAgentProtected)));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.deleteAgentConfirmationTitle),
        content: Text(strings.deleteAgentConfirmationMessage(agent.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.deleteAgent),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.client.deleteAgent(agent.id);
    await _reloadAgents();
  }

  Future<void> _installProviderAgent() async {
    if (_isInstallingProvider) return;
    setState(() => _isInstallingProvider = true);
    try {
      final pendingAgent = await widget.client.installPendingAgentProvider();
      if (pendingAgent != null) {
        await _reloadAgents();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Installed ${pendingAgent.name}')),
        );
        Navigator.of(context).pop(pendingAgent.id);
        return;
      }
      final providers = await widget.client.discoverAgentProviders();
      if (!mounted) return;
      if (providers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No Provider Agent app found. On iOS, open the provider app and tap Add to Agent Host.',
            ),
          ),
        );
        return;
      }
      final provider = providers.length == 1
          ? providers.single
          : await _selectProvider(providers);
      if (provider == null) return;
      final agent = await widget.client.installAgentProvider(provider);
      await _reloadAgents();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Installed ${agent.name}')));
      Navigator.of(context).pop(agent.id);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Provider install failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _isInstallingProvider = false);
    }
  }

  Future<void> _installPendingProviderAgent() async {
    if (_isInstallingProvider) return;
    setState(() => _isInstallingProvider = true);
    try {
      final agent = await widget.client.installPendingAgentProvider();
      if (agent == null) return;
      await _reloadAgents();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Installed ${agent.name}')));
      Navigator.of(context).pop(agent.id);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Provider install failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _isInstallingProvider = false);
    }
  }

  Future<sdk.AgentProviderDescriptor?> _selectProvider(
    List<sdk.AgentProviderDescriptor> providers,
  ) {
    return showDialog<sdk.AgentProviderDescriptor>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Install Provider Agent'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final provider in providers)
                ListTile(
                  leading: const Icon(Icons.sensors_rounded),
                  title: Text(
                    provider.label.trim().isEmpty
                        ? provider.packageName
                        : provider.label,
                  ),
                  subtitle: Text(provider.packageName),
                  onTap: () => Navigator.of(context).pop(provider),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(strings.manageAgents)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            strings.newAgent,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('agent_name_field'),
            controller: _nameController,
            decoration: InputDecoration(
              labelText: strings.agentNameLabel,
              hintText: strings.agentNameHint,
              border: const OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('agent_prompt_field'),
            controller: _promptController,
            minLines: 3,
            maxLines: 6,
            decoration: InputDecoration(
              labelText: strings.agentPromptLabel,
              hintText: strings.agentPromptHint,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const Key('agent_model_profile_field'),
            initialValue: _selectedModelProfileId ?? '',
            decoration: InputDecoration(
              labelText: strings.agentModelLabel,
              border: const OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem(
                value: '',
                child: Text(strings.agentModelInheritDefault),
              ),
              for (final profile in widget.profiles)
                DropdownMenuItem(
                  value: profile.id,
                  child: Text(profile.displayName),
                ),
            ],
            onChanged: (value) {
              setState(() {
                _selectedModelProfileId = value == null || value.isEmpty
                    ? null
                    : value;
              });
            },
          ),
          const SizedBox(height: 12),
          if (_isPreparing) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const Key('install_provider_agent_button'),
                  onPressed: _isInstallingProvider
                      ? null
                      : _installProviderAgent,
                  icon: const Icon(Icons.sensors_rounded),
                  label: Text(
                    _isInstallingProvider
                        ? 'Installing...'
                        : 'Install Provider Agent',
                  ),
                ),
                FilledButton.icon(
                  key: const Key('create_agent_button'),
                  onPressed: _isSaving ? null : _createAgent,
                  icon: const Icon(Icons.add_rounded),
                  label: Text(strings.createAgent),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          for (final agent in _agents)
            ListTile(
              leading: Icon(agent.icon),
              title: Text(agent.name),
              subtitle: Text(_agentSubtitle(strings, agent, widget.profiles)),
              selected: agent.id == widget.activeAgentId,
              onTap: () => Navigator.of(context).pop(agent.id),
              trailing: agent.isDefault
                  ? null
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          key: Key('edit_agent_${agent.id}'),
                          tooltip: strings.editAgent,
                          onPressed: () => _editAgent(agent),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          key: Key('delete_agent_${agent.id}'),
                          tooltip: strings.deleteAgent,
                          onPressed: () => _deleteAgent(agent),
                          icon: const Icon(Icons.delete_outline_rounded),
                        ),
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}

String _agentSubtitle(
  AppStrings strings,
  DemoAgent agent,
  List<LlmModelProfile> profiles,
) {
  if (agent.inheritsModel) return strings.agentModelInheritDefault;
  for (final profile in profiles) {
    if (profile.id == agent.modelProfileId) {
      return '${profile.displayName} · ${agent.id}';
    }
  }
  return '${strings.agentModelMissing(agent.modelProfileId!)} · ${agent.id}';
}

class _AgentEditPage extends StatefulWidget {
  const _AgentEditPage({
    required this.client,
    required this.agent,
    required this.profiles,
  });

  final NapaxiChatClient client;
  final DemoAgent agent;
  final List<LlmModelProfile> profiles;

  @override
  State<_AgentEditPage> createState() => _AgentEditPageState();
}

class _AgentEditPageState extends State<_AgentEditPage> {
  late final TextEditingController _nameController;
  late final TextEditingController _promptController;
  late String _selectedModelProfileId = widget.agent.modelProfileId ?? '';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.agent.name);
    _promptController = TextEditingController(text: widget.agent.systemPrompt);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final updated = await widget.client.updateAgent(
        agentId: widget.agent.id,
        name: _nameController.text,
        systemPrompt: _promptController.text,
        modelProfileId: _selectedModelProfileId.isEmpty
            ? null
            : _selectedModelProfileId,
      );
      if (mounted) Navigator.of(context).pop(updated);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.of(context).sdkError(error.toString())),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(strings.editAgent)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            key: const Key('edit_agent_name_field'),
            controller: _nameController,
            decoration: InputDecoration(
              labelText: strings.agentNameLabel,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('edit_agent_prompt_field'),
            controller: _promptController,
            minLines: 3,
            maxLines: 6,
            decoration: InputDecoration(
              labelText: strings.agentPromptLabel,
              hintText: strings.agentPromptHint,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const Key('edit_agent_model_profile_field'),
            initialValue: _selectedModelProfileId,
            decoration: InputDecoration(
              labelText: strings.agentModelLabel,
              border: const OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem(
                value: '',
                child: Text(strings.agentModelInheritDefault),
              ),
              for (final profile in widget.profiles)
                DropdownMenuItem(
                  value: profile.id,
                  child: Text(profile.displayName),
                ),
            ],
            onChanged: (value) {
              setState(() => _selectedModelProfileId = value ?? '');
            },
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: const Key('update_agent_button'),
              onPressed: _isSaving ? null : _save,
              icon: const Icon(Icons.check_rounded),
              label: Text(strings.updateAgent),
            ),
          ),
        ],
      ),
    );
  }
}
