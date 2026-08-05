part of '../main.dart';

class _ProjectIconOption {
  const _ProjectIconOption(this.key, this.icon);

  final String key;
  final IconData icon;
}

class _ProjectColorOption {
  const _ProjectColorOption(this.key, this.color);

  final String key;
  final Color color;
}

const _projectIconOptions = <_ProjectIconOption>[
  _ProjectIconOption('folder', Icons.folder_outlined),
  _ProjectIconOption('rocket', Icons.rocket_launch_outlined),
  _ProjectIconOption('idea', Icons.lightbulb_outline_rounded),
  _ProjectIconOption('code', Icons.code_rounded),
  _ProjectIconOption('design', Icons.palette_outlined),
  _ProjectIconOption('campaign', Icons.campaign_outlined),
  _ProjectIconOption('learning', Icons.school_outlined),
  _ProjectIconOption('explore', Icons.travel_explore_outlined),
];

const _projectColorOptions = <_ProjectColorOption>[
  _ProjectColorOption('blue', Color(0xFF397AEF)),
  _ProjectColorOption('violet', Color(0xFF8057D9)),
  _ProjectColorOption('green', Color(0xFF2B9B69)),
  _ProjectColorOption('orange', Color(0xFFE27B35)),
  _ProjectColorOption('rose', Color(0xFFD95D7D)),
  _ProjectColorOption('slate', Color(0xFF5B6775)),
];

_ProjectIconOption _projectIconForKey(String key) {
  for (final option in _projectIconOptions) {
    if (option.key == key) return option;
  }
  return _projectIconOptions.first;
}

_ProjectColorOption _projectColorForKey(String key) {
  for (final option in _projectColorOptions) {
    if (option.key == key) return option;
  }
  return _projectColorOptions.last;
}

class _NewProjectDraft {
  const _NewProjectDraft({
    required this.name,
    required this.iconKey,
    required this.colorKey,
  });

  final String name;
  final String iconKey;
  final String colorKey;
}

class _ChatProject {
  const _ChatProject({
    required this.id,
    required this.agentId,
    required this.name,
    required this.iconKey,
    required this.colorKey,
    required this.isPinned,
    required this.createdAt,
  });

  final String id;
  final String agentId;
  final String name;
  final String iconKey;
  final String colorKey;
  final bool isPinned;
  final DateTime createdAt;

