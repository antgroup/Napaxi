part of '../main.dart';

class _ReadFileTraceGroup extends StatefulWidget {
  const _ReadFileTraceGroup({required this.toolCalls});

  final List<AgentToolCall> toolCalls;

  @override
  State<_ReadFileTraceGroup> createState() => _ReadFileTraceGroupState();
}

class _ReadFileTraceGroupState extends State<_ReadFileTraceGroup> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final count = widget.toolCalls.length;
    final allDone = widget.toolCalls.every((call) => call.isComplete);
    final hasError = widget.toolCalls.any((call) => call.isError);
    final title = allDone ? '已读取 $count 个文件' : '正在读取 $count 个文件';
    final color = hasError ? _toolFailureColor : const Color(0xFF8A8F98);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
              child: Row(
                children: [
                  Icon(Icons.description_outlined, size: 18, color: color),
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
          if (_expanded) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final toolCall in widget.toolCalls)
                    _ReadFileTraceLine(toolCall: toolCall),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReadFileTraceLine extends StatelessWidget {
  const _ReadFileTraceLine({required this.toolCall});

  final AgentToolCall toolCall;

  @override
  Widget build(BuildContext context) {
    final label = _readFileDisplayName(toolCall);
    final color = toolCall.isError
        ? _toolFailureColor
        : const Color(0xFF8A8F98);
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Text(
        'Read $label',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 14,
          height: 1.25,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

bool _isReadFileToolCall(AgentToolCall toolCall) {
  return _canonicalToolName(toolCall.name) == 'read_file';
}

String _readFileDisplayName(AgentToolCall toolCall) {
  final args = _decodeJsonMap(toolCall.arguments);
  final result = _decodeJsonMap(toolCall.output ?? '');
  final path = _firstNonEmpty([
    _stringField(result, ['path']),
    _stringField(args, ['path']),
    toolCall.name,
  ]);
  return _basename(path);
}
