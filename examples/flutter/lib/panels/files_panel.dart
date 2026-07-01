part of '../main.dart';

class _FilesPage extends StatelessWidget {
  const _FilesPage({
    required this.clientFuture,
    required this.agentId,
    this.onBack,
  });

  final Future<NapaxiChatClient> clientFuture;
  final String agentId;
  final Future<bool> Function()? onBack;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);

    return Scaffold(
      backgroundColor: _configPageBackground,
      appBar: AppBar(
        title: Text(strings.filesTitle),
        backgroundColor: _configPageBackground,
        foregroundColor: _configTextPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: BackButton(
          onPressed: () async {
            final handled = await onBack?.call();
            if (handled != false && context.mounted) {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
      body: FutureBuilder<NapaxiChatClient>(
        future: clientFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || snapshot.data == null) {
            return _FilesMessage(
              icon: Icons.folder_off_rounded,
              title: strings.fileLoadFailed(
                _friendlyDisplayError(snapshot.error),
              ),
              description: null,
            );
          }
          return _FilesBrowser(client: snapshot.data!, agentId: agentId);
        },
      ),
    );
  }
}

class _FilesBrowser extends StatelessWidget {
  const _FilesBrowser({required this.client, required this.agentId});

  final NapaxiChatClient client;
  final String agentId;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);

    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          DecoratedBox(
            decoration: const BoxDecoration(
              color: _configPageBackground,
              border: Border(bottom: BorderSide(color: _configBorderFaint)),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final labels = [
                  strings.workspaceFilesTitle,
                  strings.memoryFilesTitle,
                  strings.journalFilesTitle,
                ];
                const labelStyle = TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                );
                const horizontalLabelPadding = 32.0;
                final textScaler = MediaQuery.textScalerOf(context);
                final maxLabelWidth = labels.fold<double>(0, (acc, label) {
                  final painter = TextPainter(
                    text: TextSpan(text: label, style: labelStyle),
                    textDirection: TextDirection.ltr,
                    textScaler: textScaler,
                  )..layout();
                  return painter.width > acc ? painter.width : acc;
                });
                final cellWidth = constraints.maxWidth / labels.length;
                final scrollable =
                    maxLabelWidth + horizontalLabelPadding > cellWidth;

                return TabBar(
                  isScrollable: scrollable,
                  tabAlignment: scrollable
                      ? TabAlignment.start
                      : TabAlignment.fill,
                  indicatorColor: _configTextPrimary,
                  indicatorSize: TabBarIndicatorSize.label,
                  labelColor: _configTextPrimary,
                  unselectedLabelColor: _configTextSecondary,
                  dividerColor: Colors.transparent,
                  labelStyle: labelStyle,
                  unselectedLabelStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  tabs: [for (final label in labels) Tab(text: label)],
                );
              },
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _FileSourceView(
                  client: client,
                  source: _FileSource.workspace,
                  agentId: agentId,
                ),
                _FileSourceView(
                  client: client,
                  source: _FileSource.memory,
                  agentId: agentId,
                ),
                _FileSourceView(
                  client: client,
                  source: _FileSource.journal,
                  agentId: agentId,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _FileAction { download, share, delete }

class _FileSourceView extends StatefulWidget {
  const _FileSourceView({
    required this.client,
    required this.source,
    required this.agentId,
  });

  final NapaxiChatClient client;
  final _FileSource source;
  final String agentId;

  @override
  State<_FileSourceView> createState() => _FileSourceViewState();
}

class _FileSourceViewState extends State<_FileSourceView> {
  late Future<List<_FileBrowserItem>> _filesFuture;
  final Set<String> _selectedItemKeys = {};
  String _currentDirectory = '';

  bool get _isSelecting => _selectedItemKeys.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _filesFuture = _loadFiles();
  }

  Future<List<_FileBrowserItem>> _loadFiles() async {
    final files = switch (widget.source) {
      _FileSource.memory => await _loadMemoryFiles(),
      _FileSource.workspace => await _loadWorkspaceFiles(),
      _FileSource.journal => await _loadJournalFiles(),
      _FileSource.repository => const <_FileBrowserItem>[],
    };
    files.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      return a.path.toLowerCase().compareTo(b.path.toLowerCase());
    });
    return files;
  }

  Future<List<_FileBrowserItem>> _loadMemoryFiles() async {
    final entries = await widget.client.listMemoryFiles(
      _currentDirectory,
      agentId: widget.agentId,
    );
    return [
      for (final entry in entries)
        if (!_isLegacyDailyMemoryPath(entry.path))
          _FileBrowserItem(
            source: _FileSource.memory,
            path: entry.path,
            name: _fileNameFromPath(entry.path),
            isDirectory: entry.isDirectory,
            browsePath: entry.isDirectory ? entry.path : null,
            modified: entry.updatedAt,
          ),
    ];
  }

  Future<List<_FileBrowserItem>> _loadJournalFiles() async {
    final days = await widget.client.listJournalDays(agentId: widget.agentId);
    return [
      for (final day in days)
        _FileBrowserItem(
          source: _FileSource.journal,
          path: day.date,
          name: day.legacy ? '${day.date} (legacy)' : day.date,
          isDirectory: false,
          mimeType: 'text/plain',
          modified: day.updatedAt,
        ),
    ];
  }

  Future<List<_FileBrowserItem>> _loadWorkspaceFiles() async {
    final files = await widget.client.listSandboxWorkspaceFiles(
      agentId: widget.agentId,
      subdir: _currentDirectory.isEmpty ? null : _currentDirectory,
      recursive: false,
    );
    final itemsByPath = <String, _FileBrowserItem>{};

    for (final file in files) {
      final logicalPath = _workspaceLogicalPath(file.sandboxPath);
      final childPath = _directChildPath(
        directory: _currentDirectory,
        path: logicalPath,
      );
      if (childPath == null) continue;

      final isDirectory = file.isDirectory || childPath != logicalPath;
      final name = _fileNameFromPath(childPath);
      itemsByPath.putIfAbsent(
        childPath,
        () => _FileBrowserItem(
          source: _FileSource.workspace,
          path: isDirectory ? childPath : file.sandboxPath,
          name: name,
          isDirectory: isDirectory,
          browsePath: isDirectory ? childPath : null,
          deletePath: isDirectory
              ? _workspaceSandboxPath(childPath)
              : file.sandboxPath,
          realPath: isDirectory ? null : file.realPath,
          mimeType: isDirectory ? null : file.mimeType,
          sizeBytes: isDirectory ? null : file.sizeBytes,
          modified: file.modified,
        ),
      );
    }

    return itemsByPath.values.toList();
  }

  void _reload() {
    setState(() {
      _selectedItemKeys.clear();
      _filesFuture = _loadFiles();
    });
  }

  Future<void> _openFile(_FileBrowserItem item) async {
    if (_isSelecting && item.canSelect) {
      _toggleSelection(item);
      return;
    }
    if (item.isDirectory) {
      setState(() {
        _currentDirectory = item.browsePath ?? item.path;
        _selectedItemKeys.clear();
        _filesFuture = _loadFiles();
      });
      return;
    }
    final deleted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => _FilePreviewPage(
          client: widget.client,
          item: item,
          agentId: widget.agentId,
        ),
      ),
    );
    if (deleted == true && mounted) _reload();
  }

  void _openParentDirectory() {
    setState(() {
      _currentDirectory = _parentDirectory(_currentDirectory);
      _selectedItemKeys.clear();
      _filesFuture = _loadFiles();
    });
  }

  String _itemKey(_FileBrowserItem item) => '${item.source.name}:${item.path}';

  void _toggleSelection(_FileBrowserItem item) {
    if (!item.canSelect) return;
    final key = _itemKey(item);
    setState(() {
      if (!_selectedItemKeys.add(key)) {
        _selectedItemKeys.remove(key);
      }
    });
  }

  void _clearSelection() {
    setState(_selectedItemKeys.clear);
  }

  Future<void> _handleFileAction(
    List<_FileBrowserItem> items,
    _FileAction action,
  ) async {
    if (items.isEmpty) return;
    try {
      final deleted = await _performFileAction(
        context: context,
        client: widget.client,
        agentId: widget.agentId,
        items: items,
        action: action,
      );
      if (!mounted) return;
      if (deleted) {
        _reload();
      } else if (_isSelecting) {
        _clearSelection();
      }
    } catch (error) {
      if (!mounted) return;
      final strings = AppStrings.of(context);
      _showFileSnackBar(
        context,
        strings.fileActionFailed(_friendlyDisplayError(error)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);

    return FutureBuilder<List<_FileBrowserItem>>(
      future: _filesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _FilesMessage(
            icon: Icons.error_outline_rounded,
            title: strings.fileLoadFailed(
              _friendlyDisplayError(snapshot.error),
            ),
            description: null,
            action: IconButton(
              tooltip: MaterialLocalizations.of(
                context,
              ).refreshIndicatorSemanticLabel,
              onPressed: _reload,
              icon: const Icon(Icons.refresh_rounded),
            ),
          );
        }

        final files = snapshot.data ?? const [];
        final selectedItems = [
          for (final item in files)
            if (_selectedItemKeys.contains(_itemKey(item))) item,
        ];
        final canTransferSelected =
            selectedItems.isNotEmpty &&
            selectedItems.every((item) => !item.isDirectory);
        final canDeleteSelected =
            selectedItems.isNotEmpty &&
            selectedItems.every((item) => item.canDelete);
        if (files.isEmpty && _currentDirectory.isEmpty) {
          return _FilesMessage(
            icon: Icons.folder_open_rounded,
            title: strings.noFilesTitle,
            description: strings.noFilesDescription,
          );
        }

        return Column(
          children: [
            if (_isSelecting)
              _FileSelectionBar(
                selectedCount: selectedItems.length,
                canTransfer: canTransferSelected,
                canDelete: canDeleteSelected,
                onClose: _clearSelection,
                onSave: () =>
                    _handleFileAction(selectedItems, _FileAction.download),
                onSend: () =>
                    _handleFileAction(selectedItems, _FileAction.share),
                onDelete: () =>
                    _handleFileAction(selectedItems, _FileAction.delete),
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => _reload(),
                child: ListView.separated(
                  key: Key('files_${widget.source.name}_list'),
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                  itemCount:
                      files.length +
                      (_currentDirectory.isEmpty ? 0 : 1) +
                      (files.isEmpty && _currentDirectory.isNotEmpty ? 1 : 0),
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    if (_currentDirectory.isNotEmpty && index == 0) {
                      return _ParentDirectoryTile(
                        directory: _currentDirectory,
                        onTap: _openParentDirectory,
                      );
                    }
                    if (files.isEmpty && _currentDirectory.isNotEmpty) {
                      return _EmptyDirectoryTile(
                        title: strings.noFilesTitle,
                        description: strings.noFilesDescription,
                      );
                    }
                    final fileIndex =
                        index - (_currentDirectory.isEmpty ? 0 : 1);
                    final item = files[fileIndex];
                    return _FileTile(
                      item: item,
                      isSelecting: _isSelecting,
                      isSelected: _selectedItemKeys.contains(_itemKey(item)),
                      onTap: () => _openFile(item),
                      onLongPress: () => _toggleSelection(item),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ParentDirectoryTile extends StatelessWidget {
  const _ParentDirectoryTile({required this.directory, required this.onTap});

  final String directory;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        key: const Key('files_parent_directory_tile'),
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.arrow_upward_rounded, color: Color(0xFF4B5563)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  directory,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF1F2937),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FileSelectionBar extends StatelessWidget {
  const _FileSelectionBar({
    required this.selectedCount,
    required this.canTransfer,
    required this.canDelete,
    required this.onClose,
    required this.onSave,
    required this.onSend,
    required this.onDelete,
  });

  final int selectedCount;
  final bool canTransfer;
  final bool canDelete;
  final VoidCallback onClose;
  final VoidCallback onSave;
  final VoidCallback onSend;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);

    return Material(
      color: Colors.white,
      elevation: 1,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              IconButton(
                tooltip: strings.cancel,
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded),
              ),
              Expanded(
                child: Text(
                  strings.selectedFilesCount(selectedCount),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF1F2937),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: strings.downloadFile,
                onPressed: canTransfer ? onSave : null,
                icon: const Icon(Icons.save_alt_rounded),
              ),
              IconButton(
                tooltip: strings.shareFile,
                onPressed: canTransfer ? onSend : null,
                icon: const Icon(Icons.send_rounded),
              ),
              IconButton(
                tooltip: strings.deleteFile,
                onPressed: canDelete ? onDelete : null,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyDirectoryTile extends StatelessWidget {
  const _EmptyDirectoryTile({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        child: Column(
          children: [
            const Icon(
              Icons.folder_open_rounded,
              color: Color(0xFF9CA3AF),
              size: 32,
            ),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF333333),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF666666),
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({
    required this.item,
    required this.isSelecting,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
  });

  final _FileBrowserItem item;
  final bool isSelecting;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final pathMeta = item.path == item.name ? '' : item.path;
    final meta = <String>[
      if (pathMeta.isNotEmpty) pathMeta,
      if (item.sizeBytes != null && !item.isDirectory)
        _formatFileSize(item.sizeBytes!),
      if (item.modified != null) _formatFileDate(item.modified!),
    ].join(' · ');

    return Material(
      color: isSelected ? const Color(0xFFEFF6FF) : Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        onLongPress: item.canSelect ? onLongPress : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              if (isSelecting && item.canSelect)
                Icon(
                  isSelected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: isSelected
                      ? const Color(0xFF2563EB)
                      : const Color(0xFF9CA3AF),
                )
              else
                Icon(
                  item.isDirectory
                      ? Icons.folder_rounded
                      : item.isHtml
                      ? Icons.web_asset_rounded
                      : item.isImage
                      ? Icons.image_rounded
                      : Icons.description_rounded,
                  color: const Color(0xFF4B5563),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF1F2937),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (!isSelecting)
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF9CA3AF),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<bool> _performFileAction({
  required BuildContext context,
  required NapaxiChatClient client,
  required String agentId,
  required List<_FileBrowserItem> items,
  required _FileAction action,
}) async {
  switch (action) {
    case _FileAction.download:
      await _downloadFiles(context, client, agentId, items);
      return false;
    case _FileAction.share:
      await _shareFiles(context, client, agentId, items);
      return false;
    case _FileAction.delete:
      return _deleteFiles(context, client, agentId, items);
  }
}

Future<String> _readJournalText(
  NapaxiChatClient client,
  String agentId,
  String date,
) async {
  final records = await client.readJournalDay(date, agentId: agentId);
  if (records.isEmpty) {
    return 'No journal records for $date.';
  }
  final buffer = StringBuffer();
  for (final record in records) {
    final createdAt = record.createdAt?.toLocal().toIso8601String() ?? '';
    buffer.writeln('## ${createdAt.isEmpty ? record.kind : createdAt}');
    if (record.kind.isNotEmpty) buffer.writeln('- Kind: ${record.kind}');
    if (record.agentId.isNotEmpty) buffer.writeln('- Agent: ${record.agentId}');
    if (record.threadId.isNotEmpty) {
      buffer.writeln('- Thread: ${record.threadId}');
    }
    if (record.user.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(record.kind == 'legacy_daily' ? 'Legacy Daily:' : 'User:')
        ..writeln(record.user.trim());
    }
    if (record.assistant.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Assistant:')
        ..writeln(record.assistant.trim());
    }
    buffer.writeln();
  }
  return buffer.toString().trimRight();
}

Future<Uint8List> _readFileBytes(
  NapaxiChatClient client,
  String agentId,
  _FileBrowserItem item,
) async {
  if (item.source == _FileSource.memory) {
    final file = await client.readMemoryFile(item.path, agentId: agentId);
    return Uint8List.fromList(utf8.encode(file?.content ?? ''));
  }
  if (item.source == _FileSource.journal) {
    return Uint8List.fromList(
      utf8.encode(await _readJournalText(client, agentId, item.path)),
    );
  }

  final realPath = item.realPath;
  if (realPath == null || realPath.isEmpty) {
    throw StateError('Workspace file path is unavailable');
  }
  return File(realPath).readAsBytes();
}

Future<void> _downloadFiles(
  BuildContext context,
  NapaxiChatClient client,
  String agentId,
  List<_FileBrowserItem> items,
) async {
  final strings = AppStrings.of(context);
  for (final item in items) {
    final bytes = await _readFileBytes(client, agentId, item);
    final savedPath = await FilePicker.platform.saveFile(
      dialogTitle: strings.downloadFile,
      fileName: item.name,
      bytes: bytes,
    );
    if (savedPath == null) return;
  }
  if (context.mounted) _showFileSnackBar(context, strings.fileDownloaded);
}

Future<void> _shareFiles(
  BuildContext context,
  NapaxiChatClient client,
  String agentId,
  List<_FileBrowserItem> items,
) async {
  final box = context.findRenderObject() as RenderBox?;
  final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
  final files = <share.XFile>[];
  final fileNameOverrides = <String>[];
  for (final item in items) {
    final mimeType = item.mimeType ?? 'text/plain';
    files.add(
      item.realPath == null || item.realPath!.isEmpty
          ? share.XFile.fromData(
              await _readFileBytes(client, agentId, item),
              name: item.name,
              mimeType: mimeType,
            )
          : share.XFile(item.realPath!, name: item.name, mimeType: mimeType),
    );
    fileNameOverrides.add(item.name);
  }

  await share.Share.shareXFiles(
    files,
    subject: items.length == 1 ? items.single.name : null,
    sharePositionOrigin: origin,
    fileNameOverrides: fileNameOverrides,
  );
}

Future<bool> _deleteFiles(
  BuildContext context,
  NapaxiChatClient client,
  String agentId,
  List<_FileBrowserItem> items,
) async {
  final strings = AppStrings.of(context);
  if (items.any((item) => item.isProtectedMemoryFile)) {
    _showFileSnackBar(context, strings.protectedMemoryFile);
    return false;
  }

  final shouldDelete = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(strings.deleteFileConfirmationTitle),
      content: Text(
        strings.deleteFileConfirmationMessage(
          _deleteConfirmationTarget(context, items),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(strings.cancel),
        ),
        FilledButton.tonal(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(strings.deleteFile),
        ),
      ],
    ),
  );
  if (shouldDelete != true) return false;

  for (final item in items) {
    if (item.source == _FileSource.memory) {
      final deleted = await client.deleteMemoryFile(
        item.path,
        agentId: agentId,
      );
      if (!deleted) throw StateError('File was not deleted');
    } else {
      await client.deleteSandboxWorkspaceFile(
        item.deletePath ?? item.path,
        agentId: agentId,
      );
    }
  }

  if (context.mounted) _showFileSnackBar(context, strings.fileDeleted);
  return true;
}

String _deleteConfirmationTarget(
  BuildContext context,
  List<_FileBrowserItem> items,
) {
  if (items.length == 1) return items.single.name;
  return switch (_AppLanguageScope.languageOf(context)) {
    AppLanguage.chinese => '${items.length} 个文件',
    AppLanguage.english => '${items.length} files',
  };
}

String _unsupportedPreviewTitle(BuildContext context) {
  return switch (_AppLanguageScope.languageOf(context)) {
    AppLanguage.chinese => '暂不支持预览',
    AppLanguage.english => 'Preview unavailable',
  };
}

String _unsupportedPreviewDescription(
  BuildContext context,
  _FileBrowserItem item,
) {
  final actionHint = switch (_AppLanguageScope.languageOf(context)) {
    AppLanguage.chinese => '可以保存副本或发送到其他应用打开。',
    AppLanguage.english => 'Save a copy or send it to another app to open it.',
  };
  final type = (item.mimeType ?? '').trim();
  if (type.isEmpty) return actionHint;
  return switch (_AppLanguageScope.languageOf(context)) {
    AppLanguage.chinese => '文件类型：$type。$actionHint',
    AppLanguage.english => 'File type: $type. $actionHint',
  };
}

void _showFileSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

String _normalizeFilePath(String path) {
  return path
      .replaceAll('\\', '/')
      .split('/')
      .where((part) => part.trim().isNotEmpty)
      .join('/');
}

bool _isLegacyDailyMemoryPath(String path) {
  final normalized = _normalizeFilePath(path);
  return normalized == 'daily' || normalized.startsWith('daily/');
}

String _workspaceLogicalPath(String sandboxPath) {
  final normalized = _normalizeFilePath(sandboxPath);
  const prefix = 'workspace/';
  if (normalized == 'workspace') return '';
  if (normalized.startsWith(prefix)) {
    return normalized.substring(prefix.length);
  }
  return normalized;
}

String _workspaceSandboxPath(String logicalPath) {
  final normalized = _normalizeFilePath(logicalPath);
  return normalized.isEmpty ? '/workspace' : '/workspace/$normalized';
}

String? _directChildPath({required String directory, required String path}) {
  final normalizedDirectory = _normalizeFilePath(directory);
  final normalizedPath = _normalizeFilePath(path);
  if (normalizedPath.isEmpty || normalizedPath == normalizedDirectory) {
    return null;
  }

  final relativePath = normalizedDirectory.isEmpty
      ? normalizedPath
      : normalizedPath.startsWith('$normalizedDirectory/')
      ? normalizedPath.substring(normalizedDirectory.length + 1)
      : null;
  if (relativePath == null || relativePath.isEmpty) return null;

  final firstSlash = relativePath.indexOf('/');
  final childName = firstSlash == -1
      ? relativePath
      : relativePath.substring(0, firstSlash);
  return normalizedDirectory.isEmpty
      ? childName
      : '$normalizedDirectory/$childName';
}

String _parentDirectory(String directory) {
  final normalized = _normalizeFilePath(directory);
  final slash = normalized.lastIndexOf('/');
  if (slash == -1) return '';
  return normalized.substring(0, slash);
}

class _FilePreviewPage extends StatefulWidget {
  const _FilePreviewPage({
    required this.client,
    required this.item,
    required this.agentId,
  });

  final NapaxiChatClient client;
  final _FileBrowserItem item;
  final String agentId;

  @override
  State<_FilePreviewPage> createState() => _FilePreviewPageState();
}

class _FilePreviewPageState extends State<_FilePreviewPage> {
  static const int _maxTextPreviewBytes = 1024 * 1024;

  late final Future<String> _textFuture = _readText();
  late final Future<WebViewController>? _webControllerFuture =
      widget.item.isHtml ? _createHtmlPreviewController() : null;
  bool _showHtmlSource = false;
  int _webProgress = 0;
  String? _blockedNavigation;

  Future<String> _readText() async {
    final item = widget.item;
    if (item.source == _FileSource.memory) {
      final file = await widget.client.readMemoryFile(
        item.path,
        agentId: widget.agentId,
      );
      return file?.content ?? '';
    }
    if (item.source == _FileSource.journal) {
      return _readJournalText(widget.client, widget.agentId, item.path);
    }

    final realPath = item.realPath;
    if (realPath == null || realPath.isEmpty) {
      throw StateError('Workspace file path is unavailable');
    }
    final file = File(realPath);
    final size = await file.length();
    if (size > _maxTextPreviewBytes) {
      return 'Preview skipped: file is larger than 1 MB.';
    }
    return file.readAsString();
  }

  Future<WebViewController> _createHtmlPreviewController() async {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) setState(() => _webProgress = progress);
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            final scheme = uri?.scheme;
            final allowed =
                scheme == 'http' ||
                scheme == 'https' ||
                scheme == 'file' ||
                scheme == 'about' ||
                scheme == 'data';
            if (!allowed) {
              if (mounted) setState(() => _blockedNavigation = request.url);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onWebResourceError: (error) {
            if (!mounted) return;
            _showFileSnackBar(
              context,
              'Web preview failed: ${error.description}',
            );
          },
        ),
      );

    final item = widget.item;
    if (item.source == _FileSource.memory ||
        item.source == _FileSource.journal) {
      await controller.loadHtmlString(await _readText());
      return controller;
    }

    final realPath = item.realPath;
    if (realPath == null || realPath.isEmpty) {
      throw StateError('Workspace file path is unavailable');
    }
    await controller.loadFile(realPath);
    return controller;
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final item = widget.item;

    return Scaffold(
      appBar: AppBar(
        title: Text(item.name),
        actions: [
          if (item.isHtml)
            _FilePreviewActionButton(
              tooltip: _showHtmlSource ? 'Render HTML' : 'View source',
              icon: _showHtmlSource
                  ? Icons.web_asset_rounded
                  : Icons.code_rounded,
              onPressed: () =>
                  setState(() => _showHtmlSource = !_showHtmlSource),
            ),
          _FilePreviewActionButton(
            tooltip: strings.downloadFile,
            icon: Icons.save_alt_rounded,
            onPressed: () =>
                _handlePreviewAction(context, _FileAction.download),
          ),
          _FilePreviewActionButton(
            tooltip: strings.shareFile,
            icon: Icons.send_rounded,
            onPressed: () => _handlePreviewAction(context, _FileAction.share),
          ),
          _FilePreviewActionButton(
            tooltip: item.isProtectedMemoryFile
                ? strings.protectedMemoryFile
                : strings.deleteFile,
            icon: Icons.delete_outline_rounded,
            onPressed: item.canDelete
                ? () => _handlePreviewAction(context, _FileAction.delete)
                : null,
          ),
        ],
      ),
      body: !item.canPreview
          ? _UnsupportedFilePreview(item: item)
          : item.isImage && item.realPath != null
          ? Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4,
                child: Image.file(
                  File(item.realPath!),
                  errorBuilder: (context, error, stackTrace) {
                    return _FilesMessage(
                      icon: Icons.broken_image_rounded,
                      title: strings.fileOpenFailed(
                        _friendlyDisplayError(error),
                      ),
                      description: null,
                    );
                  },
                ),
              ),
            )
          : item.isHtml && !_showHtmlSource
          ? _HtmlFilePreview(
              controllerFuture: _webControllerFuture!,
              progress: _webProgress,
              blockedNavigation: _blockedNavigation,
              onDismissBlockedNavigation: () =>
                  setState(() => _blockedNavigation = null),
              errorDescription: null,
            )
          : _TextFilePreview(textFuture: _textFuture),
    );
  }

  Future<void> _handlePreviewAction(
    BuildContext context,
    _FileAction action,
  ) async {
    final strings = AppStrings.of(context);
    try {
      final deleted = await _performFileAction(
        context: context,
        client: widget.client,
        agentId: widget.agentId,
        items: [widget.item],
        action: action,
      );
      if (deleted && context.mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (!context.mounted) return;
      _showFileSnackBar(
        context,
        strings.fileActionFailed(_friendlyDisplayError(error)),
      );
    }
  }
}

class _HtmlFilePreview extends StatelessWidget {
  const _HtmlFilePreview({
    required this.controllerFuture,
    required this.progress,
    required this.blockedNavigation,
    required this.onDismissBlockedNavigation,
    required this.errorDescription,
  });

  final Future<WebViewController> controllerFuture;
  final int progress;
  final String? blockedNavigation;
  final VoidCallback onDismissBlockedNavigation;
  final String? errorDescription;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return FutureBuilder<WebViewController>(
      future: controllerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || snapshot.data == null) {
          return _FilesMessage(
            icon: Icons.error_outline_rounded,
            title: strings.fileOpenFailed(
              _friendlyDisplayError(snapshot.error),
            ),
            description: errorDescription,
          );
        }
        return Column(
          children: [
            if (progress < 100) LinearProgressIndicator(value: progress / 100),
            if (blockedNavigation != null)
              MaterialBanner(
                content: Text('Blocked unsupported link: $blockedNavigation'),
                actions: [
                  TextButton(
                    onPressed: onDismissBlockedNavigation,
                    child: const Text('Dismiss'),
                  ),
                ],
              ),
            Expanded(child: WebViewWidget(controller: snapshot.data!)),
          ],
        );
      },
    );
  }
}

class _TextFilePreview extends StatelessWidget {
  const _TextFilePreview({required this.textFuture});

  final Future<String> textFuture;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return FutureBuilder<String>(
      future: textFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _FilesMessage(
            icon: Icons.error_outline_rounded,
            title: strings.fileOpenFailed(
              _friendlyDisplayError(snapshot.error),
            ),
            description: null,
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SelectableText(
            snapshot.data ?? '',
            style: const TextStyle(
              color: Color(0xFF111827),
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.45,
            ),
          ),
        );
      },
    );
  }
}

class _UnsupportedFilePreview extends StatelessWidget {
  const _UnsupportedFilePreview({required this.item});

  final _FileBrowserItem item;

  @override
  Widget build(BuildContext context) {
    return _FilesMessage(
      icon: Icons.insert_drive_file_rounded,
      title: _unsupportedPreviewTitle(context),
      description: _unsupportedPreviewDescription(context, item),
    );
  }
}

class _FilePreviewActionButton extends StatelessWidget {
  const _FilePreviewActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(tooltip: tooltip, onPressed: onPressed, icon: Icon(icon));
  }
}

class _FilesMessage extends StatelessWidget {
  const _FilesMessage({
    required this.icon,
    required this.title,
    required this.description,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? description;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: const Color(0xFF9CA3AF), size: 34),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF333333),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (description != null && description!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                description!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF666666),
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 8), action!],
          ],
        ),
      ),
    );
  }
}
