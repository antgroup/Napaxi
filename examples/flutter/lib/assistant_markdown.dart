import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/theme_map.dart';
import 'package:gpt_markdown/custom_widgets/markdown_config.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:napaxi_flutter/advanced.dart' as sdk_advanced;
import 'package:napaxi/widgets/web_preview_page.dart';

typedef MarkdownWorkspacePathResolver =
    FutureOr<String?> Function(String sandboxPath);

MarkdownWorkspacePathResolver? debugMarkdownWorkspacePathResolver;

// Keep this wrapper aligned with https://gptmarkdown.com/docs/ before changing
// the GptMarkdown integration or custom builders below.
class AssistantMarkdown extends StatelessWidget {
  const AssistantMarkdown({super.key, required this.content, this.openLink});

  final String content;
  final Future<void> Function(BuildContext context, Uri uri)? openLink;

  static const _baseTextStyle = TextStyle(
    color: Color(0xFF1F2937),
    fontSize: 16,
    height: 1.4,
  );

  @override
  Widget build(BuildContext context) {
    final normalized = _normalizeAssistantMarkdown(content);
    if (normalized.trim().isEmpty) return const SizedBox.shrink();

    return DefaultTextStyle.merge(
      style: _baseTextStyle,
      child: GptMarkdown(
        normalized,
        style: _baseTextStyle,
        inlineComponents: _assistantInlineComponents,
        useDollarSignsForLatex: false,
        onLinkTap: (url, _) {
          final uri = Uri.tryParse(url.trim());
          if (uri == null) return;
          final handler = openLink ?? _openMarkdownLink;
          unawaited(handler(context, uri));
        },
        codeBuilder: (context, name, code, closed) {
          return _CodeBlockView(name: name, code: code);
        },
        highlightBuilder: (context, text, style) {
          return _InlineCodeView(text: text, style: style);
        },
        orderedListBuilder: (context, no, child, config) {
          return _OrderedListItemView(number: no, child: child);
        },
      ),
    );
  }
}

final List<MarkdownComponent> _assistantInlineComponents = MarkdownComponent
    .inlineComponents
    .map((component) => component is BoldMd ? _AssistantBoldMd() : component)
    .toList(growable: false);

class _AssistantBoldMd extends InlineMd {
  @override
  RegExp get exp =>
      RegExp(r'(?<!\*)\*\*(?<!\s)(.+?)(?<!\s)\*\*(?!\*)', dotAll: true);

  @override
  InlineSpan span(BuildContext context, String text, GptMarkdownConfig config) {
    final match = exp.firstMatch(text.trim());
    final conf = config.copyWith(
      style: (config.style ?? const TextStyle()).copyWith(
        fontWeight: FontWeight.w600,
      ),
    );

    return TextSpan(
      children: MarkdownComponent.generate(
        context,
        '${match?[1]}',
        conf,
        false,
      ),
      style: conf.style,
    );
  }
}

class _CodeBlockView extends StatefulWidget {
  const _CodeBlockView({required this.name, required this.code});

  final String name;
  final String code;

  @override
  State<_CodeBlockView> createState() => _CodeBlockViewState();
}

class _CodeBlockViewState extends State<_CodeBlockView> {
  bool _copied = false;

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() {
      _copied = true;
    });
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    setState(() {
      _copied = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final language = _normalizedCodeLanguage(widget.name, widget.code);
    const codeStyle = TextStyle(
      fontFamily: 'JetBrainsMono',
      package: 'gpt_markdown',
      fontSize: 13.5,
      height: 1.5,
      color: Color(0xFF1F2937),
    );
    final baseTheme = Theme.of(context).brightness == Brightness.dark
        ? themeMap['atom-one-dark']!
        : themeMap['github']!;
    final theme = Map<String, TextStyle>.from(baseTheme)
      ..update(
        'root',
        (style) => style.copyWith(backgroundColor: Colors.transparent),
        ifAbsent: () => const TextStyle(backgroundColor: Colors.transparent),
      );

    return Material(
      color: colorScheme.onInverseSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text(widget.name),
              ),
              const Spacer(),
              IconButton(
                tooltip: _copied ? 'Copied' : 'Copy code',
                visualDensity: VisualDensity.compact,
                color: colorScheme.onSurface,
                onPressed: _copyCode,
                icon: Icon(
                  _copied ? Icons.done : Icons.content_paste,
                  size: 18,
                ),
              ),
            ],
          ),
          const Divider(height: 1),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(16),
            child: language == null
                ? Text(widget.code, style: codeStyle)
                : HighlightView(
                    widget.code,
                    language: language,
                    theme: theme,
                    padding: EdgeInsets.zero,
                    textStyle: codeStyle,
                  ),
          ),
        ],
      ),
    );
  }
}

const Set<String> _highlightLanguageWhitelist = {
  'bash',
  'cpp',
  'cs',
  'css',
  'dart',
  'diff',
  'dockerfile',
  'go',
  'gradle',
  'html',
  'ini',
  'java',
  'javascript',
  'json',
  'kotlin',
  'makefile',
  'markdown',
  'objectivec',
  'php',
  'plaintext',
  'powershell',
  'properties',
  'python',
  'ruby',
  'rust',
  'shell',
  'sql',
  'swift',
  'typescript',
  'xml',
  'yaml',
};

