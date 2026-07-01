import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napaxi/assistant_markdown.dart';
import 'package:napaxi/main.dart';
import 'package:napaxi_flutter/napaxi_flutter.dart' as sdk;
import 'package:napaxi_flutter/convenience.dart' as sdk;

import 'test_support.dart';

void main() {
  testWidgets('uses restrained bold and inline code styles', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AssistantMarkdown(content: '**重点** 和 `code`')),
      ),
    );

    final textSpans = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.textSpan)
        .nonNulls
        .expand(_flattenTextSpans);
    final boldSpan = textSpans.singleWhere((span) => span.text == '重点');
    expect(boldSpan.style?.fontWeight, FontWeight.w600);

    final inlineCode = tester.widget<Text>(
      find.byWidgetPredicate(
        (widget) => widget is Text && widget.data == 'code',
      ),
    );
    expect(inlineCode.style?.backgroundColor, Colors.transparent);
    expect(inlineCode.style?.fontWeight, FontWeight.w500);
  });

  testWidgets('renders dollar latex and tilde code fences', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AssistantMarkdown(
            content: r'''
公式 $E=mc^2$

$$
x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}
$$

~~~dart
final answer = 42;
~~~
''',
          ),
        ),
      ),
    );

    expect(find.textContaining(r'$E=mc^2$', findRichText: true), findsNothing);
    expect(find.textContaining(r'$$', findRichText: true), findsNothing);
    expect(find.text('dart'), findsOneWidget);
    expect(
      find.textContaining('final answer = 42;', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('~~~', findRichText: true), findsNothing);
    expect(find.text('Copy code'), findsNothing);
    expect(find.byIcon(Icons.content_paste), findsOneWidget);
    expect(find.byTooltip('Copy code'), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);

    final codeText = tester.widget<RichText>(
      find.textContaining('final answer = 42;', findRichText: true),
    );
    expect(
      codeText.text.style?.fontFamily,
      'packages/gpt_markdown/JetBrainsMono',
    );
  });

  testWidgets('renders assistant markdown without exposing syntax markers', (
    tester,
  ) async {
    final fakeClient = FakeNapaxiChatClient(
      events: const [
        sdk.ResponseEvent(
          content: '''
脚本已创建并运行成功！

**脚本功能说明：**

1. **is_prime(n, k=5)** - Miller-Rabin 素性测试
2. `generate_random_prime(bits)` - 生成指定 bit 数的随机素数

```bash
python3 /tmp/random_prime.py 256
```
''',
        ),
      ],
    );
    await tester.pumpWidget(
      NapaxiApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.enterText(
      find.byKey(const Key('chat_input_field')),
      '帮我生成一个生成随机素数的python脚本并运行',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('脚本已创建并运行成功', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('**', findRichText: true), findsNothing);
    expect(find.textContaining('```', findRichText: true), findsNothing);
    expect(find.text('1.'), findsOneWidget);
    expect(find.text('2.'), findsOneWidget);
    expect(find.text('bash'), findsOneWidget);
    expect(
      find.textContaining(
        'python3 /tmp/random_prime.py 256',
        findRichText: true,
      ),
      findsOneWidget,
    );
  });

  testWidgets('makes assistant replies selectable for copy', (tester) async {
    final fakeClient = FakeNapaxiChatClient(
      events: const [sdk.ResponseEvent(content: '可以长按选择并复制这段回复。')],
    );
    await tester.pumpWidget(
      NapaxiApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.enterText(find.byKey(const Key('chat_input_field')), '复制能力');
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pumpAndSettle();

    final reply = find.textContaining('可以长按选择并复制', findRichText: true);
    expect(reply, findsOneWidget);
    expect(
      find.ancestor(of: reply, matching: find.byType(SelectionArea)),
      findsOneWidget,
    );
  });

  testWidgets('renders GitHub flavored markdown tables', (tester) async {
    final fakeClient = FakeNapaxiChatClient(
      events: const [
        sdk.ResponseEvent(
          content: '''
| 项目 | 状态 |
| --- | --- |
| Markdown | 已适配 |
| 表格 | 已渲染 |
''',
        ),
      ],
    );
    await tester.pumpWidget(
      NapaxiApp(chatClientFactory: () async => fakeClient),
    );
    await configureSingleModel(tester);

    await tester.enterText(find.byKey(const Key('chat_input_field')), '输出一个表格');
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pumpAndSettle();

    expect(find.text('项目', findRichText: true), findsOneWidget);
    expect(find.text('状态', findRichText: true), findsOneWidget);
    expect(find.text('Markdown', findRichText: true), findsOneWidget);
    expect(find.text('已渲染', findRichText: true), findsOneWidget);
    expect(find.textContaining('| --- |', findRichText: true), findsNothing);
  });

  testWidgets('keeps code block horizontal drags from opening chat history', (
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

    final longCodeLine =
        'final generatedValue = "${List.filled(24, 'napaxi').join('_')}";';
    final fakeClient = FakeNapaxiChatClient(
      events: [
        sdk.ResponseEvent(
          content:
              '''
```dart
$longCodeLine
```
''',
        ),
      ],
    );

    await tester.pumpWidget(
      NapaxiApp(configStore: store, chatClientFactory: () async => fakeClient),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('chat_input_field')), 'code');
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('final generatedValue', findRichText: true),
      findsOneWidget,
    );

    await _dragVisibleHorizontalScrollableFrom(
      tester,
      find.textContaining('final generatedValue', findRichText: true),
      const Offset(320, 0),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recent'), findsNothing);
    expect(
      find.byKey(const Key('session_history_search_button')),
      findsNothing,
    );
  });

  testWidgets('keeps table horizontal drags from opening chat history', (
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

    final tableHeaders = List.generate(8, (index) => 'Column ${index + 1}');
    final tableValues = List.generate(
      8,
      (index) => 'wide table value ${index + 1}',
    );
    final fakeClient = FakeNapaxiChatClient(
      events: [
        sdk.ResponseEvent(
          content:
              '''
| ${tableHeaders.join(' | ')} |
| ${List.filled(tableHeaders.length, '---').join(' | ')} |
| ${tableValues.join(' | ')} |
''',
        ),
      ],
    );

    await tester.pumpWidget(
      NapaxiApp(configStore: store, chatClientFactory: () async => fakeClient),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('chat_input_field')), 'table');
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message_button')));
    await tester.pumpAndSettle();

    expect(find.text('Column 1', findRichText: true), findsOneWidget);

    await _dragVisibleHorizontalScrollableFrom(
      tester,
      find.text('Column 1', findRichText: true),
      const Offset(320, 0),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recent'), findsNothing);
    expect(
      find.byKey(const Key('session_history_search_button')),
      findsNothing,
    );
  });
}

Iterable<TextSpan> _flattenTextSpans(InlineSpan span) sync* {
  if (span is TextSpan) {
    yield span;
    for (final child in span.children ?? const <InlineSpan>[]) {
      yield* _flattenTextSpans(child);
    }
  }
}

Future<void> _dragVisibleHorizontalScrollableFrom(
  WidgetTester tester,
  Finder descendant,
  Offset offset,
) async {
  final scrollable = find.ancestor(
    of: descendant,
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is SingleChildScrollView &&
          widget.scrollDirection == Axis.horizontal,
    ),
  );
  expect(scrollable, findsOneWidget);

  final rect = tester.getRect(scrollable);
  await tester.dragFrom(rect.centerLeft + const Offset(24, 0), offset);
}
