import 'dart:async';
import 'dart:convert';

// ignore_for_file: depend_on_referenced_packages, unnecessary_import, use_super_parameters

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napaxi/main.dart';
import 'package:napaxi_flutter/napaxi_flutter.dart' as sdk;
import 'package:napaxi_flutter/advanced.dart' as sdk;
import 'package:napaxi_flutter/convenience.dart' as sdk;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'test_support.dart';

/// Matches the per-turn generated-attachments blocks, keyed
/// `turn_generated_attachments_<userMessageId|lead>_<turnIndex>`.
Finder _findTurnGeneratedAttachments() {
  return find.byWidgetPredicate(
    (widget) =>
        widget.key is ValueKey<String> &&
        (widget.key as ValueKey<String>).value.startsWith(
          'turn_generated_attachments_',
        ),
  );
}

Future<void> _pumpUntilSent(
  WidgetTester tester,
  FakeNapaxiChatClient fakeClient,
) async {
  for (var i = 0; i < 20; i++) {
    if (fakeClient.sentThreadIds.isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pumpUntilBackgroundStopped(
  WidgetTester tester,
  FakeNapaxiChatClient fakeClient,
) async {
  for (var i = 0; i < 20; i++) {
    if (fakeClient.stopBackgroundServiceCount > 0) return;
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Widget _testApp({
  NapaxiChatClientFactory? chatClientFactory,
  sdk.NapaxiConfigStore? configStore,
  DemoPreferencesStore? preferencesStore,
  DemoUpdateService? updateService,
  DemoFeedbackService? feedbackService,
  AppLanguage language = AppLanguage.english,
  TerminalBackend Function()? terminalBackendFactory,
}) {
  return NapaxiApp(
    // The demo app now defaults its UI language to Chinese; most of this suite
    // asserts against the English copy, so pin English synchronously from the
    // first frame. Tests that assert Chinese copy pass `language:
    // AppLanguage.chinese`.
    initialLanguage: language,
    chatClientFactory: chatClientFactory ?? () async => FakeNapaxiChatClient(),
    configStore: configStore ?? sdk.NapaxiConfigStore.memory(),
    preferencesStore: preferencesStore ?? MemoryDemoPreferencesStore(),
    updateService: updateService,
    feedbackService: feedbackService,
    terminalBackendFactory: terminalBackendFactory,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // The chat client eagerly builds a WebViewController when the A2A event
    // subscription starts (see _ensureA2AEventSubscription); unit tests must
    // provide a WebViewPlatform implementation or that construction asserts.
    WebViewPlatform.instance = _FakeWebViewPlatform();
  });

  test('parses queued evolution events', () {
    final event = sdk.ChatEvent.fromMap({
      'type': 'evolution_queued',
      'review_types': ['memory', 'skill'],
      'runs': [
        {'id': 'run-1', 'review_type': 'memory'},
      ],
    });

    expect(event, isA<sdk.EvolutionQueuedEvent>());
    final queued = event as sdk.EvolutionQueuedEvent;
    expect(queued.reviewTypes, ['memory', 'skill']);
    expect(queued.runIds, ['run-1']);
    expect(queued.runs.single.reviewType, 'memory');
  });

  test('parses Pgyer update fields returned as strings', () {
    final update = DemoUpdateInfo.fromMap({
      'buildKey': 'build-string',
      'buildVersion': '0.0.6',
      'buildVersionNo': 6,
      'buildBuildVersion': '106',
      'needForceUpdate': '1',
      'downloadURL': 'https://example.com/app.apk',
      'appURl': 'https://www.pgyer.com/demo',
      'buildUpdateDescription': 'String fields from Pgyer.',
      'buildFileSize': '123456',
    });

    expect(update.buildVersionNo, '6');
    expect(update.buildBuildVersion, 106);
    expect(update.needForceUpdate, isTrue);
    expect(update.fileSizeBytes, 123456);
  });

  test('attaches CLI-backfilled tool calls to the preceding assistant', () {
    // CLI engines (codex/CC) emit tool calls AFTER the assistant text of the
    // same turn, encoded as the {narrative, calls} object — the reverse of the
    // SDK-style order. The converter must reattach them to that assistant
    // instead of leaving them on a trailing empty shell message.
    final history = <sdk.ChatMessage>[
      const sdk.ChatMessage(
        role: 'user',
        content: 'List files',
        createdAt: '2026-05-12T10:00:00.000',
      ),
      const sdk.ChatMessage(
        role: 'assistant',
        content: 'Let me check the workspace.',
        createdAt: '2026-05-12T10:00:02.000',
      ),
      sdk.ChatMessage.fromMap(const <String, dynamic>{
        'role': 'tool_calls',
        'content':
            '{"narrative":"Called list_files","calls":[{"name":"list_files","call_id":"call-1","arguments":"{\\"path\\":\\"/workspace\\"}","result":"{\\"files\\":[\\"README.md\\"]}"}]}',
        'created_at': '2026-05-12T10:00:03.000',
      }),
    ];
    final messages = messagesFromSdkHistoryForTesting(
      history,
      accountId: 'flutter_demo',
      agentId: sdk.NapaxiEngine.defaultAgentId,
    );
    expect(messages, hasLength(2));
    expect(messages[0].isUser, isTrue);
    expect(messages[1].content, 'Let me check the workspace.');
    expect(messages[1].toolCalls, hasLength(1));
    expect(messages[1].toolCalls.single.name, 'list_files');
    expect(messages[1].toolCalls.single.callId, 'call-1');
  });

  test('keeps SDK-style tool calls on the following assistant message', () {
    // Pending reasoning must disable the back-attach so SDK-style order
    // ([reasoning → tool_calls → assistant]) still lands calls on the next
    // assistant, unchanged by the CLI-order fix.
    final history = <sdk.ChatMessage>[
      const sdk.ChatMessage(
        role: 'user',
        content: 'Q',
        createdAt: '2026-05-12T10:00:00.000',
      ),
      const sdk.ChatMessage(
        role: 'reasoning',
        content: 'Thinking it over',
        createdAt: '2026-05-12T10:00:01.000',
      ),
      sdk.ChatMessage.fromMap(const <String, dynamic>{
        'role': 'tool_calls',
        'content':
            '{"narrative":"Called lookup","calls":[{"name":"lookup","call_id":"c1","arguments":"{}"}]}',
        'created_at': '2026-05-12T10:00:02.000',
      }),
      const sdk.ChatMessage(
        role: 'assistant',
        content: 'Answer',
        createdAt: '2026-05-12T10:00:03.000',
      ),
    ];
    final messages = messagesFromSdkHistoryForTesting(
      history,
      accountId: 'flutter_demo',
      agentId: sdk.NapaxiEngine.defaultAgentId,
    );
    final assistant = messages.lastWhere(
      (message) => message.content == 'Answer',
    );
    expect(assistant.toolCalls, hasLength(1));
    expect(assistant.toolCalls.single.name, 'lookup');
  });

  test('reattaches each turn tool calls independently across multiple turns', () {
    final history = <sdk.ChatMessage>[
      const sdk.ChatMessage(
        role: 'user',
        content: 'First',
        createdAt: '2026-05-12T10:00:00.000',
      ),
      const sdk.ChatMessage(
        role: 'assistant',
        content: 'First answer.',
        createdAt: '2026-05-12T10:00:01.000',
      ),
      sdk.ChatMessage.fromMap(const <String, dynamic>{
        'role': 'tool_calls',
        'content':
            '{"narrative":"Called a","calls":[{"name":"tool_a","call_id":"ca","arguments":"{}"}]}',
        'created_at': '2026-05-12T10:00:02.000',
      }),
      const sdk.ChatMessage(
        role: 'user',
        content: 'Second',
        createdAt: '2026-05-12T10:00:03.000',
      ),
      const sdk.ChatMessage(
        role: 'assistant',
        content: 'Second answer.',
        createdAt: '2026-05-12T10:00:04.000',
      ),
      sdk.ChatMessage.fromMap(const <String, dynamic>{
        'role': 'tool_calls',
        'content':
            '{"narrative":"Called b","calls":[{"name":"tool_b","call_id":"cb","arguments":"{}"}]}',
        'created_at': '2026-05-12T10:00:05.000',
      }),
    ];
    final messages = messagesFromSdkHistoryForTesting(
      history,
      accountId: 'flutter_demo',
      agentId: sdk.NapaxiEngine.defaultAgentId,
    );
    // user, assistant(+a), user, assistant(+b) — no stray empty shells.
    expect(messages, hasLength(4));
    expect(messages[1].content, 'First answer.');
    expect(messages[1].toolCalls.single.name, 'tool_a');
    expect(messages[3].content, 'Second answer.');
    expect(messages[3].toolCalls.single.name, 'tool_b');
  });

  test('renders codex webSearch backfill as a web_search tool call', () {
    // Mirrors what _codexItemToHistoryMap emits for a Codex `webSearch` thread
    // item (role=tool_calls, narrative + calls[name=web_search]). Previously
    // the item was dropped because `webSearch` had no switch case and fell
    // through to `default`, which returns empty (no text/content field).
    final history = <sdk.ChatMessage>[
      const sdk.ChatMessage(
        role: 'user',
        content: 'Look up rust async',
        createdAt: '2026-05-12T10:00:00.000',
      ),
      const sdk.ChatMessage(
        role: 'assistant',
        content: 'Searching now.',
        createdAt: '2026-05-12T10:00:02.000',
      ),
      sdk.ChatMessage.fromMap(const <String, dynamic>{
        'role': 'tool_calls',
        'content':
            '{"narrative":"Searched: rust async","calls":[{"name":"web_search","call_id":"search-1","arguments":"{\\"query\\":\\"rust async\\"}"}]}',
        'created_at': '2026-05-12T10:00:03.000',
      }),
    ];
    final messages = messagesFromSdkHistoryForTesting(
      history,
      accountId: 'flutter_demo',
      agentId: sdk.NapaxiEngine.defaultAgentId,
    );
    expect(messages, hasLength(2));
    expect(messages[1].content, 'Searching now.');
    expect(messages[1].toolCalls.single.name, 'web_search');
    // Backfilled calls carry no output (webSearch has no results on the item),
    // but they must still read as finished — not "running".
    expect(messages[1].toolCalls.single.isComplete, isTrue);
  });

  testWidgets('renders the chat shell', (tester) async {
    await tester.pumpWidget(_testApp());

    expect(find.byKey(const Key('agent_selector_button')), findsOneWidget);
    expect(find.text('No model configured'), findsNothing);
    expect(find.byKey(const Key('session_history_button')), findsOneWidget);
    expect(find.byKey(const Key('context_status_button')), findsOneWidget);
    expect(find.byKey(const Key('language_menu_button')), findsNothing);
    expect(find.byKey(const Key('chat_input_field')), findsOneWidget);
    expect(find.byKey(const Key('add_attachment_button')), findsOneWidget);
    expect(find.byKey(const Key('send_message_button')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('chat_input_field')), '/');
    await tester.pump();

    expect(find.byKey(const Key('slash_command_suggestions')), findsOneWidget);
    expect(find.byKey(const Key('slash_command_help')), findsOneWidget);
    expect(find.byKey(const Key('slash_command_context')), findsOneWidget);
  });

  testWidgets('general scenario hides developer runtime agents', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'napaxi_demo.active_scenario.v1': 'napaxi.scenario.general',
    });
    final fakeClient = FakeNapaxiChatClient(
      agents: const [
        DemoAgent(
          id: sdk.NapaxiEngine.defaultAgentId,
          name: 'napaxi',
          icon: Icons.auto_awesome_rounded,
        ),
        DemoAgent(
          id: 'engine.napaxi',
          name: 'Napaxi',
          icon: Icons.terminal_rounded,
        ),
        DemoAgent(
          id: 'agent-helper',
          name: 'Helper',
          icon: Icons.person_rounded,
        ),
      ],
    );

    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await pumpUntilFound(
      tester,
      find.byKey(const Key('agent_selector_button')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('agent_selector_button')));
    await tester.pumpAndSettle();

    expect(find.text('Helper'), findsOneWidget);
    expect(find.text('Napaxi'), findsNothing);
  });

  testWidgets('renders source-aware context status details', (tester) async {
    final store = sdk.NapaxiConfigStore.memory();
    await store.saveProfile(
      const sdk.NapaxiConfigProfile(
        id: 'persisted',
        name: 'Persisted',
        provider: 'openai',
        model: 'saved-model',
        metadata: {
          'model_entries': [
            {
              'id': 'saved-model',
              'display_name': '',
              'capabilities': ['chat'],
            },
          ],
        },
      ),
      apiKey: 'sk-saved',
    );
    await store.saveSelection(
      const sdk.NapaxiConfigSelection(selectedProfileId: 'persisted'),
    );
    const sessionKey = sdk.SessionKey(
      channelType: 'app',
      accountId: 'flutter_demo',
      threadId: 'session-context',
    );
    const status = sdk.ContextStatus(
      threadId: 'session-context',
      engine: 'compressor',
      summaryPresent: false,
      compactionCount: 1,
      tokensBefore: 56000,
      tokensAfter: 22000,
      estimatedTokens: 24000,
      contextWindowTokens: 128000,
      triggerTokens: 108800,
      targetTokens: 57600,
      responseReserveTokens: 4096,
      usagePercent: 18.8,
      triggerRatio: 0.85,
      targetRatio: 0.45,
      displaySource: 'provider',
      displayUsedTokens: 24000,
      currentWindowTokens: 24000,
      transcriptEstimatedTokens: 36000,
      lastContextDeltaTokens: -7000,
      lastContextDeltaReason: 'provider_replaced_preflight',
      toolResultPrunedTokens: 1200,
      toolResultPrunedChars: 2400,
      lastPromptTokens: 24000,
      preflightEstimatedTokens: 31000,
      cacheReadTokens: 8000,
      cacheWriteTokens: 1200,
      contextWindowSource: 'config',
      breakdown: sdk.ContextTokenBreakdown(
        systemPromptTokens: 100,
        summaryTokens: 0,
        historyTokens: 200,
        toolDescriptorTokens: 300,
        toolResultTokens: 400,
        toolCallTokens: 50,
        attachmentTokens: 25,
        imageTokens: 2000,
        responseReserveTokens: 4096,
        totalTokens: 31000,
      ),
      contextBudgetStatus: sdk.ContextBudgetStatus(
        source: 'pre-prompt-estimate',
        provider: 'openai-compatible',
        model: 'gpt-4o',
        route: 'fits',
        shouldCompact: false,
        estimatedPromptTokens: 26904,
        contextTokenBudget: 128000,
        promptBudgetBeforeReserve: 123904,
        reserveTokens: 4096,
        effectiveReserveTokens: 4096,
        remainingPromptBudgetTokens: 97000,
        overflowTokens: 0,
        toolResultReducibleChars: 2000,
        messageCount: 12,
        unwindowedMessageCount: 12,
        updatedAt: '2026-05-29T10:00:00Z',
      ),
      fresh: true,
    );
    final fakeClient = FakeNapaxiChatClient(
      sessions: const [
        sdk.SessionInfo(
          key: sessionKey,
          title: 'Context chat',
          preview: 'Ready',
          messageCount: 1,
          createdAt: '2026-05-29T10:00:00.000',
          updatedAt: '2026-05-29T10:01:00.000',
        ),
      ],
      contextStatusByThreadId: const {'session-context': status},
    );

    await tester.pumpWidget(
      _testApp(configStore: store, chatClientFactory: () async => fakeClient),
    );
    await tester.pumpAndSettle();
    // Switch UI to Chinese so the test's '上下文窗口', '编辑模型' etc match.
    await openModelConfiguration(tester);
    await tapVisible(tester, const Key('language_option_zh'));
    await tester.pumpAndSettle();
    await closeSettingsSheet(tester);
    await pumpUntilFound(
      tester,
      find.bySemanticsLabel(RegExp(r'当前窗口.*总量 128k.*已用 24k.*会话记录 36k')),
    );

    await tester.tap(find.byKey(const Key('context_status_button')));
    await tester.pumpAndSettle();

    expect(find.text('上下文窗口'), findsOneWidget);
    expect(
      find.ancestor(of: find.text('上下文窗口'), matching: find.byType(Scrollable)),
      findsNothing,
    );
    expect(
      find.ancestor(of: find.text('高级详情'), matching: find.byType(Scrollable)),
      findsOneWidget,
    );
    expect(find.text('有效窗口'), findsWidgets);
    expect(find.text('128k'), findsOneWidget);
    expect(find.text('当前窗口'), findsWidgets);
    expect(find.text('24k'), findsOneWidget);
    expect(find.text('会话记录'), findsOneWidget);
    expect(find.text('36k'), findsOneWidget);
    expect(find.text('高级详情'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, '配置'));
    await tester.pumpAndSettle();

    expect(find.text('编辑模型'), findsOneWidget);
    expect(find.text('上下文'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('context_status_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('高级详情'));
    await tester.pumpAndSettle();

    expect(find.text('当前窗口'), findsWidgets);
    expect(find.text('会话记录'), findsWidgets);
  });

  testWidgets('shows context compaction banner during chat events', (
    tester,
  ) async {
    final fakeClient = FakeNapaxiChatClient(
      events: const [
        sdk.ContextCompactingEvent(usagePercent: 91.2, strategy: 'llm_summary'),
        sdk.ContextCompactedEvent(
          turnsRemoved: 3,
          tokensBefore: 98000,
          tokensAfter: 42000,
        ),
        sdk.ResponseEvent(content: 'done'),
      ],
    );

    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'Please compact the context',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await _pumpUntilSent(tester, fakeClient);
    await tester.pump();

    expect(find.byKey(const Key('context_compaction_banner')), findsOneWidget);
    expect(find.text('上下文已压缩'), findsOneWidget);
    expect(find.textContaining('98k -> 42k'), findsOneWidget);
  });

  testWidgets('asks for model configuration before SDK chat', (tester) async {
    await tester.pumpWidget(_testApp());

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'Hello napaxi',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pumpAndSettle();

    expect(find.text('Hello napaxi'), findsOneWidget);
    expect(
      find.text('Choose a chat model before chatting.', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('long pressing a sent user message can edit it in the composer', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp());

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'Original message',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('chat_input_field')), 'Draft');
    await tester.pump();
    await tester.longPress(find.text('Original message'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit_user_message_action')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('editing_message_header')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('chat_input_field')))
          .controller
          ?.text,
      'Original message',
    );

    await tester.tap(find.byKey(const Key('cancel_edit_message_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('editing_message_header')), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('chat_input_field')))
          .controller
          ?.text,
      isEmpty,
    );
  });

  testWidgets('updates the welcome message after model configuration', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => FakeNapaxiChatClient()),
    );

    expect(
      find.text(
        'Welcome to napaxi. Open Basic configuration from Settings, then chat with the SDK-backed agent.',
      ),
      findsOneWidget,
    );

    await configureSingleModel(tester);

    expect(
      find.text('napaxi is ready. Ask anything to start chatting.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Welcome to napaxi. Open Basic configuration from Settings, then chat with the SDK-backed agent.',
      ),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('session_history_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new_session_button')));
    await tester.pumpAndSettle();

    expect(
      find.text('napaxi is ready. Ask anything to start chatting.'),
      findsOneWidget,
    );
  });

  testWidgets('uses the main model for chat without a chat capability slot', (
    tester,
  ) async {
    final fakeClient = FakeNapaxiChatClient(
      skills: const [
        sdk.SkillInfo(name: 'android-project-template'),
        sdk.SkillInfo(name: 'android-apk-build'),
      ],
    );
    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );

    await openModelConfiguration(tester);
    await tester.tap(find.byKey(const Key('add_model_button')));
    await tester.pumpAndSettle();

    await enterVisibleText(tester, const Key('model_name_field'), 'Main only');
    await enterVisibleText(tester, const Key('model_field'), 'utility-model');
    await enterVisibleText(tester, const Key('api_key_field'), 'sk-utility');
    expect(find.byKey(const Key('capability_chat')), findsNothing);
    await tester.tap(find.byKey(const Key('save_model_button')));
    await tester.pumpAndSettle();
    await closeSettingsSheet(tester);

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'Hello without chat',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Fake SDK reply from utility-model: Hello without chat',
        findRichText: true,
      ),
      findsOneWidget,
    );
  });

  testWidgets('scrolls latest messages into view when input gains focus', (
    tester,
  ) async {
    final fakeClient = FakeNapaxiChatClient();
    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    for (var i = 0; i < 12; i++) {
      await tester.enterText(
        find.byKey(const Key('chat_input_field')),
        'Message $i',
      );
      await tester.tap(find.byKey(const Key('send_message_button')));
      await tester.pumpAndSettle();
    }

    final listView = tester.widget<ListView>(
      find.byKey(const Key('chat_message_list')),
    );
    final scrollController = listView.controller!;
    expect(scrollController.position.maxScrollExtent, greaterThan(0));

    scrollController.jumpTo(0);
    await tester.pump();
    expect(scrollController.offset, 0);

    await tester.tap(find.byKey(const Key('chat_input_field')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(scrollController.offset, scrollController.position.maxScrollExtent);
  });

  testWidgets('pauses auto-follow when user scrolls up during streaming', (
    tester,
  ) async {
    Stream<sdk.ChatEvent> streamEvents() async* {
      yield const sdk.ResponseDeltaEvent(
        content: 'line 1\nline 2\nline 3\nline 4\nline 5\n',
      );
      await Future<void>.delayed(const Duration(milliseconds: 900));
      yield const sdk.ResponseDeltaEvent(
        content: 'line 6\nline 7\nline 8\nline 9\nline 10\n',
      );
    }

    final history = <sdk.ChatMessage>[
      for (var i = 0; i < 18; i++) ...[
        sdk.ChatMessage(
          role: 'user',
          content: 'History $i',
          createdAt:
              '2026-05-12T10:${(i ~/ 2).toString().padLeft(2, '0')}:00.000',
        ),
        sdk.ChatMessage(
          role: 'assistant',
          content: 'Reply $i',
          createdAt:
              '2026-05-12T10:${(i ~/ 2).toString().padLeft(2, '0')}:30.000',
        ),
      ],
    ];
    const sessionKey = sdk.SessionKey(
      channelType: 'app',
      accountId: 'flutter_demo',
      threadId: 'session-42',
    );
    final fakeClient = FakeNapaxiChatClient(
      eventStreamsByThreadId: {'session-42': streamEvents()},
      sessions: const [
        sdk.SessionInfo(
          key: sessionKey,
          title: 'Saved chat',
          preview: 'Reply 17',
          messageCount: 36,
          createdAt: '2026-05-12T10:00:00.000',
          updatedAt: '2026-05-12T10:20:00.000',
        ),
      ],
      historyByThreadId: {'session-42': history},
    );
    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.text('History 0'));

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'Stream now',
    );
    await tester.tap(find.byKey(const Key('send_message_button')));
    await _pumpUntilSent(tester, fakeClient);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final scrollable = find.byKey(const Key('chat_message_list'));
    await tester.drag(scrollable, const Offset(0, 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final scrollableWidget = tester.widget<Scrollable>(
      find.descendant(of: scrollable, matching: find.byType(Scrollable)),
    );
    final before = scrollableWidget.controller!.position.pixels;

    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump(const Duration(milliseconds: 300));

    final after = scrollableWidget.controller!.position.pixels;
    expect((after - before).abs(), lessThan(4));
    expect(find.byKey(const Key('jump_to_latest_button')), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('jump_to_latest_button')),
      warnIfMissed: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final position = scrollableWidget.controller!.position;
    expect(position.maxScrollExtent - position.pixels, lessThan(4));
  });

  testWidgets('stops the active SDK chat from the input bar', (tester) async {
    final cancelCompleter = Completer<void>();
    final events = StreamController<sdk.ChatEvent>(
      onCancel: () {
        if (!cancelCompleter.isCompleted) cancelCompleter.complete();
      },
    );
    final fakeClient = FakeNapaxiChatClient(eventStream: events.stream);
    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'Keep working',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const Key('stop_message_button')), findsOneWidget);
    expect(find.byKey(const Key('run_status_stop_button')), findsNothing);
    expect(find.text('Background running'), findsNothing);
    expect(fakeClient.backgroundPermissionRequestCount, 1);

    await tester.tap(find.byKey(const Key('stop_message_button')));
    await tester.pump();
    // The stop flow waits up to 4s for the event stream to drain (the fake's
    // stream never closes, so it relies on that grace window). Pump past the
    // grace window to let the subscription cancel and the run finish, instead
    // of blocking on a future that needs the UI to advance first.
    await tester.pump(const Duration(seconds: 5));
    await cancelCompleter.future.timeout(const Duration(seconds: 1));
    await _pumpUntilBackgroundStopped(tester, fakeClient);

    expect(fakeClient.cancelCount, 1);
    expect(fakeClient.stopBackgroundServiceCount, 1);
    expect(fakeClient.canceledSession?.threadId, 'session-1');
    expect(find.text('Stopped.'), findsOneWidget);
    expect(find.byKey(const Key('send_message_button')), findsOneWidget);
  });

  testWidgets('stream reset clears partial assistant response before replay', (
    tester,
  ) async {
    final events = StreamController<sdk.ChatEvent>();
    final store = sdk.NapaxiConfigStore.memory();
    await store.saveProfile(
      const sdk.NapaxiConfigProfile(
        id: 'persisted',
        name: 'Persisted',
        provider: 'openai',
        model: 'saved-model',
        metadata: {
          'model_entries': [
            {
              'id': 'saved-model',
              'display_name': '',
              'capabilities': ['chat'],
            },
          ],
        },
      ),
      apiKey: 'sk-saved',
    );
    await store.saveSelection(
      const sdk.NapaxiConfigSelection(selectedProfileId: 'persisted'),
    );
    final fakeClient = FakeNapaxiChatClient(eventStream: events.stream);
    await tester.pumpWidget(
      _testApp(configStore: store, chatClientFactory: () async => fakeClient),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('chat_input_field')), 'Hello');
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pump();
    await _pumpUntilSent(tester, fakeClient);

    events.add(const sdk.ResponseDeltaEvent(content: 'Hel'));
    await tester.pump();
    expect(find.text('Hel'), findsOneWidget);

    events.add(const sdk.StreamResetEvent(reason: 'reconnect'));
    await tester.pump();
    expect(find.text('Hel'), findsNothing);

    events.add(const sdk.ResponseDeltaEvent(content: 'Hello after reconnect'));
    await tester.pump();
    await events.close();
    await tester.pump();

    expect(find.text('Hello after reconnect'), findsOneWidget);
    expect(find.text('HelHello after reconnect'), findsNothing);
  });

  testWidgets('queued evolution finishes the visible chat flow', (
    tester,
  ) async {
    final events = StreamController<sdk.ChatEvent>();
    final fakeClient = FakeNapaxiChatClient(
      eventStream: events.stream,
      evolutionRuns: [
        sdk.EvolutionRun(
          id: 'run-1',
          agentId: sdk.NapaxiEngine.defaultAgentId,
          threadId: 'session-1',
          reviewType: 'memory',
          status: sdk.EvolutionRunStatus.running,
          queuedAt: DateTime.now(),
        ),
      ],
    );
    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'Remember this',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pump();
    await _pumpUntilSent(tester, fakeClient);

    events.add(const sdk.ResponseEvent(content: 'I will keep that in mind.'));
    await tester.pump();
    events.add(
      const sdk.EvolutionQueuedEvent(
        reviewTypes: ['memory'],
        runs: [sdk.EvolutionQueuedRun(id: 'run-1', reviewType: 'memory')],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('I will keep that in mind.'), findsOneWidget);
    expect(find.text('Reviewing'), findsOneWidget);
    expect(
      find.text('Learning from this chat in the background.'),
      findsNothing,
    );
    expect(find.byKey(const Key('send_message_button')), findsOneWidget);

    await events.close();
  });

  testWidgets('completed evolution shows message-level result', (tester) async {
    final events = StreamController<sdk.ChatEvent>();
    final fakeClient = FakeNapaxiChatClient(
      eventStream: events.stream,
      evolutionRuns: [
        sdk.EvolutionRun(
          id: 'run-1',
          agentId: sdk.NapaxiEngine.defaultAgentId,
          threadId: 'session-1',
          reviewType: 'memory',
          status: sdk.EvolutionRunStatus.completed,
          queuedAt: DateTime.now(),
          completedAt: DateTime.now(),
          autoAppliedCount: 1,
        ),
      ],
    );
    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'Remember this',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pump();
    await _pumpUntilSent(tester, fakeClient);

    events.add(const sdk.ResponseEvent(content: 'Done.'));
    await tester.pump();
    events.add(
      const sdk.EvolutionQueuedEvent(
        reviewTypes: ['memory'],
        runs: [sdk.EvolutionQueuedRun(id: 'run-1', reviewType: 'memory')],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Done.'), findsOneWidget);
    expect(find.text('Memory updated'), findsOneWidget);
    expect(find.byKey(const Key('send_message_button')), findsOneWidget);

    await events.close();
  });

  testWidgets('pending evolution chip opens skill organize page', (
    tester,
  ) async {
    final events = StreamController<sdk.ChatEvent>();
    final fakeClient = FakeNapaxiChatClient(
      eventStream: events.stream,
      evolutionRuns: [
        sdk.EvolutionRun(
          id: 'run-1',
          agentId: sdk.NapaxiEngine.defaultAgentId,
          threadId: 'session-1',
          reviewType: 'skill',
          status: sdk.EvolutionRunStatus.completed,
          queuedAt: DateTime.now(),
          completedAt: DateTime.now(),
          pendingCount: 1,
        ),
      ],
      pendingEvolution: [
        {
          'id': 'pending-1',
          'agent_id': sdk.NapaxiEngine.defaultAgentId,
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'action_type': 'SkillPatch',
          'reasoning': 'Tighten the research workflow.',
          'action': {
            'type': 'patch',
            'params': {
              'skill_name': 'research',
              'file_path': 'SKILL.md',
              'old_string': 'Use broad web searches.',
              'new_string': 'Use focused source-backed research.',
            },
          },
        },
      ],
    );
    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'Improve this skill',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pump();
    await _pumpUntilSent(tester, fakeClient);

    events.add(const sdk.ResponseEvent(content: 'I found a skill change.'));
    await tester.pump();
    events.add(
      const sdk.EvolutionQueuedEvent(
        reviewTypes: ['skill'],
        runs: [sdk.EvolutionQueuedRun(id: 'run-1', reviewType: 'skill')],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('1 suggestion pending'), findsOneWidget);

    await tester.tap(find.text('1 suggestion pending'));
    await tester.pumpAndSettle();

    // The pending chip now opens a "Pending Suggestions" sheet listing the
    // queued skill patch directly.
    expect(find.text('Pending Suggestions'), findsOneWidget);
    expect(find.text('Patch Skill'), findsOneWidget);
    expect(find.text('Tighten the research workflow.'), findsOneWidget);

    await tester.tap(find.text('Confirm'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(fakeClient.appliedPendingEvolutionId, 'pending-1');
    await tester.pumpAndSettle();
    // Once applied, the sheet reports there is nothing left to review.
    expect(find.text('No pending suggestions'), findsOneWidget);

    await events.close();
  });

  testWidgets('stops the active SDK chat from a background action', (
    tester,
  ) async {
    final cancelCompleter = Completer<void>();
    final events = StreamController<sdk.ChatEvent>(
      onCancel: () {
        if (!cancelCompleter.isCompleted) cancelCompleter.complete();
      },
    );
    final fakeClient = FakeNapaxiChatClient(eventStream: events.stream);
    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'Keep working in background',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pump();

    fakeClient.backgroundActions.add(
      const sdk.BackgroundActionEvent(action: sdk.BackgroundAction.stop),
    );
    await tester.pump();
    // Pump past the stop flow's 4s stream-drain grace window so the run
    // finishes; the fake's event stream never closes, so without advancing
    // the clock the cancel completer never fires and the await would hang.
    await tester.pump(const Duration(seconds: 5));
    await cancelCompleter.future.timeout(const Duration(seconds: 1));
    await tester.pump();

    expect(fakeClient.cancelCount, 1);
    expect(fakeClient.stopBackgroundServiceCount, 1);
    expect(fakeClient.canceledSession?.threadId, 'session-1');
    expect(find.text('Stopped.'), findsOneWidget);
    expect(find.byKey(const Key('send_message_button')), findsOneWidget);
  });

  testWidgets('warns when notification permission blocks background runs', (
    tester,
  ) async {
    final events = StreamController<sdk.ChatEvent>();
    final fakeClient = FakeNapaxiChatClient(
      eventStream: events.stream,
      backgroundPermissionGranted: false,
    );
    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'Run without notifications',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pump();

    expect(fakeClient.backgroundPermissionRequestCount, 1);
    expect(find.text('Notifications off'), findsNothing);
    expect(
      find.text(
        'Notifications are off. You may not receive completion alerts.',
      ),
      findsOneWidget,
    );

    await events.close();
  });

  testWidgets('records notification confirmation in the active trace', (
    tester,
  ) async {
    final events = StreamController<sdk.ChatEvent>();
    final fakeClient = FakeNapaxiChatClient(eventStream: events.stream);
    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'Ask me first',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pump();

    fakeClient.backgroundActions.add(
      const sdk.BackgroundActionEvent(
        action: sdk.BackgroundAction.hitlApprove,
        payload: 'Allow',
      ),
    );
    await tester.pump();

    expect(find.text('Confirmed from notification.'), findsOneWidget);

    await events.close();
  });

  testWidgets('renders ask human card and answers an option', (tester) async {
    final events = StreamController<sdk.ChatEvent>();
    final fakeClient = FakeNapaxiChatClient(eventStream: events.stream);
    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'Plan it',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pump();

    events.add(
      const sdk.AskingHumanEvent(
        requestId: 'human-1',
        question: 'Which option should I use?',
        options: ['A', 'B'],
        context: 'Need a preference before continuing.',
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('human_request_human-1')), findsOneWidget);
    expect(find.text('Which option should I use?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('human_option_human-1_A')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(fakeClient.answeredHumanRequestId, 'human-1');
    expect(fakeClient.answeredHumanResponse, 'A');
    expect(find.text('A'), findsWidgets);

    await events.close();
  });

  testWidgets(
    'renders final response after answering ask human following delta',
    (tester) async {
      final events = StreamController<sdk.ChatEvent>();
      final fakeClient = FakeNapaxiChatClient(eventStream: events.stream);
      await tester.pumpWidget(
        _testApp(chatClientFactory: () async => fakeClient),
      );
      await configureSingleModel(tester);

      await tester.enterText(
        find.byKey(const Key('chat_input_field')),
        'Plan it',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('send_message_button')));
      await tester.pump();

      events.add(const sdk.ResponseDeltaEvent(content: 'Let me ask first.'));
      await tester.pump();
      events.add(
        const sdk.AskingHumanEvent(
          requestId: 'human-1',
          question: 'Which option should I use?',
          options: ['A', 'B'],
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('human_option_human-1_A')));
      await tester.pump();
      events.add(
        const sdk.HumanResponseEvent(requestId: 'human-1', response: 'A'),
      );
      await tester.pump();
      events.add(const sdk.ResponseEvent(content: 'Done after answer.'));
      await tester.pump();

      expect(fakeClient.answeredHumanRequestId, 'human-1');
      expect(find.text('Done after answer.'), findsOneWidget);

      await events.close();
    },
  );

  testWidgets('injects a running message into the active SDK session', (
    tester,
  ) async {
    final events = StreamController<sdk.ChatEvent>();
    final fakeClient = FakeNapaxiChatClient(eventStream: events.stream);
    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.enterText(find.byKey(const Key('chat_input_field')), 'Start');
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'Use this extra context',
    );
    await tester.pump();
    expect(find.byKey(const Key('stop_message_button')), findsNothing);
    expect(find.byKey(const Key('send_message_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(fakeClient.injectedMessage, 'Use this extra context');
    expect(fakeClient.injectedSession?.threadId, 'session-1');
    expect(find.text('Use this extra context'), findsWidgets);
    expect(find.byKey(const Key('pending_interjection_queue')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('chat_message_list')),
        matching: find.text('Use this extra context'),
      ),
      findsNothing,
    );
    expect(
      tester.getSize(find.byKey(const Key('pending_interjection_queue'))).width,
      tester.getSize(find.byKey(const Key('chat_input_container'))).width,
    );

    events.add(
      const sdk.MessageInjectedEvent(content: 'Use this extra context'),
    );
    await tester.pump();
    events.add(const sdk.ResponseDeltaEvent(content: 'Continued below.'));
    await tester.pump();

    expect(find.byKey(const Key('pending_interjection_queue')), findsNothing);
    expect(find.text('Use this extra context'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('chat_message_list')),
        matching: find.text('Use this extra context'),
      ),
      findsOneWidget,
    );
    expect(find.text('Continued below.'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Continued below.')).dy,
      greaterThan(tester.getTopLeft(find.text('Use this extra context')).dy),
    );

    await events.close();
  });

  testWidgets('stop cancels a run and restores the latest queued message', (
    tester,
  ) async {
    final events = StreamController<sdk.ChatEvent>();
    final fakeClient = FakeNapaxiChatClient(eventStream: events.stream);
    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.enterText(find.byKey(const Key('chat_input_field')), 'Start');
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'Use this extra context',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const Key('pending_interjection_queue')), findsOneWidget);
    expect(find.byKey(const Key('stop_message_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('stop_message_button')));
    await tester.pump();
    await _pumpUntilBackgroundStopped(tester, fakeClient);

    expect(fakeClient.retractCount, 1);
    expect(fakeClient.retractedMessage, 'Use this extra context');
    expect(fakeClient.cancelCount, 1);
    expect(find.byKey(const Key('pending_interjection_queue')), findsNothing);
    expect(find.byKey(const Key('send_message_button')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('chat_input_field')))
          .controller
          ?.text,
      'Use this extra context',
    );

    unawaited(events.close());
  });

  testWidgets('sends a new turn after the visible answer has finished', (
    tester,
  ) async {
    final events = StreamController<sdk.ChatEvent>.broadcast();
    final fakeClient = FakeNapaxiChatClient(eventStream: events.stream);
    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.enterText(find.byKey(const Key('chat_input_field')), 'Start');
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pump();
    await _pumpUntilSent(tester, fakeClient);

    events.add(const sdk.ResponseDeltaEvent(content: 'Old task is done.'));
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'Next task',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pump();

    expect(fakeClient.injectedMessage, isNull);
    expect(fakeClient.sentMessages, ['Start']);
    expect(find.byKey(const Key('pending_interjection_queue')), findsOneWidget);
    expect(find.text('Next task'), findsOneWidget);

    await events.close();
    await tester.pump(const Duration(milliseconds: 100));

    expect(fakeClient.sentMessages, ['Start', 'Next task']);
    expect(find.text('Next task'), findsOneWidget);
  });

  testWidgets('stop cancels a run and restores a queued next turn', (
    tester,
  ) async {
    final events = StreamController<sdk.ChatEvent>();
    final fakeClient = FakeNapaxiChatClient(eventStream: events.stream);
    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.enterText(find.byKey(const Key('chat_input_field')), 'Start');
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pump();
    await _pumpUntilSent(tester, fakeClient);

    events.add(const sdk.ResponseDeltaEvent(content: 'Old task is ongoing.'));
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'Next task',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pump();

    expect(find.byKey(const Key('pending_interjection_queue')), findsOneWidget);

    await tester.tap(find.byKey(const Key('stop_message_button')));
    await tester.pump();
    await _pumpUntilBackgroundStopped(tester, fakeClient);
    await tester.pump(const Duration(milliseconds: 50));

    expect(fakeClient.retractCount, 0);
    expect(fakeClient.cancelCount, 1);
    expect(fakeClient.sentMessages, ['Start']);
    expect(find.byKey(const Key('pending_interjection_queue')), findsNothing);
    expect(find.byKey(const Key('send_message_button')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('chat_input_field')))
          .controller
          ?.text,
      'Next task',
    );

    unawaited(events.close());
  });

  testWidgets('runs two main sessions independently', (tester) async {
    final firstEvents = StreamController<sdk.ChatEvent>();
    final secondEvents = StreamController<sdk.ChatEvent>();
    final fakeClient = FakeNapaxiChatClient(
      eventStreamsByThreadId: {
        'session-1': firstEvents.stream,
        'session-2': secondEvents.stream,
      },
    );
    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.enterText(find.byKey(const Key('chat_input_field')), 'First');
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(const Key('session_history_button')));
    await pumpUntilFound(tester, find.byKey(const Key('new_session_button')));
    await tester.tap(find.byKey(const Key('new_session_button')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byKey(const Key('new_session_button')).evaluate().isEmpty) {
        break;
      }
    }

    await tester.enterText(find.byKey(const Key('chat_input_field')), 'Second');
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(fakeClient.sentThreadIds, ['session-1', 'session-2']);
    expect(find.byKey(const Key('run_activity_button')), findsNothing);
    expect(find.text('2 running'), findsNothing);

    await firstEvents.close();
    await secondEvents.close();
  });

  testWidgets('keeps live session content when switching away and back', (
    tester,
  ) async {
    final firstEvents = StreamController<sdk.ChatEvent>();
    final fakeClient = FakeNapaxiChatClient(
      eventStreamsByThreadId: {'session-1': firstEvents.stream},
    );
    final store = sdk.NapaxiConfigStore.memory();
    await store.saveProfile(
      const sdk.NapaxiConfigProfile(
        id: 'persisted',
        name: 'Persisted',
        provider: 'openai',
        model: 'saved-model',
        metadata: {
          'model_entries': [
            {
              'id': 'saved-model',
              'display_name': '',
              'capabilities': ['chat'],
            },
          ],
          'selected_model_by_capability': {'chat': 'saved-model'},
        },
      ),
      apiKey: 'sk-saved',
    );
    await store.saveSelection(
      const sdk.NapaxiConfigSelection(selectedProfileId: 'persisted'),
    );
    await tester.pumpWidget(
      _testApp(configStore: store, chatClientFactory: () async => fakeClient),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('chat_input_field')), 'First');
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pump();
    await _pumpUntilSent(tester, fakeClient);
    expect(fakeClient.sentThreadIds, ['session-1']);

    firstEvents.add(const sdk.ResponseDeltaEvent(content: 'Still working...'));
    await tester.pump();
    expect(find.text('Still working...'), findsOneWidget);

    await tester.tap(find.byKey(const Key('session_history_button')));
    await pumpUntilFound(tester, find.byKey(const Key('new_session_button')));
    await tester.tap(find.byKey(const Key('new_session_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const Key('session_history_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await pumpUntilFound(
      tester,
      find.byKey(const Key('session_tile_session-1')),
    );
    await tester.tap(find.byKey(const Key('session_tile_session-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Still working...'), findsOneWidget);
    expect(fakeClient.sentThreadIds, ['session-1']);

    await firstEvents.close();
  });

  testWidgets('saves a typed model as chat without pressing add', (
    tester,
  ) async {
    final fakeClient = FakeNapaxiChatClient();
    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );

    await openModelConfiguration(tester);
    await tester.tap(find.byKey(const Key('add_model_button')));
    await tester.pumpAndSettle();

    await enterVisibleText(tester, const Key('model_name_field'), 'Compat');
    await selectCustomProvider(tester);
    await enterVisibleText(tester, const Key('provider_field'), 'openai');
    await enterVisibleText(tester, const Key('model_field'), 'typed-model');
    await enterVisibleText(tester, const Key('api_key_field'), 'sk-typed');
    await tester.tap(find.byKey(const Key('save_model_button')));
    await tester.pumpAndSettle();
    await closeSettingsSheet(tester);

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'Hello typed model',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Fake SDK reply from typed-model: Hello typed model',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(fakeClient.configuredProfile?.model, 'typed-model');
  });

  testWidgets('adds model profiles and displays the selected model', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => FakeNapaxiChatClient()),
    );

    await openModelConfiguration(tester);

    expect(find.text('Basic configuration'), findsOneWidget);
    expect(find.text('Models'), findsOneWidget);
    expect(find.byKey(const Key('empty_model_list')), findsOneWidget);
    expect(find.byKey(const Key('save_config_primary_button')), findsNothing);

    await tester.tap(find.byKey(const Key('add_model_button')));
    await tester.pumpAndSettle();

    expect(find.text('Edit model'), findsOneWidget);
    await enterVisibleText(tester, const Key('model_name_field'), 'Primary');
    await selectCustomProvider(tester);
    await enterVisibleText(tester, const Key('provider_field'), 'openai');
    await enterVisibleText(tester, const Key('model_field'), 'napaxi-model');
    expect(
      await revealByKey(tester, const Key('capability_imageAnalysis')),
      findsOneWidget,
    );
    await tapVisible(tester, const Key('capability_imageAnalysis'));
    expect(
      find.byKey(const Key('capability_slot_imageAnalysis')),
      findsNothing,
    );
    await enterVisibleText(
      tester,
      const Key('base_url_field'),
      'https://api.example.com/v1',
    );
    await enterVisibleText(tester, const Key('api_key_field'), 'sk-napaxi');

    await tester.tap(find.byKey(const Key('save_model_button')));
    await tester.pumpAndSettle();

    expect(find.text('Primary'), findsWidgets);
    expect(find.text('openai · napaxi-model'), findsOneWidget);
    expect(
      find.byKey(const Key('capability_slot_imageAnalysis')),
      findsOneWidget,
    );
    expect(find.text('Video generation'), findsOneWidget);
    expect(find.text('Audio analysis'), findsOneWidget);
    await enterVisibleText(
      tester,
      const Key('system_prompt_field'),
      'Be concise.',
    );

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('current_model_label')), findsNothing);
    expect(find.text('Primary · napaxi-model'), findsNothing);
    expect(find.text('No model configured'), findsNothing);
  });

  testWidgets('uses provider options and picks a known model', (tester) async {
    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => FakeNapaxiChatClient()),
    );

    await openModelConfiguration(tester);
    await tester.tap(find.byKey(const Key('add_model_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('provider_preset_field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DeepSeek').last);
    await tester.pumpAndSettle();

    expect(find.text('DeepSeek'), findsWidgets);
    expect(find.text('https://api.deepseek.com/v1'), findsOneWidget);
    expect(find.text('deepseek-chat'), findsWidgets);

    await tester.tap(find.byKey(const Key('model_picker_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('deepseek-reasoner').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('save_model_button')));
    await tester.pumpAndSettle();

    expect(find.text('DeepSeek'), findsWidgets);
    expect(find.text('deepseek · deepseek-reasoner'), findsOneWidget);
  });

  testWidgets('clears a slot when a model capability is disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => FakeNapaxiChatClient()),
    );

    await openModelConfiguration(tester);
    await tester.tap(find.byKey(const Key('add_model_button')));
    await tester.pumpAndSettle();

    await enterVisibleText(tester, const Key('model_name_field'), 'Vision');
    await enterVisibleText(tester, const Key('model_field'), 'vision-model');
    await tapVisible(tester, const Key('capability_imageAnalysis'));

    await tester.tap(find.byKey(const Key('save_model_button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('capability_slot_imageAnalysis')),
      findsOneWidget,
    );

    await tester.tap(find.byIcon(Icons.edit_outlined).first);
    await tester.pumpAndSettle();

    await tapVisible(tester, const Key('capability_imageAnalysis'));

    await tester.tap(find.byKey(const Key('save_model_button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('capability_slot_imageAnalysis')),
      findsNothing,
    );
  });

  test('maps capability models to SDK media model fields', () {
    const profile = LlmModelProfile(
      id: 'profile',
      name: 'Profile',
      provider: 'openai',
      apiKey: 'sk-test',
      models: [
        ModelEntry(id: 'chat-model'),
        ModelEntry(
          id: 'vision-model',
          capabilities: [ModelCapability.imageAnalysis],
        ),
        ModelEntry(
          id: 'image-model',
          capabilities: [ModelCapability.imageGeneration],
        ),
        ModelEntry(
          id: 'video-model',
          capabilities: [ModelCapability.videoGeneration],
        ),
        ModelEntry(
          id: 'audio-model',
          capabilities: [ModelCapability.audioAnalysis],
        ),
      ],
      selectedModelByCapability: {
        ModelCapability.chat: 'chat-model',
        ModelCapability.imageAnalysis: 'vision-model',
        ModelCapability.imageGeneration: 'image-model',
        ModelCapability.videoGeneration: 'video-model',
        ModelCapability.audioAnalysis: 'audio-model',
      },
      nativeContextWindowTokens: 1000000,
      contextWindowTokens: 200000,
      responseReserveTokens: 8192,
      compactionModel: 'compact-model',
      preCompactionMemoryFlush: true,
    );

    final config = profile.toSdkConfig(
      responseLanguage: 'zh',
      userTimezone: 'Asia/Shanghai',
    );
    final json = jsonDecode(config.toJson()) as Map<String, Object?>;

    expect(config.model, 'chat-model');
    expect(json['response_language'], 'zh');
    expect(json['system_prompt'], '你是 napaxi，一个有帮助的 AI 助手。');
    expect(config.userTimezone, 'Asia/Shanghai');
    expect(config.imageAnalysisModel, 'vision-model');
    expect(config.imageModel, 'image-model');
    expect(config.videoModel, 'video-model');
    expect(config.audioModel, 'audio-model');
    expect(json['image_analysis_model'], 'vision-model');
    expect(json['image_model'], 'image-model');
    expect(json['video_model'], 'video-model');
    expect(json['audio_model'], 'audio-model');
    expect(json['user_timezone'], 'Asia/Shanghai');
    final contextEngine = json['context_engine'] as Map<String, Object?>;
    expect(contextEngine['native_context_window_tokens'], 1000000);
    expect(contextEngine['context_window_tokens'], 200000);
    expect(contextEngine['response_reserve_tokens'], 8192);
    expect(contextEngine['compaction_model'], 'compact-model');
    expect(contextEngine['pre_compaction_memory_flush'], true);
    final capabilities = json['capability_configs'] as Map<String, Object?>;
    expect(
      (capabilities['imageAnalysis'] as Map<String, Object?>)['model'],
      'vision-model',
    );
    expect(
      (capabilities['imageGeneration'] as Map<String, Object?>)['model'],
      'image-model',
    );
  });

  test('runtime profile preserves capability provider configs', () {
    const state = LlmConfigState(
      profiles: [
        LlmModelProfile(
          id: 'chat-profile',
          name: 'Chat',
          provider: 'openai',
          baseUrl: 'https://chat.example/v1',
          apiKey: 'chat-key',
          model: 'chat-model',
          contextWindowTokens: 200000,
        ),
        LlmModelProfile(
          id: 'vision-profile',
          name: 'Vision',
          provider: 'openai-compatible',
          baseUrl: 'https://vision.example/v1',
          apiKey: 'vision-key',
          models: [
            ModelEntry(
              id: 'vision-model',
              capabilities: [ModelCapability.imageAnalysis],
            ),
          ],
        ),
      ],
      selectedProfileId: 'chat-profile',
      selectedProfileIdByCapability: {
        ModelCapability.imageAnalysis: 'vision-profile',
      },
    );

    final config = state.selectedRuntimeProfile!.toSdkConfig();
    final json = jsonDecode(config.toJson()) as Map<String, Object?>;
    final capabilities = json['capability_configs'] as Map<String, Object?>;
    final vision = capabilities['imageAnalysis'] as Map<String, Object?>;

    expect(json['provider'], 'openai');
    expect(json['api_key'], 'chat-key');
    expect(json['response_language'], 'en');
    expect(
      (json['context_engine'] as Map<String, Object?>)['context_window_tokens'],
      200000,
    );
    expect(vision['provider'], 'openai_compatible');
    expect(vision['api_key'], 'vision-key');
    expect(vision['base_url'], 'https://vision.example/v1');
    expect(vision['model'], 'vision-model');
  });

  test('resolves agent model override from saved profiles', () {
    const defaultProfile = LlmModelProfile(
      id: 'default-profile',
      name: 'Default',
      provider: 'openai',
      apiKey: 'sk-default',
      model: 'default-model',
    );
    const agentProfile = LlmModelProfile(
      id: 'agent-profile',
      name: 'Agent',
      provider: 'openai',
      apiKey: 'sk-agent',
      model: 'agent-model',
    );
    const config = LlmConfigState(
      profiles: [defaultProfile, agentProfile],
      selectedProfileId: 'default-profile',
    );

    expect(config.selectedRuntimeProfile?.model, 'default-model');
    expect(
      config.runtimeProfileFor(chatProfileId: 'agent-profile')?.model,
      'agent-model',
    );
    expect(
      config.runtimeProfileFor(chatProfileId: 'missing-profile')?.model,
      'default-model',
    );
  });

  testWidgets('shows a local validation message before connection test', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => FakeNapaxiChatClient()),
    );

    await openModelConfiguration(tester);
    await tester.tap(find.byKey(const Key('add_model_button')));
    await tester.pumpAndSettle();

    final testConnectionButton = await revealByKey(
      tester,
      const Key('test_connection_button'),
    );
    await tester.tap(testConnectionButton);
    await tester.pump();

    // The local validation result is now surfaced through a floating SnackBar
    // rather than an inline status panel.
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Enter a Base URL before connecting.'), findsOneWidget);

    // Let the SnackBar auto-dismiss and the connection-result reset timer fire
    // so no timers outlive the test.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('selects between multiple configured models', (tester) async {
    final fakeClient = FakeNapaxiChatClient();
    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );

    await openModelConfiguration(tester);

    await tester.tap(find.byKey(const Key('add_model_button')));
    await tester.pumpAndSettle();
    await enterVisibleText(tester, const Key('model_name_field'), 'Alpha');
    await selectCustomProvider(tester);
    await enterVisibleText(tester, const Key('provider_field'), 'openai');
    await enterVisibleText(tester, const Key('model_field'), 'alpha-model');
    await enterVisibleText(tester, const Key('api_key_field'), 'sk-alpha');
    await tester.tap(find.byKey(const Key('save_model_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add_model_button')));
    await tester.pumpAndSettle();
    await enterVisibleText(tester, const Key('model_name_field'), 'Beta');
    await selectCustomProvider(tester);
    await enterVisibleText(tester, const Key('provider_field'), 'anthropic');
    await enterVisibleText(tester, const Key('model_field'), 'beta-model');
    await enterVisibleText(tester, const Key('api_key_field'), 'sk-beta');
    await tester.tap(find.byKey(const Key('save_model_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();
    await closeSettingsSheet(tester);

    expect(find.text('Alpha · alpha-model'), findsNothing);

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'Use selected model',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Fake SDK reply from alpha-model: Use selected model',
        findRichText: true,
      ),
      findsOneWidget,
    );
  });

  testWidgets('restores saved model configuration after rebuild', (
    tester,
  ) async {
    final store = sdk.NapaxiConfigStore.memory();

    await tester.pumpWidget(
      _testApp(
        configStore: store,
        chatClientFactory: () async => FakeNapaxiChatClient(),
      ),
    );
    await configureSingleModel(tester, name: 'Persisted', model: 'saved-model');
    await tester.pump(const Duration(milliseconds: 50));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      _testApp(
        configStore: store,
        chatClientFactory: () async => FakeNapaxiChatClient(),
      ),
    );
    await tester.pumpAndSettle();

    await openModelConfiguration(tester);

    expect(find.text('Persisted'), findsWidgets);
    expect(find.text('openai · saved-model'), findsOneWidget);
  });

  testWidgets('uses restored chat profile for SDK messages', (tester) async {
    final store = sdk.NapaxiConfigStore.memory();
    await store.saveProfile(
      const sdk.NapaxiConfigProfile(
        id: 'persisted',
        name: 'Persisted',
        provider: 'openai',
        model: 'saved-model',
        metadata: {
          'model_entries': [
            {
              'id': 'saved-model',
              'display_name': '',
              'capabilities': ['chat'],
            },
          ],
          'selected_model_by_capability': {'chat': 'saved-model'},
        },
      ),
      apiKey: 'sk-saved',
    );
    await store.saveSelection(
      const sdk.NapaxiConfigSelection(
        selectedProfileId: 'persisted',
        systemPrompt: 'Use the global prompt.',
        maxToolIterations: 77,
      ),
    );
    final fakeClient = FakeNapaxiChatClient();

    await tester.pumpWidget(
      _testApp(configStore: store, chatClientFactory: () async => fakeClient),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'Use persisted model',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pumpAndSettle();

    expect(fakeClient.configuredProfile?.model, 'saved-model');
    expect(
      fakeClient.configuredProfile?.systemPrompt,
      'Use the global prompt.',
    );
    expect(fakeClient.lastMaxIterations, 77);
    expect(
      find.text(
        'Fake SDK reply from saved-model: Use persisted model',
        findRichText: true,
      ),
      findsOneWidget,
    );
  });

  testWidgets('restores SDK session list and selected session history', (
    tester,
  ) async {
    final store = sdk.NapaxiConfigStore.memory();
    await store.saveProfile(
      const sdk.NapaxiConfigProfile(
        id: 'persisted',
        name: 'Persisted',
        provider: 'openai',
        model: 'saved-model',
        metadata: {
          'model_entries': [
            {
              'id': 'saved-model',
              'display_name': '',
              'capabilities': ['chat'],
            },
          ],
        },
      ),
      apiKey: 'sk-saved',
    );
    await store.saveSelection(
      const sdk.NapaxiConfigSelection(selectedProfileId: 'persisted'),
    );
    const sessionKey = sdk.SessionKey(
      channelType: 'app',
      accountId: 'flutter_demo',
      threadId: 'session-42',
    );
    final fakeClient = FakeNapaxiChatClient(
      sessions: const [
        sdk.SessionInfo(
          key: sessionKey,
          title: 'Saved chat',
          preview: 'Earlier answer',
          messageCount: 2,
          createdAt: '2026-05-12T10:00:00.000',
          updatedAt: '2026-05-12T10:01:00.000',
        ),
      ],
      historyByThreadId: const {
        'session-42': [
          sdk.ChatMessage(role: 'user', content: 'Earlier question'),
          sdk.ChatMessage(role: 'assistant', content: 'Earlier answer'),
        ],
      },
    );

    await tester.pumpWidget(
      _testApp(configStore: store, chatClientFactory: () async => fakeClient),
    );
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.text('Earlier question'));

    expect(find.text('Earlier question'), findsOneWidget);
    expect(find.text('Earlier answer'), findsOneWidget);

    await tester.tap(find.byKey(const Key('session_history_button')));
    await tester.pumpAndSettle();

    expect(find.text('Saved chat'), findsOneWidget);
  });

  testWidgets('restores SDK session history with the latest page first', (
    tester,
  ) async {
    final store = sdk.NapaxiConfigStore.memory();
    await store.saveProfile(
      const sdk.NapaxiConfigProfile(
        id: 'persisted',
        name: 'Persisted',
        provider: 'openai',
        model: 'saved-model',
        metadata: {
          'model_entries': [
            {
              'id': 'saved-model',
              'display_name': '',
              'capabilities': ['chat'],
            },
          ],
        },
      ),
      apiKey: 'sk-saved',
    );
    await store.saveSelection(
      const sdk.NapaxiConfigSelection(selectedProfileId: 'persisted'),
    );
    const sessionKey = sdk.SessionKey(
      channelType: 'app',
      accountId: 'flutter_demo',
      threadId: 'session-42',
    );
    final history = List.generate(
      100,
      (index) => sdk.ChatMessage(
        role: 'user',
        content: 'Question $index',
        createdAt:
            '2026-05-12T10:${(index ~/ 60).toString().padLeft(2, '0')}:${(index % 60).toString().padLeft(2, '0')}.000Z',
      ),
    );
    final fakeClient = FakeNapaxiChatClient(
      sessions: const [
        sdk.SessionInfo(
          key: sessionKey,
          title: 'Long saved chat',
          preview: 'Question 99',
          messageCount: 100,
          createdAt: '2026-05-12T10:00:00.000Z',
          updatedAt: '2026-05-12T10:01:39.000Z',
        ),
      ],
      historyByThreadId: {'session-42': history},
    );

    await tester.pumpWidget(
      _testApp(configStore: store, chatClientFactory: () async => fakeClient),
    );
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.text('Question 99'));

    expect(fakeClient.historyRequestCount, 0);
    expect(fakeClient.historyPageRequests, hasLength(1));
    expect(fakeClient.historyPageRequests.single.threadId, 'session-42');
    expect(fakeClient.historyPageRequests.single.before, isNull);
    expect(fakeClient.historyPageRequests.single.limit, 30);
    expect(find.text('Question 99'), findsOneWidget);
  });

  testWidgets('restores tool calls when switching to SDK session history', (
    tester,
  ) async {
    final store = sdk.NapaxiConfigStore.memory();
    await store.saveProfile(
      const sdk.NapaxiConfigProfile(
        id: 'persisted',
        name: 'Persisted',
        provider: 'openai',
        model: 'saved-model',
        metadata: {
          'model_entries': [
            {
              'id': 'saved-model',
              'display_name': '',
              'capabilities': ['chat'],
            },
          ],
        },
      ),
      apiKey: 'sk-saved',
    );
    await store.saveSelection(
      const sdk.NapaxiConfigSelection(selectedProfileId: 'persisted'),
    );
    const sessionKey = sdk.SessionKey(
      channelType: 'app',
      accountId: 'flutter_demo',
      threadId: 'session-42',
    );
    final fakeClient = FakeNapaxiChatClient(
      sessions: const [
        sdk.SessionInfo(
          key: sessionKey,
          title: 'Saved tool chat',
          preview: 'I found README.md.',
          messageCount: 4,
          createdAt: '2026-05-12T10:00:00.000',
          updatedAt: '2026-05-12T10:01:00.000',
        ),
      ],
      historyByThreadId: {
        'session-42': [
          const sdk.ChatMessage(
            role: 'user',
            content: 'List files',
            createdAt: '2026-05-12T10:00:00.000',
          ),
          const sdk.ChatMessage(
            role: 'thinking',
            content: 'Checking the workspace.',
            createdAt: '2026-05-12T10:00:01.000',
          ),
          const sdk.ChatMessage(
            role: 'reasoning',
            content: 'Checking the workspace.',
            createdAt: '2026-05-12T10:00:01.500',
          ),
          const sdk.ChatMessage(
            role: 'tool_calls',
            content:
                '[{"call_id":"call-1","name":"list_files","arguments":{"path":"/workspace"},"result":"{\\"files\\":[\\"README.md\\"]}"}]',
            createdAt: '2026-05-12T10:00:02.000',
            toolCalls: [
              sdk.ToolCallInfo(
                callId: 'call-1',
                name: 'list_files',
                arguments: {'path': '/workspace'},
                result: '{"files":["README.md"]}',
              ),
            ],
          ),
          const sdk.ChatMessage(
            role: 'assistant',
            content: 'I found README.md.',
            createdAt: '2026-05-12T10:00:03.000',
          ),
        ],
      },
    );

    await tester.pumpWidget(
      _testApp(configStore: store, chatClientFactory: () async => fakeClient),
    );
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.text('I found README.md.'));

    expect(find.text('I found README.md.'), findsOneWidget);
    expect(find.text('Thought through'), findsOneWidget);

    await tester.tap(find.text('Thought through'));
    await tester.pumpAndSettle();

    expect(find.text('Checking the workspace.'), findsOneWidget);
    expect(find.text('list_files'), findsOneWidget);

    await tester.tap(find.text('list_files'));
    await tester.pumpAndSettle();

    expect(find.text('Arguments'), findsOneWidget);
    expect(find.text('Result'), findsOneWidget);
    expect(find.textContaining('README.md'), findsWidgets);
  });

  testWidgets('restores segmented assistant history like live streaming', (
    tester,
  ) async {
    final store = sdk.NapaxiConfigStore.memory();
    await store.saveProfile(
      const sdk.NapaxiConfigProfile(
        id: 'persisted',
        name: 'Persisted',
        provider: 'openai',
        model: 'saved-model',
        metadata: {
          'model_entries': [
            {
              'id': 'saved-model',
              'display_name': '',
              'capabilities': ['chat'],
            },
          ],
        },
      ),
      apiKey: 'sk-saved',
    );
    await store.saveSelection(
      const sdk.NapaxiConfigSelection(selectedProfileId: 'persisted'),
    );
    const sessionKey = sdk.SessionKey(
      channelType: 'app',
      accountId: 'flutter_demo',
      threadId: 'session-42',
    );
    final fakeClient = FakeNapaxiChatClient(
      sessions: const [
        sdk.SessionInfo(
          key: sessionKey,
          title: 'Saved segmented chat',
          preview: 'Second answer.',
          messageCount: 5,
          createdAt: '2026-05-12T10:00:00.000',
          updatedAt: '2026-05-12T10:01:00.000',
        ),
      ],
      historyByThreadId: const {
        'session-42': [
          sdk.ChatMessage(role: 'user', content: 'Explain in parts'),
          sdk.ChatMessage(
            role: 'reasoning',
            content: 'Thinking about the first part.',
          ),
          sdk.ChatMessage(role: 'assistant', content: 'First answer.'),
          sdk.ChatMessage(
            role: 'reasoning',
            content: 'Thinking about the second part.',
          ),
          sdk.ChatMessage(role: 'assistant', content: 'Second answer.'),
        ],
      },
    );

    await tester.pumpWidget(
      _testApp(configStore: store, chatClientFactory: () async => fakeClient),
    );
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.text('Second answer.'));

    expect(find.text('First answer.'), findsOneWidget);
    expect(find.text('Second answer.'), findsOneWidget);
    expect(find.text('Thought through'), findsNWidgets(2));

    await tester.tap(find.text('Thought through').at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thought through').at(1));
    await tester.pumpAndSettle();

    expect(find.text('Thinking about the first part.'), findsOneWidget);
    expect(find.text('Thinking about the second part.'), findsOneWidget);
  });

  testWidgets('browses memory files by folder level', (tester) async {
    final fakeClient = FakeNapaxiChatClient(
      memoryFilesByDirectory: {
        '': const [
          sdk.WorkspaceEntry(path: 'projects', isDirectory: true),
          sdk.WorkspaceEntry(path: 'MEMORY.md'),
        ],
        'projects': const [sdk.WorkspaceEntry(path: 'projects/alpha.md')],
      },
      memoryFilesByPath: const {
        'projects/alpha.md': sdk.WorkspaceFile(
          path: 'projects/alpha.md',
          content: 'Project note',
        ),
      },
    );

    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.tap(find.byKey(const Key('session_history_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('files_menu_item')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Memory'));
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.text('projects'));

    expect(find.text('projects'), findsWidgets);
    expect(find.text('MEMORY.md'), findsOneWidget);
    expect(find.text('alpha.md'), findsNothing);

    await tester.tap(find.text('projects').first);
    await tester.pumpAndSettle();

    expect(find.text('alpha.md'), findsOneWidget);
    expect(find.text('MEMORY.md'), findsNothing);
  });

  testWidgets('shows journal days outside the memory tab', (tester) async {
    final fakeClient = FakeNapaxiChatClient(
      memoryFilesByDirectory: {
        '': const [
          sdk.WorkspaceEntry(path: 'daily', isDirectory: true),
          sdk.WorkspaceEntry(path: 'MEMORY.md'),
        ],
      },
      journalDays: const [
        sdk.JournalDay(
          date: '2026-05-13',
          path: 'daily/2026-05-13.md',
          legacy: true,
          turnCount: 1,
        ),
      ],
      journalRecordsByDate: const {
        '2026-05-13': [
          sdk.JournalTurnRecord(
            turnId: 'legacy-daily-2026-05-13',
            user: 'Legacy daily note',
            kind: 'legacy_daily',
          ),
        ],
      },
    );

    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.tap(find.byKey(const Key('session_history_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('files_menu_item')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Memory'));
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.text('MEMORY.md'));

    expect(find.text('daily'), findsNothing);

    await tester.tap(find.text('Journal'));
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.text('2026-05-13 (legacy)'));
    await tester.tap(find.text('2026-05-13 (legacy)'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Legacy daily note'), findsOneWidget);
  });

  testWidgets('keeps recall out of the files tabs', (tester) async {
    final fakeClient = FakeNapaxiChatClient(
      memoryFilesByDirectory: {
        '': const [sdk.WorkspaceEntry(path: 'MEMORY.md')],
      },
    );

    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.tap(find.byKey(const Key('session_history_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('files_menu_item')));
    await tester.pumpAndSettle();

    expect(find.text('Workspace'), findsOneWidget);
    expect(find.text('Memory'), findsOneWidget);
    expect(find.text('Journal'), findsOneWidget);
    expect(find.text('Recall'), findsNothing);
  });

  testWidgets('does not expose paths for unsupported workspace previews', (
    tester,
  ) async {
    final fakeClient = FakeNapaxiChatClient(
      workspaceFiles: [
        sdk.WorkspaceFileInfo(
          name: 'archive.bin',
          sandboxPath: '/workspace/archive.bin',
          realPath: '/private/raw/archive.bin',
          mimeType: 'application/octet-stream',
          isDirectory: false,
          sizeBytes: 32,
          modified: DateTime(2026, 5, 13, 10),
        ),
      ],
    );

    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.tap(find.byKey(const Key('session_history_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('files_menu_item')));
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.text('archive.bin'));

    await tester.tap(find.text('archive.bin'));
    await tester.pumpAndSettle();

    expect(find.text('Preview unavailable'), findsOneWidget);
    expect(find.textContaining('/workspace'), findsNothing);
    expect(find.textContaining('/private/raw'), findsNothing);
  });

  testWidgets('returns to the side menu when backing out of files', (
    tester,
  ) async {
    final fakeClient = FakeNapaxiChatClient(
      memoryFilesByDirectory: {
        '': const [sdk.WorkspaceEntry(path: 'MEMORY.md')],
      },
    );

    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.tap(find.byKey(const Key('session_history_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('files_menu_item')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Memory'));
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.text('MEMORY.md'));

    expect(find.text('Files'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('files_menu_item')), findsOneWidget);
    expect(find.byKey(const Key('skills_menu_item')), findsOneWidget);
    expect(find.text('MEMORY.md'), findsNothing);
  });

  testWidgets('opens localized scenarios from settings', (tester) async {
    const generalScenario = sdk.NapaxiScenarioPack(
      id: 'napaxi.scenario.general',
      version: '1',
      label: 'General',
      description: 'General scenario.',
      risk: 'medium',
      activation: 'manual',
      executionPlanes: ['core'],
      uiSurfaces: ['chat'],
      memoryScopes: ['workspace', 'session'],
    );
    const scenario = sdk.NapaxiScenarioPack(
      id: 'napaxi.scenario.mobile_development',
      version: '1',
      label: 'Developer Workbench',
      description: 'Privileged mobile development scenario.',
      risk: 'critical',
      activation: 'host_policy',
      executionPlanes: ['core', 'host_bridge'],
      uiSurfaces: ['chat', 'terminal_panel'],
      memoryScopes: ['project', 'workspace'],
    );
    const hiddenScenario = sdk.NapaxiScenarioPack(
      id: 'napaxi.scenario.experimental_hidden',
      version: '1',
      label: 'Experimental Hidden Scenario',
      description: 'Should stay hidden in the demo scenario anchors.',
      risk: 'high',
      activation: 'host_policy',
    );
    const status = sdk.NapaxiScenarioStatus(
      definition: scenario,
      registered: true,
      available: false,
      enabled: false,
      missingRequiredCapabilities: ['napaxi.tool.git'],
    );
    const resolution = sdk.NapaxiScenarioResolution(
      status: status,
      activationPlan: sdk.NapaxiScenarioActivationPlan(
        enabledCapabilities: ['napaxi.tool.file'],
        hostRequiredCapabilities: ['napaxi.service.developer_workbench'],
        remoteRequiredCapabilities: ['napaxi.tool.shell_remote'],
        policyRequiredCapabilities: ['napaxi.policy.approval'],
      ),
    );
    final fakeClient = FakeNapaxiChatClient(
      scenarioPacks: const [generalScenario, scenario, hiddenScenario],
      scenarioStatuses: const [status],
      scenarioResolution: resolution,
    );
    final preferencesStore = MemoryDemoPreferencesStore();
    await preferencesStore.saveLanguage(AppLanguage.chinese);

    await tester.pumpWidget(
      _testApp(
        chatClientFactory: () async => fakeClient,
        preferencesStore: preferencesStore,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('scenarios_button')), findsNothing);

    await tester.tap(find.byKey(const Key('session_history_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('files_menu_item')), findsOneWidget);
    expect(find.byKey(const Key('scenarios_menu_item')), findsNothing);
    expect(find.byKey(const Key('skills_menu_item')), findsOneWidget);
    expect(find.text('场景'), findsNothing);

    await tester.tap(find.byKey(const Key('settings_menu_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings_basic_item')), findsOneWidget);
    expect(find.byKey(const Key('settings_scenarios_item')), findsOneWidget);
    expect(find.byKey(const Key('settings_engines_item')), findsNothing);
    expect(find.byKey(const Key('settings_about_item')), findsOneWidget);
    expect(find.text('当前：通用'), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings_scenarios_item')));
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.text('开发工作台'));

    expect(find.text('当前场景：通用'), findsOneWidget);
    expect(find.text('开发工作台'), findsOneWidget);
    expect(find.text('日常对话、文件、记忆和常用技能。'), findsOneWidget);
    expect(find.text('Android 项目、Git、构建和环境配置。'), findsNothing);

    await tester.tap(find.text('开发工作台'));
    await tester.pumpAndSettle();

    expect(find.text('Android 项目、Git、构建和环境配置。'), findsOneWidget);
    expect(find.text('可以切换使用'), findsOneWidget);
    expect(find.text('激活计划'), findsNothing);
    expect(find.text('关键'), findsNothing);
    expect(find.text('宿主策略'), findsNothing);
    expect(find.text('宿主桥接'), findsNothing);
    expect(find.byKey(const Key('scenario_apply_button')), findsOneWidget);
    expect(find.text('Experimental Hidden Scenario'), findsNothing);
    expect(find.text('Scenarios'), findsNothing);
    expect(find.text('Developer Workbench'), findsNothing);

    await tester.tap(find.byKey(const Key('scenario_apply_button')));
    await tester.pumpAndSettle();

    expect(fakeClient.appliedCapabilitySelection, isNotNull);
    expect(
      fakeClient.appliedCapabilitySelection!.config['scenario_id'],
      'napaxi.scenario.mobile_development',
    );
    expect(
      fakeClient.appliedCapabilitySelection!.enabledCapabilities,
      contains('napaxi.tool.git'),
    );
    expect(
      fakeClient.appliedCapabilitySelection!.enabledCapabilities,
      contains('napaxi.tool.shell_remote'),
    );
    // After applying, the active scenario label is reflected in more than one
    // surface (the scenarios page and the settings entry).
    expect(find.text('当前场景：开发工作台'), findsWidgets);

    await tester.tap(find.byType(BackButton).first);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings_engines_item')), findsOneWidget);
  });

  testWidgets('mobile developer scenario uses engine runtime scope', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'napaxi_demo.active_scenario.v1': 'napaxi.scenario.mobile_development',
    });
    final store = sdk.NapaxiConfigStore.memory();
    await store.saveProfile(
      const sdk.NapaxiConfigProfile(
        id: 'dev-model',
        name: 'Dev model',
        provider: 'openai',
        model: 'dev-chat',
      ),
      apiKey: 'sk-dev',
    );
    await store.saveSelection(
      const sdk.NapaxiConfigSelection(selectedProfileId: 'dev-model'),
    );
    const sessionKey = sdk.SessionKey(
      channelType: 'app',
      accountId: 'mobile_development',
      threadId: 'dev-session',
    );
    final fakeClient = FakeNapaxiChatClient(
      sessions: const [
        sdk.SessionInfo(
          key: sessionKey,
          title: 'Dev workspace',
          preview: 'Project context',
          messageCount: 1,
          createdAt: '2026-06-10T08:00:00.000',
          updatedAt: '2026-06-10T08:01:00.000',
        ),
      ],
      skills: const [sdk.SkillInfo(name: 'git-tools')],
    );

    await tester.pumpWidget(
      _testApp(configStore: store, chatClientFactory: () async => fakeClient),
    );
    await pumpUntilFound(
      tester,
      find.byKey(const Key('engine_selector_button')),
    );

    expect(find.byKey(const Key('engine_selector_button')), findsOneWidget);
    expect(find.byKey(const Key('agent_selector_button')), findsNothing);
    expect(find.text('napaxi'), findsOneWidget);
    expect(find.text('Development engine: Napaxi'), findsNothing);

    for (var i = 0; i < 20; i++) {
      if (fakeClient.lastListSessionsAgentId != null) break;
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(fakeClient.lastListSessionsAgentId, 'engine.napaxi');

    await tester.tap(find.byKey(const Key('engine_selector_button')));
    await tester.pumpAndSettle();
    expect(find.text('CC'), findsOneWidget);
    expect(find.text('Codex'), findsOneWidget);
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('session_history_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('skills_menu_item')));
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.text('git-tools'));

    expect(fakeClient.lastSkillAgentId, 'engine.napaxi');
  });

  testWidgets('hides repository workbench outside contributed scenarios', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'napaxi_demo.active_scenario.v1': 'napaxi.scenario.general',
    });
    const mobileScenario = sdk.NapaxiScenarioPack(
      id: 'napaxi.scenario.mobile_development',
      version: '1',
      label: 'Developer Workbench',
      description: 'Mobile development scenario.',
      risk: 'critical',
      activation: 'host_policy',
      uiContributions: [
        sdk.NapaxiScenarioUiContribution(
          id: 'ui.repo_workbench',
          capabilityId: 'napaxi.tool.git',
          placement: 'left_menu',
          title: 'Projects',
          icon: 'folder_git',
          renderer: 'repo_workbench',
        ),
      ],
    );
    final fakeClient = FakeNapaxiChatClient(
      scenarioPacks: const [mobileScenario],
    );

    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.tap(find.byKey(const Key('session_history_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('files_menu_item')), findsOneWidget);
    expect(find.byKey(const Key('repo_workbench_menu_item')), findsNothing);
    expect(find.byKey(const Key('environment_menu_item')), findsNothing);
  });

  testWidgets('opens environment tool list in mobile developer scenario', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'napaxi_demo.active_scenario.v1': 'napaxi.scenario.mobile_development',
    });
    // The environment panel marks a preset skill as "已内置" when the SDK reports
    // it installed, so seed both mobile-dev preset skills.
    final fakeClient = FakeNapaxiChatClient(
      skills: const [
        sdk.SkillInfo(name: 'android-project-template'),
        sdk.SkillInfo(name: 'android-apk-build'),
      ],
    );

    await tester.pumpWidget(
      _testApp(
        chatClientFactory: () async => fakeClient,
        language: AppLanguage.chinese,
      ),
    );
    await configureSingleModel(tester);

    await tester.tap(find.byKey(const Key('session_history_button')));
    await tester.pumpAndSettle();
    await pumpUntilFound(
      tester,
      find.byKey(const Key('environment_menu_item')),
    );

    await tester.tap(find.byKey(const Key('environment_menu_item')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('environment_page')), findsOneWidget);
    expect(find.text('预设技能'), findsOneWidget);
    expect(find.text('Android Project Template'), findsOneWidget);
    expect(find.text('Android APK Build'), findsOneWidget);
    expect(find.text('工具清单'), findsOneWidget);

    expect(
      find.byKey(const Key('preset_skill_install_android-project-template')),
      findsNothing,
    );
    expect(find.text('已内置'), findsNWidgets(2));
    expect(
      find.byKey(const Key('environment_add_tool_button')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('environment_check_button')), findsOneWidget);

    // The tool list lives in a lazily-rendered scroll view. The overview card
    // (check button) and preset skills sit at the top; the tool tiles follow.
    final envScrollable = find
        .descendant(
          of: find.byKey(const Key('environment_page')),
          matching: find.byType(Scrollable),
        )
        .first;
    Future<void> scrollToText(String text, {double delta = 240}) async {
      await tester.scrollUntilVisible(
        find.text(text),
        delta,
        scrollable: envScrollable,
      );
      await tester.pumpAndSettle();
    }

    await scrollToText('OpenJDK');
    expect(find.text('OpenJDK'), findsOneWidget);
    await scrollToText('Android build-tools');
    expect(find.text('Android build-tools'), findsOneWidget);
    await scrollToText('aapt2');
    expect(find.text('aapt2'), findsOneWidget);
    expect(find.text('keytool'), findsNothing);

    // Jump back to the top to reach the overview card's self-check button.
    final scrollable = tester.widget<Scrollable>(envScrollable);
    scrollable.controller!.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('environment_check_button')));
    await tester.pumpAndSettle();

    // The self-check result shows both inline and in a SnackBar.
    expect(find.textContaining('自检完成'), findsWidgets);
    expect(find.textContaining('个工具缺失'), findsWidgets);

    // SnackBars are queued by ScaffoldMessenger; clear the self-check one so the
    // later install-failure SnackBar can surface.
    ScaffoldMessenger.of(
      tester.element(find.byKey(const Key('environment_page'))),
    ).clearSnackBars();
    await tester.pumpAndSettle();

    await scrollToText('OpenJDK');
    await tester.tap(find.byKey(const Key('environment_install_openjdk')));
    await tester.pumpAndSettle();

    // Installing surfaces a transient "installing" SnackBar first; drain the
    // queue so the failure SnackBar (and inline message) can show.
    for (
      var i = 0;
      i < 6 && find.textContaining('OpenJDK 安装失败').evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    }

    // The install-failure feedback surfaces both as the tool's status pill and
    // in a SnackBar / inline message.
    expect(find.textContaining('OpenJDK 安装失败'), findsWidgets);
  });

  testWidgets('opens repository workbench from mobile scenario contribution', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'napaxi_demo.active_scenario.v1': 'napaxi.scenario.mobile_development',
    });
    const mobileScenario = sdk.NapaxiScenarioPack(
      id: 'napaxi.scenario.mobile_development',
      version: '1',
      label: 'Developer Workbench',
      description: 'Mobile development scenario.',
      risk: 'critical',
      activation: 'host_policy',
      uiContributions: [
        sdk.NapaxiScenarioUiContribution(
          id: 'ui.repo_workbench',
          capabilityId: 'napaxi.tool.git',
          placement: 'left_menu',
          title: 'Projects',
          icon: 'folder_git',
          renderer: 'repo_workbench',
        ),
      ],
    );
    final fakeClient = FakeNapaxiChatClient(
      scenarioPacks: const [mobileScenario],
      gitRepositories: [
        DemoRepositoryInfo(
          name: 'openclaw',
          directory: 'openclaw',
          displayDirectory: 'openclaw',
          absolutePath: '/tmp/git_repos/openclaw',
          modified: DateTime(2026, 1, 2, 3, 4),
        ),
        DemoRepositoryInfo(
          name: 'napaxi',
          directory: 'napaxi',
          displayDirectory: 'napaxi',
          absolutePath: '/tmp/git_repos/napaxi',
          modified: DateTime(2026, 1, 3, 3, 4),
          locationLabel: 'Git tool',
        ),
      ],
      gitStatuses: const {
        'openclaw': DemoGitRepositoryStatus(
          success: true,
          branch: 'main',
          changedFiles: ['lib/main.dart'],
        ),
        'napaxi': DemoGitRepositoryStatus(
          success: true,
          branch: 'dev',
          changedFiles: ['README.md', 'pubspec.yaml'],
        ),
      },
      gitBranches: const {
        'openclaw': [
          DemoGitBranchInfo(
            name: 'main',
            remote: false,
            current: true,
            upstream: 'origin/main',
          ),
          DemoGitBranchInfo(name: 'feature', remote: false, current: false),
          DemoGitBranchInfo(
            name: 'origin/feature',
            remote: true,
            current: false,
          ),
        ],
        'napaxi': [DemoGitBranchInfo(name: 'dev', remote: false, current: true)],
      },
      gitRemotes: const {
        'openclaw': [
          DemoGitRemoteInfo(
            name: 'origin',
            fetchUrl: 'https://example.com/openclaw.git',
            pushUrl: 'https://example.com/openclaw.git',
          ),
        ],
      },
      gitRepositoryChildren: {
        'openclaw:': [
          DemoRepositoryFileItem(
            name: 'lib',
            relativePath: 'lib',
            absolutePath: '/tmp/git_repos/openclaw/lib',
            isDirectory: true,
            modified: DateTime(2026, 1, 2, 3, 5),
          ),
        ],
        'openclaw:lib': [
          DemoRepositoryFileItem(
            name: 'main.dart',
            relativePath: 'lib/main.dart',
            absolutePath: '/tmp/git_repos/openclaw/lib/main.dart',
            isDirectory: false,
            sizeBytes: 120,
            modified: DateTime(2026, 1, 2, 3, 6),
            mimeType: 'text/plain',
          ),
        ],
        'napaxi:': [
          DemoRepositoryFileItem(
            name: 'README.md',
            relativePath: 'README.md',
            absolutePath: '/tmp/git_repos/napaxi/README.md',
            isDirectory: false,
            sizeBytes: 256,
            modified: DateTime(2026, 1, 3, 3, 6),
            mimeType: 'text/plain',
          ),
        ],
      },
    );

    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.tap(find.byKey(const Key('session_history_button')));
    await tester.pumpAndSettle();
    await pumpUntilFound(
      tester,
      find.byKey(const Key('repo_workbench_menu_item')),
    );

    await tester.tap(find.byKey(const Key('repo_workbench_menu_item')));
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.text('openclaw'));

    expect(find.text('Branch: main'), findsOneWidget);
    expect(find.text('1 changed files'), findsOneWidget);
    expect(find.byKey(const Key('project_selector_button')), findsOneWidget);
    expect(find.byKey(const Key('git_branch_selector_button')), findsOneWidget);
    expect(find.byKey(const Key('git_remote_origin')), findsOneWidget);
    expect(
      fakeClient.gitRepositoryChildrenRequests,
      contains(
        isA<FakeGitRepositoryChildrenRequest>()
            .having((request) => request.directory, 'directory', 'openclaw')
            .having((request) => request.subdir, 'subdir', '')
            .having((request) => request.query, 'query', ''),
      ),
    );

    await tester.tap(find.byKey(const Key('git_branch_selector_button')));
    await tester.pumpAndSettle();
    await pumpUntilFound(
      tester,
      find.byKey(const Key('git_branch_search_field')),
    );
    await tester.enterText(
      find.byKey(const Key('git_branch_search_field')),
      'feature',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('git_branch_feature')));
    await tester.pumpAndSettle();

    expect(fakeClient.switchedGitDirectory, 'openclaw');
    expect(fakeClient.switchedGitBranch, 'feature');
    expect(fakeClient.switchedGitBranchWasRemote, false);
    expect(fakeClient.switchedGitBranchAllowedDirty, false);

    await tester.tap(find.text('lib'));
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.text('main.dart'));

    expect(
      fakeClient.gitRepositoryChildrenRequests,
      contains(
        isA<FakeGitRepositoryChildrenRequest>()
            .having((request) => request.directory, 'directory', 'openclaw')
            .having((request) => request.subdir, 'subdir', 'lib')
            .having((request) => request.query, 'query', ''),
      ),
    );

    await tester.tap(find.byKey(const Key('project_selector_button')));
    await tester.pumpAndSettle();
    await pumpUntilFound(
      tester,
      find.byKey(const Key('project_picker_search_field')),
    );
    await tester.enterText(
      find.byKey(const Key('project_picker_search_field')),
      'napaxi',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('project_picker_item_napaxi')));
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.text('Branch: dev'));

    expect(find.text('2 changed files'), findsOneWidget);
    expect(find.byKey(const Key('repo_file_README.md')), findsOneWidget);
    expect(
      fakeClient.gitRepositoryChildrenRequests,
      contains(
        isA<FakeGitRepositoryChildrenRequest>()
            .having((request) => request.directory, 'directory', 'napaxi')
            .having((request) => request.subdir, 'subdir', '')
            .having((request) => request.query, 'query', ''),
      ),
    );
  });

  testWidgets('repo workbench refresh drops missing repository selection', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'napaxi_demo.active_scenario.v1': 'napaxi.scenario.mobile_development',
    });
    const mobileScenario = sdk.NapaxiScenarioPack(
      id: 'napaxi.scenario.mobile_development',
      version: '1',
      label: 'Developer Workbench',
      description: 'Mobile development scenario.',
      risk: 'critical',
      activation: 'host_policy',
      uiContributions: [
        sdk.NapaxiScenarioUiContribution(
          id: 'ui.repo_workbench',
          capabilityId: 'napaxi.tool.git',
          placement: 'left_menu',
          title: 'Projects',
          icon: 'folder_git',
          renderer: 'repo_workbench',
        ),
      ],
    );
    final fakeClient = FakeNapaxiChatClient(
      scenarioPacks: const [mobileScenario],
      gitRepositories: [
        DemoRepositoryInfo(
          name: 'openclaw',
          directory: 'openclaw',
          displayDirectory: 'openclaw',
          absolutePath: '/tmp/git_repos/openclaw',
          modified: DateTime(2026, 1, 2, 3, 4),
        ),
        DemoRepositoryInfo(
          name: 'fscan',
          directory: 'codex/fscan',
          displayDirectory: 'codex/fscan',
          absolutePath: '/tmp/git_repos/codex/fscan',
          modified: DateTime(2026, 1, 1, 3, 4),
        ),
      ],
      gitStatuses: const {
        'openclaw': DemoGitRepositoryStatus(
          success: true,
          branch: 'main',
          changedFiles: [],
        ),
        'codex/fscan': DemoGitRepositoryStatus(
          success: true,
          branch: 'feature',
          changedFiles: [],
        ),
      },
    );

    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.tap(find.byKey(const Key('session_history_button')));
    await tester.pumpAndSettle();
    await pumpUntilFound(
      tester,
      find.byKey(const Key('repo_workbench_menu_item')),
    );
    await tester.tap(find.byKey(const Key('repo_workbench_menu_item')));
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.text('fscan'));

    await tester.tap(find.byKey(const Key('project_selector_button')));
    await tester.pumpAndSettle();
    await pumpUntilFound(
      tester,
      find.byKey(const Key('project_picker_search_field')),
    );
    await tester.enterText(
      find.byKey(const Key('project_picker_search_field')),
      'fscan',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('project_picker_item_codex/fscan')));
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.text('Branch: feature'));

    fakeClient.setGitRepositories([
      DemoRepositoryInfo(
        name: 'openclaw',
        directory: 'openclaw',
        displayDirectory: 'openclaw',
        absolutePath: '/tmp/git_repos/openclaw',
        modified: DateTime(2026, 1, 2, 3, 4),
      ),
    ]);

    await tester.tap(find.byKey(const Key('repo_workbench_status_refresh')));
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.text('Branch: main'));

    expect(find.text('fscan'), findsNothing);
    expect(find.byKey(const Key('project_selector_button')), findsOneWidget);
    expect(find.text('Branch: main'), findsOneWidget);
  });

  testWidgets('selects files with long press actions', (tester) async {
    final fakeClient = FakeNapaxiChatClient(
      memoryFilesByDirectory: {
        '': const [
          sdk.WorkspaceEntry(path: 'MEMORY.md'),
          sdk.WorkspaceEntry(path: 'notes.md'),
        ],
      },
    );

    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.tap(find.byKey(const Key('session_history_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('files_menu_item')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Memory'));
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.text('notes.md'));

    expect(find.byIcon(Icons.more_vert_rounded), findsNothing);

    await tester.longPress(find.text('notes.md'));
    await tester.pumpAndSettle();

    expect(find.text('1 selected'), findsOneWidget);
    expect(find.byTooltip('Save copy'), findsAtLeastNWidgets(1));
    expect(find.byTooltip('Send'), findsAtLeastNWidgets(1));
    expect(find.byTooltip('Delete'), findsAtLeastNWidgets(1));
  });

  testWidgets('opens skills from the side menu and removes a skill', (
    tester,
  ) async {
    final fakeClient = FakeNapaxiChatClient(
      skills: const [
        sdk.SkillInfo(
          name: 'research',
          version: '1.0.0',
          description: 'Finds and summarizes source material.',
          source: 'local',
          tags: ['search', 'summary'],
          keywords: ['papers'],
          promptContent: 'Use reliable sources.',
          supportFiles: ['notes.md', 'scripts/run.sh'],
          lifecycle: sdk.SkillLifecycleSummary(useCount: 2, viewCount: 1),
        ),
      ],
      skillStatusReport: const sdk.SkillStatusReport(
        entries: [
          sdk.SkillStatusEntry(
            name: 'research',
            description: 'Finds and summarizes source material.',
            status: 'ready',
            eligible: true,
            metadata: sdk.SkillOpenClawMetadata(skillKey: 'local:research'),
          ),
        ],
        ready: 1,
      ),
      skillSupportFiles: const {
        'research/notes.md': 'Prefer primary sources.',
        'research/scripts/run.sh': '#!/bin/sh\necho research',
      },
      catalogPackages: const [
        sdk.CatalogSkillInfo(
          slug: 'writer',
          name: 'writer',
          description: 'Drafts polished copy.',
          version: '0.2.0',
          stars: 12,
        ),
      ],
    );

    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.tap(find.byKey(const Key('session_history_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('files_menu_item')), findsOneWidget);
    expect(find.byKey(const Key('skills_menu_item')), findsOneWidget);

    await tester.tap(find.byKey(const Key('skills_menu_item')));
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.text('research'));

    expect(find.text('Skills'), findsOneWidget);
    expect(find.text('Installed'), findsWidgets);
    expect(find.text('Store'), findsOneWidget);
    expect(find.text('Finds and summarizes source material.'), findsOneWidget);
    expect(find.text('search'), findsOneWidget);
    expect(find.text('Ready'), findsWidgets);
    expect(find.text('Needs Attention'), findsNothing);
    expect(find.text('local'), findsNothing);
    expect(find.text('Trusted'), findsNothing);
    expect(find.text('Sources'), findsNothing);
    expect(find.text('Snapshots'), findsNothing);
    expect(find.text('Secrets'), findsNothing);
    expect(find.text('Fixes'), findsNothing);
    expect(fakeClient.lastSkillAgentId, sdk.NapaxiEngine.defaultAgentId);

    await tester.tap(find.text('research').first);
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.text('Overview'));

    expect(fakeClient.viewedSkillName, 'research');
    expect(find.text('v1.0.0'), findsWidgets);
    expect(find.text('Enablement'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Files')).dy,
      greaterThan(tester.getTopLeft(find.text('Enablement')).dy),
    );
    expect(find.text('Setup needed'), findsNothing);
    expect(find.text('Diagnostics'), findsNothing);
    expect(find.text('papers'), findsOneWidget);
    expect(find.text('2 uses · 1 views · 0 patches'), findsOneWidget);
    expect(find.text('3 files'), findsOneWidget);
    expect(find.text('SKILL.md'), findsOneWidget);
    expect(find.text('notes.md'), findsOneWidget);
    expect(find.text('scripts'), findsOneWidget);
    expect(find.text('run.sh'), findsOneWidget);
    expect(find.byKey(const Key('toggle_skill_research')), findsOneWidget);
    expect(find.text('Enable skill'), findsNothing);
    expect(find.text('Ready to use.'), findsNothing);

    // The skill prompt is now surfaced as a SKILL.md file; its body shows in
    // the file preview sheet rather than inline on the detail page.
    await tester.tap(find.text('SKILL.md'));
    await tester.pumpAndSettle();
    expect(find.text('Use reliable sources.'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded).last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('toggle_skill_research')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK').last);
    await tester.pump(const Duration(milliseconds: 200));
    expect(fakeClient.toggledSkillName, 'research');
    expect(fakeClient.toggledSkillEnabled, isFalse);

    await tester.tap(find.text('notes.md'));
    await tester.pumpAndSettle();
    expect(fakeClient.readSupportSkillName, 'research');
    expect(fakeClient.readSupportFilePath, 'notes.md');
    expect(find.text('Prefer primary sources.'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('run.sh'));
    await tester.pumpAndSettle();
    expect(fakeClient.readSupportSkillName, 'research');
    expect(fakeClient.readSupportFilePath, 'scripts/run.sh');
    expect(find.textContaining('echo research'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded).last);
    await tester.pumpAndSettle();

    // remove_skill_* lives on the installed-skills list, so leave the detail
    // page before deleting.
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('remove_skill_research')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove').last);
    await tester.pump(const Duration(milliseconds: 200));

    expect(fakeClient.removedSkillName, 'research');
    expect(fakeClient.removedSkillAgentId, sdk.NapaxiEngine.defaultAgentId);
  });

  testWidgets('filters installed skills by status and search', (tester) async {
    final fakeClient = FakeNapaxiChatClient(
      skills: const [
        sdk.SkillInfo(name: 'research', description: 'Finds sources.'),
        sdk.SkillInfo(name: 'writer', description: 'Drafts copy.'),
        sdk.SkillInfo(name: 'calendar', description: 'Manages meetings.'),
      ],
      skillStatusReport: const sdk.SkillStatusReport(
        entries: [
          sdk.SkillStatusEntry(
            name: 'research',
            status: 'ready',
            eligible: true,
          ),
          sdk.SkillStatusEntry(
            name: 'writer',
            status: 'missing_requirements',
            eligible: false,
          ),
          sdk.SkillStatusEntry(
            name: 'calendar',
            status: 'disabled',
            enabled: false,
            eligible: false,
          ),
        ],
        ready: 1,
        missingRequirements: 1,
        disabled: 1,
      ),
    );

    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.tap(find.byKey(const Key('session_history_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('skills_menu_item')));
    await tester.pumpAndSettle();
    await pumpUntilFound(
      tester,
      find.byKey(const Key('installed_skill_search_field')),
    );

    expect(find.text('All 3'), findsOneWidget);
    expect(find.text('Ready 1'), findsOneWidget);
    expect(find.text('Needs setup 1'), findsOneWidget);
    expect(find.text('Disabled 1'), findsOneWidget);
    expect(find.text('research'), findsOneWidget);
    expect(find.text('writer'), findsOneWidget);
    expect(find.text('calendar'), findsOneWidget);

    await tester.tap(find.byKey(const Key('installed_skill_filter_disabled')));
    await tester.pumpAndSettle();
    expect(find.text('calendar'), findsOneWidget);
    expect(find.text('research'), findsNothing);
    expect(find.text('writer'), findsNothing);

    await tester.tap(find.byKey(const Key('installed_skill_filter_all')));
    await tester.enterText(
      find.byKey(const Key('installed_skill_search_field')),
      'writer',
    );
    await tester.pumpAndSettle();
    // 'writer' now matches both the search field's EditableText and the single
    // surviving list row, so assert the filtered-out skills are gone instead.
    expect(find.text('research'), findsNothing);
    expect(find.text('calendar'), findsNothing);
    expect(find.text('writer'), findsWidgets);
  });

  testWidgets('runs skill setup actions from the detail page', (tester) async {
    final fakeClient = FakeNapaxiChatClient(
      skills: const [
        sdk.SkillInfo(
          name: 'secret-search',
          version: '1.0.0',
          description: 'Searches authenticated sources.',
          source: 'local',
        ),
      ],
      skillStatusReport: const sdk.SkillStatusReport(
        entries: [
          sdk.SkillStatusEntry(
            name: 'secret-search',
            description: 'Searches authenticated sources.',
            trust: 'trusted',
            status: 'missing_requirements',
            eligible: false,
            requirements: sdk.SkillRequirementSummary(env: ['SEARCH_TOKEN']),
            missing: sdk.SkillRequirementSummary(env: ['SEARCH_TOKEN']),
            remediationActions: [
              sdk.SkillRemediationAction(
                id: 'env:SEARCH_TOKEN',
                kind: 'env',
                label: 'Provide token',
                requirement: 'SEARCH_TOKEN',
              ),
            ],
          ),
        ],
        missingRequirements: 1,
      ),
    );

    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.tap(find.byKey(const Key('session_history_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('skills_menu_item')));
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.text('secret-search'));

    expect(find.text('Needs setup'), findsWidgets);

    await tester.tap(find.text('secret-search').first);
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.text('Provide token'));
    expect(find.text('Setup needed'), findsOneWidget);
    expect(find.text('env: SEARCH_TOKEN'), findsOneWidget);

    await tester.tap(find.text('Provide token'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK').last);
    await tester.pump(const Duration(milliseconds: 200));

    expect(fakeClient.requestedRemediationSkillName, 'secret-search');
    expect(fakeClient.requestedRemediationActionId, 'env:SEARCH_TOKEN');
    expect(fakeClient.updatedSkillConfigKey, 'secret-search');
    expect(fakeClient.updatedSkillConfigPatch, {
      'env_keys': ['SEARCH_TOKEN'],
    });
  });

  testWidgets('hides duplicate enable remediation in skill details', (
    tester,
  ) async {
    final fakeClient = FakeNapaxiChatClient(
      skills: const [
        sdk.SkillInfo(
          name: 'research',
          version: '1.0.0',
          description: 'Finds and summarizes source material.',
        ),
      ],
      skillStatusReport: const sdk.SkillStatusReport(
        entries: [
          sdk.SkillStatusEntry(
            name: 'research',
            status: 'disabled',
            enabled: false,
            eligible: false,
            remediationActions: [
              sdk.SkillRemediationAction(
                id: 'enable:research',
                kind: 'enable',
                label: 'Enable research',
                requirement: 'research',
              ),
            ],
          ),
        ],
        disabled: 1,
      ),
    );

    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.tap(find.byKey(const Key('session_history_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('skills_menu_item')));
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.text('research'));

    await tester.tap(find.text('research').first);
    await tester.pumpAndSettle();
    await pumpUntilFound(
      tester,
      find.byKey(const Key('toggle_skill_research')),
    );

    expect(find.text('Enable research'), findsNothing);
    expect(find.text('Currently disabled.'), findsNothing);
  });

  testWidgets('returns to the side menu when backing out of skills', (
    tester,
  ) async {
    final fakeClient = FakeNapaxiChatClient(
      skills: const [
        sdk.SkillInfo(
          name: 'research',
          version: '1.0.0',
          description: 'Finds and summarizes source material.',
          source: 'local',
          tags: ['search', 'summary'],
        ),
      ],
    );

    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.tap(find.byKey(const Key('session_history_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('skills_menu_item')));
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.text('research'));

    expect(find.text('Skills'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('files_menu_item')), findsOneWidget);
    expect(find.byKey(const Key('skills_menu_item')), findsOneWidget);
    expect(find.text('research'), findsNothing);
  });

  testWidgets('browses the skill store and installs catalog skills inline', (
    tester,
  ) async {
    final fakeClient = FakeNapaxiChatClient(
      catalogPackages: const [
        sdk.CatalogSkillInfo(
          slug: 'writer',
          name: 'writer',
          description: 'Drafts polished copy.',
          version: '0.2.0',
          ownerName: 'napaxi',
          stars: 12,
        ),
      ],
    );

    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.tap(find.byKey(const Key('session_history_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('skills_menu_item')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Store'));
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.text('writer'));

    expect(find.byKey(const Key('skill_store_search_field')), findsOneWidget);
    expect(find.text('Drafts polished copy.'), findsOneWidget);
    expect(find.text('v0.2.0 · napaxi · 12 stars'), findsOneWidget);

    await tester.tap(find.byKey(const Key('install_skill_writer')));
    await tester.pumpAndSettle();

    expect(fakeClient.installedCatalogSlug, 'writer');
    expect(fakeClient.installedCatalogAgentId, sdk.NapaxiEngine.defaultAgentId);
    expect(fakeClient.sentMessages, isEmpty);
    expect(find.text('writer installed'), findsOneWidget);
    await tester.tap(find.text('Installed'));
    await tester.pumpAndSettle();
    expect(find.text('writer'), findsOneWidget);
  });

  testWidgets('updates installed catalog skills inline', (tester) async {
    // The Store's "Update" affordance is driven by the persisted slug->name map
    // recorded at install time, so seed it for the already-installed skill.
    SharedPreferences.setMockInitialValues({
      'skill_slug_to_name': ['writer=writer'],
    });
    final fakeClient = FakeNapaxiChatClient(
      skills: const [sdk.SkillInfo(name: 'writer')],
      catalogPackages: const [
        sdk.CatalogSkillInfo(
          slug: 'writer',
          name: 'writer',
          description: 'Drafts polished copy.',
          version: '0.2.0',
        ),
      ],
    );

    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.tap(find.byKey(const Key('session_history_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('skills_menu_item')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Store'));
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.text('writer'));

    expect(find.text('Update'), findsOneWidget);
    await tester.tap(find.byKey(const Key('install_skill_writer')));
    await tester.pumpAndSettle();

    expect(fakeClient.installedCatalogSlug, 'writer');
    expect(fakeClient.installedCatalogAgentId, sdk.NapaxiEngine.defaultAgentId);
    expect(find.text('writer updated'), findsOneWidget);
  });

  testWidgets('shows skill organize pending unused and tucked away items', (
    tester,
  ) async {
    final fakeClient = FakeNapaxiChatClient(
      pendingEvolution: [
        {
          'id': 'pending-1',
          'agent_id': sdk.NapaxiEngine.defaultAgentId,
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'action_type': 'SkillPatch',
          'reasoning': 'Tighten the research workflow.',
          'action': {
            'type': 'patch',
            'params': {'skill_name': 'research'},
          },
        },
      ],
      skillUsage: const [
        sdk.SkillUsageRecord(
          skillName: 'research',
          state: 'stale',
          createdBy: 'agent',
          useCount: 1,
        ),
        sdk.SkillUsageRecord(
          skillName: 'legacy-writer',
          state: 'archived',
          absorbedInto: 'writer',
        ),
      ],
    );

    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.tap(find.byKey(const Key('session_history_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('skills_menu_item')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Organize 1'));
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.text('research'));

    expect(find.text('Organize'), findsNothing);
    expect(find.text('1 skill suggestion pending'), findsOneWidget);
    expect(find.text('Suggestions'), findsOneWidget);
    expect(find.text('Unused'), findsOneWidget);
    expect(find.textContaining('Skill Patch'), findsOneWidget);
    expect(find.text('research'), findsWidgets);

    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.text('Suggestion details'), findsOneWidget);
    // The details dialog renders the suggestion reasoning plus humanized
    // action lines (Action / Skill); it does not render before/after diff
    // bodies. Assert against what is actually shown.
    expect(find.textContaining('Tighten the research workflow.'), findsWidgets);
    expect(find.textContaining('Skill: research'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Confirm'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(fakeClient.appliedPendingEvolutionId, 'pending-1');

    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('skill_governance_list')),
      const Offset(0, -260),
    );
    await tester.pumpAndSettle();
    // 'Tucked away' is the bottom section; assert it after scrolling it in.
    expect(find.text('Tucked away'), findsOneWidget);
    expect(find.text('legacy-writer'), findsOneWidget);

    await tester.ensureVisible(find.text('Restore'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(fakeClient.restoredSkillName, 'legacy-writer');
  });

  testWidgets('ignores a pending skill suggestion without surfacing an error', (
    tester,
  ) async {
    final fakeClient = FakeNapaxiChatClient(
      pendingEvolution: [
        {
          'id': 'pending-1',
          'agent_id': sdk.NapaxiEngine.defaultAgentId,
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'action_type': 'SkillPatch',
          'reasoning': 'Tighten the research workflow.',
          'action': {
            'type': 'patch',
            'params': {'skill_name': 'research'},
          },
        },
      ],
    );

    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.tap(find.byKey(const Key('session_history_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('skills_menu_item')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Organize 1'));
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.text('research'));

    await tester.tap(find.text('Ignore'));
    await tester.pumpAndSettle();

    expect(fakeClient.rejectedPendingEvolutionId, 'pending-1');
    expect(find.text('Organize 1'), findsNothing);
    expect(find.textContaining('Skill organizing failed'), findsNothing);
  });

  testWidgets('folds recursive workspace files into folders', (tester) async {
    final modified = DateTime(2026, 5, 13, 10);
    final fakeClient = FakeNapaxiChatClient(
      workspaceFiles: [
        sdk.WorkspaceFileInfo(
          name: 'daily',
          sandboxPath: '/workspace/daily',
          realPath: '',
          mimeType: 'inode/directory',
          isDirectory: true,
          sizeBytes: 0,
          modified: modified,
        ),
        sdk.WorkspaceFileInfo(
          name: '2026-05-13.md',
          sandboxPath: '/workspace/daily/2026-05-13.md',
          realPath: '/tmp/2026-05-13.md',
          mimeType: 'text/markdown',
          isDirectory: false,
          sizeBytes: 42,
          modified: modified,
        ),
        sdk.WorkspaceFileInfo(
          name: 'README.md',
          sandboxPath: '/workspace/README.md',
          realPath: '/tmp/README.md',
          mimeType: 'text/markdown',
          isDirectory: false,
          sizeBytes: 8,
          modified: modified,
        ),
      ],
    );

    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.tap(find.byKey(const Key('session_history_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('files_menu_item')));
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.text('daily'));

    expect(find.text('daily'), findsWidgets);
    expect(find.text('README.md'), findsOneWidget);
    expect(find.text('2026-05-13.md'), findsNothing);

    await tester.tap(find.text('daily').first);
    await tester.pumpAndSettle();

    expect(find.text('2026-05-13.md'), findsOneWidget);
    expect(find.text('README.md'), findsNothing);
  });

  testWidgets('shows parent directory entry inside an empty workspace folder', (
    tester,
  ) async {
    final modified = DateTime(2026, 5, 13, 10);
    final fakeClient = FakeNapaxiChatClient(
      workspaceFiles: [
        sdk.WorkspaceFileInfo(
          name: 'daily',
          sandboxPath: '/workspace/daily',
          realPath: '',
          mimeType: 'inode/directory',
          isDirectory: true,
          sizeBytes: 0,
          modified: modified,
        ),
      ],
    );

    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.tap(find.byKey(const Key('session_history_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('files_menu_item')));
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.text('daily'));

    await tester.tap(find.text('daily').first);
    await tester.pumpAndSettle();

    expect(find.text('daily'), findsOneWidget);
    expect(find.text('No files yet'), findsOneWidget);

    await tester.tap(find.byKey(const Key('files_parent_directory_tile')));
    await tester.pumpAndSettle();

    expect(find.text('daily'), findsWidgets);
  });

  testWidgets('deletes workspace folder from long press selection', (
    tester,
  ) async {
    final modified = DateTime(2026, 5, 13, 10);
    final fakeClient = FakeNapaxiChatClient(
      workspaceFiles: [
        sdk.WorkspaceFileInfo(
          name: 'daily',
          sandboxPath: '/workspace/daily',
          realPath: '',
          mimeType: 'inode/directory',
          isDirectory: true,
          sizeBytes: 0,
          modified: modified,
        ),
      ],
    );

    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.tap(find.byKey(const Key('session_history_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('files_menu_item')));
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.text('daily'));

    await tester.longPress(find.text('daily').first);
    await tester.pumpAndSettle();

    expect(find.text('1 selected'), findsOneWidget);
    expect(find.byTooltip('Delete'), findsAtLeastNWidgets(1));

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(
      fakeClient.deletedSandboxWorkspacePaths,
      contains('/workspace/daily'),
    );
  });

  testWidgets('renders streamed thinking separately from final response', (
    tester,
  ) async {
    final fakeClient = FakeNapaxiChatClient(
      events: const [
        sdk.ThinkingEvent(content: 'Checking the available context.'),
        sdk.ResponseEvent(content: 'Final answer from napaxi.'),
      ],
    );
    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'Explain trace',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pumpAndSettle();

    expect(
      find.text('Final answer from napaxi.', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Thought through'), findsOneWidget);

    await tester.tap(find.text('Thought through'));
    await tester.pumpAndSettle();

    expect(find.text('Checking the available context.'), findsOneWidget);
  });

  testWidgets('renders activated skills in assistant trace', (tester) async {
    final fakeClient = FakeNapaxiChatClient(
      events: const [
        sdk.SkillActivatedEvent(
          agentId: 'napaxi',
          skills: [
            sdk.ActivatedSkillInfo(
              name: 'research',
              version: '1.0.0',
              trust: 'trusted',
              reason: 'loaded',
            ),
            sdk.ActivatedSkillInfo(name: 'writer', trust: 'installed'),
          ],
        ),
        sdk.ResponseEvent(content: 'Used the available guidance.'),
      ],
    );
    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'Use my skills',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pumpAndSettle();

    expect(
      find.text('Used the available guidance.', findRichText: true),
      findsOneWidget,
    );
    expect(find.byKey(const Key('activated_skills_trace')), findsNothing);

    await tester.tap(find.text('Thought through'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('activated_skills_trace')), findsOneWidget);
    expect(find.text('Skills enabled'), findsOneWidget);
    expect(find.text('research'), findsOneWidget);
    expect(find.text('writer'), findsOneWidget);
    expect(find.text('Loaded · v1.0.0 · trusted'), findsOneWidget);
    expect(find.text('installed'), findsOneWidget);
  });

  testWidgets(
    'renders response and reasoning deltas as a live assistant turn',
    (tester) async {
      final fakeClient = FakeNapaxiChatClient(
        events: const [
          sdk.ReasoningDeltaEvent(content: 'Reading context. '),
          sdk.ReasoningDeltaEvent(content: 'Preparing answer.'),
          sdk.ResponseDeltaEvent(content: 'Here is '),
          sdk.ResponseDeltaEvent(content: 'the answer.'),
        ],
      );
      await tester.pumpWidget(
        _testApp(chatClientFactory: () async => fakeClient),
      );
      await configureSingleModel(tester);

      await tester.enterText(
        find.byKey(const Key('chat_input_field')),
        'Stream please',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('send_message_button')));
      await tester.pumpAndSettle();

      expect(
        find.text('Here is the answer.', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Thought through'), findsOneWidget);

      await tester.tap(find.text('Thought through'));
      await tester.pumpAndSettle();

      expect(find.text('Reading context. Preparing answer.'), findsOneWidget);
    },
  );

  testWidgets('starts a new assistant bubble when reasoning resumes', (
    tester,
  ) async {
    final fakeClient = FakeNapaxiChatClient(
      events: const [
        sdk.ReasoningDeltaEvent(content: 'Thinking about the first part.'),
        sdk.ResponseDeltaEvent(content: 'First answer.'),
        sdk.ReasoningDeltaEvent(content: 'Thinking about the second part.'),
        sdk.ResponseDeltaEvent(content: 'Second answer.'),
      ],
    );
    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'Stream in parts',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pumpAndSettle();

    expect(find.text('First answer.', findRichText: true), findsOneWidget);
    expect(find.text('Second answer.', findRichText: true), findsOneWidget);
    expect(find.text('Thought through'), findsNWidgets(2));

    await tester.tap(find.text('Thought through').at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thought through').at(1));
    await tester.pumpAndSettle();

    final firstThinking = find.text('Thinking about the first part.');
    final firstAnswer = find.text('First answer.', findRichText: true);
    final secondThinking = find.text('Thinking about the second part.');
    final secondAnswer = find.text('Second answer.', findRichText: true);
    expect(firstThinking, findsOneWidget);
    expect(secondThinking, findsOneWidget);
    expect(
      tester.getTopLeft(firstThinking).dy,
      lessThan(tester.getTopLeft(firstAnswer).dy),
    );
    expect(
      tester.getTopLeft(firstAnswer).dy,
      lessThan(tester.getTopLeft(secondThinking).dy),
    );
    expect(
      tester.getTopLeft(secondThinking).dy,
      lessThan(tester.getTopLeft(secondAnswer).dy),
    );
  });

  testWidgets('renders tool call and completed tool result', (tester) async {
    final fakeClient = FakeNapaxiChatClient(
      events: const [
        sdk.ToolCallEvent(
          callId: 'call-1',
          name: 'list_files',
          arguments: '{"path":"/workspace"}',
        ),
        sdk.ToolResultEvent(
          callId: 'call-1',
          name: 'list_files',
          output: '{"files":["README.md"]}',
          isError: false,
        ),
        sdk.ResponseEvent(content: 'I found README.md.'),
      ],
    );
    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'List files',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pumpAndSettle();

    expect(find.text('I found README.md.', findRichText: true), findsOneWidget);
    await tester.tap(find.text('Thought through'));
    await tester.pumpAndSettle();
    expect(find.text('list_files'), findsOneWidget);

    await tester.tap(find.text('list_files'));
    await tester.pumpAndSettle();

    expect(find.text('Arguments'), findsOneWidget);
    expect(find.text('Result'), findsOneWidget);
    expect(find.textContaining('README.md'), findsWidgets);
  });

  testWidgets('interleaves thinking steps with their tool calls', (
    tester,
  ) async {
    final fakeClient = FakeNapaxiChatClient(
      events: const [
        sdk.ThinkingEvent(content: 'First I inspect files.'),
        sdk.ToolCallEvent(
          callId: 'call-1',
          name: 'list_files',
          arguments: '{"path":"/workspace"}',
        ),
        sdk.ToolResultEvent(
          callId: 'call-1',
          name: 'list_files',
          output: '{"files":["README.md"]}',
          isError: false,
        ),
        sdk.ThinkingEvent(content: 'Then I read the match.'),
        sdk.ToolCallEvent(
          callId: 'call-2',
          name: 'read_file',
          arguments: '{"path":"/workspace/README.md"}',
        ),
        sdk.ToolResultEvent(
          callId: 'call-2',
          name: 'read_file',
          output:
              '{"path":"/workspace/README.md","content":"README mentions napaxi.","bytes_read":19,"size_bytes":19}',
          isError: false,
        ),
        sdk.ResponseEvent(content: 'README.md mentions napaxi.'),
      ],
    );
    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'Inspect README',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Thought through'));
    await tester.pumpAndSettle();

    final firstThinking = find.text('First I inspect files.');
    final firstTool = find.text('list_files');
    final secondThinking = find.text('Then I read the match.');
    final secondTool = find.text('已读取 1 个文件');
    final readLine = find.text('Read README.md');

    expect(firstThinking, findsOneWidget);
    expect(firstTool, findsOneWidget);
    expect(secondThinking, findsOneWidget);
    expect(secondTool, findsOneWidget);
    expect(readLine, findsNothing);
    expect(
      tester.getTopLeft(firstThinking).dy,
      lessThan(tester.getTopLeft(firstTool).dy),
    );
    expect(
      tester.getTopLeft(firstTool).dy,
      lessThan(tester.getTopLeft(secondThinking).dy),
    );
    expect(
      tester.getTopLeft(secondThinking).dy,
      lessThan(tester.getTopLeft(secondTool).dy),
    );

    await tester.tap(secondTool);
    await tester.pumpAndSettle();
    expect(readLine, findsOneWidget);
    expect(find.text('README mentions napaxi.'), findsNothing);
  });

  testWidgets('groups read file tool calls in a compact trace view', (
    tester,
  ) async {
    final fakeClient = FakeNapaxiChatClient(
      events: const [
        sdk.ThinkingEvent(content: 'I read the implementation files.'),
        sdk.ToolCallEvent(
          callId: 'call-1',
          name: 'read_file',
          arguments: '{"path":"/workspace/file.rs"}',
        ),
        sdk.ToolResultEvent(
          callId: 'call-1',
          name: 'read_file',
          output: '{"path":"/workspace/file.rs","content":"file body"}',
          isError: false,
        ),
        sdk.ToolCallEvent(
          callId: 'call-2',
          name: 'read_file',
          arguments: '{"path":"/workspace/http.rs"}',
        ),
        sdk.ToolResultEvent(
          callId: 'call-2',
          name: 'read_file',
          output: '{"path":"/workspace/http.rs","content":"http body"}',
          isError: false,
        ),
        sdk.ToolCallEvent(
          callId: 'call-3',
          name: 'read_file',
          arguments: '{"path":"/workspace/builtin.rs"}',
        ),
        sdk.ToolResultEvent(
          callId: 'call-3',
          name: 'read_file',
          output: '{"path":"/workspace/builtin.rs","content":"builtin body"}',
          isError: false,
        ),
        sdk.ResponseEvent(content: 'I checked the files.'),
      ],
    );
    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'Read files',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Thought through'));
    await tester.pumpAndSettle();

    expect(find.text('已读取 3 个文件'), findsOneWidget);
    expect(find.text('Read file.rs'), findsNothing);
    expect(find.text('Read http.rs'), findsNothing);
    expect(find.text('Read builtin.rs'), findsNothing);
    expect(find.text('read_file'), findsNothing);
    expect(find.text('file body'), findsNothing);
    expect(find.text('http body'), findsNothing);
    expect(find.text('builtin body'), findsNothing);

    await tester.tap(find.text('已读取 3 个文件'));
    await tester.pumpAndSettle();

    expect(find.text('Read file.rs'), findsOneWidget);
    expect(find.text('Read http.rs'), findsOneWidget);
    expect(find.text('Read builtin.rs'), findsOneWidget);
    expect(find.text('file body'), findsNothing);
    expect(find.text('http body'), findsNothing);
    expect(find.text('builtin body'), findsNothing);
  });

  testWidgets('renders write file tool calls with patch summary', (
    tester,
  ) async {
    final fakeClient = FakeNapaxiChatClient(
      events: const [
        sdk.ThinkingEvent(content: 'I will patch the workspace files.'),
        sdk.ToolCallEvent(
          callId: 'call-1',
          name: 'write_file',
          arguments:
              '{"patch":"*** Begin Patch\\n*** Update File: /workspace/plan.md\\n@@\\n old\\n-new\\n+newer\\n*** End Patch"}',
        ),
        sdk.ToolOutputChunkEvent(
          callId: 'call-1',
          stream: 'patch',
          content:
              '{"type":"apply_patch_progress","action":"updated","path":"/workspace/plan.md","added_lines":1,"removed_lines":1}',
        ),
        sdk.ToolOutputChunkEvent(
          callId: 'call-1',
          stream: 'patch',
          content:
              '{"type":"apply_patch_progress","action":"added","path":"/workspace/notes.md","added_lines":3,"removed_lines":0}',
        ),
        sdk.ToolResultEvent(
          callId: 'call-1',
          name: 'write_file',
          output:
              '{"status":"patched","file_count":2,"files":[{"action":"updated","path":"/workspace/plan.md","size_bytes":12,"line_count":1,"added_lines":1,"removed_lines":1},{"action":"added","path":"/workspace/notes.md","size_bytes":10,"line_count":3,"added_lines":3,"removed_lines":0}]}',
          isError: false,
        ),
        sdk.ResponseEvent(content: 'Done patching.'),
      ],
    );
    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'Patch files',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Thought through'));
    await tester.pumpAndSettle();

    expect(find.text('已编辑 2 个文件'), findsOneWidget);
    expect(find.text('Write file'), findsNothing);

    await tester.tap(find.text('已编辑 2 个文件'));
    await tester.pumpAndSettle();

    expect(find.text('已编辑 2 个文件'), findsOneWidget);
    expect(find.text('编辑 plan.md +1 -1'), findsOneWidget);
    expect(find.text('新增 notes.md +3 -0'), findsOneWidget);
    expect(find.text('Raw details'), findsNothing);
  });

  testWidgets('renders write file tool call while arguments stream', (
    tester,
  ) async {
    final events = StreamController<sdk.ChatEvent>();
    final fakeClient = FakeNapaxiChatClient(eventStream: events.stream);

    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'Rewrite snake',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    events.add(const sdk.ThinkingEvent(content: 'I will rewrite the file.'));
    events.add(
      const sdk.ToolCallDeltaEvent(
        callId: 'call-1',
        name: 'write_file',
        argumentsDelta:
            '{"patch":"*** Begin Patch\\n*** Add File: /workspace/snake.html\\n+<html>',
        argumentsSoFar:
            '{"patch":"*** Begin Patch\\n*** Add File: /workspace/snake.html\\n+<html>',
      ),
    );
    await tester.pump();

    expect(find.text('正在编辑 snake.html +1 -0'), findsOneWidget);
    expect(find.textContaining('<html>'), findsNothing);

    events.add(
      const sdk.ToolCallDeltaEvent(
        callId: 'call-1',
        name: 'write_file',
        argumentsDelta: '+<body>Snake</body>',
        argumentsSoFar:
            '{"patch":"*** Begin Patch\\n*** Add File: /workspace/snake.html\\n+<html>\\n+<body>Snake</body>',
      ),
    );
    await tester.pump();

    expect(find.text('正在编辑 snake.html +2 -0'), findsOneWidget);
    expect(find.textContaining('<body>Snake</body>'), findsNothing);

    events.add(
      const sdk.ToolCallEvent(
        callId: 'call-1',
        name: 'write_file',
        arguments:
            '{"patch":"*** Begin Patch\\n*** Add File: /workspace/snake.html\\n+<html>\\n+<body>Snake</body>\\n*** End Patch"}',
      ),
    );
    events.add(
      const sdk.ToolResultEvent(
        callId: 'call-1',
        name: 'write_file',
        output:
            '{"status":"patched","file_count":1,"files":[{"action":"added","path":"/workspace/snake.html","added_lines":2,"removed_lines":0}]}',
        isError: false,
      ),
    );
    events.add(const sdk.ResponseEvent(content: 'Done.'));
    await events.close();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thought through'));
    await tester.pumpAndSettle();
    expect(find.text('新增 snake.html +2 -0'), findsOneWidget);
  });

  testWidgets('renders write file patch counts while arguments stream', (
    tester,
  ) async {
    final events = StreamController<sdk.ChatEvent>();
    final fakeClient = FakeNapaxiChatClient(eventStream: events.stream);

    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'Patch snake',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pump();
    await _pumpUntilSent(tester, fakeClient);

    events.add(
      const sdk.ToolCallDeltaEvent(
        callId: 'call-1',
        name: 'write_file',
        argumentsDelta:
            '{"patch":"*** Begin Patch\\n*** Update File: /workspace/snake.html\\n@@\\n-old title\\n+new title',
        argumentsSoFar:
            '{"patch":"*** Begin Patch\\n*** Update File: /workspace/snake.html\\n@@\\n-old title\\n+new title',
      ),
    );
    await tester.pump();

    expect(find.text('正在编辑 snake.html +1 -1'), findsOneWidget);
    expect(find.textContaining('old title'), findsNothing);
    expect(find.textContaining('new title'), findsNothing);

    events.add(
      const sdk.ToolCallEvent(
        callId: 'call-1',
        name: 'write_file',
        arguments:
            '{"patch":"*** Begin Patch\\n*** Update File: /workspace/snake.html\\n@@\\n-old title\\n+new title\\n*** End Patch"}',
      ),
    );
    events.add(
      const sdk.ToolResultEvent(
        callId: 'call-1',
        name: 'write_file',
        output:
            '{"status":"patched","file_count":1,"files":[{"action":"updated","path":"/workspace/snake.html","added_lines":1,"removed_lines":1}]}',
        isError: false,
      ),
    );
    events.add(const sdk.ResponseEvent(content: 'Done.'));
    await events.close();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Thought through'));
    await tester.pumpAndSettle();
    expect(find.text('已编辑 snake.html +1 -1'), findsOneWidget);
  });

  testWidgets('renders write file replacement counts while arguments stream', (
    tester,
  ) async {
    final events = StreamController<sdk.ChatEvent>();
    final fakeClient = FakeNapaxiChatClient(eventStream: events.stream);

    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'Replace snake title',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pump();
    await _pumpUntilSent(tester, fakeClient);

    events.add(
      const sdk.ToolCallDeltaEvent(
        callId: 'call-1',
        name: 'write_file',
        argumentsDelta:
            '{"patch":"*** Begin Patch\\n*** Update File: /workspace/snake.html\\n@@\\n-old title\\n+new title',
        argumentsSoFar:
            '{"patch":"*** Begin Patch\\n*** Update File: /workspace/snake.html\\n@@\\n-old title\\n+new title',
      ),
    );
    await tester.pump();

    expect(find.text('正在编辑 snake.html +1 -1'), findsOneWidget);
    expect(find.textContaining('old title'), findsNothing);
    expect(find.textContaining('new title'), findsNothing);

    events.add(
      const sdk.ToolCallEvent(
        callId: 'call-1',
        name: 'write_file',
        arguments:
            '{"patch":"*** Begin Patch\\n*** Update File: /workspace/snake.html\\n@@\\n-old title\\n+new title\\n*** End Patch"}',
      ),
    );
    events.add(
      const sdk.ToolResultEvent(
        callId: 'call-1',
        name: 'write_file',
        output:
            '{"status":"patched","file_count":1,"files":[{"action":"updated","path":"/workspace/snake.html","added_lines":1,"removed_lines":1}]}',
        isError: false,
      ),
    );
    events.add(const sdk.ResponseEvent(content: 'Done.'));
    await events.close();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Thought through'));
    await tester.pumpAndSettle();
    expect(find.text('已编辑 snake.html +1 -1'), findsOneWidget);
  });

  testWidgets('merges streamed write file updates for the same file', (
    tester,
  ) async {
    final fakeClient = FakeNapaxiChatClient(
      events: const [
        sdk.ThinkingEvent(content: 'I am updating snake.html.'),
        sdk.ToolCallEvent(
          callId: 'call-1',
          name: 'write_file',
          arguments:
              '{"patch":"*** Begin Patch\\n*** Update File: /workspace/snake.html\\n@@\\n-old\\n+new\\n*** End Patch"}',
        ),
        sdk.ToolOutputChunkEvent(
          callId: 'call-1',
          stream: 'patch',
          content:
              '{"type":"apply_patch_progress","action":"updated","path":"/workspace/snake.html","added_lines":3,"removed_lines":4}',
        ),
        sdk.ToolOutputChunkEvent(
          callId: 'call-1',
          stream: 'patch',
          content:
              '{"type":"apply_patch_progress","action":"updated","path":"/workspace/snake.html","added_lines":9,"removed_lines":10}',
        ),
        sdk.ToolOutputChunkEvent(
          callId: 'call-1',
          stream: 'patch',
          content:
              '{"type":"apply_patch_progress","action":"updated","path":"/workspace/snake.html","added_lines":14,"removed_lines":7}',
        ),
        sdk.ResponseEvent(content: 'Still patching.'),
      ],
    );

    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'Patch snake',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Thought through'));
    await tester.pumpAndSettle();

    expect(find.text('正在编辑 snake.html +26 -21'), findsOneWidget);
    expect(
      find.text('write_file patch did not match the targ...'),
      findsNothing,
    );

    await tester.tap(find.text('正在编辑 snake.html +26 -21'));
    await tester.pumpAndSettle();

    expect(find.text('编辑 snake.html +26 -21'), findsOneWidget);
    expect(find.text('编辑 snake.html +3 -4'), findsNothing);
    expect(find.text('编辑 snake.html +9 -10'), findsNothing);
    expect(find.text('编辑 snake.html +14 -7'), findsNothing);
  });

  testWidgets('renders apply_patch failure as concise error label', (
    tester,
  ) async {
    final fakeClient = FakeNapaxiChatClient(
      events: const [
        sdk.ThinkingEvent(content: 'I will patch the workspace.'),
        sdk.ToolCallEvent(
          callId: 'call-1',
          name: 'apply_patch',
          arguments:
              '{"patch":"*** Begin Patch\\n*** Update File: /workspace/plan.md\\n@@\\n-nope\\n+changed\\n*** End Patch"}',
        ),
        sdk.ToolResultEvent(
          callId: 'call-1',
          name: 'apply_patch',
          output:
              '{"status":"error","error":"hunk did not match","error_kind":"hunk_context_not_found","path":"/workspace/plan.md","line":3,"pattern_excerpt":["nope"],"hint":"include a few unchanged lines immediately above and below the change"}',
          isError: true,
        ),
        sdk.ResponseEvent(content: 'Sorry, that patch failed.'),
      ],
    );

    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'Patch a missing line',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Thought through'));
    await tester.pumpAndSettle();

    expect(find.text('编辑失败'), findsOneWidget);
  });

  testWidgets('shows single write file counts from patch arguments fallback', (
    tester,
  ) async {
    final fakeClient = FakeNapaxiChatClient(
      events: const [
        sdk.ThinkingEvent(content: 'I updated snake.html.'),
        sdk.ToolCallEvent(
          callId: 'call-1',
          name: 'write_file',
          arguments:
              '{"patch":"*** Begin Patch\\n*** Update File: /workspace/snake.html\\n@@\\n-old\\n+new\\n+extra\\n*** End Patch"}',
        ),
        sdk.ToolResultEvent(
          callId: 'call-1',
          name: 'write_file',
          output: '{"status":"patched","file_count":1}',
          isError: false,
        ),
        sdk.ResponseEvent(content: 'Done.'),
      ],
    );

    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'Patch fallback',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Thought through'));
    await tester.pumpAndSettle();

    expect(find.text('已编辑 snake.html +2 -1'), findsOneWidget);

    await tester.tap(find.text('已编辑 snake.html +2 -1'));
    await tester.pumpAndSettle();

    expect(find.text('编辑 snake.html +2 -1'), findsOneWidget);
  });

  testWidgets('shows generated files as chat attachments', (tester) async {
    final fakeClient = FakeNapaxiChatClient(
      detectedFiles: const [
        sdk.ResolvedFile(
          sandboxPath: '/workspace/snake.html',
          realPath: '/tmp/snake.html',
          filename: 'snake.html',
          mimeType: 'text/html',
          isImage: false,
          exists: true,
        ),
        sdk.ResolvedFile(
          sandboxPath: '/workspace/notes.md',
          realPath: '/tmp/notes.md',
          filename: 'notes.md',
          mimeType: 'text/markdown',
          isImage: false,
          exists: true,
        ),
      ],
      events: const [
        sdk.ToolCallEvent(
          callId: 'read-1',
          name: 'read_file',
          arguments: '{"path":"/workspace/README.md"}',
        ),
        sdk.ToolResultEvent(
          callId: 'read-1',
          name: 'read_file',
          output: '{"path":"/workspace/README.md","content":"See snake.html"}',
          isError: false,
        ),
        sdk.ToolCallEvent(
          callId: 'write-1',
          name: 'write_file',
          arguments:
              '{"patch":"*** Begin Patch\\n*** Update File: /workspace/snake.html\\n@@\\n-old\\n+new\\n*** Update File: /workspace/notes.md\\n@@\\n-old\\n+new\\n*** End Patch"}',
        ),
        sdk.ToolResultEvent(
          callId: 'write-1',
          name: 'write_file',
          output:
              '{"files":[{"action":"updated","path":"/workspace/snake.html"},{"action":"updated","path":"/workspace/notes.md"}]}',
          isError: false,
        ),
        sdk.ResponseEvent(content: 'Updated files.'),
      ],
    );

    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'Update preview',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pumpAndSettle();

    expect(fakeClient.detectedFileTexts, isNotEmpty);
    expect(
      fakeClient.detectedFileTexts.first,
      contains('/workspace/snake.html'),
    );
    expect(fakeClient.detectedFileTexts.first, contains('/workspace/notes.md'));
    expect(fakeClient.detectedFileTexts.first, isNot(contains('README.md')));
    expect(
      find.byKey(const Key('message_attachment_preview_list')),
      findsNothing,
    );
    expect(find.text('snake.html'), findsOneWidget);
    expect(find.text('notes.md'), findsOneWidget);
  });

  testWidgets('uses SDK thread id for generated attachment cache keys', (
    tester,
  ) async {
    const uuidThreadId = '7f96db72-5b5b-4693-b275-38ac32b5d9c4';
    final fakeClient = FakeNapaxiChatClient(
      createdThreadIds: const {'session-1': uuidThreadId},
      detectedFiles: const [
        sdk.ResolvedFile(
          sandboxPath: '/workspace/snake.html',
          realPath: '/tmp/snake.html',
          filename: 'snake.html',
          mimeType: 'text/html',
          isImage: false,
          exists: true,
        ),
      ],
      events: const [
        sdk.ToolCallEvent(
          callId: 'write-1',
          name: 'write_file',
          arguments: '{"path":"/workspace/snake.html"}',
        ),
        sdk.ToolResultEvent(
          callId: 'write-1',
          name: 'write_file',
          output:
              '{"files":[{"action":"updated","path":"/workspace/snake.html"}]}',
          isError: false,
        ),
        sdk.ResponseEvent(content: 'Updated files.'),
      ],
    );

    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'Update preview',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pumpAndSettle();

    expect(fakeClient.sentThreadIds, [uuidThreadId]);
    expect(find.text('snake.html'), findsOneWidget);

    await tester.tap(find.byKey(const Key('session_history_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('session_tile_$uuidThreadId')), findsOneWidget);
    expect(find.byKey(const Key('session_tile_session-1')), findsNothing);
  });

  testWidgets('shows current conversation attachments from the top bar', (
    tester,
  ) async {
    final fakeClient = FakeNapaxiChatClient(
      detectedFiles: const [
        sdk.ResolvedFile(
          sandboxPath: '/workspace/snake.html',
          realPath: '/tmp/snake.html',
          filename: 'snake.html',
          mimeType: 'text/html',
          isImage: false,
          exists: true,
        ),
      ],
      events: const [
        sdk.ToolCallEvent(
          callId: 'write-1',
          name: 'write_file',
          arguments:
              '{"patch":"*** Begin Patch\\n*** Add File: /workspace/snake.html\\n+<html></html>\\n*** End Patch"}',
        ),
        sdk.ToolResultEvent(
          callId: 'write-1',
          name: 'write_file',
          output:
              '{"files":[{"action":"added","path":"/workspace/snake.html"}]}',
          isError: false,
        ),
        sdk.ResponseEvent(content: 'Built snake.'),
      ],
    );

    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.enterText(find.byKey(const Key('chat_input_field')), 'Build');
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('conversation_attachments_badge')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('conversation_attachments_button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('conversation_attachments_panel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('conversation_attachments_list')),
      findsOneWidget,
    );
    expect(find.text('Conversation attachments'), findsOneWidget);
    expect(
      find.text('Generated · HTML · /workspace/snake.html'),
      findsOneWidget,
    );
  });

  testWidgets('does not surface uploaded attachment paths as generated files', (
    tester,
  ) async {
    final fakeClient = FakeNapaxiChatClient(
      detectedFiles: const [
        sdk.ResolvedFile(
          sandboxPath: '/workspace/attachments/session-1/photo.jpg',
          realPath: '/tmp/photo.jpg',
          filename: 'photo.jpg',
          mimeType: 'image/jpeg',
          isImage: true,
          exists: true,
        ),
        sdk.ResolvedFile(
          sandboxPath: '/workspace/snake.html',
          realPath: '/tmp/snake.html',
          filename: 'snake.html',
          mimeType: 'text/html',
          isImage: false,
          exists: true,
        ),
      ],
      events: const [
        sdk.ToolCallEvent(
          callId: 'write-1',
          name: 'write_file',
          arguments:
              '{"patch":"*** Begin Patch\\n*** Update File: /workspace/snake.html\\n+<html></html>\\n*** End Patch"}',
        ),
        sdk.ToolResultEvent(
          callId: 'write-1',
          name: 'write_file',
          output:
              '{"files":[{"action":"updated","path":"/workspace/attachments/session-1/photo.jpg"},{"action":"updated","path":"/workspace/snake.html"}]}',
          isError: false,
        ),
        sdk.ResponseEvent(content: 'Analyzed the uploaded photo.'),
      ],
    );

    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'Analyze photo',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pumpAndSettle();

    expect(find.text('photo.jpg'), findsNothing);
    expect(find.text('snake.html'), findsOneWidget);

    await tester.tap(find.byKey(const Key('conversation_attachments_button')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Generated · Image · /workspace/attachments/session-1/photo.jpg',
      ),
      findsNothing,
    );
    expect(
      find.text('Generated · HTML · /workspace/snake.html'),
      findsOneWidget,
    );
  });

  // Shell results are plain stdout with no file manifest, so (matching Codex)
  // files a shell command writes are NOT surfaced as attachments — neither the
  // file nor its parent directory. The removed workspace-diff logic used to
  // scoop these up at end-of-run; this locks in that it no longer does.
  testWidgets('does not surface shell-generated files as attachments', (
    tester,
  ) async {
    final controller = StreamController<sdk.ChatEvent>();
    final fakeClient = FakeNapaxiChatClient(
      detectedFiles: const [
        sdk.ResolvedFile(
          sandboxPath: '/workspace/generated',
          realPath: '/tmp/generated',
          filename: 'generated',
          mimeType: 'inode/directory',
          isImage: false,
          isDirectory: true,
          exists: true,
        ),
        sdk.ResolvedFile(
          sandboxPath: '/workspace/generated/report.txt',
          realPath: '/tmp/generated/report.txt',
          filename: 'report.txt',
          mimeType: 'text/plain',
          isImage: false,
          exists: true,
        ),
      ],
      eventStream: controller.stream,
    );

    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'Run shell',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pump();
    await _pumpUntilSent(tester, fakeClient);

    controller.add(
      const sdk.ToolCallEvent(
        callId: 'shell-1',
        name: 'shell',
        arguments:
            '{"cmd":"mkdir -p /workspace/generated && echo hi > /workspace/generated/report.txt"}',
      ),
    );
    controller.add(
      const sdk.ToolResultEvent(
        callId: 'shell-1',
        name: 'shell',
        output:
            'wrote /workspace/generated/report.txt under /workspace/generated',
        isError: false,
      ),
    );
    await tester.pump();

    expect(find.text('report.txt'), findsNothing);
    expect(find.text('generated'), findsNothing);

    controller.add(const sdk.ResponseEvent(content: 'Shell finished.'));
    await controller.close();
    await tester.pumpAndSettle();

    // Even after the run ends, the shell side-effect file does not appear.
    expect(find.text('report.txt'), findsNothing);
    expect(find.text('generated'), findsNothing);
  });

  testWidgets('defers generated file attachments until the response ends', (
    tester,
  ) async {
    final controller = StreamController<sdk.ChatEvent>();
    final fakeClient = FakeNapaxiChatClient(
      detectedFiles: const [
        sdk.ResolvedFile(
          sandboxPath: '/workspace/index.html',
          realPath: '/tmp/index.html',
          filename: 'index.html',
          mimeType: 'text/html',
          isImage: false,
          exists: true,
        ),
      ],
      eventStream: controller.stream,
    );

    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.enterText(find.byKey(const Key('chat_input_field')), 'Build');
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pump();
    await _pumpUntilSent(tester, fakeClient);

    controller.add(
      const sdk.ToolCallEvent(
        callId: 'write-1',
        name: 'write_file',
        arguments:
            '{"patch":"*** Begin Patch\\n*** Add File: /workspace/index.html\\n+<html></html>\\n*** End Patch"}',
      ),
    );
    await tester.pump();

    controller.add(
      const sdk.ToolResultEvent(
        callId: 'write-1',
        name: 'write_file',
        output: '{"files":[{"action":"added","path":"/workspace/index.html"}]}',
        isError: false,
      ),
    );
    await tester.pump();

    expect(find.text('index.html'), findsNothing);
    expect(
      find.byKey(const Key('message_attachment_preview_list')),
      findsNothing,
    );

    controller.add(const sdk.ResponseEvent(content: 'Done building.'));
    await controller.close();
    await tester.pumpAndSettle();

    expect(find.text('index.html'), findsOneWidget);
  });

  testWidgets('restores streamed write file attachments from arguments', (
    tester,
  ) async {
    final controller = StreamController<sdk.ChatEvent>();
    final fakeClient = FakeNapaxiChatClient(
      detectedFiles: const [
        sdk.ResolvedFile(
          sandboxPath: '/workspace/snake.html',
          realPath: '/tmp/snake.html',
          filename: 'snake.html',
          mimeType: 'text/html',
          isImage: false,
          exists: true,
        ),
      ],
      eventStream: controller.stream,
    );

    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'Build snake',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pump();
    await _pumpUntilSent(tester, fakeClient);

    controller.add(
      const sdk.ToolCallDeltaEvent(
        callId: 'write-1',
        name: 'write_file',
        argumentsDelta:
            '{"patch":"*** Begin Patch\\n*** Add File: /workspace/snake.html\\n+<html>',
        argumentsSoFar:
            '{"patch":"*** Begin Patch\\n*** Add File: /workspace/snake.html\\n+<html>',
      ),
    );
    await tester.pump();

    expect(find.text('正在编辑 snake.html +1 -0'), findsOneWidget);

    controller.add(
      const sdk.ToolCallEvent(
        callId: 'write-1',
        name: 'write_file',
        arguments:
            '{"patch":"*** Begin Patch\\n*** Add File: /workspace/snake.html\\n+<html></html>\\n*** End Patch"}',
      ),
    );
    controller.add(
      const sdk.ToolResultEvent(
        callId: 'write-1',
        name: 'write_file',
        output:
            '{"status":"patched","file_count":1,"files":[{"action":"added","path":"/workspace/snake.html","added_lines":1,"removed_lines":0}]}',
        isError: false,
      ),
    );
    await tester.pump();

    controller.add(const sdk.ResponseEvent(content: 'Done building.'));
    await controller.close();
    await tester.pumpAndSettle();

    expect(
      fakeClient.detectedFileTexts.last,
      contains('/workspace/snake.html'),
    );
    expect(find.text('snake.html'), findsOneWidget);
  });

  testWidgets('restores assistant generated attachments after rebuild', (
    tester,
  ) async {
    const sessionKey = sdk.SessionKey(
      channelType: 'app',
      accountId: 'flutter_demo',
      threadId: 'session-42',
    );
    SharedPreferences.setMockInitialValues({
      'napaxi_demo.assistant_attachments.v1': jsonEncode({
        // Cache keys are now scoped by account id:
        // `<accountId>::<agentId>::<sessionId>::<assistantTurnIndex>`.
        '${sdk.NapaxiEngine.defaultAccountId}::${sdk.NapaxiEngine.defaultAgentId}::session-42::0':
            [
              {
                'name': 'snake.html',
                'path': '/tmp/snake.html',
                'type': 'file',
                'sandbox_path': '/workspace/snake.html',
                'mime_type': 'text/html',
              },
              {
                'name': 'notes.md',
                'path': '/tmp/notes.md',
                'type': 'file',
                'sandbox_path': '/workspace/notes.md',
                'mime_type': 'text/markdown',
              },
            ],
      }),
    });
    final store = sdk.NapaxiConfigStore.memory();
    await store.saveProfile(
      const sdk.NapaxiConfigProfile(
        id: 'persisted',
        name: 'Persisted',
        provider: 'openai',
        model: 'saved-model',
        metadata: {
          'model_entries': [
            {
              'id': 'saved-model',
              'display_name': '',
              'capabilities': ['chat'],
            },
          ],
        },
      ),
      apiKey: 'sk-saved',
    );
    await store.saveSelection(
      const sdk.NapaxiConfigSelection(selectedProfileId: 'persisted'),
    );
    final fakeClient = FakeNapaxiChatClient(
      sessions: const [
        sdk.SessionInfo(
          key: sessionKey,
          title: 'Saved preview',
          preview: 'Saved answer',
          messageCount: 2,
          createdAt: '2026-05-12T10:00:00.000',
          updatedAt: '2026-05-12T10:01:00.000',
        ),
      ],
      historyByThreadId: const {
        'session-42': [
          sdk.ChatMessage(role: 'user', content: 'Make a page'),
          sdk.ChatMessage(role: 'assistant', content: 'Saved answer'),
        ],
      },
    );

    await tester.pumpWidget(
      _testApp(configStore: store, chatClientFactory: () async => fakeClient),
    );
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.text('Saved answer'));

    expect(find.text('Saved answer'), findsOneWidget);
    expect(find.text('snake.html'), findsOneWidget);
    expect(find.text('notes.md'), findsOneWidget);

    await tester.tap(find.byKey(const Key('conversation_attachments_button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('conversation_attachments_panel')),
      findsOneWidget,
    );
    expect(
      find.text('Generated · HTML · /workspace/snake.html'),
      findsOneWidget,
    );
    expect(find.text('Generated · MD · /workspace/notes.md'), findsOneWidget);
  });

  testWidgets('backfills restored generated attachments from tool history', (
    tester,
  ) async {
    const sessionKey = sdk.SessionKey(
      channelType: 'app',
      accountId: 'flutter_demo',
      threadId: 'session-42',
    );
    final store = sdk.NapaxiConfigStore.memory();
    await store.saveProfile(
      const sdk.NapaxiConfigProfile(
        id: 'persisted',
        name: 'Persisted',
        provider: 'openai',
        model: 'saved-model',
        metadata: {
          'model_entries': [
            {
              'id': 'saved-model',
              'display_name': '',
              'capabilities': ['chat'],
            },
          ],
        },
      ),
      apiKey: 'sk-saved',
    );
    await store.saveSelection(
      const sdk.NapaxiConfigSelection(selectedProfileId: 'persisted'),
    );
    final fakeClient = FakeNapaxiChatClient(
      sessions: const [
        sdk.SessionInfo(
          key: sessionKey,
          title: 'Saved preview',
          preview: 'Saved answer',
          messageCount: 3,
          createdAt: '2026-05-12T10:00:00.000',
          updatedAt: '2026-05-12T10:01:00.000',
        ),
      ],
      historyByThreadId: const {
        'session-42': [
          sdk.ChatMessage(role: 'user', content: 'Make a page'),
          sdk.ChatMessage(
            role: 'tool_calls',
            content: '',
            toolCalls: [
              sdk.ToolCallInfo(
                callId: 'write-1',
                name: 'write_file',
                arguments: {'path': '/workspace/snake.html'},
                result:
                    '{"files":[{"action":"updated","path":"/workspace/snake.html"}]}',
              ),
            ],
          ),
          sdk.ChatMessage(role: 'assistant', content: 'Saved answer'),
        ],
      },
      detectedFiles: const [
        sdk.ResolvedFile(
          sandboxPath: '/workspace/snake.html',
          realPath: '/tmp/snake.html',
          filename: 'snake.html',
          mimeType: 'text/html',
          isImage: false,
          exists: true,
        ),
      ],
    );

    await tester.pumpWidget(
      _testApp(configStore: store, chatClientFactory: () async => fakeClient),
    );
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.text('Saved answer'));

    expect(find.text('Saved answer'), findsOneWidget);
    expect(find.text('snake.html'), findsOneWidget);

    await tester.tap(find.byKey(const Key('conversation_attachments_button')));
    await tester.pumpAndSettle();

    expect(
      find.text('Generated · HTML · /workspace/snake.html'),
      findsOneWidget,
    );
  });

  testWidgets('shows grouped tool count in thinking header', (tester) async {
    final fakeClient = FakeNapaxiChatClient(
      events: const [
        sdk.ThinkingEvent(content: 'I inspected and patched the file.'),
        sdk.ToolCallEvent(
          callId: 'call-1',
          name: 'read_file',
          arguments: '{"path":"/workspace/snake.html"}',
        ),
        sdk.ToolResultEvent(
          callId: 'call-1',
          name: 'read_file',
          output: '{"path":"/workspace/snake.html","content":"body"}',
          isError: false,
        ),
        sdk.ToolCallEvent(
          callId: 'call-2',
          name: 'write_file',
          arguments:
              '{"patch":"*** Begin Patch\\n*** Update File: /workspace/snake.html\\n@@\\n-old\\n+new\\n*** End Patch"}',
        ),
        sdk.ToolOutputChunkEvent(
          callId: 'call-2',
          stream: 'patch',
          content:
              '{"type":"apply_patch_progress","action":"updated","path":"/workspace/snake.html","added_lines":1,"removed_lines":1}',
        ),
        sdk.ToolCallEvent(
          callId: 'call-3',
          name: 'write_file',
          arguments:
              '{"patch":"*** Begin Patch\\n*** Update File: /workspace/snake.html\\n@@\\n-old2\\n+new2\\n*** End Patch"}',
        ),
        sdk.ToolOutputChunkEvent(
          callId: 'call-3',
          stream: 'patch',
          content:
              '{"type":"apply_patch_progress","action":"updated","path":"/workspace/snake.html","added_lines":2,"removed_lines":1}',
        ),
        sdk.ResponseEvent(content: 'Done.'),
      ],
    );

    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'Grouped count',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Thought through'));
    await tester.pumpAndSettle();

    expect(find.text('2'), findsOneWidget);
    expect(find.text('已读取 1 个文件'), findsOneWidget);
    expect(find.text('正在编辑 snake.html +3 -2'), findsOneWidget);
  });

  testWidgets('renders SDK error as friendly assistant text', (tester) async {
    final fakeClient = FakeNapaxiChatClient(
      events: const [sdk.ErrorEvent(message: 'network unavailable')],
    );
    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'Trigger error',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pumpAndSettle();

    expect(
      find.text('napaxi error: network unavailable', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('switches the UI to Chinese', (tester) async {
    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => FakeNapaxiChatClient()),
    );

    await openModelConfiguration(tester);
    await tapVisible(tester, const Key('language_option_zh'));
    await tester.pumpAndSettle();
    await closeSettingsSheet(tester);

    expect(find.text('未配置模型'), findsNothing);
    expect(find.text('给 napaxi 发消息'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      '你好 napaxi',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pumpAndSettle();

    expect(find.text('你好 napaxi', findRichText: true), findsOneWidget);
    expect(find.text('请先选择聊天模型，再开始对话。', findRichText: true), findsOneWidget);
  });

  testWidgets('passes selected UI language to SDK config', (tester) async {
    final fakeClient = FakeNapaxiChatClient();
    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await openModelConfiguration(tester);
    await tapVisible(tester, const Key('language_option_zh'));
    await tester.pumpAndSettle();
    await closeSettingsSheet(tester);

    await tester.enterText(find.byKey(const Key('chat_input_field')), '你好');
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pumpAndSettle();

    expect(fakeClient.configuredResponseLanguage, 'zh');
  });

  testWidgets('restores saved UI language after rebuild', (tester) async {
    final preferences = MemoryDemoPreferencesStore();

    await tester.pumpWidget(_testApp(preferencesStore: preferences));
    await openModelConfiguration(tester);
    await tapVisible(tester, const Key('language_option_zh'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(_testApp(preferencesStore: preferences));
    await tester.pumpAndSettle();

    expect(find.text('给 napaxi 发消息'), findsOneWidget);

    await openModelConfiguration(tester);

    expect(find.text('基础配置'), findsOneWidget);
    expect(find.text('模型'), findsOneWidget);
  });

  testWidgets('opens chat history and starts a new chat', (tester) async {
    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => FakeNapaxiChatClient()),
    );

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'First conversation',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('session_history_button')));
    await tester.pumpAndSettle();

    expect(find.text('Recent'), findsOneWidget);
    expect(
      find.byKey(const Key('session_history_search_button')),
      findsOneWidget,
    );
    expect(find.text('First conversation'), findsWidgets);
    expect(find.text('just now'), findsOneWidget);
    expect(find.byKey(const Key('new_session_button')), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);

    await tester.tap(find.byKey(const Key('new_session_button')));
    await tester.pumpAndSettle();

    expect(find.text('First conversation'), findsNothing);
    expect(
      find.text(
        'Welcome to napaxi. Open Basic configuration from Settings, then chat with the SDK-backed agent.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows about page with current version and update action', (
    tester,
  ) async {
    final updates = FakeDemoUpdateService();

    await tester.pumpWidget(_testApp(updateService: updates));
    await tester.pumpAndSettle();

    await openAbout(tester);

    expect(find.text('About'), findsOneWidget);
    expect(find.text('Current version'), findsOneWidget);
    expect(find.byKey(const Key('about_current_version')), findsOneWidget);
    expect(find.text('0.0.13+13'), findsOneWidget);
    expect(find.byKey(const Key('about_check_update_button')), findsOneWidget);
  });

  testWidgets('about page hides update action when platform is unsupported', (
    tester,
  ) async {
    final updates = FakeDemoUpdateService(supportsUpdateCheck: false);

    await tester.pumpWidget(_testApp(updateService: updates));
    await tester.pumpAndSettle();

    await openAbout(tester);

    expect(find.text('About'), findsOneWidget);
    expect(find.text('Current version'), findsOneWidget);
    expect(find.text('0.0.13+13'), findsOneWidget);
    expect(find.byKey(const Key('about_check_update_button')), findsNothing);
  });

  testWidgets('opens native contact page from the about page', (tester) async {
    final updates = FakeDemoUpdateService();

    await tester.pumpWidget(_testApp(updateService: updates));
    await tester.pumpAndSettle();

    await openAbout(tester);
    await tester.tap(find.byKey(const Key('about_contact_button')));
    await tester.pumpAndSettle();

    expect(find.text('Contact us'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('tommi.m886@gmail.com'), findsOneWidget);
    expect(find.text('DingTalk community'), findsOneWidget);
    expect(find.text('WeChat community'), findsOneWidget);
    expect(find.text('Admin WeChat'), findsOneWidget);
    expect(find.text('shu_wentao'), findsOneWidget);
  });

  testWidgets('submits feedback from the about page', (tester) async {
    final updates = FakeDemoUpdateService();
    final feedback = FakeDemoFeedbackService();

    await tester.pumpWidget(
      _testApp(updateService: updates, feedbackService: feedback),
    );
    await tester.pumpAndSettle();

    await openAbout(tester);
    await tester.tap(find.byKey(const Key('about_feedback_button')));
    await tester.pumpAndSettle();

    expect(find.text('Feedback'), findsOneWidget);
    expect(find.byKey(const Key('feedback_content_field')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('feedback_content_field')),
      'The update installer page was confusing.',
    );
    await tester.enterText(
      find.byKey(const Key('feedback_contact_field')),
      'tester@example.com',
    );
    await tester.tap(find.byKey(const Key('submit_feedback_button')));
    await tester.pumpAndSettle();

    expect(
      feedback.submittedRequest?.content,
      'The update installer page was confusing.',
    );
    expect(feedback.submittedRequest?.contact, 'tester@example.com');
    expect(feedback.submittedRequest?.appVersion.display, '0.0.13+13');
    expect(find.text('Feedback submitted.'), findsOneWidget);
  });

  testWidgets('startup update prompt can be skipped until build changes', (
    tester,
  ) async {
    final updates = FakeDemoUpdateService(update: demoUpdate);

    await tester.pumpWidget(_testApp(updateService: updates));
    await tester.pumpAndSettle();

    expect(find.text('Update available'), findsOneWidget);
    expect(find.text('Bug fixes and polish.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('update_later_button')));
    await tester.pumpAndSettle();
    expect(updates.skipCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(_testApp(updateService: updates));
    await tester.pumpAndSettle();

    expect(find.text('Update available'), findsNothing);

    updates.update = const DemoUpdateInfo(
      buildKey: 'build-7',
      buildVersion: '0.0.7',
      buildVersionNo: '7',
      buildBuildVersion: 7,
      needForceUpdate: false,
      downloadUrl: 'https://example.com/app.apk',
      appUrl: 'https://www.pgyer.com/demo',
      updateDescription: 'Another build.',
      fileSizeBytes: 22345678,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(_testApp(updateService: updates));
    await tester.pumpAndSettle();

    expect(find.text('Update available'), findsOneWidget);
    expect(find.text('Another build.'), findsOneWidget);
  });

  testWidgets('manual update check ignores skipped version', (tester) async {
    final updates = FakeDemoUpdateService(update: demoUpdate)
      ..skippedIdentity = demoUpdate.identity;

    await tester.pumpWidget(_testApp(updateService: updates));
    await tester.pumpAndSettle();

    expect(find.text('Update available'), findsNothing);

    await openAbout(tester);
    await tester.tap(find.byKey(const Key('about_check_update_button')));
    await tester.pumpAndSettle();

    expect(updates.respectSkippedValues, contains(false));
    expect(find.text('Update available'), findsOneWidget);
  });

  testWidgets('update install keeps status visible until acknowledged', (
    tester,
  ) async {
    final updates = FakeDemoUpdateService(update: demoUpdate);

    await tester.pumpWidget(_testApp(updateService: updates));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('install_update_button')));
    await tester.pumpAndSettle();

    expect(updates.installCount, 1);
    expect(find.text('Update available'), findsOneWidget);
    expect(find.text('Android installer opened.'), findsOneWidget);
    expect(find.byKey(const Key('update_done_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('update_done_button')));
    await tester.pumpAndSettle();

    expect(find.text('Update available'), findsNothing);
  });

  testWidgets('force update prompt cannot be skipped', (tester) async {
    final updates = FakeDemoUpdateService(
      update: const DemoUpdateInfo(
        buildKey: 'build-6',
        buildVersion: '0.0.6',
        buildVersionNo: '6',
        buildBuildVersion: 6,
        needForceUpdate: true,
        downloadUrl: 'https://example.com/app.apk',
        appUrl: 'https://www.pgyer.com/demo',
        updateDescription: 'Security update.',
        fileSizeBytes: 12345678,
      ),
    );

    await tester.pumpWidget(_testApp(updateService: updates));
    await tester.pumpAndSettle();

    expect(find.text('Update available'), findsOneWidget);
    expect(find.text('This update is required.'), findsOneWidget);
    expect(find.byKey(const Key('update_later_button')), findsNothing);
  });

  testWidgets('favorites and unfavorites chat attachments from the side menu', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'napaxi_demo.favorite_attachments.v1': jsonEncode([
        {
          'id': 'path:https://example.com/report.html',
          'name': 'example.com',
          'path': 'https://example.com/report.html',
          'type': 'file',
          'mime_type': 'text/uri-list',
          'created_at': DateTime(2026, 5, 18).toIso8601String(),
        },
      ]),
    });

    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => FakeNapaxiChatClient()),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'Budget planning',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('session_history_button')));
    await tester.pumpAndSettle();

    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('example.com'), findsOneWidget);
    expect(find.text('Recent'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Favorites')).dy,
      lessThan(tester.getTopLeft(find.text('Recent')).dy),
    );

    await tester.tap(find.byKey(const Key('session_history_search_button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('session_history_search_field')),
      'example',
    );
    await tester.pumpAndSettle();

    expect(find.text('example.com'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('session_history_list')),
        matching: find.text('Budget planning'),
      ),
      findsNothing,
    );

    await tester.enterText(
      find.byKey(const Key('session_history_search_field')),
      'budget',
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('session_history_list')),
        matching: find.text('Budget planning'),
      ),
      findsWidgets,
    );
    expect(find.text('example.com'), findsNothing);

    await tester.tap(find.byKey(const Key('session_history_search_close')));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Remove from favorites'));
    await tester.pumpAndSettle();

    expect(find.text('Favorites'), findsNothing);
    expect(find.text('example.com'), findsNothing);
  });

  testWidgets(
    'matches restored uploaded attachments to legacy path favorites',
    (tester) async {
      const sessionKey = sdk.SessionKey(
        channelType: 'app',
        accountId: 'flutter_demo',
        threadId: 'session-42',
      );
      SharedPreferences.setMockInitialValues({
        'napaxi_demo.favorite_attachments.v1': jsonEncode([
          {
            'id': 'path:/tmp/photo.jpg',
            'name': 'photo.jpg',
            'path': '/tmp/photo.jpg',
            'type': 'image',
            'mime_type': 'image/jpeg',
            'created_at': DateTime(2026, 5, 18).toIso8601String(),
          },
        ]),
      });
      final store = sdk.NapaxiConfigStore.memory();
      await store.saveProfile(
        const sdk.NapaxiConfigProfile(
          id: 'persisted',
          name: 'Persisted',
          provider: 'openai',
          model: 'saved-model',
          metadata: {
            'model_entries': [
              {
                'id': 'saved-model',
                'display_name': '',
                'capabilities': ['chat'],
              },
            ],
          },
        ),
        apiKey: 'sk-saved',
      );
      await store.saveSelection(
        const sdk.NapaxiConfigSelection(selectedProfileId: 'persisted'),
      );
      final fakeClient = FakeNapaxiChatClient(
        sessions: const [
          sdk.SessionInfo(
            key: sessionKey,
            title: 'Photo chat',
            preview: 'Uploaded a photo',
            messageCount: 1,
            createdAt: '2026-05-18T10:00:00.000',
            updatedAt: '2026-05-18T10:01:00.000',
          ),
        ],
        historyByThreadId: const {
          'session-42': [
            sdk.ChatMessage(
              role: 'user',
              content: 'Uploaded a photo',
              attachments: [
                sdk.ChatAttachment(
                  kind: 'image',
                  mimeType: 'image/jpeg',
                  filename: 'photo.jpg',
                  sandboxPath: '/workspace/attachments/session-42/photo.jpg',
                ),
              ],
            ),
          ],
        },
      );

      await tester.pumpWidget(
        _testApp(configStore: store, chatClientFactory: () async => fakeClient),
      );
      await tester.pumpAndSettle();
      await pumpUntilFound(
        tester,
        find.byKey(const Key('favorite_attachment_on')),
      );

      expect(find.byKey(const Key('favorite_attachment_on')), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('conversation_attachments_button')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Uploaded · Image · /workspace/attachments/session-42/photo.jpg',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Generated · Image · /workspace/attachments/session-42/photo.jpg',
        ),
        findsNothing,
      );

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('favorite_attachment_on')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('session_history_button')));
      await tester.pumpAndSettle();

      expect(find.text('Favorites'), findsNothing);
      expect(find.text('photo.jpg'), findsNothing);
    },
  );

  testWidgets(
    'returns to the side menu after previewing a favorite attachment',
    (tester) async {
      WebViewPlatform.instance = _FakeWebViewPlatform();
      SharedPreferences.setMockInitialValues({
        'napaxi_demo.favorite_attachments.v1': jsonEncode([
          {
            'id': 'path:https://example.com/report.html',
            'name': 'example.com',
            'path': 'https://example.com/report.html',
            'type': 'file',
            'mime_type': 'text/uri-list',
            'created_at': DateTime(2026, 5, 18).toIso8601String(),
          },
        ]),
      });

      await tester.pumpWidget(_testApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('session_history_button')));
      await tester.pumpAndSettle();

      const favoriteId = 'path:https://example.com/report.html';
      await tester.tap(
        find.byKey(Key('favorite_attachment_tile_${favoriteId.hashCode}')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Preview'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('session_history_list')), findsOneWidget);
      expect(find.text('Favorites'), findsOneWidget);
      expect(find.text('example.com'), findsOneWidget);
    },
  );

  testWidgets('does not extract content web links into references', (
    tester,
  ) async {
    final fakeClient = FakeNapaxiChatClient(
      events: const [
        sdk.ResponseEvent(
          content:
              '参考链接：\nhttps://openai.com/docs\nhttps://platform.openai.com/docs',
        ),
      ],
    );

    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.enterText(find.byKey(const Key('chat_input_field')), 'links');
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('message_web_link_reference_list')),
      findsNothing,
    );
    expect(find.byKey(const Key('web_link_reference_1')), findsNothing);
    expect(find.byKey(const Key('web_link_reference_2')), findsNothing);
    expect(
      find.byKey(const Key('message_attachment_preview_list')),
      findsNothing,
    );
  });

  testWidgets('restores uploaded attachment from local path history metadata', (
    tester,
  ) async {
    const sessionKey = sdk.SessionKey(
      channelType: 'app',
      accountId: 'flutter_demo',
      threadId: 'session-local-attachment',
    );
    final store = sdk.NapaxiConfigStore.memory();
    await store.saveProfile(
      const sdk.NapaxiConfigProfile(
        id: 'persisted',
        name: 'Persisted',
        provider: 'openai',
        model: 'saved-model',
        metadata: {
          'model_entries': [
            {
              'id': 'saved-model',
              'display_name': '',
              'capabilities': ['chat'],
            },
          ],
        },
      ),
      apiKey: 'sk-saved',
    );
    await store.saveSelection(
      const sdk.NapaxiConfigSelection(selectedProfileId: 'persisted'),
    );
    final fakeClient = FakeNapaxiChatClient(
      sessions: const [
        sdk.SessionInfo(
          key: sessionKey,
          title: 'Local file chat',
          preview: 'Uploaded notes',
          messageCount: 1,
          createdAt: '2026-05-18T10:00:00.000',
          updatedAt: '2026-05-18T10:01:00.000',
        ),
      ],
      historyByThreadId: const {
        'session-local-attachment': [
          sdk.ChatMessage(
            role: 'user',
            content: 'Uploaded notes',
            attachments: [
              sdk.ChatAttachment(
                kind: 'document',
                mimeType: 'text/plain',
                filename: 'notes.txt',
                localPath: '/local/demo/notes.txt',
              ),
            ],
          ),
        ],
      },
    );

    await tester.pumpWidget(
      _testApp(configStore: store, chatClientFactory: () async => fakeClient),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('conversation_attachments_button')));
    await tester.pumpAndSettle();

    expect(
      find.text('Uploaded · Text · /local/demo/notes.txt'),
      findsOneWidget,
    );
    expect(find.text('Generated · Text · /local/demo/notes.txt'), findsNothing);
  });

  testWidgets('collapses long web link attachments until expanded', (
    tester,
  ) async {
    const sessionKey = sdk.SessionKey(
      channelType: 'app',
      accountId: 'test_user',
      threadId: 'session-links',
    );
    final store = sdk.NapaxiConfigStore.memory();
    await store.saveProfile(
      const sdk.NapaxiConfigProfile(
        id: 'persisted',
        name: 'Persisted',
        provider: 'openai',
        model: 'saved-model',
        metadata: {
          'model_entries': [
            {
              'id': 'saved-model',
              'display_name': '',
              'capabilities': ['chat'],
            },
          ],
        },
      ),
      apiKey: 'sk-saved',
    );
    await store.saveSelection(
      const sdk.NapaxiConfigSelection(selectedProfileId: 'persisted'),
    );
    final fakeClient = FakeNapaxiChatClient(
      sessions: const [
        sdk.SessionInfo(
          key: sessionKey,
          title: 'Link attachments',
          preview: 'Saved links',
          messageCount: 1,
          createdAt: '2026-05-18T10:00:00.000',
          updatedAt: '2026-05-18T10:01:00.000',
        ),
      ],
      historyByThreadId: const {
        'session-links': [
          sdk.ChatMessage(
            role: 'assistant',
            content: '参考链接已保存。',
            attachments: [
              sdk.ChatAttachment(
                kind: 'document',
                mimeType: 'text/uri-list',
                filename: 'openai.com',
                sandboxPath: 'https://openai.com/docs',
              ),
              sdk.ChatAttachment(
                kind: 'document',
                mimeType: 'text/uri-list',
                filename: 'platform.openai.com',
                sandboxPath: 'https://platform.openai.com/docs',
              ),
              sdk.ChatAttachment(
                kind: 'document',
                mimeType: 'text/uri-list',
                filename: 'example.com',
                sandboxPath: 'https://example.com/third',
              ),
            ],
          ),
        ],
      },
    );

    await tester.pumpWidget(
      _testApp(configStore: store, chatClientFactory: () async => fakeClient),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('message_web_link_reference_section')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('message_web_link_reference_list')),
      findsNothing,
    );
    expect(find.textContaining('+1 more'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('toggle_web_link_reference_section')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('message_web_link_reference_list')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('web_link_reference_1')), findsOneWidget);
    expect(find.byKey(const Key('web_link_reference_2')), findsOneWidget);
    expect(find.byKey(const Key('web_link_reference_3')), findsOneWidget);
    expect(find.text('https://example.com/third'), findsOneWidget);
  });

  testWidgets('orders chat history by most recent update', (tester) async {
    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => FakeNapaxiChatClient()),
    );

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'Older conversation',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('session_history_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new_session_button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'Newer conversation',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('session_history_button')));
    await tester.pumpAndSettle();

    final newerTop = tester
        .getTopLeft(find.byKey(const Key('session_tile_session-2')))
        .dy;
    final olderTop = tester
        .getTopLeft(find.byKey(const Key('session_tile_session-1')))
        .dy;

    expect(newerTop, lessThan(olderTop));
  });

  testWidgets('long-presses chat history to pin and delete sessions', (
    tester,
  ) async {
    final fakeClient = FakeNapaxiChatClient();
    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'Older conversation',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('session_history_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new_session_button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'Newer conversation',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('session_history_button')));
    await tester.pumpAndSettle();
    await tester.longPress(find.byKey(const Key('session_tile_session-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('session_pin_action_session-1')));
    await tester.pumpAndSettle();

    expect(find.text('Pinned'), findsOneWidget);
    final pinnedTop = tester
        .getTopLeft(find.byKey(const Key('session_tile_session-1')))
        .dy;
    final recentTop = tester
        .getTopLeft(find.byKey(const Key('session_tile_session-2')))
        .dy;
    expect(pinnedTop, lessThan(recentTop));

    await tester.longPress(find.byKey(const Key('session_tile_session-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('session_delete_action_session-2')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('confirm_delete_session_button')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('confirm_delete_session_button')));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (fakeClient.deleteCount > 0 &&
          find.byKey(const Key('session_tile_session-2')).evaluate().isEmpty) {
        break;
      }
    }
    await tester.pumpAndSettle();

    expect(fakeClient.deletedSession?.threadId, 'session-2');
    expect(fakeClient.deleteCount, 1);
    expect(find.byKey(const Key('session_tile_session-2')), findsNothing);
  });

  testWidgets('searches chat history from the side menu', (tester) async {
    await tester.pumpWidget(_testApp());

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'Budget planning',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('session_history_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new_session_button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'Travel ideas',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('session_history_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('session_history_search_button')));
    await tester.pumpAndSettle();

    expect(find.text('Recent'), findsNothing);
    expect(find.byKey(const Key('new_session_button')), findsNothing);

    await tester.enterText(
      find.byKey(const Key('session_history_search_field')),
      'budget',
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('session_history_list')),
        matching: find.byKey(const Key('session_tile_session-1')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('session_history_list')),
        matching: find.byKey(const Key('session_tile_session-2')),
      ),
      findsNothing,
    );

    await tester.enterText(
      find.byKey(const Key('session_history_search_field')),
      'nothing-here',
    );
    await tester.pumpAndSettle();

    expect(find.text('No matching chats'), findsOneWidget);
  });

  testWidgets('swipes chat history open and closed', (tester) async {
    await tester.pumpWidget(_testApp());

    await tester.drag(
      find.byKey(const Key('chat_message_list')),
      const Offset(320, 0),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recent'), findsOneWidget);
    expect(
      find.byKey(const Key('session_history_search_button')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('new_session_button')), findsOneWidget);

    await tester.dragFrom(const Offset(320, 300), const Offset(-320, 0));
    await tester.pumpAndSettle();

    expect(find.text('Recent'), findsNothing);
    expect(
      find.byKey(const Key('session_history_search_button')),
      findsNothing,
    );
    expect(find.byKey(const Key('new_session_button')), findsNothing);
  });

  testWidgets('dismisses the keyboard focus when tapping the message list', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp());

    await tester.tap(find.byKey(const Key('chat_input_field')));
    await tester.pump();

    var input = tester.widget<TextField>(
      find.byKey(const Key('chat_input_field')),
    );
    expect(input.focusNode?.hasFocus, isTrue);

    await tester.tap(find.byKey(const Key('chat_message_list')));
    await tester.pump();

    input = tester.widget<TextField>(find.byKey(const Key('chat_input_field')));
    expect(input.focusNode?.hasFocus, isFalse);
  });

  testWidgets('shows regenerated file once per turn', (tester) async {
    const sessionKey = sdk.SessionKey(
      channelType: 'app',
      accountId: 'flutter_demo',
      threadId: 'session-dedup',
    );
    final store = sdk.NapaxiConfigStore.memory();
    await store.saveProfile(
      const sdk.NapaxiConfigProfile(
        id: 'persisted',
        name: 'Persisted',
        provider: 'openai',
        model: 'saved-model',
        metadata: {
          'model_entries': [
            {
              'id': 'saved-model',
              'display_name': '',
              'capabilities': ['chat'],
            },
          ],
        },
      ),
      apiKey: 'sk-saved',
    );
    await store.saveSelection(
      const sdk.NapaxiConfigSelection(selectedProfileId: 'persisted'),
    );

    final fakeClient = FakeNapaxiChatClient(
      sessions: const [
        sdk.SessionInfo(
          key: sessionKey,
          title: 'Clock',
          preview: 'Title fixed.',
          messageCount: 4,
          createdAt: '2026-06-01T10:00:00.000',
          updatedAt: '2026-06-01T10:02:00.000',
        ),
      ],
      historyByThreadId: const {
        'session-dedup': [
          sdk.ChatMessage(role: 'user', content: 'Create clock'),
          sdk.ChatMessage(
            role: 'tool_calls',
            content: '',
            toolCalls: [
              sdk.ToolCallInfo(
                callId: 'write-1',
                name: 'write_file',
                arguments: {'path': '/workspace/clock.html'},
                result:
                    '{"files":[{"action":"added","path":"/workspace/clock.html"}]}',
              ),
            ],
          ),
          sdk.ChatMessage(role: 'assistant', content: 'Clock created.'),
          sdk.ChatMessage(role: 'user', content: 'Fix title'),
          sdk.ChatMessage(
            role: 'tool_calls',
            content: '',
            toolCalls: [
              sdk.ToolCallInfo(
                callId: 'write-2',
                name: 'write_file',
                arguments: {'path': '/workspace/clock.html'},
                result:
                    '{"files":[{"action":"updated","path":"/workspace/clock.html"}]}',
              ),
            ],
          ),
          sdk.ChatMessage(role: 'assistant', content: 'Title fixed.'),
        ],
      },
      detectedFiles: const [
        sdk.ResolvedFile(
          sandboxPath: '/workspace/clock.html',
          realPath: '/tmp/clock.html',
          filename: 'clock.html',
          mimeType: 'text/html',
          isImage: false,
          exists: true,
        ),
      ],
    );

    await tester.pumpWidget(
      _testApp(configStore: store, chatClientFactory: () async => fakeClient),
    );
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.text('Title fixed.'));

    // clock.html is generated in turn 1 (added) and again in turn 2 (updated),
    // so it appears once per turn — deduped within each turn, not across the
    // whole conversation. Two per-turn trailing blocks render it.
    expect(find.text('clock.html'), findsNWidgets(2));
    final trailingBlocks = _findTurnGeneratedAttachments();
    expect(trailingBlocks, findsNWidgets(2));

    // The first turn's attachment block must sit ABOVE the second user bubble
    // ('Fix title') — i.e. attachments land at the end of THEIR turn, not all
    // pinned below the whole conversation.
    final firstBlockY = tester.getTopLeft(trailingBlocks.first).dy;
    final secondUserBubbleY = tester.getTopLeft(find.text('Fix title')).dy;
    expect(firstBlockY, lessThan(secondUserBubbleY));
  });

  testWidgets('shows generated files in trailing section after interrupted run', (
    tester,
  ) async {
    const sessionKey = sdk.SessionKey(
      channelType: 'app',
      accountId: 'flutter_demo',
      threadId: 'session-interrupted',
    );
    final store = sdk.NapaxiConfigStore.memory();
    await store.saveProfile(
      const sdk.NapaxiConfigProfile(
        id: 'persisted',
        name: 'Persisted',
        provider: 'openai',
        model: 'saved-model',
        metadata: {
          'model_entries': [
            {
              'id': 'saved-model',
              'display_name': '',
              'capabilities': ['chat'],
            },
          ],
        },
      ),
      apiKey: 'sk-saved',
    );
    await store.saveSelection(
      const sdk.NapaxiConfigSelection(selectedProfileId: 'persisted'),
    );

    final fakeClient = FakeNapaxiChatClient(
      sessions: const [
        sdk.SessionInfo(
          key: sessionKey,
          title: 'Clock',
          preview: 'Build clock',
          messageCount: 2,
          createdAt: '2026-06-01T10:00:00.000',
          updatedAt: '2026-06-01T10:01:00.000',
        ),
      ],
      historyByThreadId: const {
        'session-interrupted': [
          sdk.ChatMessage(role: 'user', content: 'Build clock'),
          sdk.ChatMessage(
            role: 'tool_calls',
            content: '',
            toolCalls: [
              sdk.ToolCallInfo(
                callId: 'write-1',
                name: 'write_file',
                arguments: {'path': '/workspace/clock.html'},
                result:
                    '{"files":[{"action":"added","path":"/workspace/clock.html"}]}',
              ),
            ],
          ),
          sdk.ChatMessage(role: 'assistant', content: ''),
        ],
      },
      detectedFiles: const [
        sdk.ResolvedFile(
          sandboxPath: '/workspace/clock.html',
          realPath: '/tmp/clock.html',
          filename: 'clock.html',
          mimeType: 'text/html',
          isImage: false,
          exists: true,
        ),
      ],
    );

    await tester.pumpWidget(
      _testApp(configStore: store, chatClientFactory: () async => fakeClient),
    );
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.text('Build clock'));

    // File must appear in trailing section even though assistant content is
    // empty (simulates an interrupted run where response was not delivered).
    expect(find.text('clock.html'), findsOneWidget);
    expect(_findTurnGeneratedAttachments(), findsOneWidget);
  });

  testWidgets('shell that only reads a file produces no attachment', (
    tester,
  ) async {
    const sessionKey = sdk.SessionKey(
      channelType: 'app',
      accountId: 'flutter_demo',
      threadId: 'session-shell-read',
    );
    final store = sdk.NapaxiConfigStore.memory();
    await store.saveProfile(
      const sdk.NapaxiConfigProfile(
        id: 'persisted',
        name: 'Persisted',
        provider: 'openai',
        model: 'saved-model',
        metadata: {
          'model_entries': [
            {
              'id': 'saved-model',
              'display_name': '',
              'capabilities': ['chat'],
            },
          ],
        },
      ),
      apiKey: 'sk-saved',
    );
    await store.saveSelection(
      const sdk.NapaxiConfigSelection(selectedProfileId: 'persisted'),
    );

    final fakeClient = FakeNapaxiChatClient(
      sessions: const [
        sdk.SessionInfo(
          key: sessionKey,
          title: 'Inspect',
          preview: 'Here is the file.',
          messageCount: 2,
          createdAt: '2026-06-01T10:00:00.000',
          updatedAt: '2026-06-01T10:01:00.000',
        ),
      ],
      historyByThreadId: const {
        'session-shell-read': [
          sdk.ChatMessage(role: 'user', content: 'Show config'),
          sdk.ChatMessage(
            role: 'tool_calls',
            content: '',
            toolCalls: [
              // A read-only shell command that merely *mentions* a path. It
              // must not surface the file as a generated attachment.
              sdk.ToolCallInfo(
                callId: 'shell-1',
                name: 'shell',
                arguments: {'command': 'cat /workspace/config.json'},
                result: 'contents of /workspace/config.json',
              ),
            ],
          ),
          sdk.ChatMessage(role: 'assistant', content: 'Here is the file.'),
        ],
      },
      detectedFiles: const [
        sdk.ResolvedFile(
          sandboxPath: '/workspace/config.json',
          realPath: '/tmp/config.json',
          filename: 'config.json',
          mimeType: 'application/json',
          isImage: false,
          exists: true,
        ),
      ],
    );

    await tester.pumpWidget(
      _testApp(configStore: store, chatClientFactory: () async => fakeClient),
    );
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.text('Here is the file.'));

    // The file was only read, never created/modified, so no attachment chip
    // and no per-turn trailing block should appear.
    expect(find.text('config.json'), findsNothing);
    expect(_findTurnGeneratedAttachments(), findsNothing);
  });

  testWidgets('shell side-effect files are not surfaced as attachments', (
    tester,
  ) async {
    const sessionKey = sdk.SessionKey(
      channelType: 'app',
      accountId: 'flutter_demo',
      threadId: 'session-shell-venv',
    );
    final store = sdk.NapaxiConfigStore.memory();
    await store.saveProfile(
      const sdk.NapaxiConfigProfile(
        id: 'persisted',
        name: 'Persisted',
        provider: 'openai',
        model: 'saved-model',
        metadata: {
          'model_entries': [
            {
              'id': 'saved-model',
              'display_name': '',
              'capabilities': ['chat'],
            },
          ],
        },
      ),
      apiKey: 'sk-saved',
    );
    await store.saveSelection(
      const sdk.NapaxiConfigSelection(selectedProfileId: 'persisted'),
    );

    final fakeClient = FakeNapaxiChatClient(
      sessions: const [
        sdk.SessionInfo(
          key: sessionKey,
          title: 'Venv',
          preview: 'Environment ready.',
          messageCount: 2,
          createdAt: '2026-06-01T10:00:00.000',
          updatedAt: '2026-06-01T10:01:00.000',
        ),
      ],
      historyByThreadId: const {
        'session-shell-venv': [
          sdk.ChatMessage(role: 'user', content: 'Set up a venv'),
          sdk.ChatMessage(
            role: 'tool_calls',
            content: '',
            toolCalls: [
              // A shell command whose side effect creates a whole venv tree.
              // Its result is plain stdout — no structured file manifest — so
              // (matching Codex) none of the created files become attachments.
              sdk.ToolCallInfo(
                callId: 'shell-venv',
                name: 'shell',
                arguments: {'command': 'python -m venv .venv'},
                result: '',
              ),
            ],
          ),
          sdk.ChatMessage(role: 'assistant', content: 'Environment ready.'),
        ],
      },
      // The venv files exist in the sandbox listing. The removed workspace-diff
      // logic would have scooped these up as "new" generated attachments; the
      // Codex-style explicit-only path must ignore the workspace listing here.
      workspaceFiles: [
        sdk.WorkspaceFileInfo(
          name: 'pyvenv.cfg',
          sandboxPath: '/workspace/.venv/pyvenv.cfg',
          realPath: '/tmp/.venv/pyvenv.cfg',
          mimeType: 'text/plain',
          isDirectory: false,
          sizeBytes: 120,
          modified: DateTime(2026, 6, 1, 10),
        ),
        sdk.WorkspaceFileInfo(
          name: 'python3.12',
          sandboxPath: '/workspace/.venv/bin/python3.12',
          realPath: '/tmp/.venv/bin/python3.12',
          mimeType: 'application/octet-stream',
          isDirectory: false,
          sizeBytes: 2048,
          modified: DateTime(2026, 6, 1, 10),
        ),
      ],
    );

    await tester.pumpWidget(
      _testApp(configStore: store, chatClientFactory: () async => fakeClient),
    );
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.text('Environment ready.'));

    // No per-turn attachment block, and none of the venv noise files surface.
    expect(_findTurnGeneratedAttachments(), findsNothing);
    expect(find.text('pyvenv.cfg'), findsNothing);
    expect(find.text('python3.12'), findsNothing);
  });

  group('Developer workspace terminal', () {
    testWidgets('overflow menu hidden in general scenario', (tester) async {
      SharedPreferences.setMockInitialValues({
        'napaxi_demo.active_scenario.v1': 'napaxi.scenario.general',
      });
      final fakeClient = FakeNapaxiChatClient();
      await tester.pumpWidget(
        _testApp(chatClientFactory: () async => fakeClient),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('dev_overflow_menu_button')), findsNothing);
    });

    testWidgets('overflow menu present in developer scenario', (tester) async {
      SharedPreferences.setMockInitialValues({
        'napaxi_demo.active_scenario.v1': 'napaxi.scenario.mobile_development',
      });
      final fakeClient = FakeNapaxiChatClient();
      await tester.pumpWidget(
        _testApp(chatClientFactory: () async => fakeClient),
      );
      await pumpUntilFound(
        tester,
        find.byKey(const Key('dev_overflow_menu_button')),
      );

      expect(find.byKey(const Key('dev_overflow_menu_button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('dev_overflow_menu_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('menu_new_terminal')), findsOneWidget);
      expect(find.byKey(const Key('menu_copy_workspace_path')), findsOneWidget);
      expect(find.byKey(const Key('menu_copy_branch_name')), findsOneWidget);
    });

    testWidgets('New Terminal opens an embedded terminal session', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'napaxi_demo.active_scenario.v1': 'napaxi.scenario.mobile_development',
      });
      final fakeClient = FakeNapaxiChatClient();
      await tester.pumpWidget(
        _testApp(
          chatClientFactory: () async => fakeClient,
          terminalBackendFactory: FakeTerminalBackend.new,
        ),
      );
      await pumpUntilFound(
        tester,
        find.byKey(const Key('dev_overflow_menu_button')),
      );

      await tester.tap(find.byKey(const Key('dev_overflow_menu_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('menu_new_terminal')));
      // _openSandboxTerminal awaits _resolveWorkspaceDir() before switching
      // sessions, so pump a few frames for that async gap rather than
      // pumpAndSettle (the terminal's blinking cursor never settles).
      await pumpUntilFound(tester, find.byKey(const Key('chat_terminal_view')));

      expect(find.byKey(const Key('chat_terminal_view')), findsOneWidget);
      expect(find.byType(SandboxTerminalScreen), findsNothing);
    });
  });

  group('FakeTerminalBackend', () {
    test('start emits welcome banner', () async {
      final backend = FakeTerminalBackend();
      final chunks = <String>[];
      final sub = backend.output.listen(chunks.add);
      await backend.start(
        argv: const ['/bin/sh', '-lc'],
        workdir: '/workspace',
        cols: 80,
        rows: 24,
      );
      await Future<void>.delayed(Duration.zero);
      expect(chunks.join(), contains('napaxi fake terminal ready'));
      await sub.cancel();
      await backend.kill();
    });

    test('write echoes input and re-prompts on newline', () async {
      final backend = FakeTerminalBackend();
      final chunks = <String>[];
      final sub = backend.output.listen(chunks.add);
      backend.write('ls\r');
      await Future<void>.delayed(Duration.zero);
      final joined = chunks.join();
      expect(joined, contains('ls')); // echoed
      expect(joined, contains('\$ ')); // re-prompt
      await sub.cancel();
      await backend.kill();
    });
  });

  group('TerminalModifierController', () {
    test('Ctrl applies to the next text input and then clears', () {
      final modifiers = TerminalModifierController();
      addTearDown(modifiers.dispose);

      modifiers.toggleCtrl();
      expect(modifiers.ctrlActive, isTrue);

      expect(modifiers.consumeTextInput('c'), '\x03');
      expect(modifiers.ctrlActive, isFalse);
      expect(modifiers.consumeTextInput('c'), 'c');
    });

    test('Ctrl handles uppercase letters with the same control character', () {
      final modifiers = TerminalModifierController();
      addTearDown(modifiers.dispose);

      modifiers.toggleCtrl();

      expect(modifiers.consumeTextInput('C'), '\x03');
      expect(modifiers.ctrlActive, isFalse);
    });

    test('Space passes through and Ctrl+Space sends NUL', () {
      final modifiers = TerminalModifierController();
      addTearDown(modifiers.dispose);

      expect(modifiers.consumeTextInput(' '), ' ');

      modifiers.toggleCtrl();

      expect(modifiers.consumeTextInput(' '), '\x00');
      expect(modifiers.ctrlActive, isFalse);
    });
  });

  testWidgets('dev workbench drawer shows source-control tabs and commits', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'napaxi_demo.active_scenario.v1': 'napaxi.scenario.mobile_development',
    });
    const mobileScenario = sdk.NapaxiScenarioPack(
      id: 'napaxi.scenario.mobile_development',
      version: '1',
      label: 'Developer Workbench',
      description: 'Mobile development scenario.',
      risk: 'critical',
      activation: 'host_policy',
      uiContributions: [
        sdk.NapaxiScenarioUiContribution(
          id: 'ui.repo_workbench',
          capabilityId: 'napaxi.tool.git',
          placement: 'left_menu',
          title: 'Projects',
          icon: 'folder_git',
          renderer: 'repo_workbench',
        ),
      ],
    );
    final fakeClient = FakeNapaxiChatClient(
      scenarioPacks: const [mobileScenario],
      gitRepositories: [
        DemoRepositoryInfo(
          name: 'demo',
          directory: 'demo',
          displayDirectory: 'demo',
          absolutePath: '/tmp/git_repos/demo',
          modified: DateTime(2026, 1, 2, 3, 4),
        ),
      ],
      gitChangesSets: {
        'demo': const DemoGitChangeSet(
          success: true,
          branch: 'main',
          entries: [
            DemoGitChangeEntry(
              path: 'lib/main.dart',
              indexCode: 'M',
              workCode: ' ',
              area: DemoGitChangeArea.staged,
              category: DemoGitChangeCategory.modified,
              additions: 5,
              deletions: 1,
            ),
            DemoGitChangeEntry(
              path: 'README.md',
              indexCode: ' ',
              workCode: 'M',
              area: DemoGitChangeArea.unstaged,
              category: DemoGitChangeCategory.modified,
              additions: 2,
              deletions: 0,
            ),
          ],
        ),
      },
      gitBranches: const {
        'demo': [
          DemoGitBranchInfo(name: 'main', remote: false, current: true),
          DemoGitBranchInfo(name: 'feature', remote: false, current: false),
        ],
      },
      gitCommitHistory: {
        'demo': [
          DemoGitCommitInfo(
            graph: '*',
            hash: 'abc123def456',
            shortHash: 'abc123d',
            subject: 'Add source control graph',
            authorName: 'Ada',
            authoredAt: DateTime(2026, 1, 2, 3, 8),
            refs: 'HEAD -> main',
          ),
        ],
      },
      gitCommitDiffs: const {
        'demo:abc123def456': DemoGitCommitDiff(
          success: true,
          files: [
            DemoGitCommitFileChange(
              path: 'lib/main.dart',
              additions: 2,
              deletions: 1,
            ),
          ],
          hunks: [
            DemoDiffHunk(
              header: '@@ -1,2 +1,3 @@',
              lines: [
                DemoDiffLine(
                  type: DemoDiffLineType.context,
                  text: 'void main() {',
                  oldLine: 1,
                  newLine: 1,
                ),
                DemoDiffLine(
                  type: DemoDiffLineType.added,
                  text: '  print("graph");',
                  newLine: 2,
                ),
              ],
            ),
          ],
        ),
      },
      gitRepositoryChildren: {
        'demo:': [
          DemoRepositoryFileItem(
            name: 'lib',
            relativePath: 'lib',
            absolutePath: '/tmp/git_repos/demo/lib',
            isDirectory: true,
            modified: DateTime(2026, 1, 2, 3, 5),
          ),
          DemoRepositoryFileItem(
            name: 'README.md',
            relativePath: 'README.md',
            absolutePath: '/tmp/git_repos/demo/README.md',
            isDirectory: false,
            sizeBytes: 256,
            modified: DateTime(2026, 1, 2, 3, 6),
            mimeType: 'text/plain',
          ),
        ],
        'demo:lib': [
          DemoRepositoryFileItem(
            name: 'main.dart',
            relativePath: 'lib/main.dart',
            absolutePath: '/tmp/git_repos/demo/lib/main.dart',
            isDirectory: false,
            sizeBytes: 120,
            modified: DateTime(2026, 1, 2, 3, 7),
            mimeType: 'text/plain',
          ),
        ],
      },
    );

    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.tap(find.byKey(const Key('dev_workbench_button')));
    await tester.pumpAndSettle();
    await pumpUntilFound(
      tester,
      find.byKey(const Key('source_control_tab_files')),
    );

    // Two tabs render.
    expect(find.byKey(const Key('source_control_tab_files')), findsOneWidget);
    expect(find.byKey(const Key('source_control_tab_changes')), findsOneWidget);

    // Files tab (default): root tree shows the folder + the modified file row.
    await pumpUntilFound(tester, find.byKey(const Key('repo_file_row_lib')));
    expect(find.byKey(const Key('repo_file_row_lib')), findsOneWidget);
    expect(find.byKey(const Key('repo_file_row_README.md')), findsOneWidget);

    // Expand the folder -> child file row appears.
    await tester.tap(find.byKey(const Key('repo_file_row_lib')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('repo_file_row_lib/main.dart')),
      findsOneWidget,
    );

    // Switch to the Changes tab.
    await tester.tap(find.byKey(const Key('source_control_tab_changes')));
    await tester.pumpAndSettle();
    await pumpUntilFound(
      tester,
      find.byKey(const Key('source_control_staged_group')),
    );
    expect(
      find.byKey(const Key('source_control_staged_group')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('source_control_unstaged_group')),
      findsOneWidget,
    );
    expect(find.text('2 changed'), findsOneWidget);
    expect(find.textContaining('main · 2 changed'), findsNothing);

    // The branch label in the drawer header opens the same searchable branch
    // picker used by the full-screen workbench.
    await tester.tap(
      find.byKey(const Key('source_control_branch_selector_button')),
    );
    await tester.pumpAndSettle();
    await pumpUntilFound(
      tester,
      find.byKey(const Key('git_branch_search_field')),
    );
    await tester.enterText(
      find.byKey(const Key('git_branch_search_field')),
      'feature',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('git_branch_feature')));
    await tester.pumpAndSettle();
    expect(fakeClient.switchedGitDirectory, 'demo');
    expect(fakeClient.switchedGitBranch, 'feature');
    expect(fakeClient.switchedGitBranchAllowedDirty, false);

    // The status-line branch label opens a Git graph; tapping a commit reveals
    // the files and diff for that commit.
    await tester.tap(find.byKey(const Key('source_control_git_graph_button')));
    await tester.pumpAndSettle();
    await pumpUntilFound(
      tester,
      find.byKey(const Key('git_graph_commit_list')),
    );
    expect(find.text('Add source control graph'), findsOneWidget);
    await tester.tap(find.byKey(const Key('git_graph_commit_abc123d')));
    await tester.pumpAndSettle();
    expect(find.text('lib/main.dart'), findsWidgets);
    expect(find.textContaining('print("graph")'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    // Stage the unstaged file.
    await tester.tap(find.byKey(const Key('source_control_stage_README.md')));
    await tester.pumpAndSettle();
    expect(fakeClient.stagedGitPaths, contains('README.md'));

    // Commit flow: open dialog, type a message, confirm.
    await tester.tap(find.byKey(const Key('commit_button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('commit_message_field')),
      'Initial commit',
    );
    await tester.tap(find.byKey(const Key('commit_confirm_button')));
    await tester.pumpAndSettle();
    expect(fakeClient.commitMessages.last, 'Initial commit');
  });

  testWidgets('commit split-button dropdown drives push and pull', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'napaxi_demo.active_scenario.v1': 'napaxi.scenario.mobile_development',
    });
    const mobileScenario = sdk.NapaxiScenarioPack(
      id: 'napaxi.scenario.mobile_development',
      version: '1',
      label: 'Developer Workbench',
      description: 'Mobile development scenario.',
      risk: 'critical',
      activation: 'host_policy',
      uiContributions: [
        sdk.NapaxiScenarioUiContribution(
          id: 'ui.repo_workbench',
          capabilityId: 'napaxi.tool.git',
          placement: 'left_menu',
          title: 'Projects',
          icon: 'folder_git',
          renderer: 'repo_workbench',
        ),
      ],
    );
    final fakeClient = FakeNapaxiChatClient(
      scenarioPacks: const [mobileScenario],
      gitRepositories: [
        DemoRepositoryInfo(
          name: 'demo',
          directory: 'demo',
          displayDirectory: 'demo',
          absolutePath: '/tmp/git_repos/demo',
          modified: DateTime(2026, 1, 2, 3, 4),
        ),
      ],
      gitChangesSets: {
        'demo': const DemoGitChangeSet(
          success: true,
          branch: 'main',
          entries: [
            DemoGitChangeEntry(
              path: 'lib/main.dart',
              indexCode: 'M',
              workCode: ' ',
              area: DemoGitChangeArea.staged,
              category: DemoGitChangeCategory.modified,
              additions: 5,
              deletions: 1,
            ),
          ],
        ),
      },
      gitRemotes: {
        'demo': const [DemoGitRemoteInfo(name: 'origin')],
      },
      gitRepositoryChildren: const {},
    );

    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.tap(find.byKey(const Key('dev_workbench_button')));
    await tester.pumpAndSettle();
    await pumpUntilFound(
      tester,
      find.byKey(const Key('source_control_tab_changes')),
    );
    await tester.tap(find.byKey(const Key('source_control_tab_changes')));
    await tester.pumpAndSettle();
    await pumpUntilFound(
      tester,
      find.byKey(const Key('source_control_staged_group')),
    );
    // Let the remote-availability check resolve so the dropdown is enabled.
    await tester.pumpAndSettle();

    // Selecting Pull from the menu only stages the selection — it must NOT
    // execute until the main button is tapped.
    await tester.tap(find.byKey(const Key('commit_actions_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('commit_action_pull')));
    await tester.pumpAndSettle();
    expect(fakeClient.pulledGitDirectory, isNull);

    // Tapping the main body runs the selected action (pull).
    await tester.tap(find.byKey(const Key('commit_button')));
    await tester.pumpAndSettle();
    expect(fakeClient.pulledGitDirectory, 'demo');

    // Select Push, then run it from the main button.
    await tester.tap(find.byKey(const Key('commit_actions_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('commit_action_push')));
    await tester.pumpAndSettle();
    expect(fakeClient.pushedGitDirectory, isNull);
    await tester.tap(find.byKey(const Key('commit_button')));
    await tester.pumpAndSettle();
    expect(fakeClient.pushedGitDirectory, 'demo');

    // Commit & Push runs the dialog flow, commits, then pushes.
    await tester.tap(find.byKey(const Key('commit_actions_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('commit_action_commit_and_push')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('commit_button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('commit_message_field')),
      'Ship it',
    );
    await tester.tap(find.byKey(const Key('commit_confirm_button')));
    await tester.pumpAndSettle();
    expect(fakeClient.commitMessages.last, 'Ship it');
    expect(fakeClient.pushedGitDirectory, 'demo');
  });

  testWidgets('change row expands an inline diff when tapped', (tester) async {
    SharedPreferences.setMockInitialValues({
      'napaxi_demo.active_scenario.v1': 'napaxi.scenario.mobile_development',
    });
    const mobileScenario = sdk.NapaxiScenarioPack(
      id: 'napaxi.scenario.mobile_development',
      version: '1',
      label: 'Developer Workbench',
      description: 'Mobile development scenario.',
      risk: 'critical',
      activation: 'host_policy',
      uiContributions: [
        sdk.NapaxiScenarioUiContribution(
          id: 'ui.repo_workbench',
          capabilityId: 'napaxi.tool.git',
          placement: 'left_menu',
          title: 'Projects',
          icon: 'folder_git',
          renderer: 'repo_workbench',
        ),
      ],
    );
    final fakeClient = FakeNapaxiChatClient(
      scenarioPacks: const [mobileScenario],
      gitRepositories: [
        DemoRepositoryInfo(
          name: 'demo',
          directory: 'demo',
          displayDirectory: 'demo',
          absolutePath: '/tmp/git_repos/demo',
          modified: DateTime(2026, 1, 2, 3, 4),
        ),
      ],
      gitChangesSets: {
        'demo': const DemoGitChangeSet(
          success: true,
          branch: 'main',
          entries: [
            DemoGitChangeEntry(
              path: 'lib/main.dart',
              indexCode: ' ',
              workCode: 'M',
              area: DemoGitChangeArea.unstaged,
              category: DemoGitChangeCategory.modified,
              additions: 2,
              deletions: 1,
            ),
          ],
        ),
      },
      gitFileDiffs: {
        'demo:lib/main.dart:0': const DemoGitFileDiff(
          success: true,
          hunks: [
            DemoDiffHunk(
              header: '@@ -1,2 +1,3 @@',
              lines: [
                DemoDiffLine(
                  type: DemoDiffLineType.context,
                  text: 'void main() {',
                  oldLine: 1,
                  newLine: 1,
                ),
                DemoDiffLine(
                  type: DemoDiffLineType.removed,
                  text: '  print("hi");',
                  oldLine: 2,
                ),
                DemoDiffLine(
                  type: DemoDiffLineType.added,
                  text: '  print("hello");',
                  newLine: 2,
                ),
              ],
            ),
          ],
        ),
      },
    );

    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.tap(find.byKey(const Key('dev_workbench_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('source_control_tab_changes')));
    await tester.pumpAndSettle();
    await pumpUntilFound(
      tester,
      find.byKey(const Key('source_control_change_unstaged_lib/main.dart')),
    );

    // Diff is hidden until the row is tapped.
    expect(find.textContaining('print("hello")'), findsNothing);

    await tester.tap(
      find.byKey(const Key('source_control_change_unstaged_lib/main.dart')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('@@ -1,2 +1,3 @@'), findsOneWidget);
    expect(find.textContaining('print("hello")'), findsOneWidget);
    expect(find.textContaining('print("hi")'), findsOneWidget);
  });
}

class _FakeWebViewPlatform extends WebViewPlatform {
  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) {
    return _FakePlatformNavigationDelegate(params);
  }

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    return _FakePlatformWebViewController(params);
  }

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) {
    return _FakePlatformWebViewWidget(params);
  }
}

class _FakePlatformNavigationDelegate extends PlatformNavigationDelegate {
  _FakePlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) : super.implementation(params);

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback onNavigationRequest,
  ) async {}

  @override
  Future<void> setOnPageStarted(PageEventCallback onPageStarted) async {}

  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async {}

  @override
  Future<void> setOnProgress(ProgressCallback onProgress) async {
    onProgress(100);
  }

  @override
  Future<void> setOnWebResourceError(
    WebResourceErrorCallback onWebResourceError,
  ) async {}
}

class _FakePlatformWebViewController extends PlatformWebViewController {
  _FakePlatformWebViewController(PlatformWebViewControllerCreationParams params)
    : super.implementation(params);

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {}

  @override
  Future<void> loadRequest(LoadRequestParams params) async {}

  @override
  Future<void> loadFile(String absoluteFilePath) async {}
}

class _FakePlatformWebViewWidget extends PlatformWebViewWidget {
  _FakePlatformWebViewWidget(PlatformWebViewWidgetCreationParams params)
    : super.implementation(params);

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFFFFFFFF),
      child: Center(child: Text('Web preview')),
    );
  }
}