String? _normalizedCodeLanguage(String language, String code) {
  final normalized = language.trim().toLowerCase();
  if (normalized.isNotEmpty) {
    final mapped = switch (normalized) {
      'py' => 'python',
      'rb' => 'ruby',
      'sh' || 'shell' || 'zsh' => 'bash',
      'js' => 'javascript',
      'ts' => 'typescript',
      'tsx' => 'typescript',
      'jsx' => 'javascript',
      'yml' => 'yaml',
      'kt' => 'kotlin',
      'rs' => 'rust',
      'cs' || 'csharp' => 'cs',
      'objc' => 'objectivec',
      'md' => 'markdown',
      'text' || 'txt' => 'plaintext',
      'shell-session' || 'console' => 'shell',
      _ => normalized,
    };
    return _highlightLanguageWhitelist.contains(mapped) ? mapped : null;
  }

  if (RegExp(r'\b(def|import|from|class)\b', multiLine: true).hasMatch(code) &&
      code.contains(':')) {
    return 'python';
  }
  if (RegExp(
    r'\b(public|private|protected|class|static|void)\b',
    multiLine: true,
  ).hasMatch(code)) {
    return 'java';
  }
  if (RegExp(
    "\\b(import\\s+['\"]package:|class\\s+\\w+|extends\\s+\\w+|Widget\\b|State<|Future<)",
    multiLine: true,
  ).hasMatch(code)) {
    return 'dart';
  }
  if (RegExp(
    r'\b(function|const|let|var|console\.log)\b',
    multiLine: true,
  ).hasMatch(code)) {
    return 'javascript';
  }
  if (RegExp(r'^\s*\{[\s\S]*\}\s*$', multiLine: true).hasMatch(code)) {
    return 'json';
  }
  return null;
}

class _InlineCodeView extends StatelessWidget {
  const _InlineCodeView({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: style.copyWith(
        color: const Color(0xFF334155),
        fontSize: 13.5,
        fontFamily: 'monospace',
        fontWeight: FontWeight.w500,
        backgroundColor: Colors.transparent,
      ),
    );
  }
}

class _OrderedListItemView extends StatelessWidget {
  const _OrderedListItemView({required this.number, required this.child});

  final String number;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24,
          child: Text(
            '$number.',
            style: const TextStyle(
              color: Color(0xFF4B5563),
              fontSize: 15,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

String _normalizeAssistantMarkdown(String source) {
  final normalizedNewLines = source.replaceAll('\r\n', '\n');
  final normalizedFences = normalizedNewLines.replaceAllMapped(
    RegExp(r'(^|\n)~~~'),
    (match) => '${match.group(1)}```',
  );
  final normalized = _closeOpenCodeFence(
    _normalizeDollarLatex(normalizedFences),
  );
  return _linkifyBareUrls(normalized);
}

String _normalizeDollarLatex(String source) {
  final blockNormalized = source.replaceAllMapped(
    RegExp(r'(?<!\\)\$\$([\s\S]*?)(?<!\\)\$\$'),
    (match) => '\\[${match.group(1) ?? ''}\\]',
  );

  return blockNormalized.replaceAllMapped(
    RegExp(r'(?<!\\)\$((?:[^$\\]|\\.)*?)(?<!\\)\$'),
    (match) => '\\(${match.group(1) ?? ''}\\)',
  );
}

String _closeOpenCodeFence(String source) {
  final matches = RegExp(r'(^|\n)```').allMatches(source).toList();
  if (matches.length.isEven) return source;
  return source.endsWith('\n') ? '$source```' : '$source\n```';
}

String _linkifyBareUrls(String source) {
  if (!source.contains('://')) return source;

  final lines = source.split('\n');
  final buffer = StringBuffer();
  var insideFence = false;
  final fencePattern = RegExp(r'^\s*```');

  for (var i = 0; i < lines.length; i++) {
    if (i > 0) buffer.write('\n');
    final line = lines[i];
    if (fencePattern.hasMatch(line)) {
      buffer.write(line);
      insideFence = !insideFence;
      continue;
    }
    buffer.write(insideFence ? line : _linkifyBareUrlsInInlineText(line));
  }

  return buffer.toString();
}

String _linkifyBareUrlsInInlineText(String source) {
  final buffer = StringBuffer();
  var cursor = 0;
  for (final match in RegExp(r'`+[^`]*`+').allMatches(source)) {
    buffer.write(
      _linkifyBareUrlsInPlainText(source.substring(cursor, match.start)),
    );
    buffer.write(match.group(0));
    cursor = match.end;
  }
  buffer.write(_linkifyBareUrlsInPlainText(source.substring(cursor)));
  return buffer.toString();
}

String _linkifyBareUrlsInPlainText(String source) {
  final existingLinkRanges = _existingMarkdownLinkRanges(source);
  return source.replaceAllMapped(RegExp(r'https?://[^\s<>)\]]+'), (match) {
    final raw = match.group(0)!;
    final url = _trimTrailingMarkdownFromUrl(raw);
    if (url.isEmpty ||
        _isInsideRanges(match.start, existingLinkRanges) ||
        _isExistingMarkdownLinkDestination(source, match.start)) {
      return raw;
    }
    final trailing = raw.substring(url.length);
    return '[$url]($url)$trailing';
  });
}

List<(int, int)> _existingMarkdownLinkRanges(String source) {
  return [
    for (final match in RegExp(
      r'!?\[[^\]\n]*\]\([^\s)]+(?:\s+"[^"]*")?\)',
    ).allMatches(source))
      (match.start, match.end),
  ];
}

bool _isInsideRanges(int index, List<(int, int)> ranges) {
  for (final (start, end) in ranges) {
    if (index >= start && index < end) return true;
  }
  return false;
}

bool _isExistingMarkdownLinkDestination(String source, int urlStart) {
  if (urlStart == 0) return false;
  if (source.codeUnitAt(urlStart - 1) == '<'.codeUnitAt(0)) return true;
  if (source.codeUnitAt(urlStart - 1) != '('.codeUnitAt(0)) return false;

  var index = urlStart - 2;
  while (index >= 0 && source.codeUnitAt(index) == ' '.codeUnitAt(0)) {
    index--;
  }
  return index >= 0 && source.codeUnitAt(index) == ']'.codeUnitAt(0);
}

String _trimTrailingMarkdownFromUrl(String url) {
  var trimmed = url.replaceFirst(RegExp(r'[.,;:!?]+$'), '');
  while (true) {
    final next = trimmed.replaceFirst(RegExp(r'(\*{1,3}|_{1,3}|~{2}|`+)$'), '');
    if (next == trimmed) return trimmed;
    trimmed = next;
  }
}

Future<void> _openMarkdownLink(BuildContext context, Uri uri) async {
  final target = await _resolveMarkdownPreviewTarget(uri);
  if (!context.mounted) return;
  if (target == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Unsupported markdown link: ${uri.toString()}')),
    );
    return;
  }

  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => WebPreviewPage(
        title: 'Preview',
        displayUrl: target.displayUrl,
        initialUrl: target.initialUrl,
        initialFilePath: target.initialFilePath,
        shareText: target.shareText,
        shareFilePath: target.shareFilePath,
        shareFileName: target.shareFileName,
        shareFileMimeType: target.shareFileMimeType,
      ),
    ),
  );
}

