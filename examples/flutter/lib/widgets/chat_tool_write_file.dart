part of '../main.dart';

class _WriteFileTraceGroup extends StatefulWidget {
  const _WriteFileTraceGroup({required this.toolCalls});

  final List<AgentToolCall> toolCalls;

  @override
  State<_WriteFileTraceGroup> createState() => _WriteFileTraceGroupState();
}

class _WriteFileTraceGroupState extends State<_WriteFileTraceGroup> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final files = _collectGroupedWriteFileResults(widget.toolCalls);
    final allDone = widget.toolCalls.every((call) => call.isComplete);
    final hasError = widget.toolCalls.any(_writeFileHasError);
    final color = hasError ? _toolFailureColor : const Color(0xFF8A8F98);
    final title = _writeFileGroupTitle(widget.toolCalls, files, allDone);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: files.isEmpty
                ? null
                : () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
              child: Row(
                children: [
                  Icon(Icons.edit_note_rounded, size: 18, color: color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: 14,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (files.isNotEmpty)
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 20,
                      color: color,
                    ),
                ],
              ),
            ),
          ),
          if (_expanded && files.isNotEmpty) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final file in files) _WriteFileTraceLine(file: file),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WriteFileTraceLine extends StatelessWidget {
  const _WriteFileTraceLine({required this.file});

  final _WriteFileResult file;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Text(
        _writeFileCollapsedLabel(file),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFF8A8F98),
          fontSize: 14,
          height: 1.25,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _WriteFileResult {
  const _WriteFileResult({
    required this.action,
    required this.path,
    this.addedLines = 0,
    this.removedLines = 0,
  });

  final String action;
  final String path;
  final int addedLines;
  final int removedLines;

  _WriteFileResult copyWith({
    String? action,
    String? path,
    int? addedLines,
    int? removedLines,
  }) {
    return _WriteFileResult(
      action: action ?? this.action,
      path: path ?? this.path,
      addedLines: addedLines ?? this.addedLines,
      removedLines: removedLines ?? this.removedLines,
    );
  }
}

bool _isWriteFileToolCall(AgentToolCall toolCall) {
  final canonical = _canonicalToolName(toolCall.name);
  return canonical == 'write_file' || canonical == 'apply_patch';
}

String _writeFilePreview(AgentToolCall toolCall) {
  if (_writeFileHasError(toolCall)) return '编辑失败';
  final files = _collectWriteFileResults(toolCall);
  if (files.isNotEmpty) {
    final count = files.length;
    return count == 1
        ? _writeFileCollapsedLabel(files.first)
        : '已编辑 $count 个文件';
  }
  final target = _writeFileTargetLabel(toolCall);
  if (target.isNotEmpty) return '编辑 $target';
  if (toolCall.isError) return '编辑失败';
  return '正在编辑文件';
}

bool _writeFileHasError(AgentToolCall toolCall) {
  if (toolCall.isError) return true;
  final raw = toolCall.output;
  if (raw == null || raw.isEmpty) return false;
  final decoded = _decodeJsonMap(raw);
  return _stringField(decoded, ['status']) == 'error';
}

String _writeFileGroupTitle(
  List<AgentToolCall> toolCalls,
  List<_WriteFileResult> files,
  bool allDone,
) {
  final allErrors =
      toolCalls.isNotEmpty && toolCalls.every(_writeFileHasError);
  if (allErrors) return '编辑失败';
  if (files.length == 1) {
    final file = files.first;
    final prefix = allDone
        ? _writeFileDonePrefix(file.action)
        : '正在编辑';
    return '$prefix ${_basename(file.path)} +${file.addedLines} -${file.removedLines}';
  }
  if (files.isNotEmpty) {
    final prefix = allDone ? '已编辑' : '正在编辑';
    return '$prefix ${files.length} 个文件';
  }
  final first = toolCalls.first;
  final target = _writeFileTargetLabel(first);
  if (target.isNotEmpty) {
    final prefix = allDone ? '已编辑' : '正在编辑';
    return '$prefix $target';
  }
  return allDone ? '编辑失败' : '正在编辑文件';
}

List<_WriteFileResult> _collectGroupedWriteFileResults(
  List<AgentToolCall> toolCalls,
) {
  final merged = <String, _WriteFileResult>{};
  for (final toolCall in toolCalls) {
    for (final file in _collectWriteFileResults(toolCall)) {
      final previous = merged[file.path];
      merged[file.path] = previous == null
          ? file
          : previous.copyWith(
              action: file.action,
              addedLines: previous.addedLines + file.addedLines,
              removedLines: previous.removedLines + file.removedLines,
            );
    }
  }
  return merged.values.where((file) => file.path.isNotEmpty).toList();
}

List<_WriteFileResult> _collectWriteFileResults(AgentToolCall toolCall) {
  final merged = <String, _WriteFileResult>{};
  for (final file in _parseWriteFileProgressChunks(toolCall.outputChunks)) {
    final previous = merged[file.path];
    merged[file.path] = previous == null
        ? file
        : previous.copyWith(
            action: file.action,
            addedLines: previous.addedLines + file.addedLines,
            removedLines: previous.removedLines + file.removedLines,
          );
  }
  final result = _decodeJsonMap(toolCall.output ?? '');
  for (final file in _parseWriteFileResults(result)) {
    final previous = merged[file.path];
    merged[file.path] = previous == null
        ? file
        : previous.copyWith(
            action: file.action,
            addedLines: file.addedLines == 0
                ? previous.addedLines
                : file.addedLines,
            removedLines: file.removedLines == 0
                ? previous.removedLines
                : file.removedLines,
          );
  }
  final inferred = _parseWriteFilePatchArguments(toolCall.arguments);
  for (final file in inferred) {
    final previous = merged[file.path];
    merged[file.path] = previous == null
        ? file
        : previous.copyWith(
            action: previous.action.isEmpty ? file.action : previous.action,
            addedLines: previous.addedLines == 0
                ? file.addedLines
                : previous.addedLines,
            removedLines: previous.removedLines == 0
                ? file.removedLines
                : previous.removedLines,
          );
  }
  final direct = _parseCompletedDirectWriteFileArguments(toolCall.arguments);
  if (toolCall.isComplete && direct != null) {
    final previous = merged[direct.path];
    merged[direct.path] = previous == null
        ? direct
        : previous.copyWith(
            action: previous.action.isEmpty ? direct.action : previous.action,
          );
  }
  if (!toolCall.isComplete) {
    final streaming = _parseStreamingWriteFileArguments(toolCall.arguments);
    for (final file in streaming) {
      final previous = merged[file.path];
      merged[file.path] = previous == null
          ? file
          : previous.copyWith(
              action: previous.action.isEmpty ? file.action : previous.action,
              addedLines: previous.addedLines == 0
                  ? file.addedLines
                  : previous.addedLines,
              removedLines: previous.removedLines == 0
                  ? file.removedLines
                  : previous.removedLines,
            );
    }
  }
  return merged.values.where((file) => file.path.isNotEmpty).toList();
}

List<_WriteFileResult> _parseWriteFileResults(Map<String, dynamic> result) {
  final rawFiles = result['files'];
  if (rawFiles is! List) return const [];
  return [
    for (final item in rawFiles)
      if (item is Map)
        (() {
          final json = Map<String, dynamic>.from(item);
          return _WriteFileResult(
            action: _stringField(json, ['action']),
            path: _firstNonEmpty([
              _stringField(json, ['path']),
              _stringField(json, ['real_path']),
            ]),
            addedLines: _intField(json, ['added_lines']),
            removedLines: _intField(json, ['removed_lines']),
          );
        })(),
  ].where((file) => file.path.isNotEmpty).toList();
}

List<_WriteFileResult> _parseWriteFileProgressChunks(
  List<AgentToolOutputChunk> chunks,
) {
  return [
    for (final chunk in chunks)
      if (chunk.stream == 'patch')
        () {
          final payload = _decodeJsonMap(chunk.content);
          final type = _stringField(payload, ['type']);
          // Accept the new `apply_patch_progress` name as well as the
          // legacy `write_file_patch_progress` that older sessions and
          // mocks still emit.
          if (type != 'apply_patch_progress' &&
              type != 'write_file_patch_progress') {
            return null;
          }
          final path = _stringField(payload, ['path']);
          if (path.isEmpty) return null;
          return _WriteFileResult(
            action: _stringField(payload, ['action']),
            path: path,
            addedLines: _intField(payload, ['added_lines']),
            removedLines: _intField(payload, ['removed_lines']),
          );
        }(),
  ].whereType<_WriteFileResult>().toList();
}

int _intField(Map<String, dynamic> source, List<String> keys) {
  final value = _stringField(source, keys);
  return int.tryParse(value) ?? 0;
}

String _writeFileActionLabel(String action) {
  return switch (action) {
    'added' => '新增',
    'deleted' => '删除',
    _ => '编辑',
  };
}

/// Group-title prefix once the write has finished. Added/deleted files use the
/// action verb ('新增'/'删除'); everything else falls back to '已编辑' so an edited
/// file keeps reading "已编辑 foo.dart +1 -1".
String _writeFileDonePrefix(String action) {
  return switch (action) {
    'added' => '新增',
    'deleted' => '删除',
    _ => '已编辑',
  };
}

String _writeFileCollapsedLabel(_WriteFileResult file) {
  return '${_writeFileActionLabel(file.action)} ${_basename(file.path)} +${file.addedLines} -${file.removedLines}';
}

String _writeFileTargetLabel(AgentToolCall toolCall) {
  final files = _parsePatchTargets(toolCall.arguments);
  if (files.isNotEmpty) {
    return files.length == 1 ? _basename(files.first) : '${files.length} 个文件';
  }
  final directPath = _partialWriteFilePath(toolCall.arguments);
  if (directPath.isNotEmpty) return _basename(directPath);
  final patchPath = _partialPatchPath(
    _partialJsonStringValue(toolCall.arguments, 'patch') ?? '',
  );
  if (patchPath.isNotEmpty) return _basename(patchPath);
  return '';
}

List<String> _parsePatchTargets(String arguments) {
  return [
    for (final file in _parseWriteFilePatchArguments(arguments)) file.path,
  ];
}

String _partialWriteFilePath(String arguments) {
  final decoded = _decodeJsonMap(arguments);
  final completePath = _stringField(decoded, ['path', 'file_path']);
  if (completePath.isNotEmpty) return completePath;
  final match = RegExp(
    r'"(?:path|file_path)"\s*:\s*"([^"]+)',
  ).firstMatch(arguments);
  return match?.group(1)?.trim() ?? '';
}

_WriteFileResult? _parseCompletedDirectWriteFileArguments(String arguments) {
  final decoded = _decodeJsonMap(arguments);
  if (decoded.isEmpty || _stringField(decoded, ['patch']).isNotEmpty) {
    return null;
  }
  final path = _stringField(decoded, ['path', 'file_path']);
  if (path.isEmpty) return null;
  final operation = _stringField(decoded, ['operation']);
  final action = operation == 'create' ? 'added' : 'updated';
  return _WriteFileResult(action: action, path: path);
}

List<_WriteFileResult> _parseStreamingWriteFileArguments(String arguments) {
  final patch = _partialJsonStringValue(arguments, 'patch');
  if (patch != null && patch.trim().isNotEmpty) {
    return _parseWriteFilePatchText(patch);
  }

  final path = _partialWriteFilePath(arguments);
  if (path.isEmpty) return const [];

  final replacement = _parseStreamingReplaceArguments(arguments, path);
  if (replacement != null) return [replacement];

  final content =
      _partialJsonStringValue(arguments, 'content') ??
      _partialJsonStringValue(arguments, 'text') ??
      _partialJsonStringValue(arguments, 'contents');
  if (content == null || content.isEmpty) return const [];
  return [
    _WriteFileResult(
      action: 'updated',
      path: path,
      addedLines: _countLines(content),
      removedLines: 0,
    ),
  ];
}

_WriteFileResult? _parseStreamingReplaceArguments(
  String arguments,
  String path,
) {
  final oldString = _partialJsonStringValue(arguments, 'old_string');
  final newString = _partialJsonStringValue(arguments, 'new_string');
  final removedLines = oldString == null ? 0 : _countLines(oldString);
  final addedLines = newString == null ? 0 : _countLines(newString);
  if (removedLines == 0 && addedLines == 0) return null;
  return _WriteFileResult(
    action: 'updated',
    path: path,
    addedLines: addedLines,
    removedLines: removedLines,
  );
}

String _partialPatchPath(String patch) {
  final match = RegExp(
    r'\*\*\* (?:Add|Update|Delete) File: ([^\r\n]+)',
  ).firstMatch(patch);
  return match?.group(1)?.trim() ?? '';
}

int _countLines(String content) {
  if (content.isEmpty) return 0;
  return const LineSplitter().convert(content).length;
}

String? _partialJsonStringValue(String text, String key) {
  final decoded = _decodeJsonMap(text);
  final complete = _stringField(decoded, [key]);
  if (complete.isNotEmpty) return complete;
  final match = RegExp('"$key"\\s*:\\s*"').firstMatch(text);
  if (match == null) return null;
  final start = match.end;
  final buffer = StringBuffer();
  var escaping = false;
  for (var i = start; i < text.length; i++) {
    final char = text[i];
    if (escaping) {
      buffer.write(_decodeJsonEscape(char));
      escaping = false;
      continue;
    }
    if (char == r'\') {
      escaping = true;
      continue;
    }
    if (char == '"') break;
    buffer.write(char);
  }
  return buffer.toString();
}

String _decodeJsonEscape(String char) {
  return switch (char) {
    'n' => '\n',
    'r' => '\r',
    't' => '\t',
    '"' => '"',
    r'\' => r'\',
    _ => char,
  };
}

List<_WriteFileResult> _parseWriteFilePatchArguments(String arguments) {
  final patch = _stringField(_decodeJsonMap(arguments), ['patch']);
  if (patch.isEmpty) return const [];
  return _parseWriteFilePatchText(patch);
}

List<_WriteFileResult> _parseWriteFilePatchText(String patch) {
  final lines = const LineSplitter().convert(patch);
  final results = <_WriteFileResult>[];

  String? currentPath;
  String currentAction = 'updated';
  var addedLines = 0;
  var removedLines = 0;

  void flush() {
    final path = currentPath;
    if (path == null || path.trim().isEmpty) return;
    results.add(
      _WriteFileResult(
        action: currentAction,
        path: path.trim(),
        addedLines: addedLines,
        removedLines: removedLines,
      ),
    );
  }

  for (final rawLine in lines) {
    if (rawLine.startsWith('*** Add File: ')) {
      flush();
      currentPath = rawLine.substring('*** Add File: '.length).trim();
      currentAction = 'added';
      addedLines = 0;
      removedLines = 0;
      continue;
    }
    if (rawLine.startsWith('*** Update File: ')) {
      flush();
      currentPath = rawLine.substring('*** Update File: '.length).trim();
      currentAction = 'updated';
      addedLines = 0;
      removedLines = 0;
      continue;
    }
    if (rawLine.startsWith('*** Delete File: ')) {
      flush();
      currentPath = rawLine.substring('*** Delete File: '.length).trim();
      currentAction = 'deleted';
      addedLines = 0;
      removedLines = 0;
      continue;
    }
    if (currentPath == null) continue;
    if (rawLine.startsWith('*** End Patch') ||
        rawLine.startsWith('*** End of File')) {
      continue;
    }
    if (rawLine.startsWith('@@')) continue;
    if (rawLine.startsWith('+++') || rawLine.startsWith('---')) continue;
    if (rawLine.startsWith('+')) {
      addedLines += 1;
      continue;
    }
    if (rawLine.startsWith('-')) {
      removedLines += 1;
      continue;
    }
  }

  flush();
  return results.where((file) => file.path.isNotEmpty).toList();
}
