part of '../main.dart';

class _ChatProject {
  const _ChatProject({
    required this.id,
    required this.agentId,
    required this.name,
    required this.createdAt,
  });

  final String id;
  final String agentId;
  final String name;
  final DateTime createdAt;

  Map<String, Object?> toMap() => {
    'id': id,
    'agentId': agentId,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
  };

  factory _ChatProject.fromMap(Map<String, Object?> map) {
    return _ChatProject(
      id: map['id']?.toString().trim() ?? '',
      agentId: map['agentId']?.toString().trim() ?? '',
      name: map['name']?.toString().trim() ?? '',
      createdAt:
          DateTime.tryParse(map['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

String _projectCopy(
  BuildContext context, {
  required String english,
  required String chinese,
}) {
  return _AppLanguageScope.languageOf(context) == AppLanguage.chinese
      ? chinese
      : english;
}

class _CreateProjectDialog extends StatefulWidget {
  const _CreateProjectDialog();

  @override
  State<_CreateProjectDialog> createState() => _CreateProjectDialogState();
}

class _CreateProjectDialogState extends State<_CreateProjectDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _canCreate = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22),
      child: Material(
        color: _appSurfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: _appSurfaceBorderColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _projectCopy(context, english: 'New project', chinese: '新建项目'),
                style: const TextStyle(
                  color: _sessionMenuText,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('new_project_name_field'),
                controller: _controller,
                autofocus: true,
                maxLength: 80,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                onChanged: (value) {
                  final canCreate = value.trim().isNotEmpty;
                  if (canCreate != _canCreate) {
                    setState(() => _canCreate = canCreate);
                  }
                },
                decoration: InputDecoration(
                  hintText: _projectCopy(
                    context,
                    english: 'Project name',
                    chinese: '项目名称',
                  ),
                  counterText: '',
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 15,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(color: _appSurfaceBorderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(color: _appSurfaceBorderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(color: Color(0xFF999999)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('cancel_create_project_button'),
                      onPressed: () {
                        FocusScope.of(context).unfocus();
                        Navigator.of(context).pop();
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _sessionMenuText,
                        minimumSize: const Size.fromHeight(48),
                        side: const BorderSide(color: _appSurfaceBorderColor),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        _projectCopy(context, english: 'Cancel', chinese: '取消'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      key: const Key('confirm_create_project_button'),
                      onPressed: _canCreate ? _submit : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF222222),
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        _projectCopy(context, english: 'Create', chinese: '创建'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectsPage extends StatelessWidget {
  const _ProjectsPage({
    required this.projects,
    required this.sessionCounts,
    required this.onMenu,
    required this.onAdd,
    required this.onProjectTap,
  });

  final List<_ChatProject> projects;
  final Map<String, int> sessionCounts;
  final VoidCallback onMenu;
  final VoidCallback onAdd;
  final ValueChanged<_ChatProject> onProjectTap;

  @override
  Widget build(BuildContext context) {
    final sortedProjects = [...projects]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Scaffold(
      key: const Key('projects_page'),
      resizeToAvoidBottomInset: false,
      backgroundColor: _appSurfaceColor,
      appBar: AppBar(
        backgroundColor: _appSurfaceColor,
        foregroundColor: _sessionMenuText,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          key: const Key('projects_menu_button'),
          tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
          onPressed: onMenu,
          icon: const Icon(Icons.menu_rounded),
        ),
        title: Text(
          _projectCopy(context, english: 'Projects', chinese: '项目'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            key: const Key('add_project_button'),
            tooltip: _projectCopy(
              context,
              english: 'Add project',
              chinese: '添加项目',
            ),
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded, size: 28),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: sortedProjects.isEmpty
          ? _ProjectsEmptyState(onAdd: onAdd)
          : ListView.separated(
              key: const Key('projects_list'),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              itemCount: sortedProjects.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final project = sortedProjects[index];
                final count = sessionCounts[project.id] ?? 0;
                return Material(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: const BorderSide(color: _appSurfaceBorderColor),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: Key('project_tile_${project.id}'),
                    onTap: () => onProjectTap(project),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0F1F3),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.folder_rounded,
                              color: Color(0xFF303030),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  project.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _sessionMenuText,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _projectCopy(
                                    context,
                                    english:
                                        '$count ${count == 1 ? 'chat' : 'chats'}',
                                    chinese: '$count 个对话',
                                  ),
                                  style: const TextStyle(
                                    color: _sessionMenuMuted,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: Color(0xFF999999),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _ProjectsEmptyState extends StatelessWidget {
  const _ProjectsEmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.folder_open_rounded,
              size: 48,
              color: Color(0xFF9A9A9A),
            ),
            const SizedBox(height: 16),
            Text(
              _projectCopy(
                context,
                english: 'No projects yet',
                chinese: '还没有项目',
              ),
              style: const TextStyle(
                color: _sessionMenuText,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _projectCopy(
                context,
                english: 'Create a project to organize related chats.',
                chinese: '创建项目，把相关的对话整理在一起。',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _sessionMenuMuted,
                fontSize: 14,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: Text(
                _projectCopy(context, english: 'New project', chinese: '新建项目'),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF222222),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectDetailPage extends StatefulWidget {
  const _ProjectDetailPage({
    required this.project,
    required this.sessions,
    required this.onBack,
    required this.onSessionTap,
    required this.onStartChat,
    this.chatClient,
    required this.agentId,
  });

  final _ChatProject project;
  final List<ChatSession> sessions;
  final VoidCallback onBack;
  final ValueChanged<String> onSessionTap;
  final Future<void> Function(
    String message,
    List<ChatAttachment> attachments,
    List<String> pinnedSkillNames,
  )
  onStartChat;
  final NapaxiChatClient? chatClient;
  final String agentId;

  @override
  State<_ProjectDetailPage> createState() => _ProjectDetailPageState();
}

class _ProjectDetailPageState extends State<_ProjectDetailPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isStarting = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit(
    List<ChatAttachment> attachments, {
    List<String> pinnedSkillNames = const [],
  }) async {
    final message = _controller.text.trim();
    if ((message.isEmpty && attachments.isEmpty) || _isStarting) return;
    setState(() => _isStarting = true);
    _controller.clear();
    try {
      await widget.onStartChat(message, attachments, pinnedSkillNames);
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessions = [...widget.sessions]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return Scaffold(
      key: Key('project_detail_${widget.project.id}'),
      resizeToAvoidBottomInset: true,
      backgroundColor: _appSurfaceColor,
      appBar: AppBar(
        backgroundColor: _appSurfaceColor,
        foregroundColor: _sessionMenuText,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          key: const Key('project_detail_back_button'),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(
          widget.project.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: sessions.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Text(
                        _projectCopy(
                          context,
                          english:
                              'Start with the input below. Your new chat will appear here.',
                          chinese: '在下方输入任务，新建的对话会显示在这里。',
                        ),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: _sessionMenuMuted,
                          fontSize: 15,
                          height: 1.5,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    key: const Key('project_sessions_list'),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                    itemCount: sessions.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final session = sessions[index];
                      return Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          key: Key('project_session_${session.id}'),
                          onTap: () => widget.onSessionTap(session.id),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 15,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _sessionHistoryDisplayTitle(session),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: _sessionMenuText,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  color: Color(0xFF999999),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          _ChatInputShell(
            roundedBottom: false,
            child: _ChatInputBar(
              controller: _controller,
              focusNode: _focusNode,
              isSending: _isStarting,
              slashCommands: const [],
              contextStatus: null,
              isContextStatusLoading: false,
              hasContextSession: false,
              onContextStatusTap: () {},
              onSend: _submit,
              onStop: () async {},
              chatClient: widget.chatClient,
              agentId: widget.agentId,
              showContextStatus: false,
              inputFieldKey: const Key('project_chat_input'),
              sendButtonKey: const Key('project_start_chat_button'),
              stopButtonKey: const Key('project_stop_chat_button'),
            ),
          ),
        ],
      ),
    );
  }
}