Future<_MarkdownPreviewTarget?> _resolveMarkdownPreviewTarget(Uri uri) async {
  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'http' || scheme == 'https') {
    return _MarkdownPreviewTarget.web(uri);
  }

  final localPath = await debugResolveMarkdownLocalPath(uri);
  if (localPath != null) {
    return _MarkdownPreviewTarget.file(
      displayUrl: uri.toString(),
      path: localPath,
    );
  }

  return null;
}

@visibleForTesting
Future<String?> debugResolveMarkdownLocalPath(Uri uri) async {
  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'file') {
    final path = uri.toFilePath();
    return await File(path).exists() ? path : null;
  }

  final raw = uri.toString().trim();
  if (!raw.startsWith('/workspace/')) return null;
  final path = _resolveWorkspaceMarkdownPath(raw);
  if (path == null || !await File(path).exists()) return null;
  return path;
}

String? _resolveWorkspaceMarkdownPath(String sandboxPath) {
  final override = debugMarkdownWorkspacePathResolver;
  if (override != null) {
    final resolved = override(sandboxPath);
    if (resolved is Future<String?>) {
      throw StateError(
        'debugMarkdownWorkspacePathResolver must return synchronously.',
      );
    }
    return resolved;
  }
  if (!sdk_advanced.NapaxiFileBridge.isInitialized) return null;
  final trimmed = sandboxPath.trim();
  if (trimmed.isEmpty) return null;
  return sdk_advanced.NapaxiFileBridge.instance.sandboxToReal(trimmed);
}

class _MarkdownPreviewTarget {
  const _MarkdownPreviewTarget._({
    required this.displayUrl,
    this.initialUrl,
    this.initialFilePath,
    this.shareText,
    this.shareFilePath,
    this.shareFileName,
    this.shareFileMimeType,
  });

  factory _MarkdownPreviewTarget.web(Uri uri) {
    final value = uri.toString();
    return _MarkdownPreviewTarget._(
      displayUrl: value,
      initialUrl: uri,
      shareText: value,
    );
  }

  factory _MarkdownPreviewTarget.file({
    required String displayUrl,
    required String path,
  }) {
    final name = path.split(Platform.pathSeparator).last;
    return _MarkdownPreviewTarget._(
      displayUrl: displayUrl,
      initialFilePath: path,
      shareFilePath: path,
      shareFileName: name,
      shareFileMimeType: name.toLowerCase().endsWith('.html')
          ? 'text/html'
          : null,
    );
  }

  final String displayUrl;
  final Uri? initialUrl;
  final String? initialFilePath;
  final String? shareText;
  final String? shareFilePath;
  final String? shareFileName;
  final String? shareFileMimeType;
}
