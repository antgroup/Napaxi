import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('local A2A stays on the slash-first surface', () {
    // The A2A mixin lives in chat_screen_a2a.dart; the slash registration
    // stays in chat_screen.dart. Read both to cover the full contract.
    final source = [
      File('lib/screens/chat_screen.dart').readAsStringSync(),
      File('lib/screens/chat_screen_a2a.dart').readAsStringSync(),
    ].join('\n');

    expect(source, contains("name: '/a2a'"));
    expect(source, contains("description: '通过斜杠指令发现、配对并协作附近设备。'"));

    final helpStart = source.indexOf('String _slashA2AHelpMessage()');
    expect(helpStart, isNonNegative);
    final helpEnd = source.indexOf('Future<String> _slashA2AStatusMessage');
    expect(helpEnd, greaterThan(helpStart));

    final helpSource = source.substring(helpStart, helpEnd);
    expect(helpSource, contains('`/a2a doctor`'));
    expect(helpSource, contains('`/a2a inbox`'));
    expect(helpSource, contains('`/a2a trace <编号>`'));
    expect(helpSource, contains('`/a2a scan`'));
    expect(helpSource, contains('配对后可以直接在聊天里说'));
    expect(helpSource, contains('一般不需要手动输入任务编号'));
    expect(helpSource, isNot(contains('taskId')));
    expect(helpSource, isNot(contains('sessionId')));
    expect(helpSource, isNot(contains('peerId')));
    expect(helpSource, isNot(contains('endpoint')));
    expect(helpSource, isNot(contains('/a2a panel')));

    expect(
      source,
      isNot(contains("_appendSlashCommandResult(commandText, '已发送。')")),
    );
    expect(source, isNot(contains("_showChatSnackBar('已发送给 ")));
    expect(source, isNot(contains("'我：\\n\\n\$message'")));
    expect(source, contains('local A2A task result not delivered'));
    expect(source, isNot(contains('对方 Agent 回复后会直接显示在聊天里。')));
    expect(source, contains('_a2aTaskIdFromMessage(task)'));
    expect(source, contains('Future<void> _resendA2ASlashTask'));
    expect(source, contains('_a2aOriginalTaskRequestMessage(client, task)'));
    expect(source, contains("task.source != 'local_transport_outbound'"));
    expect(source, contains("purpose: '重发任务'"));
    expect(source, contains('String _a2aSendFailureMessage'));
    expect(source, contains(r'messageId：`${message.messageId}`'));
    expect(source, contains(r'`/a2a trace ${message.sessionId}`'));
    expect(source, contains(r'`/a2a trace $taskId`'));
    expect(source, contains('progressEvidence.deliveryStatus'));
    expect(source, contains('submitLocalA2AChannelTask'));
    expect(source, contains('runLocalA2AChannelTask'));
    expect(source, contains('local_a2a'));
    expect(source, contains('client.listLocalA2ADeliveryRecords'));
    expect(source, contains('client.listLocalA2APeerMessages'));
    expect(source, contains('Future<String> _slashA2ATraceMessage'));
    expect(source, contains('Peer messages'));
    expect(source, contains('Delivery'));
    expect(
      source,
      contains('Future<sdk.A2ATaskRecord?> _a2aTaskRecordByReference'),
    );
    expect(source, contains(r'delivery：`${delivery.status}`'));
    expect(source, contains("kind: 'pairing_request'"));
    expect(source, contains("'endpoint': status.endpoint"));
    expect(source, contains('Future<void> _acceptA2APairingRequest'));
    expect(source, contains('_a2aPeerFromPairingRequest(message)'));
    expect(
      source,
      contains(r'`/a2a pair-accept ${message.fromPeerId} <对方配对密钥>`'),
    );
    expect(source, contains('不会让对端自动信任本机'));
  });

  test('local A2A auto-run displays inbound text before processing', () {
    final source = File('lib/screens/chat_screen_a2a.dart').readAsStringSync();
    final branchStart = source.indexOf('} else if (autoRunCollaboration) {');
    expect(branchStart, isNonNegative);
    final appendIndex = source.indexOf(
      '_appendA2AInboundChatMessage(',
      branchStart,
    );
    final runIndex = source.indexOf(
      '_autoRunA2ACollaborationTask(',
      branchStart,
    );
    expect(appendIndex, isNonNegative);
    expect(runIndex, isNonNegative);
    expect(appendIndex, lessThan(runIndex));
  });

  test('local A2A auto-run shows a transient local thinking bubble', () {
    final source = File('lib/screens/chat_screen_a2a.dart').readAsStringSync();
    final bubbleSource = File(
      'lib/widgets/chat_message.dart',
    ).readAsStringSync();

    final autoRunStart = source.indexOf(
      'Future<void> _autoRunA2ACollaborationTask',
    );
    expect(autoRunStart, isNonNegative);
    final submitIndex = source.indexOf(
      'await client.submitLocalA2AChannelTask',
      autoRunStart,
    );
    final pendingIndex = source.indexOf(
      '_appendA2AConversationPendingReply(',
      autoRunStart,
    );
    final runIndex = source.indexOf(
      'await client.runLocalA2AChannelTask',
      autoRunStart,
    );
    expect(pendingIndex, isNonNegative);
    expect(submitIndex, isNonNegative);
    expect(runIndex, isNonNegative);
    expect(pendingIndex, lessThan(submitIndex));
    expect(submitIndex, lessThan(runIndex));

    expect(source, contains('String _a2aVisibleMessageId'));
    expect(source, contains('String _a2aVisibleLocalReplyMessageId'));
    expect(
      source,
      contains(
        'final stableMessageId = _a2aVisibleLocalReplyMessageId(normalizedTaskId);',
      ),
    );
    expect(source, contains('isStreaming: true'));
    expect(source, contains('role: ChatRole.assistant'));
    expect(source, contains("reasoning: '正在思考回复。\\n'"));
    expect(source, contains("AgentTraceStep(reasoning: '正在思考回复。\\n')"));
    expect(source, contains("messageId: '\$taskId-local-reply'"));
    expect(source, contains('existingMessage.isStreaming'));
    expect(source, contains('existingMessage.copyWith('));
    expect(source, contains('!message.isStreaming'));
    expect(source, contains('message.content.trim().isNotEmpty'));
    expect(
      bubbleSource,
      contains(
        'if (message.content.isEmpty && !hasVisibleAgentTrace && message.isStreaming)',
      ),
    );
    expect(
      bubbleSource,
      contains('if (message.toolCalls.isEmpty) return false;'),
    );
  });

  test('local A2A semantic messages stay in collaboration conversations', () {
    final chatSource = File('lib/screens/chat_screen.dart').readAsStringSync();
    final source = File('lib/screens/chat_screen_a2a.dart').readAsStringSync();
    final demoSource = File(
      'lib/demo_client/napaxi_chat_client.dart',
    ).readAsStringSync();
    final bubbleSource = File(
      'lib/widgets/chat_message.dart',
    ).readAsStringSync();
    final historySource = File(
      'lib/panels/session_history.dart',
    ).readAsStringSync();
    final modelSource = File('lib/models/chat_models.dart').readAsStringSync();

    expect(chatSource, contains('final isLocalA2A = _isLocalA2AChannelName'));
    expect(chatSource, contains('if (isLocalA2A)'));
    expect(chatSource, contains('_handleLocalA2ABridgeEvent(event)'));
    expect(chatSource, contains('_recordLocalA2ABridgeEvidence(event)'));
    expect(chatSource, contains('_persistA2AConversationSessions()'));
    expect(chatSource, contains('_isWeakA2AConversationTitle(currentTitle)'));
    expect(
      chatSource,
      contains('_sanitizeA2AProtocolText(\n      session.displayTitle,'),
    );
    expect(chatSource, contains("_sanitizeA2AProtocolText(title ?? '')"));
    expect(
      historySource,
      contains('_sanitizeA2AProtocolText(message.content)'),
    );
    expect(modelSource, contains('if (!_isA2AToolName(call.name))'));
    expect(
      modelSource,
      contains('final content = _sanitizeA2AProtocolText(item.content)'),
    );
    expect(
      modelSource,
      contains('final reasoning = _sanitizeA2AProtocolText(pendingReasoning)'),
    );
    expect(
      modelSource,
      contains('reasoning: _sanitizeA2AProtocolText(pendingStepReasoning)'),
    );
    expect(
      modelSource,
      contains('reasoning.trim().isEmpty && toolCalls.isEmpty'),
    );
    expect(modelSource, contains('content.trim().isEmpty &&'));
    final localBridgeStart = demoSource.indexOf(
      '_localA2AChannelBridgeSubscription = bridge.events.listen',
    );
    expect(localBridgeStart, isNonNegative);
    final localBridgeEnd = demoSource.indexOf(
      '_localA2AChannelBridge = bridge;',
      localBridgeStart,
    );
    expect(localBridgeEnd, greaterThan(localBridgeStart));
    final localBridgeSource = demoSource.substring(
      localBridgeStart,
      localBridgeEnd,
    );
    expect(
      localBridgeSource,
      isNot(contains('_channelBridgeEvents.add(event);')),
    );
    expect(
      localBridgeSource,
      contains('_channelBridgeEvents.add(provider.withUiContext(event));'),
    );
    expect(
      demoSource,
      contains('sdk.NapaxiChannelAgentBridgeEvent withUiContext'),
    );
    expect(
      demoSource,
      contains("'conversationSessionId': context.visibleConversationSessionId"),
    );
    expect(
      demoSource,
      contains("'localReplyMessageId': context.localReplyMessageId"),
    );
    expect(chatSource, contains('_projectA2AWaitMessagesResult'));
    expect(chatSource, contains('_projectA2ASendMessageResult'));
    expect(chatSource, contains("name == 'a2a_wait_messages'"));
    expect(chatSource, contains("name == 'a2a_send_message'"));
    expect(chatSource, contains('if (targetSessionId == null) continue;'));
    expect(chatSource, isNot(contains('??\n          sessionId')));
    expect(chatSource, contains('createdAtMs.isEmpty'));
    expect(chatSource, contains("'sent-\$createdAtMs'"));
    expect(chatSource, contains('updatedAtMs.isEmpty'));
    expect(chatSource, contains("'observation-\$updatedAtMs'"));
    expect(chatSource, contains('content: sanitizedText'));
    expect(chatSource, contains('final content = sanitizedText;'));
    final projectedLocalStart = chatSource.indexOf(
      "_a2aVisibleMessageId('\$taskId-local-sent')",
    );
    expect(projectedLocalStart, isNonNegative);
    expect(
      chatSource.indexOf('role: ChatRole.user', projectedLocalStart),
      isNonNegative,
    );
    expect(
      chatSource,
      contains('_a2aVisibleConversationSessionIdFromToolResult'),
    );
    expect(chatSource, contains('newSessionTitle'));
    expect(chatSource, contains('_showA2AConversationUpdatedNotice'));
    expect(chatSource, contains('_a2aUnreadConversationSessionIds'));
    expect(chatSource, contains('a2aUnreadSessionIds: Set.unmodifiable'));
    expect(historySource, contains('final Set<String> a2aUnreadSessionIds'));
    expect(historySource, contains('class _A2AUnreadBadge'));
    expect(chatSource, contains('_isHiddenSdkSessionInfo'));
    expect(chatSource, contains('!_isHiddenSdkSessionInfo(info)'));
    expect(chatSource, contains('bool _isUserVisibleChatMessage'));
    expect(chatSource, contains('if (_isUserVisibleChatMessage(message))'));
    expect(chatSource, contains('return _hasVisibleAgentTrace(message);'));

    expect(demoSource, isNot(contains("'parentSession': _currentSession")));
    expect(demoSource, contains('final conversationThreadId'));
    expect(demoSource, contains('threadId: conversationThreadId.isEmpty'));
    expect(demoSource, contains("'a2a_conversation_id': conversationThreadId"));
    expect(
      demoSource,
      contains('_a2aVisibleConversationSessionIdForCollaboration'),
    );
    expect(source, contains('String _a2aVisibleConversationSessionId'));
    expect(
      source,
      contains('String _a2aVisibleConversationSessionIdForCollaboration'),
    );
    expect(
      source,
      contains('String? _a2aVisibleConversationSessionIdFromToolResult'),
    );
    expect(
      source,
      contains('return _a2aVisibleConversationSessionIdForCollaboration'),
    );
    expect(demoSource, isNot(contains('nearby-agent:\${peer.peerId}:')));
    final toolResultSessionStart = source.indexOf(
      'String? _a2aVisibleConversationSessionIdFromToolResult',
    );
    final toolResultTitleStart = source.indexOf(
      'String _a2aVisibleConversationTitleFromToolResult',
      toolResultSessionStart,
    );
    expect(toolResultSessionStart, isNonNegative);
    expect(toolResultTitleStart, greaterThan(toolResultSessionStart));
    final toolResultSessionSource = source.substring(
      toolResultSessionStart,
      toolResultTitleStart,
    );
    expect(toolResultSessionSource, isNot(contains('peerKey')));
    expect(
      toolResultSessionSource,
      isNot(contains(r'$_a2aConversationSessionPrefix:$peerId:')),
    );
    expect(source, contains('_a2aTaskBelongsToLocalOutbound'));
    expect(source, isNot(contains('return parentSessionId;')));
    expect(source, isNot(contains('_a2aParentSessionId')));
    expect(source, contains('_a2aConversationSessionPrefix'));
    expect(source, contains("message.kind == 'task_result'"));
    expect(source, contains("'task_progress' => ''"));
    expect(source, isNot(contains("'task_progress' => '\$label")));
    expect(source, contains('isTaskUpdate && !isTaskRequest'));
    expect(source, contains('role: role'));
    expect(source, contains("message.kind == 'task_request'"));
    expect(source, contains('? ChatRole.user'));
    expect(source, contains(': ChatRole.assistant'));
    expect(
      source,
      contains("'task_request' when conversation != null => taskTitle"),
    );
    expect(source, contains("'task_result' => text"));
    expect(source, isNot(contains("'\$label：\\n\\n")));
    expect(source, contains('String _a2aVisibleConversationMessageId'));
    expect(source, contains(r"'$taskId-remote-reply'"));
    expect(bubbleSource, contains('bool _isA2AToolCall'));
    expect(bubbleSource, contains('bool _isA2AToolName'));
    expect(bubbleSource, contains('bool _hasVisibleAgentTrace'));
    expect(bubbleSource, contains('message.toolCalls.every(_isA2AToolCall)'));
    expect(chatSource, contains('if (!isA2ATool)'));
    expect(chatSource, contains('if (!_isA2AToolName(name))'));
    final projectedRemoteStart = chatSource.indexOf(
      "_a2aVisibleMessageId('\$taskId-remote-reply')",
    );
    expect(projectedRemoteStart, isNonNegative);
    expect(
      chatSource.indexOf('role: ChatRole.assistant', projectedRemoteStart),
      isNonNegative,
    );
  });

  test('local A2A semantic conversation messages are durable overlays', () {
    final chatSource = File('lib/screens/chat_screen.dart').readAsStringSync();
    final source = File('lib/screens/chat_screen_a2a.dart').readAsStringSync();

    expect(source, contains('_a2aConversationSessionsKey'));
    expect(source, contains('_a2aDeletedConversationSessionsKey'));
    expect(source, contains('Future<void> _persistA2AConversationSessions()'));
    expect(source, contains('Future<void> _restoreA2AConversationSessions()'));
    expect(source, contains('Future<void> _markDeletedA2AConversationSession'));
    expect(
      source,
      contains('Future<void> _forgetDeletedA2AConversationSession'),
    );
    expect(
      source,
      contains(
        'Future<List<ChatSession>> _loadA2AConversationSessionsFromLedger()',
      ),
    );
    expect(source, contains('_mergeA2AConversationOverlayIntoSession'));
    expect(source, contains('bool _isWeakA2AConversationTitle'));
    expect(source, contains('bool _isCanonicalA2AConversationSessionId'));
    expect(source, contains("return tail.isNotEmpty && !tail.contains(':');"));
    expect(
      source,
      contains(
        'List<ChatSession> _dropRecoverableLegacyA2AConversationSessions',
      ),
    );
    expect(source, contains("message.id.startsWith('a2a-')"));
    expect(
      source,
      contains(
        "final content = _sanitizeA2AProtocolText(map['content']?.toString() ?? '');",
      ),
    );
    expect(
      source,
      contains(
        "title: _sanitizeA2AProtocolText(map['title']?.toString() ?? '')",
      ),
    );
    expect(source, contains('String? _a2aConversationSemanticKey'));
    expect(source, contains('seenSemanticKeys'));
    expect(source, contains("task.request.context['conversationTurn']"));
    expect(source, contains("'conversationId'"));
    expect(source, contains("'conversation_id'"));
    expect(source, contains('-local-sent'));
    expect(source, contains('-remote-reply'));
    final ledgerLocalStart = source.indexOf(
      "id: _a2aVisibleMessageId('\${task.taskId}-local-sent')",
    );
    expect(ledgerLocalStart, isNonNegative);
    expect(
      source.indexOf('role: ChatRole.user', ledgerLocalStart),
      isNonNegative,
    );
    expect(source, contains('a2a-ledger-request-'));
    expect(source, contains('-local-reply'));
    final ledgerInboundStart = source.indexOf('a2a-ledger-request-');
    expect(ledgerInboundStart, isNonNegative);
    expect(
      source.indexOf('role: ChatRole.user', ledgerInboundStart),
      isNonNegative,
    );
    final ledgerLocalReplyStart = source.indexOf(
      'id: _a2aVisibleLocalReplyMessageId(task.taskId)',
    );
    expect(ledgerLocalReplyStart, isNonNegative);
    expect(
      source.indexOf('role: ChatRole.assistant', ledgerLocalReplyStart),
      isNonNegative,
    );
    expect(source, contains('bool _a2aTaskHasUserVisibleResult'));
    expect(source, contains('_a2aTaskHasUserVisibleResult(task)'));
    final ledgerRemoteStart = source.indexOf(
      "id: _a2aVisibleMessageId('\${task.taskId}-remote-reply')",
    );
    expect(ledgerRemoteStart, isNonNegative);
    expect(
      source.indexOf('role: ChatRole.assistant', ledgerRemoteStart),
      isNonNegative,
    );
    expect(source, contains("'account_id': _activeAccountId"));
    expect(source, contains("'agent_id': _activeAgentId"));
    expect(chatSource, contains('await _restoreA2AConversationSessions();'));
    expect(
      chatSource,
      contains('_markDeletedA2AConversationSession(sessionId)'),
    );
    expect(
      chatSource,
      contains('final a2aOverlays = await _loadA2AConversationSessions();'),
    );
    expect(
      chatSource,
      contains('unawaited(_persistA2AConversationSessions());'),
    );
  });

  test('local A2A receiver stores its own semantic reply', () {
    final source = File('lib/screens/chat_screen_a2a.dart').readAsStringSync();

    expect(source, isNot(contains("'我：\\n\\n\$summary'")));
    expect(source, contains('content: sanitized'));
    expect(source, contains('client.claimLocalA2AAutoRunTask(taskId)'));
    expect(source, contains('Future<void> _projectClaimedA2AAutoRunTask'));
    expect(source, contains('_projectClaimedA2AAutoRunTask('));
    expect(
      source,
      contains('client.releaseLocalA2AAutoRunTask(taskId, handled: handled)'),
    );
    expect(source, contains('var handled = false;'));
    expect(source, contains('run.summary.trim()'));
    expect(source, contains("messageId: '\$taskId-local-reply'"));
    final localReplyStart = source.indexOf("messageId: '\$taskId-local-reply'");
    expect(localReplyStart, isNonNegative);
    expect(
      source.indexOf('role: ChatRole.assistant', localReplyStart),
      isNonNegative,
    );
    final projectedStart = source.indexOf(
      'Future<void> _projectClaimedA2AAutoRunTask',
    );
    expect(projectedStart, isNonNegative);
    expect(
      source.indexOf('_appendA2AConversationPendingReply(', projectedStart),
      isNonNegative,
    );
    expect(
      source.indexOf('const Duration(minutes: 3)', projectedStart),
      isNonNegative,
    );
    expect(
      source.indexOf('_a2aTaskHasUserVisibleResult(record)', projectedStart),
      isNonNegative,
    );
    expect(
      source.indexOf('_removeA2AConversationPendingReply(', projectedStart),
      isNonNegative,
    );
    expect(
      source.indexOf("messageId: '\$taskId-local-reply'", projectedStart),
      isNonNegative,
    );
    expect(source, contains('void _removeA2AConversationPendingReply'));
    expect(source, isNot(contains('本机 Agent 已生成回复，但暂时没有送达对方。')));
    expect(source, isNot(contains('附近消息已收到，但暂时找不到可回复的连接。')));
  });

  test('local A2A generic peer labels are hidden from user-facing names', () {
    final source = [
      File('lib/screens/chat_screen.dart').readAsStringSync(),
      File('lib/screens/chat_screen_a2a.dart').readAsStringSync(),
      File('lib/demo_client/napaxi_chat_client.dart').readAsStringSync(),
    ].join('\n');

    expect(source, contains('bool _isGenericA2APeerLabel'));
    expect(source, contains('String _channelBridgeVisibleInboundText'));
    expect(
      source,
      isNot(contains("return '\${_localA2AChannelPeerLabel(event)}：")),
    );
    expect(source, contains("normalized.startsWith('napaxi:')"));
    expect(source, contains('_isGenericA2APeerLabel(displayName)'));
    expect(source, contains('_isGenericA2APeerLabel(label)'));
  });

  test('local A2A collaboration store stays mutable for send updates', () {
    final source = File(
      'lib/demo_client/napaxi_chat_client.dart',
    ).readAsStringSync();

    final loadStart = source.indexOf(
      'Future<List<Map<String, dynamic>>> _a2aLoadCollaborations()',
    );
    expect(loadStart, isNonNegative);
    final loadEnd = source.indexOf(
      'Future<Map<String, dynamic>?> _a2aLoadCollaboration',
      loadStart,
    );
    expect(loadEnd, greaterThan(loadStart));

    final loadSource = source.substring(loadStart, loadEnd);
    expect(loadSource, contains('.toList();'));
    expect(loadSource, isNot(contains('toList(growable: false)')));
  });

  test('local A2A sends only through verified current endpoints', () {
    final demoSource = File(
      'lib/demo_client/napaxi_chat_client.dart',
    ).readAsStringSync();
    final sdkSource = File(
      '../../packages/flutter/lib/api/a2a_api.dart',
    ).readAsStringSync();
    final docsSource = File(
      '../../docs/mobile-capabilities.md',
    ).readAsStringSync();

    expect(
      sdkSource,
      contains('final found = <String, A2ALocalPeerAdvertisement>{};'),
    );
    expect(sdkSource, contains('localTransportEvents.listen'));
    expect(sdkSource, contains('await Future<void>.delayed'));

    expect(demoSource, contains('class _A2AConnectivityReport'));
    expect(demoSource, contains("'hasVerifiedChannel': hasVerifiedChannel"));
    expect(demoSource, contains("'code': 'a2a_no_verified_channel'"));
    expect(demoSource, contains("'reachability': connectivity.summaryJson()"));
    expect(demoSource, contains('Map<String, dynamic> summaryJson()'));
    expect(demoSource, contains("'hasVerifiedLocalChannel': endpoint != null"));
    expect(demoSource, contains('_a2aPeerWithoutCurrentEndpoint(peer)'));
    expect(demoSource, contains('_a2aAdvertisementMatchesTrustedPeer'));
    expect(demoSource, contains('_freshPeerForContext(context.peer)'));
    expect(demoSource, contains('local_a2a_no_verified_result_channel'));

    expect(docsSource, contains('Pairing proves peer identity and trust'));
    expect(docsSource, contains('short-lived leases'));
    expect(docsSource, contains('host-provided/xChannel relay'));
  });

  test('local A2A user-visible output is protocol-sanitized', () {
    final chatSource = File('lib/screens/chat_screen.dart').readAsStringSync();
    final a2aSource = File(
      'lib/screens/chat_screen_a2a.dart',
    ).readAsStringSync();
    final demoSource = File(
      'lib/demo_client/napaxi_chat_client.dart',
    ).readAsStringSync();

    expect(chatSource, contains('String _sanitizeA2AProtocolText'));
    expect(chatSource, contains('const String _a2aProtocolFieldPattern'));
    expect(chatSource, contains('_sanitizeAssistantVisibleMessage'));
    expect(chatSource, contains('_sanitizeLocalA2AVisibleMessage'));
    expect(chatSource, contains('_sanitizeLocalA2AToolCall'));
    expect(chatSource, contains('_sanitizeA2AProtocolText(responseText)'));
    expect(chatSource, contains('_sanitizeA2AProtocolText(step.reasoning)'));
    expect(chatSource, contains('_sanitizeA2AProtocolText(call.arguments)'));
    expect(chatSource, contains('peer_id'));
    expect(chatSource, contains('session_id'));
    expect(chatSource, contains('task_id'));
    expect(chatSource, contains('message_id'));
    expect(chatSource, contains(r'["`]$_a2aProtocolFieldPattern["`]'));
    expect(chatSource, contains(r'^\s*连接信息\s*,?\s*$'));
    expect(chatSource, contains('Conversation so far'));
    expect(chatSource, contains('Conversation goal'));
    expect(chatSource, contains('Recent dialogue'));
    expect(chatSource, contains('Incoming message'));
    expect(chatSource, contains('Message from the other Agent'));
    expect(chatSource, contains('Discussion goal'));
    expect(chatSource, contains('Output only the next message'));
    expect(chatSource, contains('routing note'));
    expect(chatSource, contains('conversationTurn'));
    expect(chatSource, contains('replyToTurnId'));
    expect(chatSource, contains('sentIntent'));
    expect(chatSource, contains('remoteIntent'));
    expect(chatSource, contains('requiresResponse'));
    expect(chatSource, contains('conversationNeedsResponse'));
    expect(a2aSource, contains('_sanitizeA2AProtocolText(content)'));
    expect(
      a2aSource,
      contains('sanitizedContent.trim().isEmpty && attachments.isEmpty'),
    );

    expect(demoSource, contains('_localA2AAutoResponderTaskIds'));
    expect(demoSource, contains('_localA2AAutoResponderHandledTaskIds'));
    expect(demoSource, contains('bool claimLocalA2AAutoRunTask'));
    expect(
      demoSource,
      contains(
        'void releaseLocalA2AAutoRunTask(String taskId, {bool handled = true})',
      ),
    );
    expect(demoSource, contains('if (!handled) return;'));
    expect(demoSource, contains('takeTaskResultSummary'));
    expect(
      demoSource,
      contains('_resultSummariesByTaskId[context.taskId] = text'),
    );
    expect(demoSource, contains("'noRemoteReply': observations.isEmpty"));
    expect(demoSource, contains("'openQuestionCount': openQuestionCount"));
    expect(
      demoSource,
      contains("'conversationNeedsResponse': openQuestionCount > 0"),
    );
    expect(demoSource, contains("'requiresResponse': requiresResponse"));
    expect(demoSource, contains("'conversationTurn': {"));
    expect(demoSource, contains("'turnKind': 'conversation_turn'"));
    expect(
      demoSource,
      contains(
        'Your output will be delivered as the next natural-language conversation turn.',
      ),
    );
    expect(demoSource, contains('remoteIntent: remoteIntent'));
    expect(
      demoSource,
      isNot(contains('_a2aSpeechActForText(text, intent: intent)')),
    );
    expect(demoSource, contains("speechAct == 'question'"));
    expect(demoSource, contains('If any message has requiresResponse=true'));
    expect(demoSource, contains("'lastSentAtMs'"));
    expect(demoSource, contains("'sentMessages': sentMessages"));
    expect(demoSource, contains("'displayLabel': '我'"));
    expect(
      demoSource,
      contains("((a['updatedAtMs'] as int?) ?? 0).compareTo("),
    );
    final sentMessagesStart = demoSource.indexOf('sentMessages.add({');
    final sentMessagesEnd = demoSource.indexOf('});', sentMessagesStart);
    expect(sentMessagesStart, isNonNegative);
    expect(sentMessagesEnd, greaterThan(sentMessagesStart));
    final sentMessagesSource = demoSource.substring(
      sentMessagesStart,
      sentMessagesEnd,
    );
    expect(sentMessagesSource, isNot(contains("'taskId':")));
    expect(sentMessagesSource, isNot(contains("'sessionId':")));
    expect(sentMessagesSource, isNot(contains("'toPeerId':")));
    final observationJsonStart = demoSource.indexOf(
      'Map<String, dynamic>? _a2aObservationMessageJson',
    );
    final speechActStart = demoSource.indexOf(
      'String _a2aSpeechActForText',
      observationJsonStart,
    );
    expect(observationJsonStart, isNonNegative);
    expect(speechActStart, greaterThan(observationJsonStart));
    final observationJsonSource = demoSource.substring(
      observationJsonStart,
      speechActStart,
    );
    expect(observationJsonSource, isNot(contains("'taskId':")));
    expect(observationJsonSource, isNot(contains("'sessionId':")));
    expect(observationJsonSource, isNot(contains("'fromPeerId':")));
    expect(observationJsonSource, isNot(contains("'turnId':")));
    expect(observationJsonSource, isNot(contains("'replyToTurnId':")));
    expect(observationJsonSource, isNot(contains("'sentIntent':")));
    expect(demoSource, contains("'exchangeCount': 0"));
    expect(demoSource, contains("'safetyBudget': safetyBudget"));
    expect(demoSource, isNot(contains("'remainingRounds':")));
    expect(demoSource, isNot(contains("'maxRounds':")));
    expect(demoSource, isNot(contains("'conversationBudgetExhausted'")));
    expect(demoSource, isNot(contains("'minRounds':")));
    expect(demoSource, isNot(contains("'remainingRequiredRounds':")));
    expect(demoSource, isNot(contains("'mustContinue':")));
    expect(demoSource, contains("'mustNotSpeculate': observations.isEmpty"));
    expect(demoSource, isNot(contains("'shouldConsiderContinuing'")));
    expect(
      demoSource,
      contains(
        "'displayText': observations.isEmpty ? '目前还没有收到对方 Agent 的回复。' : ''",
      ),
    );
    expect(
      demoSource,
      contains('do not echo the remote turn just because it arrived'),
    );
    expect(
      demoSource,
      contains(
        'Successful A2A tool results are evidence for your next decision',
      ),
    );
    expect(
      demoSource,
      contains('displayText is only user-facing for no-channel'),
    );
    final listAgentsStart = demoSource.indexOf('Future<String> _a2aListAgents');
    final startCollaborationStart = demoSource.indexOf(
      'Future<String> _a2aStartCollaboration',
      listAgentsStart,
    );
    expect(listAgentsStart, isNonNegative);
    expect(startCollaborationStart, greaterThan(listAgentsStart));
    final listAgentsSource = demoSource.substring(
      listAgentsStart,
      startCollaborationStart,
    );
    expect(listAgentsSource, contains("        : '';"));
    expect(listAgentsSource, contains('This is discovery evidence only.'));
    expect(listAgentsSource, contains('continue with a2a_start_collaboration'));
    expect(
      listAgentsSource,
      isNot(contains('发现 \${peers.length} 个可连接的附近 Agent。')),
    );
    expect(
      demoSource,
      isNot(contains('If an A2A tool result includes displayText, repeat')),
    );
    final startToolStart = demoSource.indexOf(
      'name: _a2aStartCollaborationTool',
    );
    final sendToolStart = demoSource.indexOf('name: _a2aSendMessageTool');
    expect(startToolStart, isNonNegative);
    expect(sendToolStart, greaterThan(startToolStart));
    final startToolSource = demoSource.substring(startToolStart, sendToolStart);
    expect(startToolSource, isNot(contains("'maxRounds': {")));
    expect(demoSource, contains('The user does not choose a number of turns.'));
    expect(
      demoSource,
      contains('Treat this as one turn in an ongoing Agent conversation'),
    );
    expect(
      demoSource,
      contains('Your reply may be a question, clarification request'),
    );
    expect(
      demoSource,
      contains('Do not pretend the discussion is complete just because'),
    );
    expect(demoSource, contains('If the remote Agent asked a question'));
    expect(demoSource, contains('_a2aConversationHistoryForPrompt'));
    expect(demoSource, contains('Conversation so far:'));
    expect(demoSource, contains("'\n\nTreat this as one turn'"));
    expect(chatSource, contains('Treat this as one turn'));
    expect(demoSource, contains("localLabel: 'Other Agent'"));
    expect(demoSource, contains("remoteLabel: 'You'"));
    expect(demoSource, isNot(contains("localLabel: '本机 Agent'")));
    expect(demoSource, contains("'conversationHistory': conversationHistory"));
    expect(demoSource, contains('conversationHistory: conversationHistory'));
    expect(demoSource, isNot(contains(r'Collaboration session: $sessionId')));
    expect(demoSource, isNot(contains('From peerId:')));
    expect(demoSource, isNot(contains('Your peerId:')));
    expect(demoSource, isNot(contains('local_a2a channel will return')));
    expect(
      demoSource,
      contains(
        'A2A is a multi-turn conversation, not a single request/response.',
      ),
    );
    expect(
      demoSource,
      contains(
        'Do not infer the remote Agent opinion or close the discussion.',
      ),
    );
    expect(demoSource, isNot(contains("'endpoint': delivery['endpoint']")));
    expect(demoSource, isNot(contains("'messageId': task.messageId")));
  });

  test('local A2A media artifacts are portable and user-visible', () {
    final a2aSource = File(
      'lib/screens/chat_screen_a2a.dart',
    ).readAsStringSync();
    final demoSource = File(
      'lib/demo_client/napaxi_chat_client.dart',
    ).readAsStringSync();

    expect(demoSource, contains('_a2aUnportableArtifactIssues'));
    expect(demoSource, contains('local_artifact_not_portable'));
    expect(demoSource, contains('_persistLocalA2AResolvedBlobArtifact'));
    expect(demoSource, contains('_loadPersistedLocalA2ABlobArtifact'));
    expect(demoSource, contains('a2a_blob_not_resolved'));
    expect(demoSource, contains('a2a_artifact_not_available_locally'));
    expect(demoSource, contains('resolveLocalA2AArtifacts'));

    expect(a2aSource, contains('_a2aVisibleAttachmentsForMessage'));
    expect(a2aSource, contains('attachments: visibleAttachments'));
    expect(a2aSource, contains('_a2aChatAttachmentsFromArtifacts'));
    expect(a2aSource, contains('void addCandidate(String? path)'));
    expect(a2aSource, contains('File(path).existsSync()'));
    expect(a2aSource, contains('_a2aChatAttachmentToMap'));
    expect(a2aSource, contains('_a2aChatAttachmentFromMap'));
    expect(a2aSource, contains('message.attachments.isNotEmpty'));
  });
}
