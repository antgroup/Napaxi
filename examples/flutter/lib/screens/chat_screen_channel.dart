part of '../main.dart';

mixin _ChatScreenChannelMixin on State<ChatScreen> {
  Future<NapaxiChatClient> _getChatClient();
  void _appendSlashCommandResult(String command, String content);
  String _compactMiddle(String value);
  String get _activeAgentId;

  Future<void> _handleChannelSlashCommand(
    String commandText,
    String args,
  ) async {
    final parts = args
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    final parsed = _parseChannelCommand(parts);
    final channelName = parsed.channelName;
    final action = parsed.action;

    try {
      switch (action) {
        case 'help':
          _appendSlashCommandResult(commandText, _channelHelpMessage());
          return;
        case 'setup':
          await _showChannelSetupDialog(commandText, channelName);
          return;
        case 'connect':
          final client = await _getChatClient();
          _appendSlashCommandResult(
            commandText,
            _channelStatusMessage(await client.connectChannel(channelName)),
          );
          return;
        case 'status':
          final client = await _getChatClient();
          _appendSlashCommandResult(
            commandText,
            _channelStatusMessage(await client.channelStatus(channelName)),
          );
          return;
        case 'clear':
          final client = await _getChatClient();
          await client.clearChannelCredentials(channelName);
          _appendSlashCommandResult(
            commandText,
            'Channel `${_normalizeChannelLabel(channelName)}` credentials cleared.',
          );
          return;
        case 'say':
          await _submitHeadsetTranscript(commandText, parts, parsed);
          return;
        case 'ptt':
          await _captureHeadsetTranscriptCommand(commandText, parsed);
          return;
        default:
          _appendSlashCommandResult(
            commandText,
            '未知 channel 子命令 `$action`。\n\n${_channelHelpMessage()}',
          );
      }
    } catch (error) {
      _appendSlashCommandResult(commandText, 'Channel command failed: $error');
    }
  }

  _ParsedChannelCommand _parseChannelCommand(List<String> parts) {
    if (parts.isEmpty) {
      return const _ParsedChannelCommand(
        channelName: sdk.QqBotChannelProvider.channelName,
        action: 'help',
      );
    }
    const actions = {
      'help',
      'setup',
      'connect',
      'status',
      'clear',
      'say',
      'ptt',
    };
    final first = parts.first.toLowerCase();
    if (actions.contains(first)) {
      return _ParsedChannelCommand(
        channelName: parts.length >= 2
            ? parts[1]
            : sdk.QqBotChannelProvider.channelName,
        action: first,
      );
    }
    return _ParsedChannelCommand(
      channelName: first,
      action: parts.length >= 2 ? parts[1].toLowerCase() : 'status',
    );
  }

  Future<void> _showChannelSetupDialog(
    String commandText,
    String channelName,
  ) async {
    final normalized = _normalizeChannelLabel(channelName);
    if (normalized == sdk.BluetoothHeadsetChannelProvider.channelName) {
      final client = await _getChatClient();
      final existing = await client.loadChannelCredentials(normalized);
      final agents = await client.listAgents();
      if (!mounted) return;
      final existingHeadset = existing == null
          ? null
          : DemoBluetoothHeadsetChannelCredentials.fromChannelCredentials(
              existing,
            );
      final credentials = await _showHeadsetChannelSetupSheet(
        context,
        existing: existingHeadset,
        agents: agents,
      );
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;

      if (credentials == null) {
        _appendSlashCommandResult(commandText, '已取消 channel setup。');
        return;
      }
      await client.saveChannelCredentials(credentials);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final status = await client.connectChannel(normalized);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      _appendSlashCommandResult(
        commandText,
        [
          'Channel `${sdk.BluetoothHeadsetChannelProvider.channelName}` credentials saved.',
          '',
          _channelStatusMessage(status),
        ].join('\n'),
      );
      return;
    }
    if (normalized != sdk.QqBotChannelProvider.channelName) {
      _appendSlashCommandResult(commandText, '暂不支持 channel `$channelName`。');
      return;
    }
    final client = await _getChatClient();
    final existing = await client.loadChannelCredentials(normalized);
    final agents = await client.listAgents();
    if (!mounted) return;
    final existingQq = existing == null
        ? null
        : DemoQqChannelCredentials.fromChannelCredentials(existing);
    final credentials = await _showQqChannelSetupSheet(
      context,
      existing: existingQq,
      agents: agents,
    );
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    if (credentials == null) {
      _appendSlashCommandResult(commandText, '已取消 channel setup。');
      return;
    }
    await client.saveChannelCredentials(credentials);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final status = await client.connectChannel(normalized);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    _appendSlashCommandResult(
      commandText,
      [
        'Channel `${sdk.QqBotChannelProvider.channelName}` credentials saved.',
        '',
        _channelStatusMessage(status),
      ].join('\n'),
    );
  }

  String _channelHelpMessage() {
    return [
      'Channel commands',
      '',
      '`/channel qqbot setup` 保存 QQBot AppID/AppSecret，并选择接收消息的 Agent。',
      '`/channel qqbot connect` 重新连接 QQBot Gateway。',
      '`/channel qqbot status` 查看 provider 状态。',
      '`/channel qqbot clear` 清除凭据并断开。',
      '',
      '`/channel headset setup` 配置蓝牙设备语音 channel。',
      '`/channel headset ptt` 使用蓝牙设备语音输入并触发 agent 回复。',
      '`/channel headset status` 查看蓝牙设备 channel 状态。',
      '`/channel headset clear` 清除蓝牙设备 channel 配置。',
      '',
      '后续新增微信、飞书或其他外设 provider 时，仍使用 `/channel <provider> <action>`。',
    ].join('\n');
  }

  String _channelStatusMessage(DemoChannelStatus status) {
    final manifest = status.manifest;
    final registered = status.channels.any(
      (channel) => channel.name == manifest.channelName,
    );
    return [
      'Channel status',
      '',
      '- Provider: `${manifest.providerId}`',
      '- Channel: `${manifest.channelName}`',
      '- Account: `${manifest.accountId}`',
      '- Agent: `${manifest.config['agent_id'] ?? sdk.NapaxiEngine.defaultAgentId}`',
      '- Configured: ${status.configured ? 'yes' : 'no'}',
      '- Connected: ${status.connected ? 'yes' : 'no'}',
      '- Registered in core: ${registered ? 'yes' : 'no'}',
      '- Transport: `${status.mode.isEmpty ? manifest.transport : status.mode}`',
      if (manifest.config.containsKey('sandbox'))
        '- Environment: ${manifest.config['sandbox'] == true ? 'sandbox' : 'production'}',
      if (status.deviceId != null) '- Device: `${status.deviceId}`',
      if (status.deviceName != null) '- Device name: `${status.deviceName}`',
      if (status.listening) '- Listening: yes',
      if (status.lastTranscript != null)
        '- Last transcript: ${status.lastTranscript}',
      if (status.lastSpokenText != null)
        '- Last spoken: ${status.lastSpokenText}',
      if (status.gatewayPhase != null)
        '- Gateway phase: `${status.gatewayPhase}`',
      if (status.credentialFingerprint != null)
        '- Credential: `${status.credentialFingerprint}`',
      '- Inbound accepted: ${status.inboundCount}',
      '- Outbound delivered: ${status.deliveredCount}',
      if (status.gatewayUrl != null)
        '- Gateway: `${_compactMiddle(status.gatewayUrl!)}`',
      if (status.gatewayShardCount != null)
        '- Gateway shards: ${status.gatewayShardCount}',
      if (status.gatewaySessionRemaining != null ||
          status.gatewaySessionMaxConcurrency != null)
        '- Gateway session limit: remaining=${status.gatewaySessionRemaining ?? 'unknown'}, max_concurrency=${status.gatewaySessionMaxConcurrency ?? 'unknown'}',
      if (status.sessionId != null)
        '- Session: `${_compactMiddle(status.sessionId!)}`',
      if (status.lastOpcode != null) '- Last op: ${status.lastOpcode}',
      if (status.lastEventType != null)
        '- Last event: `${status.lastEventType}`',
      if (status.heartbeatAckCount > 0)
        '- Heartbeat ACKs: ${status.heartbeatAckCount}',
      if (status.gatewayCloseCode != null || status.gatewayCloseReason != null)
        '- Gateway close: code=${status.gatewayCloseCode ?? 'unknown'}, reason=${status.gatewayCloseReason ?? 'none'}',
      if (status.bridgePhase != null) '- Bridge phase: `${status.bridgePhase}`',
      '- Bridge processed: ${status.bridgeProcessedCount}',
      '- Bridge replies: ${status.bridgeReplyCount}',
      if (status.bridgeLastError != null)
        '- Bridge error: ${status.bridgeLastError}',
      if (status.lastError != null) '- Last error: ${status.lastError}',
    ].join('\n');
  }

  String _normalizeChannelLabel(String channelName) {
    final normalized = channelName.trim().toLowerCase();
    if (normalized == 'qq') return sdk.QqBotChannelProvider.channelName;
    if (normalized == 'headset' ||
        normalized == 'bluetooth' ||
        normalized == 'bluetooth_headset' ||
        normalized == 'bt_headset') {
      return sdk.BluetoothHeadsetChannelProvider.channelName;
    }
    return normalized.isEmpty
        ? sdk.QqBotChannelProvider.channelName
        : normalized;
  }

  Future<void> _submitHeadsetTranscript(
    String commandText,
    List<String> parts,
    _ParsedChannelCommand parsed,
  ) async {
    final normalized = _normalizeChannelLabel(parsed.channelName);
    if (normalized != sdk.BluetoothHeadsetChannelProvider.channelName) {
      _appendSlashCommandResult(commandText, '`say` 目前只支持蓝牙设备音频 channel。');
      return;
    }
    final transcript = _channelCommandTail(parts, parsed).trim();
    if (transcript.isEmpty) {
      _appendSlashCommandResult(commandText, '请提供要提交的转写文本。');
      return;
    }
    final client = await _getChatClient();
    final result = await client.submitHeadsetTranscript(text: transcript);
    _appendSlashCommandResult(
      commandText,
      [
        result.accepted
            ? 'Bluetooth device transcript accepted.'
            : 'Bluetooth device transcript rejected.',
        if (result.inboundId != null) '- Inbound: `${result.inboundId}`',
        if (result.error != null) '- Error: ${result.error}',
        '',
        _channelStatusMessage(result.status),
      ].join('\n'),
    );
  }

  Future<void> _captureHeadsetTranscriptCommand(
    String commandText,
    _ParsedChannelCommand parsed,
  ) async {
    final normalized = _normalizeChannelLabel(parsed.channelName);
    if (normalized != sdk.BluetoothHeadsetChannelProvider.channelName) {
      _appendSlashCommandResult(commandText, '`ptt` 目前只支持蓝牙设备音频 channel。');
      return;
    }
    final client = await _getChatClient();
    final result = await client.captureHeadsetTranscript(
      agentId: _activeAgentId,
    );
    _appendSlashCommandResult(
      commandText,
      [
        result.accepted
            ? 'Bluetooth device voice input accepted.'
            : 'Bluetooth device voice input failed.',
        if (result.transcript?.trim().isNotEmpty == true)
          '- Transcript: ${result.transcript}',
        if (result.inboundId != null) '- Inbound: `${result.inboundId}`',
        if (result.error != null) '- Error: ${result.error}',
        '',
        _channelStatusMessage(result.status),
      ].join('\n'),
    );
  }

  String _channelCommandTail(List<String> parts, _ParsedChannelCommand parsed) {
    if (parts.isEmpty) return '';
    final first = parts.first.toLowerCase();
    if (first == parsed.action) {
      return parts.skip(2).join(' ');
    }
    return parts.skip(2).join(' ');
  }
}

