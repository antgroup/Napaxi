import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napaxi/assistant_markdown.dart';

void main() {
  setUp(() {
    debugMarkdownWorkspacePathResolver = null;
  });

  tearDown(() {
    debugMarkdownWorkspacePathResolver = null;
  });

  testWidgets('routes markdown hyperlinks through the in-app preview handler', (
    tester,
  ) async {
    Uri? openedUri;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssistantMarkdown(
            content: '[OpenAI](https://openai.com/docs)',
            openLink: (_, uri) async {
              openedUri = uri;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('OpenAI'));
    await tester.pump();

    expect(openedUri?.toString(), 'https://openai.com/docs');
  });

  testWidgets('routes bare web links through the in-app preview handler', (
    tester,
  ) async {
    Uri? openedUri;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssistantMarkdown(
            content: '参考链接：https://openai.com/docs.',
            openLink: (_, uri) async {
              openedUri = uri;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('https://openai.com/docs'));
    await tester.pump();

    expect(openedUri?.toString(), 'https://openai.com/docs');
  });

  testWidgets('does not linkify bare web links inside code spans', (
    tester,
  ) async {
    Uri? openedUri;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssistantMarkdown(
            content: '`https://openai.com/docs`',
            openLink: (_, uri) async {
              openedUri = uri;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('https://openai.com/docs'));
    await tester.pump();

    expect(openedUri, isNull);
  });

  test('resolves workspace markdown links to local files', () async {
    final directory = await Directory.systemTemp.createTemp(
      'assistant_markdown_links_test',
    );
    final file = File('${directory.path}/index.html');
    await file.writeAsString('<html><body>workspace preview</body></html>');
    debugMarkdownWorkspacePathResolver = (_) => file.path;

    addTearDown(() async {
      debugMarkdownWorkspacePathResolver = null;
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    final resolved = await debugResolveMarkdownLocalPath(
      Uri.parse('/workspace/codex/index.html'),
    );

    expect(resolved, file.path);
  });
}
