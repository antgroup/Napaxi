import 'dart:io';

void main() {
  final root = Directory.current;
  final chat = _read(root, 'lib/screens/chat_screen.dart');
  final a2a = _read(root, 'lib/screens/chat_screen_a2a.dart');
  final demo = _read(root, 'lib/demo_client/napaxi_chat_client.dart');
  final models = _read(root, 'lib/models/chat_models.dart');
  final bubble = _read(root, 'lib/widgets/chat_message.dart');
  final history = _read(root, 'lib/panels/session_history.dart');
  final failures = <String>[];
  final chatWithoutSanitizer = _withoutBlock(
    chat,
    'String _sanitizeA2AProtocolText',
    'bool _isLocalA2AChannelName',
  );

  void has(String name, String source, String needle) {
    if (!source.contains(needle)) {
      failures.add('$name should contain: $needle');
    }
  }

  void lacks(String name, String source, String needle) {
    if (source.contains(needle)) {
      failures.add('$name should not contain: $needle');
    }
  }

  void blockLacks(
    String name,
    String source,
    String start,
    String end,
    List<String> needles,
  ) {
    final block = _between(source, start, end, failures, name);
    for (final needle in needles) {
      lacks(name, block, needle);
    }
  }

  has('sanitizer', chat, 'String _sanitizeA2AProtocolText');
  has('sanitizer field pattern', chat, 'const String _a2aProtocolFieldPattern');
  has('sanitizer snake peer id', chat, 'peer_id');
  has('sanitizer snake session id', chat, 'session_id');
  has('sanitizer snake task id', chat, 'task_id');
  has('sanitizer snake message id', chat, 'message_id');
  has(
    'sanitizer quoted protocol field',
    chat,
    r'["`]$_a2aProtocolFieldPattern["`]',
  );
  has('sanitizer removes placeholder-only lines', chat, r'^\s*连接信息\s*,?\s*$');
  has('stream sanitization', chat, '_sanitizeA2AProtocolText(message.content)');
  has('final sanitization', chat, '_sanitizeA2AProtocolText(responseText)');
  has('A2A bridge routing', chat, '_handleLocalA2ABridgeEvent(event)');
  has(
    'A2A bridge trace sanitization',
    chat,
    '_updateAssistantMessage(messageId, _sanitizeLocalA2AVisibleMessage)',
  );
  has(
    'A2A reasoning sanitization',
    chat,
    '_sanitizeA2AProtocolText(step.reasoning)',
  );
  has(
    'A2A tool argument sanitization',
    chat,
    '_sanitizeA2AProtocolText(call.arguments)',
  );
  has('A2A projection persistence', chat, '_persistA2AConversationSessions()');
  has(
    'A2A send projection uses visible id helper',
    chat,
    "_a2aVisibleMessageId('\$taskId-local-sent')",
  );
  has('A2A send projection uses stable local id', chat, "'sent-\$createdAtMs'");
  has(
    'A2A wait projection uses visible id helper',
    chat,
    "_a2aVisibleMessageId('\$taskId-remote-reply')",
  );
  has(
    'A2A wait projection uses stable local id',
    chat,
    "'observation-\$updatedAtMs'",
  );

  has(
    'empty assistant waiting state',
    bubble,
    'if (message.toolCalls.isEmpty) return false;',
  );
  has(
    'A2A waiting indicator',
    bubble,
    'if (message.content.isEmpty &&\n            !hasVisibleAgentTrace &&\n            message.isStreaming)',
  );

  has('auto responder', demo, '_ensureLocalA2AAutoResponder');
  has('auto responder claim', demo, 'bool claimLocalA2AAutoRunTask');
  has(
    'foreground claim-lost projection',
    a2a,
    'Future<void> _projectClaimedA2AAutoRunTask',
  );
  has(
    'claim-lost projection pending bubble',
    a2a,
    '_appendA2AConversationPendingReply(',
  );
  has(
    'A2A pending reply visible thinking trace',
    a2a,
    "AgentTraceStep(reasoning: '正在思考回复。\\n')",
  );
  has(
    'A2A final reply preserves pending trace',
    a2a,
    'existingMessage.copyWith(',
  );
  has(
    'claim-lost stale pending cleanup',
    a2a,
    '_removeA2AConversationPendingReply(',
  );
  has(
    'A2A semantic dedupe is narrow',
    a2a,
    'const Duration(seconds: 2).inMilliseconds',
  );
  has(
    'A2A legacy conversation ids canonicalize on restore',
    a2a,
    'String _canonicalA2AConversationSessionId(String sessionId)',
  );
  has('A2A restored conversation uses canonical id', a2a, 'id: canonicalId,');
  has(
    'A2A raw Android ids are weak titles',
    a2a,
    r"RegExp(r'\bandroid-[a-z0-9_.:-]{6,}\b')",
  );
  has(
    'A2A raw iOS ids are weak titles',
    a2a,
    r"RegExp(r'\bios-[a-z0-9_.:-]{6,}\b')",
  );
  has(
    'A2A auto-run honors expectsReply',
    a2a,
    "final expectsReply = collaboration['expectsReply'] != false;",
  );
  has(
    'A2A fallback responder honors expectsReply',
    demo,
    "final expectsReply = collaboration['expectsReply'] != false;",
  );
  has('A2A failure reply stays conversational', a2a, '我暂时没能完成回复。');
  has('A2A delivery failure reply stays conversational', a2a, '我刚才的回复没有送达。');
  has(
    'multi-turn instruction',
    demo,
    'A2A is a multi-turn conversation, not a single request/response.',
  );
  has(
    'wait continuation instruction',
    demo,
    'If any message has requiresResponse=true',
  );
  has(
    'wait open conversation is model-decided',
    demo,
    'If the result says the conversation is still open but no message requires response',
  );
  lacks(
    'wait instruction avoids raw conversationOpen comparison',
    demo,
    'If conversationOpen=true but no message requires response',
  );
  has(
    'wait conversation-open evidence',
    demo,
    "'conversationOpen': conversationOpen",
  );
  has(
    'wait safety budget evidence',
    demo,
    'final withinSafetyBudget = exchangeCount < safetyBudget;',
  );
  has(
    'wait safety budget closes open discussion',
    demo,
    'withinSafetyBudget &&',
  );
  has(
    'wait final-summary closes discussion evidence',
    demo,
    'finalSummaryCount == 0',
  );
  has(
    'A2A observed messages stay chronological',
    demo,
    "((a['updatedAtMs'] as int?) ?? 0).compareTo(",
  );
  has(
    'no fixed turn count',
    demo,
    'The user does not choose a number of turns.',
  );
  has(
    'shared visible conversation id helper',
    a2a,
    'String _a2aVisibleConversationSessionIdForCollaboration',
  );
  has(
    'bridge uses shared visible conversation id',
    demo,
    '_a2aVisibleConversationSessionIdForCollaboration',
  );
  has(
    'ledger uses shared visible conversation id',
    a2a,
    'return _a2aVisibleConversationSessionIdForCollaboration',
  );
  has(
    'canonical visible conversation id rejects legacy peer segment',
    a2a,
    "return tail.isNotEmpty && !tail.contains(':');",
  );
  has(
    'session history title sanitization',
    history,
    'String _sessionHistoryDisplayTitle(ChatSession session)',
  );
  has(
    'session history preview sanitization',
    history,
    'String _sessionHistoryPreview(ChatSession session)',
  );
  has(
    'session history search message sanitization',
    history,
    '_sanitizeA2AProtocolText(message.content)',
  );
  has(
    'delete confirmation title sanitization',
    chat,
    '_sanitizeA2AProtocolText(\n      session.displayTitle,',
  );
  has(
    'A2A conversation notice title sanitization',
    chat,
    "_sanitizeA2AProtocolText(title ?? '')",
  );
  has(
    'A2A tool activity uses user language',
    chat,
    "activity: isA2ATool ? '附近 Agent'",
  );
  lacks(
    'A2A tool activity avoids English debug label',
    chat,
    "activity: isA2ATool ? 'Nearby Agent'",
  );
  has(
    'A2A conversation unread state',
    chat,
    '_a2aUnreadConversationSessionIds',
  );
  has('A2A restore future state', a2a, '_a2aConnectionRestoreFuture');
  has(
    'A2A readiness before user turn',
    chat,
    'await _ensureA2AConnectionReadyForUserTurn();',
  );
  has(
    'A2A restore scheduling helper',
    a2a,
    'void _scheduleA2AConnectionRestoreIfAllowed()',
  );
  has(
    'A2A restore scheduling is single-flight',
    a2a,
    'if (_a2aConnectionRestoreFuture != null) return;',
  );
  has(
    'A2A send-time restore gate',
    a2a,
    'Future<void> _ensureA2AConnectionReadyForUserTurn()',
  );
  has(
    'A2A conversation unread history pass-through',
    chat,
    'a2aUnreadSessionIds: Set.unmodifiable',
  );
  has('A2A conversation unread badge', history, 'class _A2AUnreadBadge');
  has('A2A conversation unread user label', history, '附近对话有新消息');
  has(
    'SDK history A2A tool filtering',
    models,
    'if (!_isA2AToolName(call.name))',
  );
  has(
    'SDK history assistant content sanitization',
    models,
    'final content = _sanitizeA2AProtocolText(item.content)',
  );
  has(
    'SDK history reasoning sanitization',
    models,
    'final reasoning = _sanitizeA2AProtocolText(pendingReasoning)',
  );
  has(
    'SDK history skips empty sanitized pending trace',
    models,
    'reasoning.trim().isEmpty && toolCalls.isEmpty',
  );
  has(
    'SDK history skips empty sanitized assistant',
    models,
    'content.trim().isEmpty &&',
  );
  has(
    'A2A persistence filters visible messages',
    a2a,
    '.where(_isA2AConversationMessage)',
  );
  has(
    'A2A notices drop empty sanitized content',
    a2a,
    'if (sanitizedContent.trim().isEmpty) return;',
  );
  lacks(
    'bridge visible conversation id',
    demo,
    'nearby-agent:\${peer.peerId}:',
  );
  blockLacks(
    'A2A persisted session payload',
    a2a,
    'Map<String, Object?> _a2aConversationMessageToMap',
    'ChatMessage? _a2aConversationMessageFromMap',
    const ['reasoning', 'toolCalls', 'traceSteps', 'activatedSkills'],
  );
  has(
    'A2A restored message content sanitization',
    a2a,
    "final content = _sanitizeA2AProtocolText(map['content']?.toString() ?? '');",
  );
  has(
    'A2A restored title sanitization',
    a2a,
    "title: _sanitizeA2AProtocolText(map['title']?.toString() ?? '')",
  );
  blockLacks(
    'session history tile raw labels',
    history,
    'class _SessionHistoryTile extends StatelessWidget',
    'class _SessionRunBadge extends StatelessWidget',
    const ['session.displayTitle,', 'session.preview,'],
  );
  blockLacks(
    'tool-result visible conversation id',
    a2a,
    'String? _a2aVisibleConversationSessionIdFromToolResult',
    'String _a2aVisibleConversationTitleFromToolResult',
    const ['peerKey', r'$_a2aConversationSessionPrefix:$peerId:'],
  );

  blockLacks(
    '/a2a help user text',
    a2a,
    'String _slashA2AHelpMessage()',
    'Future<String> _slashA2AE2EGuideMessage',
    const ['taskId', 'sessionId', 'peerId', 'endpoint', '/a2a panel'],
  );
  blockLacks(
    '/a2a peers user text',
    a2a,
    'Future<String> _slashA2APeersMessage',
    'sdk.A2ALocalPeerAdvertisement? _resolveA2ASlashPeer',
    const ['peerId：', 'endpoint：', 'transport：', 'trusted peer'],
  );
  blockLacks(
    'tool sentMessages model-visible JSON',
    demo,
    'sentMessages.add({',
    '});',
    const ["'taskId':", "'sessionId':", "'toPeerId':"],
  );
  blockLacks(
    'tool observed messages model-visible JSON',
    demo,
    'Map<String, dynamic>? _a2aObservationMessageJson',
    'String _a2aSpeechActForText',
    const [
      "'taskId':",
      "'sessionId':",
      "'fromPeerId':",
      "'turnId':",
      "'replyToTurnId':",
      "'sentIntent':",
      "'messageId':",
      "'endpoint':",
      "'transport':",
    ],
  );

  for (final source in {
    'chat_screen.dart': chatWithoutSanitizer,
    'chat_screen_a2a.dart': a2a,
  }.entries) {
    for (final phrase in const [
      '本机 Agent 自动处理',
      '对端已自动接收',
      '对端已收到并记录',
      '收到本地 A2A 配对请求',
      'trusted peer',
      'local_a2a channel',
      'Collaboration session',
      'From peerId',
      'Your peerId',
    ]) {
      lacks('${source.key} user-visible source', source.value, phrase);
    }
  }

  if (failures.isNotEmpty) {
    stderr.writeln('A2A user contract failed:');
    for (final failure in failures) {
      stderr.writeln('- $failure');
    }
    exitCode = 1;
    return;
  }
  stdout.writeln('A2A user contract passed.');
}

String _read(Directory root, String relativePath) {
  return File('${root.path}/$relativePath').readAsStringSync();
}

String _between(
  String source,
  String start,
  String end,
  List<String> failures,
  String name,
) {
  final startIndex = source.indexOf(start);
  if (startIndex < 0) {
    failures.add('$name missing block start: $start');
    return '';
  }
  final endIndex = source.indexOf(end, startIndex + start.length);
  if (endIndex < 0) {
    failures.add('$name missing block end: $end');
    return source.substring(startIndex);
  }
  return source.substring(startIndex, endIndex);
}

String _withoutBlock(String source, String start, String end) {
  final startIndex = source.indexOf(start);
  if (startIndex < 0) return source;
  final endIndex = source.indexOf(end, startIndex + start.length);
  if (endIndex < 0) return source.substring(0, startIndex);
  return source.replaceRange(startIndex, endIndex, '');
}