class _ParsedChannelCommand {
  final String channelName;
  final String action;

  const _ParsedChannelCommand({
    required this.channelName,
    required this.action,
  });
}

Future<DemoChannelCredentials?> _showQqChannelSetupSheet(
  BuildContext context, {
  required DemoQqChannelCredentials? existing,
  required List<DemoAgent> agents,
}) {
  return showModalBottomSheet<DemoChannelCredentials>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) =>
        _QqChannelSetupDialog(existing: existing, agents: agents),
  );
}

Future<DemoChannelCredentials?> _showHeadsetChannelSetupSheet(
  BuildContext context, {
  required DemoBluetoothHeadsetChannelCredentials? existing,
  required List<DemoAgent> agents,
}) {
  return showModalBottomSheet<DemoChannelCredentials>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) =>
        _HeadsetChannelSetupDialog(existing: existing, agents: agents),
  );
}

class _ChannelSetupSheetFrame extends StatelessWidget {
  const _ChannelSetupSheetFrame({
    required this.title,
    required this.child,
    this.actions = const [],
  });

  final String title;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final height = MediaQuery.sizeOf(context).height;
    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(bottom: viewInsets.bottom),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Material(
              color: _configSurface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(18),
              ),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: height * 0.88),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: _configBorder,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _configTextPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: _channelText(
                              context,
                              zh: '关闭',
                              en: 'Close',
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          20,
                          4,
                          20,
                          actions.isEmpty ? 24 : 12,
                        ),
                        child: child,
                      ),
                    ),
                    if (actions.isNotEmpty) ...[
                      Container(height: 1, color: _configBorderFaint),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                        child: Row(
                          children: [
                            for (final action in actions) ...[
                              Expanded(child: action),
                              if (action != actions.last)
                                const SizedBox(width: 12),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QqChannelSetupDialog extends StatefulWidget {
  const _QqChannelSetupDialog({required this.agents, this.existing});

  final List<DemoAgent> agents;
  final DemoQqChannelCredentials? existing;

  @override
  State<_QqChannelSetupDialog> createState() => _QqChannelSetupDialogState();
}

class _QqChannelSetupDialogState extends State<_QqChannelSetupDialog> {
  late final TextEditingController _appIdController;
  late final TextEditingController _appSecretController;
  late String _agentId;
  late bool _sandbox;
  late bool _advancedExpanded;
  bool _appSecretVisible = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _appIdController = TextEditingController(text: existing?.appId ?? '');
    _appSecretController = TextEditingController();
    _agentId = _channelInitialAgentId(existing?.agentId, widget.agents);
    _sandbox = existing?.sandbox ?? false;
    _advancedExpanded = _sandbox;
  }

  @override
  void dispose() {
    _appIdController.dispose();
    _appSecretController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    return _ChannelSetupSheetFrame(
      title: 'QQ Channel',
      actions: [
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: _configTextSecondary,
            side: const BorderSide(color: _configBorderFaint),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_channelText(context, zh: '取消', en: 'Cancel')),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: _configTextPrimary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: _save,
          child: Text(_channelText(context, zh: '保存并连接', en: 'Save')),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _appIdController,
            decoration: _configInputDecoration(labelText: 'AppID'),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('qqbot_app_secret_field'),
            controller: _appSecretController,
            decoration: _configInputDecoration(
              labelText: 'AppSecret',
              helperText: existing?.appSecret.isNotEmpty == true
                  ? _channelText(
                      context,
                      zh: '留空沿用已保存密钥',
                      en: 'Leave empty to keep the saved secret',
                    )
                  : null,
              suffixIcon: SizedBox(
                width: 96,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      key: const Key('qqbot_app_secret_paste_button'),
                      tooltip: _channelText(
                        context,
                        zh: '粘贴 AppSecret',
                        en: 'Paste AppSecret',
                      ),
                      icon: const Icon(Icons.content_paste_rounded),
                      onPressed: _pasteAppSecret,
                    ),
                    IconButton(
                      key: const Key('qqbot_app_secret_visibility_button'),
                      tooltip: _appSecretVisible
                          ? _channelText(
                              context,
                              zh: '隐藏 AppSecret',
                              en: 'Hide AppSecret',
                            )
                          : _channelText(
                              context,
                              zh: '显示 AppSecret',
                              en: 'Show AppSecret',
                            ),
                      icon: Icon(
                        _appSecretVisible
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                      ),
                      onPressed: () {
                        setState(() {
                          _appSecretVisible = !_appSecretVisible;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            autocorrect: false,
            enableSuggestions: false,
            enableInteractiveSelection: true,
            keyboardType: TextInputType.visiblePassword,
            obscureText: !_appSecretVisible,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          _ChannelAgentPicker(
            key: const Key('qqbot_agent_picker'),
            agents: widget.agents,
            value: _agentId,
            onChanged: (value) => setState(() => _agentId = value),
          ),
          const SizedBox(height: 12),
          _ChannelAdvancedTile(
            initiallyExpanded: _advancedExpanded,
            onExpansionChanged: (value) => _advancedExpanded = value,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: _configTextPrimary,
                title: Text(
                  _channelText(context, zh: '使用 QQ 沙箱环境', en: 'Use QQ sandbox'),
                ),
                subtitle: Text(
                  _channelText(
                    context,
                    zh: '仅调试官方沙箱应用时开启；日常接入自己的 QQ Bot 保持关闭。',
                    en: 'Only enable this for official sandbox apps. Keep it off for normal QQ Bot use.',
                  ),
                ),
                value: _sandbox,
                onChanged: (value) {
                  setState(() {
                    _sandbox = value;
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pasteAppSecret() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _channelText(
              context,
              zh: '剪贴板里没有可粘贴的文本。',
              en: 'Clipboard does not contain text.',
            ),
          ),
        ),
      );
      return;
    }
    _appSecretController
      ..text = text
      ..selection = TextSelection.collapsed(offset: text.length);
  }

  void _save() {
    final existing = widget.existing;
    final appSecret = _appSecretController.text.trim().isEmpty
        ? existing?.appSecret ?? ''
        : _appSecretController.text.trim();
    Navigator.of(context).pop(
      DemoQqChannelCredentials(
        appId: _appIdController.text.trim(),
        appSecret: appSecret,
        sandbox: _sandbox,
        intents: existing?.intents ?? DemoQqChannelCredentials.defaultIntents,
        agentId: _agentId,
        sessionAccountId: existing?.sessionAccountId ?? '',
      ).toChannelCredentials(),
    );
  }
}

class _HeadsetChannelSetupDialog extends StatefulWidget {
  const _HeadsetChannelSetupDialog({required this.agents, this.existing});

  final List<DemoAgent> agents;
  final DemoBluetoothHeadsetChannelCredentials? existing;

  @override
  State<_HeadsetChannelSetupDialog> createState() =>
      _HeadsetChannelSetupDialogState();
}

class _HeadsetChannelSetupDialogState
    extends State<_HeadsetChannelSetupDialog> {
  late final TextEditingController _deviceIdController;
  late final TextEditingController _deviceNameController;
  late Future<sdk.BluetoothHeadsetDeviceDiscoveryResult> _devicesFuture;
  late String _agentId;
  late bool _ttsEnabled;
  bool _manualExpanded = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _deviceIdController = TextEditingController(
      text:
          existing?.deviceId ??
          sdk.BluetoothHeadsetChannelCredentials.defaultDeviceId,
    );
    _deviceNameController = TextEditingController(
      text:
          existing?.deviceName ??
          sdk.BluetoothHeadsetChannelCredentials.defaultDeviceName,
    );
    _agentId = _channelInitialAgentId(existing?.agentId, widget.agents);
    _ttsEnabled = existing?.ttsEnabled ?? true;
    _manualExpanded = existing != null;
    _devicesFuture = _loadDevices();
  }

  @override
  void dispose() {
    _deviceIdController.dispose();
    _deviceNameController.dispose();
    super.dispose();
  }

  Future<sdk.BluetoothHeadsetDeviceDiscoveryResult> _loadDevices() {
    return sdk.BluetoothHeadsetDeviceDiscovery().listAudioDevices();
  }

  @override
  Widget build(BuildContext context) {
    return _ChannelSetupSheetFrame(
      title: _channelText(
        context,
        zh: '蓝牙设备 Channel',
        en: 'Bluetooth Device Channel',
      ),
      actions: [
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: _configTextSecondary,
            side: const BorderSide(color: _configBorderFaint),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_channelText(context, zh: '取消', en: 'Cancel')),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: _configTextPrimary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: _save,
          child: Text(_channelText(context, zh: '保存并连接', en: 'Save')),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildDevicePicker(context),
          const SizedBox(height: 12),
          _ChannelAgentPicker(
            key: const Key('headset_agent_picker'),
            agents: widget.agents,
            value: _agentId,
            onChanged: (value) => setState(() => _agentId = value),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            key: const Key('headset_tts_enabled_switch'),
            contentPadding: EdgeInsets.zero,
            activeThumbColor: _configTextPrimary,
            title: Text(
              _channelText(context, zh: '语音播报回复', en: 'Speak replies'),
            ),
            subtitle: Text(
              _channelText(
                context,
                zh: '开启后，Agent 回复会交给蓝牙音频设备播报。',
                en: 'When enabled, agent replies are handed to the Bluetooth audio device for speech.',
              ),
            ),
            value: _ttsEnabled,
            onChanged: (value) {
              setState(() {
                _ttsEnabled = value;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDevicePicker(BuildContext context) {
    return FutureBuilder<sdk.BluetoothHeadsetDeviceDiscoveryResult>(
      future: _devicesFuture,
      builder: (context, snapshot) {
        final result = snapshot.data;
        final loading = snapshot.connectionState != ConnectionState.done;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _channelText(
                      context,
                      zh: '选择蓝牙音频设备',
                      en: 'Bluetooth Audio Devices',
                    ),
                    style: const TextStyle(
                      color: _configTextPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: loading
                      ? null
                      : () {
                          setState(() {
                            _devicesFuture = _loadDevices();
                          });
                        },
                  icon: const Icon(Icons.refresh_rounded, size: 17),
                  label: Text(_channelText(context, zh: '查找', en: 'Find')),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (loading)
              const LinearProgressIndicator(minHeight: 2)
            else if (result == null)
              _ChannelSetupHint(
                text: _channelText(
                  context,
                  zh: '暂时无法读取蓝牙设备。',
                  en: 'Unable to read Bluetooth devices.',
                ),
              )
            else if (!result.supported)
              _ChannelSetupHint(
                text: result.error?.trim().isNotEmpty == true
                    ? result.error!.trim()
                    : _channelText(
                        context,
                        zh: '当前平台不支持蓝牙设备选择。',
                        en: 'Bluetooth device picking is not available on this platform.',
                      ),
              )
            else if (!result.permissionGranted)
              _ChannelSetupHint(
                text: _channelText(
                  context,
                  zh: '没有蓝牙权限。请在系统设置里允许蓝牙/附近设备权限后再查找。',
                  en: 'Bluetooth permission is not granted. Enable Bluetooth/Nearby Devices permission in system settings, then try again.',
                ),
              )
            else if (result.devices.isEmpty)
              _ChannelSetupHint(
                text: result.otherDevices.isNotEmpty
                    ? _channelText(
                        context,
                        zh: '找到了蓝牙设备，但没有适合当前音频 Channel 的设备。手机、车机或未知设备不会默认作为耳机接入。',
                        en: 'Bluetooth devices were found, but none are suitable for this audio channel. Phones, car kits, and unknown devices are not attached as headsets by default.',
                      )
                    : _channelText(
                        context,
                        zh: '没有找到已配对的蓝牙音频设备。先在系统蓝牙里连接设备，或展开手动填写。',
                        en: 'No paired Bluetooth audio device found. Pair or connect the device in system Bluetooth settings, or enter it manually.',
                      ),
              )
            else
              for (final device in result.devices) ...[
                _HeadsetDeviceOption(
                  device: device,
                  selected: _deviceIdController.text.trim() == device.id,
                  onTap: () => _selectDevice(device),
                ),
                const SizedBox(height: 8),
              ],
            if (!loading &&
                result != null &&
                result.permissionGranted &&
                result.otherDevices.isNotEmpty) ...[
              const SizedBox(height: 2),
              _BluetoothOtherDevicesTile(devices: result.otherDevices),
            ],
            const SizedBox(height: 10),
            _ChannelAdvancedTile(
              title: _channelText(
                context,
                zh: '手动填写音频设备',
                en: 'Manual Audio Device',
              ),
              initiallyExpanded: _manualExpanded,
              onExpansionChanged: (value) => _manualExpanded = value,
              children: [
                TextField(
                  key: const Key('headset_device_id_field'),
                  controller: _deviceIdController,
                  decoration: _configInputDecoration(
                    labelText: _channelText(
                      context,
                      zh: '设备 ID',
                      en: 'Device ID',
                    ),
                    helperText: _channelText(
                      context,
                      zh: '用于生成稳定会话；优先选择系统识别出的蓝牙音频设备。',
                      en: 'Used for stable sessions. Prefer a Bluetooth audio device from the list.',
                    ),
                  ),
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('headset_device_name_field'),
                  controller: _deviceNameController,
                  decoration: _configInputDecoration(
                    labelText: _channelText(
                      context,
                      zh: '设备名称',
                      en: 'Device Name',
                    ),
                  ),
                  textInputAction: TextInputAction.next,
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  void _selectDevice(sdk.BluetoothHeadsetDeviceInfo device) {
    setState(() {
      _deviceIdController.text = device.id;
      _deviceNameController.text = device.name;
      _manualExpanded = false;
    });
  }

  void _save() {
    final existing = widget.existing;
    final deviceId = _deviceIdController.text.trim().isEmpty
        ? sdk.BluetoothHeadsetChannelCredentials.defaultDeviceId
        : _deviceIdController.text.trim();
    Navigator.of(context).pop(
      DemoBluetoothHeadsetChannelCredentials(
        deviceId: deviceId,
        deviceName: _deviceNameController.text.trim().isEmpty
            ? sdk.BluetoothHeadsetChannelCredentials.defaultDeviceName
            : _deviceNameController.text.trim(),
        accountId: existing?.accountId.trim().isNotEmpty == true
            ? existing!.accountId.trim()
            : deviceId,
        agentId: _agentId,
        ttsEnabled: _ttsEnabled,
        sessionAccountId: existing?.sessionAccountId ?? '',
      ).toChannelCredentials(),
    );
  }
}

class _ChannelAgentPicker extends StatelessWidget {
  const _ChannelAgentPicker({
    super.key,
    required this.agents,
    required this.value,
    required this.onChanged,
  });

  final List<DemoAgent> agents;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = _channelAgentOptions(agents);
    final selected = options.any((agent) => agent.id == value)
        ? value
        : options.first.id;
    return DropdownButtonFormField<String>(
      initialValue: selected,
      decoration: _configInputDecoration(
        labelText: _channelText(context, zh: '选择 Agent', en: 'Agent'),
        helperText: _channelText(
          context,
          zh: '这个 Channel 收到的消息会交给所选 Agent 处理。',
          en: 'Messages from this channel will be handled by the selected agent.',
        ),
      ),
      items: [
        for (final agent in options)
          DropdownMenuItem<String>(
            value: agent.id,
            child: Text(
              _channelAgentOptionLabel(context, agent),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (value) {
        if (value == null) return;
        onChanged(value);
      },
    );
  }
}

class _HeadsetDeviceOption extends StatelessWidget {
  const _HeadsetDeviceOption({
    required this.device,
    required this.selected,
    required this.onTap,
  });

  final sdk.BluetoothHeadsetDeviceInfo device;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _configSelectedSurface : const Color(0xFFF7F7F7),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? _configTextPrimary : _configTextTertiary,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _configTextPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _bluetoothDeviceSubtitle(context, device),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _configTextSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (device.connected)
                _ChannelMiniPill(
                  text: _channelText(context, zh: '已连接', en: 'Online'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BluetoothOtherDevicesTile extends StatelessWidget {
  const _BluetoothOtherDevicesTile({required this.devices});

  final List<sdk.BluetoothHeadsetDeviceInfo> devices;

  @override
  Widget build(BuildContext context) {
    return _ChannelAdvancedTile(
      title: _channelText(context, zh: '其他蓝牙设备', en: 'Other Bluetooth Devices'),
      children: [
        for (final device in devices) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F7F7),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _configBorderFaint),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _configTextPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _bluetoothDeviceSubtitle(context, device),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _configTextSecondary,
                    fontSize: 12,
                  ),
                ),
                _warning(context, device),
              ].whereType<Widget>().toList(growable: false),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget? _warning(
    BuildContext context,
    sdk.BluetoothHeadsetDeviceInfo device,
  ) {
    final warning = _bluetoothDeviceWarning(context, device);
    if (warning.trim().isEmpty) return null;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        warning,
        style: const TextStyle(
          color: _configTextTertiary,
          fontSize: 11,
          height: 1.3,
        ),
      ),
    );
  }
}

class _ChannelAdvancedTile extends StatelessWidget {
  const _ChannelAdvancedTile({
    required this.children,
    this.title,
    this.initiallyExpanded = false,
    this.onExpansionChanged,
  });

  final String? title;
  final List<Widget> children;
  final bool initiallyExpanded;
  final ValueChanged<bool>? onExpansionChanged;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        initiallyExpanded: initiallyExpanded,
        onExpansionChanged: onExpansionChanged,
        title: Text(
          title ?? _channelText(context, zh: '高级设置', en: 'Advanced'),
          style: const TextStyle(
            color: _configTextPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        children: children,
      ),
    );
  }
}

class _ChannelSetupHint extends StatelessWidget {
  const _ChannelSetupHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _configBorderFaint),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: _configTextSecondary,
          fontSize: 12,
          height: 1.35,
        ),
      ),
    );
  }
}

class _ChannelMiniPill extends StatelessWidget {
  const _ChannelMiniPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF047857),
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

String _bluetoothDeviceSubtitle(
  BuildContext context,
  sdk.BluetoothHeadsetDeviceInfo device,
) {
  final kind = _bluetoothDeviceKindLabel(context, device.deviceKind);
  final profiles = device.profiles
      .map((profile) => _bluetoothProfileLabel(context, profile))
      .where((profile) => profile.trim().isNotEmpty)
      .join(', ');
  final id = device.id.trim();
  if (profiles.isNotEmpty && id.isNotEmpty) return '$kind · $profiles · $id';
  if (profiles.isNotEmpty) return '$kind · $profiles';
  if (id.isNotEmpty) return '$kind · $id';
  return kind;
}

String _bluetoothDeviceWarning(
  BuildContext context,
  sdk.BluetoothHeadsetDeviceInfo device,
) {
  switch (device.deviceKind) {
    case sdk.BluetoothDeviceKind.phone:
      return _channelText(
        context,
        zh: '手机更适合通过 Nearby/A2A 接入，不会默认作为蓝牙音频设备。',
        en: 'Phones should connect through Nearby/A2A and are not attached as Bluetooth audio devices by default.',
      );
    case sdk.BluetoothDeviceKind.carAudio:
      return _channelText(
        context,
        zh: '车机需要独立的车机场景 Channel，不会默认作为耳机接入。',
        en: 'Car audio needs a dedicated car channel and is not attached as a headset by default.',
      );
    case sdk.BluetoothDeviceKind.unknown:
      return _channelText(
        context,
        zh: '类型未知，暂不默认接入音频 Channel。',
        en: 'Device type is unknown, so it is not attached to the audio channel by default.',
      );
  }
  final explicit = device.warning?.trim() ?? '';
  if (explicit.isNotEmpty) {
    return explicit;
  }
  return '';
}

String _bluetoothDeviceKindLabel(BuildContext context, String kind) {
  switch (kind) {
    case sdk.BluetoothDeviceKind.headset:
      return _channelText(context, zh: '耳机', en: 'Headset');
    case sdk.BluetoothDeviceKind.speaker:
      return _channelText(context, zh: '音箱', en: 'Speaker');
    case sdk.BluetoothDeviceKind.carAudio:
      return _channelText(context, zh: '车载音频', en: 'Car Audio');
    case sdk.BluetoothDeviceKind.phone:
      return _channelText(context, zh: '手机', en: 'Phone');
    case sdk.BluetoothDeviceKind.computer:
      return _channelText(context, zh: '电脑', en: 'Computer');
    case sdk.BluetoothDeviceKind.wearable:
      return _channelText(context, zh: '穿戴设备', en: 'Wearable');
    case sdk.BluetoothDeviceKind.sensor:
      return _channelText(context, zh: '传感器', en: 'Sensor');
    case sdk.BluetoothDeviceKind.input:
      return _channelText(context, zh: '控制设备', en: 'Input Device');
  }
  return _channelText(context, zh: '未知设备', en: 'Unknown Device');
}

String _bluetoothProfileLabel(BuildContext context, String profile) {
  switch (profile) {
    case sdk.BluetoothDeviceProfile.a2dp:
      return 'A2DP';
    case sdk.BluetoothDeviceProfile.headset:
      return _channelText(context, zh: '通话音频', en: 'Headset');
    case sdk.BluetoothDeviceProfile.hearingAid:
      return _channelText(context, zh: '助听设备', en: 'Hearing Aid');
    case sdk.BluetoothDeviceProfile.gatt:
      return 'GATT';
    case sdk.BluetoothDeviceProfile.hid:
      return 'HID';
    case sdk.BluetoothDeviceProfile.pan:
      return 'PAN';
  }
  return '';
}

List<DemoAgent> _channelAgentOptions(List<DemoAgent> agents) {
  final options = <DemoAgent>[];
  final seen = <String>{};
  for (final agent in [_defaultDemoAgent, ...agents]) {
    if (agent.id.trim().isEmpty || !seen.add(agent.id)) continue;
    options.add(agent);
  }
  return options.isEmpty ? const [_defaultDemoAgent] : options;
}

String _channelInitialAgentId(String? current, List<DemoAgent> agents) {
  final options = _channelAgentOptions(agents);
  final desired = current?.trim() ?? '';
  if (desired.isNotEmpty && options.any((agent) => agent.id == desired)) {
    return desired;
  }
  return options.any((agent) => agent.id == sdk.NapaxiEngine.defaultAgentId)
      ? sdk.NapaxiEngine.defaultAgentId
      : options.first.id;
}

String _channelAgentOptionLabel(BuildContext context, DemoAgent agent) {
  final label = agent.label(_AppLanguageScope.languageOf(context)).trim();
  return label.isEmpty ? agent.id : label;
}