  _ChatProject copyWith({
    String? name,
    String? iconKey,
    String? colorKey,
    bool? isPinned,
  }) {
    return _ChatProject(
      id: id,
      agentId: agentId,
      name: name ?? this.name,
      iconKey: iconKey ?? this.iconKey,
      colorKey: colorKey ?? this.colorKey,
      isPinned: isPinned ?? this.isPinned,
      createdAt: createdAt,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'agentId': agentId,
    'name': name,
    'iconKey': iconKey,
    'colorKey': colorKey,
    'isPinned': isPinned,
    'createdAt': createdAt.toIso8601String(),
  };

  factory _ChatProject.fromMap(Map<String, Object?> map) {
    return _ChatProject(
      id: map['id']?.toString().trim() ?? '',
      agentId: map['agentId']?.toString().trim() ?? '',
      name: map['name']?.toString().trim() ?? '',
      iconKey: _projectIconForKey(map['iconKey']?.toString().trim() ?? '').key,
      colorKey: _projectColorForKey(
        map['colorKey']?.toString().trim() ?? '',
      ).key,
      isPinned: map['isPinned'] == true,
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

class _CreateProjectSheet extends StatefulWidget {
  const _CreateProjectSheet({this.initialDraft});

  final _NewProjectDraft? initialDraft;

  @override
  State<_CreateProjectSheet> createState() => _CreateProjectSheetState();
}

class _CreateProjectSheetState extends State<_CreateProjectSheet> {
  final TextEditingController _controller = TextEditingController();
  late String _selectedIconKey;
  late String _selectedColorKey;
  bool _canCreate = false;
  bool _isChoosingIcon = false;

  @override
  void initState() {
    super.initState();
    final initialDraft = widget.initialDraft;
    if (initialDraft != null) {
      _controller.text = initialDraft.name;
      _selectedIconKey = _projectIconForKey(initialDraft.iconKey).key;
      _selectedColorKey = _projectColorForKey(initialDraft.colorKey).key;
      _canCreate = initialDraft.name.trim().isNotEmpty;
      return;
    }
    final random = math.Random();
    _selectedIconKey =
        _projectIconOptions[random.nextInt(_projectIconOptions.length)].key;
    _selectedColorKey =
        _projectColorOptions[random.nextInt(_projectColorOptions.length)].key;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(
      _NewProjectDraft(
        name: name,
        iconKey: _selectedIconKey,
        colorKey: _selectedColorKey,
      ),
    );
  }

  void _showIconChoices() {
    FocusScope.of(context).unfocus();
    setState(() => _isChoosingIcon = true);
  }

  void _hideIconChoices() {
    setState(() => _isChoosingIcon = false);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Material(
        key: const Key('create_project_bottom_sheet'),
        color: _appSurfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    height: 22,
                    child: Center(
                      child: SizedBox(
                        width: 38,
                        height: 4,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Color(0xFFD2D4D8),
                            borderRadius: BorderRadius.all(Radius.circular(2)),
                          ),
                        ),
                      ),
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: _isChoosingIcon
                        ? _buildIconChoices(context)
                        : _buildProjectName(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProjectName(BuildContext context) {
    final icon = _projectIconForKey(_selectedIconKey);
    final selectedColor = _projectColorForKey(_selectedColorKey);
    return Column(
      key: const ValueKey('project_name_step'),
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 48,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                widget.initialDraft == null
                    ? _projectCopy(
                        context,
                        english: 'New project',
                        chinese: '新建项目',
                      )
                    : _projectCopy(
                        context,
                        english: 'Project settings',
                        chinese: '项目设置',
                      ),
                style: const TextStyle(
                  color: _sessionMenuText,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  key: const Key('cancel_create_project_button'),
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: () {
                    FocusScope.of(context).unfocus();
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.close_rounded, size: 22),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const Key('confirm_create_project_button'),
                  onPressed: _canCreate ? _submit : null,
                  child: Text(
                    widget.initialDraft == null
                        ? _projectCopy(
                            context,
                            english: 'Create',
                            chinese: '创建',
                          )
                        : _projectCopy(context, english: 'Save', chinese: '保存'),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
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
            prefixIconConstraints: const BoxConstraints(
              minWidth: 64,
              minHeight: 56,
            ),
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 8, right: 8),
              child: Material(
                key: const Key('new_project_icon_button'),
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _showIconChoices,
                  child: SizedBox.square(
                    dimension: 44,
                    child: Icon(
                      icon.icon,
                      color: selectedColor.color,
                      size: 23,
                    ),
                  ),
                ),
              ),
            ),
            contentPadding: const EdgeInsets.only(
              left: 4,
              right: 16,
              top: 16,
              bottom: 16,
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
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _buildIconChoices(BuildContext context) {
    final icon = _projectIconForKey(_selectedIconKey);
    final color = _projectColorForKey(_selectedColorKey);
    return Column(
      key: const ValueKey('project_icon_step'),
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 48,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                _projectCopy(context, english: 'Choose icon', chinese: '选择图标'),
                style: const TextStyle(
                  color: _sessionMenuText,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  key: const Key('project_icon_back_button'),
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: _hideIconChoices,
                  icon: const Icon(Icons.arrow_back_rounded, size: 22),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  key: const Key('confirm_project_icon_button'),
                  tooltip: MaterialLocalizations.of(context).okButtonLabel,
                  onPressed: _hideIconChoices,
                  icon: const Icon(Icons.check_rounded, size: 23),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          key: const Key('project_icon_preview'),
          width: 82,
          height: 82,
          child: Icon(icon.icon, color: color.color, size: 48),
        ),
        const SizedBox(height: 24),
        GridView.builder(
          key: const Key('project_icon_options'),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
          ),
          itemCount: _projectIconOptions.length,
          itemBuilder: (context, index) {
            final option = _projectIconOptions[index];
            final selected = option.key == _selectedIconKey;
            return Center(
              child: InkResponse(
                key: Key('project_icon_option_${option.key}'),
                radius: 34,
                onTap: () => setState(() => _selectedIconKey = option.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: selected
                        ? color.color.withValues(alpha: 0.1)
                        : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    option.icon,
                    size: 29,
                    color: selected ? color.color : _sessionMenuText,
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 22),
        SizedBox(
          height: 44,
          child: ListView.separated(
            key: const Key('project_color_options'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: _projectColorOptions.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final option = _projectColorOptions[index];
              return _ProjectColorChoice(
                option: option,
                selected: option.key == _selectedColorKey,
                onTap: () => setState(() => _selectedColorKey = option.key),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _ProjectColorChoice extends StatelessWidget {
  const _ProjectColorChoice({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _ProjectColorOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: InkResponse(
        key: Key('project_color_option_${option.key}'),
        radius: 25,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: option.color,
            shape: BoxShape.circle,
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: option.color.withValues(alpha: 0.28),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: selected
              ? const Icon(Icons.check_rounded, color: Colors.white, size: 20)
              : null,
        ),
      ),
    );
  }
}

class _RenameProjectSessionSheet extends StatefulWidget {
  const _RenameProjectSessionSheet({required this.initialTitle});

  final String initialTitle;

  @override
  State<_RenameProjectSessionSheet> createState() =>
      _RenameProjectSessionSheetState();
}

class _RenameProjectSessionSheetState
    extends State<_RenameProjectSessionSheet> {
  late final TextEditingController _controller;
  late bool _canSave;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialTitle);
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
    _canSave = _controller.text.trim().isNotEmpty;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _controller.text.trim();
    if (title.isEmpty) return;
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(title);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Material(
        color: _appSurfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  height: 22,
                  child: Center(
                    child: SizedBox(
                      width: 38,
                      height: 4,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Color(0xFFD2D4D8),
                          borderRadius: BorderRadius.all(Radius.circular(2)),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: 48,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Text(
                        _projectCopy(
                          context,
                          english: 'Rename chat',
                          chinese: '重命名',
                        ),
                        style: const TextStyle(
                          color: _sessionMenuText,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded, size: 22),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          key: const Key(
                            'confirm_project_session_rename_button',
                          ),
                          onPressed: _canSave ? _submit : null,
                          child: Text(
                            _projectCopy(
                              context,
                              english: 'Save',
                              chinese: '保存',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('project_session_rename_field'),
                  controller: _controller,
                  autofocus: true,
                  maxLength: 80,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  onChanged: (value) {
                    final canSave = value.trim().isNotEmpty;
                    if (canSave != _canSave) {
                      setState(() => _canSave = canSave);
                    }
                  },
                  decoration: InputDecoration(
                    counterText: '',
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: const BorderSide(
                        color: _appSurfaceBorderColor,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: const BorderSide(
                        color: _appSurfaceBorderColor,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: const BorderSide(color: Color(0xFF999999)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProjectAvatar extends StatelessWidget {
  const _ProjectAvatar({super.key, required this.project});

  final _ChatProject project;

  @override
  Widget build(BuildContext context) {
    final icon = _projectIconForKey(project.iconKey);
    final color = _projectColorForKey(project.colorKey);
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon.icon, size: 24, color: color.color),
    );
  }
}

enum _ProjectAction { pinToggle, settings, delete }

class _ProjectsPage extends StatelessWidget {
  const _ProjectsPage({
    required this.projects,
    required this.sessionCounts,
    required this.onMenu,
    required this.onAdd,
    required this.onProjectTap,
    required this.onProjectPinToggle,
    required this.onProjectSettings,
    required this.onProjectDelete,
  });

  final List<_ChatProject> projects;
  final Map<String, int> sessionCounts;
  final VoidCallback onMenu;
  final VoidCallback onAdd;
  final ValueChanged<_ChatProject> onProjectTap;
  final ValueChanged<_ChatProject> onProjectPinToggle;
  final ValueChanged<_ChatProject> onProjectSettings;
  final ValueChanged<_ChatProject> onProjectDelete;

  Future<void> _showProjectActions(
    BuildContext context,
    _ChatProject project,
  ) async {
    final action = await showModalBottomSheet<_ProjectAction>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.22),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Material(
            color: _appSurfaceColor,
            borderRadius: BorderRadius.circular(22),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SessionSheetAction(
                    key: Key('project_pin_action_${project.id}'),
                    icon: Icons.push_pin_outlined,
                    showIconSlash: project.isPinned,
                    label: project.isPinned
                        ? _projectCopy(
                            context,
                            english: 'Unpin',
                            chinese: '取消置顶',
                          )
                        : _projectCopy(context, english: 'Pin', chinese: '置顶'),
                    onTap: () => Navigator.of(
                      sheetContext,
                    ).pop(_ProjectAction.pinToggle),
                  ),
                  const SizedBox(height: 2),
                  _SessionSheetAction(
                    key: Key('project_settings_action_${project.id}'),
                    icon: Icons.edit_outlined,
                    label: _projectCopy(
                      context,
                      english: 'Settings',
                      chinese: '设置',
                    ),
                    onTap: () =>
                        Navigator.of(sheetContext).pop(_ProjectAction.settings),
                  ),
                  const SizedBox(height: 2),
                  _SessionSheetAction(
                    key: Key('project_delete_action_${project.id}'),
                    icon: Icons.delete_outline_rounded,
                    label: _projectCopy(
                      context,
                      english: 'Delete',
                      chinese: '删除',
                    ),
                    isDestructive: true,
                    onTap: () =>
                        Navigator.of(sheetContext).pop(_ProjectAction.delete),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (action == null) return;
    switch (action) {
      case _ProjectAction.pinToggle:
        onProjectPinToggle(project);
        return;
      case _ProjectAction.settings:
        onProjectSettings(project);
        return;
      case _ProjectAction.delete:
        onProjectDelete(project);
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sortedProjects = [...projects]
      ..sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        return b.createdAt.compareTo(a.createdAt);
      });

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
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: Key('project_tile_${project.id}'),
                    onTap: () => onProjectTap(project),
                    onLongPress: () => _showProjectActions(context, project),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
                      child: Row(
                        children: [
                          _ProjectAvatar(
                            key: Key('project_avatar_${project.id}'),
                            project: project,
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
                          if (project.isPinned)
                            Icon(
                              Icons.push_pin_outlined,
                              key: Key('project_pinned_icon_${project.id}'),
                              color: _sessionMenuMuted,
                              size: 19,
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

enum _ProjectSessionAction { pinToggle, rename, remove, delete }

class _ProjectDetailPage extends StatefulWidget {
  const _ProjectDetailPage({
    required this.project,
    required this.sessions,
    this.workspaceMismatchSessionIds = const {},
    required this.onBack,
    required this.onSessionTap,
    required this.onSessionPinToggle,
    required this.onSessionRename,
    required this.onSessionRemove,
    required this.onSessionDelete,
    required this.onStartChat,
    required this.onFiles,
    this.chatClient,
    required this.agentId,
  });

  final _ChatProject project;
  final List<ChatSession> sessions;
  final Set<String> workspaceMismatchSessionIds;
  final VoidCallback onBack;
  final ValueChanged<String> onSessionTap;
  final ValueChanged<String> onSessionPinToggle;
  final ValueChanged<ChatSession> onSessionRename;
  final ValueChanged<String> onSessionRemove;
  final ValueChanged<String> onSessionDelete;
  final Future<void> Function(
    String message,
    List<ChatAttachment> attachments,
    List<String> pinnedSkillNames,
  )
  onStartChat;
  final VoidCallback onFiles;
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
    sdk.AgentProviderSelection? providerSelection,
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

  Future<void> _showSessionActions(ChatSession session) async {
    final action = await showModalBottomSheet<_ProjectSessionAction>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.22),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Material(
            color: _appSurfaceColor,
            borderRadius: BorderRadius.circular(22),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SessionSheetAction(
                    key: Key('project_session_pin_action_${session.id}'),
                    icon: Icons.push_pin_outlined,
                    showIconSlash: session.isPinned,
                    label: session.isPinned
                        ? _projectCopy(
                            context,
                            english: 'Unpin',
                            chinese: '取消置顶',
                          )
                        : _projectCopy(context, english: 'Pin', chinese: '置顶'),
                    onTap: () => Navigator.of(
                      sheetContext,
                    ).pop(_ProjectSessionAction.pinToggle),
                  ),
                  const SizedBox(height: 2),
                  _SessionSheetAction(
                    key: Key('project_session_rename_action_${session.id}'),
                    icon: Icons.edit_outlined,
                    label: _projectCopy(
                      context,
                      english: 'Rename',
                      chinese: '重命名',
                    ),
                    onTap: () => Navigator.of(
                      sheetContext,
                    ).pop(_ProjectSessionAction.rename),
                  ),
                  const SizedBox(height: 2),
                  _SessionSheetAction(
                    key: Key('project_session_remove_action_${session.id}'),
                    icon: Icons.folder_off_outlined,
                    label: _projectCopy(
                      context,
                      english: 'Remove from project',
                      chinese: '从项目移出',
                    ),
                    onTap: () => Navigator.of(
                      sheetContext,
                    ).pop(_ProjectSessionAction.remove),
                  ),
                  const SizedBox(height: 2),
                  _SessionSheetAction(
                    key: Key('project_session_delete_action_${session.id}'),
                    icon: Icons.delete_outline_rounded,
                    label: _projectCopy(
                      context,
                      english: 'Delete',
                      chinese: '删除',
                    ),
                    isDestructive: true,
                    onTap: () => Navigator.of(
                      sheetContext,
                    ).pop(_ProjectSessionAction.delete),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _ProjectSessionAction.pinToggle:
        widget.onSessionPinToggle(session.id);
        return;
      case _ProjectSessionAction.rename:
        widget.onSessionRename(session);
        return;
      case _ProjectSessionAction.remove:
        widget.onSessionRemove(session.id);
        return;
      case _ProjectSessionAction.delete:
        widget.onSessionDelete(session.id);
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessions = [...widget.sessions]
      ..sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });

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
        actions: [
          IconButton(
            key: const Key('project_files_button'),
            tooltip: _projectCopy(
              context,
              english: 'Project files',
              chinese: '项目文件',
            ),
            onPressed: widget.onFiles,
            icon: const Icon(Icons.folder_open_outlined),
          ),
          const SizedBox(width: 4),
        ],
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
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          key: Key('project_session_${session.id}'),
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => widget.onSessionTap(session.id),
                          onLongPress: () => _showSessionActions(session),
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
                                if (widget.workspaceMismatchSessionIds.contains(
                                  session.id,
                                ))
                                  Tooltip(
                                    message: _projectCopy(
                                      context,
                                      english: 'Runs in a different workspace',
                                      chinese: '当前在其他工作区执行',
                                    ),
                                    child: Icon(
                                      Icons.drive_file_move_outline,
                                      key: Key(
                                        'project_session_workspace_mismatch_${session.id}',
                                      ),
                                      color: const Color(0xFFD97706),
                                      size: 18,
                                    ),
                                  ),
                                if (widget.workspaceMismatchSessionIds.contains(
                                  session.id,
                                ))
                                  const SizedBox(width: 8),
                                if (session.isPinned)
                                  Icon(
                                    Icons.push_pin_outlined,
                                    key: Key(
                                      'project_session_pinned_${session.id}',
                                    ),
                                    color: _sessionMenuMuted,
                                    size: 18,
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
              messageHint: _projectCopy(
                context,
                english: 'Message ${widget.project.name}',
                chinese: '给${widget.project.name}发消息',
              ),
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
