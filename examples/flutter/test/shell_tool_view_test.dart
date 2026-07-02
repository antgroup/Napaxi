import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napaxi_flutter/convenience.dart' as sdk;
import 'package:napaxi_flutter/napaxi_flutter.dart' as sdk;
import 'package:napaxi/main.dart';

import 'test_support.dart';

Widget _testApp({
  NapaxiChatClientFactory? chatClientFactory,
  sdk.NapaxiConfigStore? configStore,
  DemoPreferencesStore? preferencesStore,
}) {
  return NapaxiApp(
    initialLanguage: AppLanguage.english,
    chatClientFactory: chatClientFactory,
    configStore: configStore ?? sdk.NapaxiConfigStore.memory(),
    preferencesStore: preferencesStore ?? MemoryDemoPreferencesStore(),
  );
}

void main() {
  testWidgets('renders shell command without padded spaces after prompt', (
    tester,
  ) async {
    final fakeClient = FakeNapaxiChatClient(
      events: const [
        sdk.ToolCallEvent(
          callId: 'call-2',
          name: 'shell',
          arguments:
              '{"cmd":"which convert magick ffmpeg 2>/dev/null | head -5"}',
        ),
        sdk.ToolOutputChunkEvent(
          callId: 'call-2',
          content: '/usr/bin/ffmpeg\n',
          stream: 'stdout',
        ),
        sdk.ResponseEvent(content: 'Command is still running.'),
      ],
    );

    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'Run command',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Thought through'));
    await tester.pump();
    await tester.tap(find.text('Shell'));
    await tester.pump();

    expect(find.byKey(const Key('tool_terminal_call-2')), findsOneWidget);
    expect(
      find.textContaining('/usr/bin/ffmpeg', findRichText: true),
      findsWidgets,
    );
    expect(
      find.textContaining(r'$ which convert magick ffmpeg', findRichText: true),
      findsWidgets,
    );
    expect(
      find.textContaining(
        r'$       which convert magick ffmpeg',
        findRichText: true,
      ),
      findsNothing,
    );
  });

  testWidgets('renders reasoning trace alongside shell output and response', (
    tester,
  ) async {
    final fakeClient = FakeNapaxiChatClient(
      events: const [
        sdk.ReasoningDeltaEvent(content: 'Checking the PATH first.'),
        sdk.ToolCallEvent(
          callId: 'call-3',
          name: 'shell',
          arguments: '{"cmd":"which codex"}',
        ),
        sdk.ToolOutputChunkEvent(
          callId: 'call-3',
          content: '/usr/local/bin/codex\n',
          stream: 'stdout',
        ),
        sdk.ToolResultEvent(
          callId: 'call-3',
          name: 'shell',
          output: '/usr/local/bin/codex\n',
          isError: false,
        ),
        sdk.ResponseEvent(content: 'Codex is available in PATH.'),
      ],
    );

    await tester.pumpWidget(
      _testApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      'Check codex',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pumpAndSettle();

    expect(
      find.text('Codex is available in PATH.', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Thought through'), findsOneWidget);

    await tester.tap(find.text('Thought through'));
    await tester.pumpAndSettle();

    expect(find.text('Checking the PATH first.'), findsOneWidget);
    expect(find.text('Shell'), findsOneWidget);

    await tester.tap(find.text('Shell'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('tool_terminal_call-3')), findsOneWidget);
    expect(find.textContaining('/usr/local/bin/codex'), findsWidgets);
  });
}
