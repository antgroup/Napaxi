part of '../main.dart';

class _ChatInputShell extends StatelessWidget {
  const _ChatInputShell({required this.child, required this.roundedBottom});

  final Widget child;
  final bool roundedBottom;

  @override
  Widget build(BuildContext context) {
    final radius = roundedBottom ? 24.0 : 0.0;
    return ColoredBox(
      color: roundedBottom ? Colors.black : _appSurfaceColor,
      child: ClipRRect(
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(radius)),
        child: ColoredBox(color: _appSurfaceColor, child: child),
      ),
    );
  }
}

String _browserDockTitle(String? title, String? url) {
  if (url != null && url.isNotEmpty) {
    final host = Uri.tryParse(url)?.host;
    if (host != null && host.isNotEmpty) return host;
  }
  if (title != null && title.isNotEmpty) return title;
  return 'Browser';
}

String _browserModeLabel(AppStrings strings, sdk.BrowserViewportMode mode) {
  return switch (mode) {
    sdk.BrowserViewportMode.desktop => strings.browserDesktopMode,
    sdk.BrowserViewportMode.mobile => strings.browserMobileMode,
  };
}

class _ChatTopBar extends StatelessWidget {
  const _ChatTopBar({
    required this.activeAgent,
    required this.agents,
    required this.runtimeProfile,
    required this.language,
    required this.hasAttachments,
    required this.newAttachmentCount,
    required this.onAgentSelected,
    required this.onEngineSelected,
    required this.onManageAgents,
    required this.onSessionsTap,
    required this.onAttachmentsTap,
    this.onNewTerminal,
    this.onCopyWorkspacePath,
    this.onCopyBranchName,
    this.onOpenWorkbench,
  });

  final DemoAgent activeAgent;
  final List<DemoAgent> agents;
  final DemoScenarioRuntimeProfile runtimeProfile;
  final AppLanguage language;
  final bool hasAttachments;
  final int newAttachmentCount;
  final ValueChanged<String> onAgentSelected;
  final ValueChanged<String> onEngineSelected;
  final VoidCallback onManageAgents;
  final VoidCallback onSessionsTap;
  final VoidCallback onAttachmentsTap;
  final VoidCallback? onNewTerminal;
  final VoidCallback? onCopyWorkspacePath;
  final VoidCallback? onCopyBranchName;
  final VoidCallback? onOpenWorkbench;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 40,
            child: IconButton(
              key: const Key('session_history_button'),
              tooltip: strings.sessionsTooltip,
              padding: EdgeInsets.zero,
              onPressed: onSessionsTap,
              icon: const Icon(Icons.menu_rounded),
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: runtimeProfile.supportsAgents
                  ? PopupMenuButton<String>(
                      key: const Key('agent_selector_button'),
                      tooltip: activeAgent.label(language),
                      initialValue: activeAgent.id,
                      position: PopupMenuPosition.under,
                      offset: const Offset(0, 8),
                      onSelected: (value) {
                        if (value == '__manage_agents__') {
                          onManageAgents();
                          return;
                        }
                        onAgentSelected(value);
                      },
                      itemBuilder: (context) => [
                        for (final agent in agents)
                          PopupMenuItem(
                            value: agent.id,
                            child: Row(
                              children: [
                                Icon(agent.icon, size: 20),
                                const SizedBox(width: 10),
                                Text(agent.label(language)),
                              ],
                            ),
                          ),
                        const PopupMenuDivider(),
                        PopupMenuItem(
                          value: '__manage_agents__',
                          child: Row(
                            children: [
                              const Icon(
                                Icons.manage_accounts_rounded,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Text(strings.manageAgents),
                            ],
                          ),
                        ),
                      ],
                      child: _TopBarSelectorLabel(
                        icon: activeAgent.icon,
                        label: activeAgent.label(language),
                      ),
                    )
                  : PopupMenuButton<String>(
                      key: const Key('engine_selector_button'),
                      tooltip: runtimeProfile.activeEngine.label,
                      initialValue: runtimeProfile.activeEngineId,
                      position: PopupMenuPosition.under,
                      offset: const Offset(0, 8),
                      onSelected: onEngineSelected,
                      itemBuilder: (context) => [
                        for (final engine in runtimeProfile.engines)
                          PopupMenuItem(
                            value: engine.id,
                            enabled: engine.enabled,
                            child: Row(
                              children: [
                                Icon(engine.icon, size: 20),
                                const SizedBox(width: 10),
                                Expanded(child: Text(engine.label)),
                                if (!engine.enabled)
                                  Text(
                                    strings.developerEngineUnavailable,
                                    style: const TextStyle(
                                      color: Color(0xFF737373),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                      child: _TopBarSelectorLabel(
                        icon: runtimeProfile.activeEngine.icon,
                        label: runtimeProfile.activeEngine.label,
                      ),
                    ),
            ),
          ),
          SizedBox.square(
            dimension: 40,
            child: IconButton(
              key: const Key('conversation_attachments_button'),
              tooltip: strings.conversationAttachmentsTooltip,
              padding: EdgeInsets.zero,
              onPressed: onAttachmentsTap,
              icon: _TopBarAttachmentIcon(
                hasAttachments: hasAttachments,
                newCount: newAttachmentCount,
              ),
            ),
          ),
          if (runtimeProfile.isDeveloper)
            SizedBox.square(
              dimension: 40,
              child: PopupMenuButton<String>(
                key: const Key('dev_overflow_menu_button'),
                tooltip: '',
                position: PopupMenuPosition.under,
                offset: const Offset(0, 8),
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.more_vert),
                onSelected: (value) {
                  switch (value) {
                    case 'new_terminal':
                      onNewTerminal?.call();
                    case 'copy_workspace':
                      onCopyWorkspacePath?.call();
                    case 'copy_branch':
                      onCopyBranchName?.call();
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    key: const Key('menu_new_terminal'),
                    value: 'new_terminal',
                    child: Row(
                      children: [
                        const Icon(Icons.terminal_rounded, size: 20),
                        const SizedBox(width: 10),
                        Flexible(child: Text(strings.menuNewTerminal)),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    key: const Key('menu_copy_workspace_path'),
                    value: 'copy_workspace',
                    child: Row(
                      children: [
                        const Icon(Icons.folder_copy_outlined, size: 20),
                        const SizedBox(width: 10),
                        Flexible(child: Text(strings.menuCopyWorkspacePath)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    key: const Key('menu_copy_branch_name'),
                    value: 'copy_branch',
                    child: Row(
                      children: [
                        const Icon(Icons.commit_outlined, size: 20),
                        const SizedBox(width: 10),
                        Flexible(child: Text(strings.menuCopyBranchName)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (runtimeProfile.isDeveloper)
            SizedBox.square(
              dimension: 40,
              child: IconButton(
                key: const Key('dev_workbench_button'),
                tooltip: 'Workbench',
                padding: EdgeInsets.zero,
                onPressed: onOpenWorkbench,
                icon: const _SourceControlPanelIcon(),
              ),
            ),
        ],
      ),
    );
  }
}

/// Reproduces paseo's source-control-panel "workbench" glyph: an outlined
/// rounded square containing a plus above a minus. Mirrors the icon used by the
/// workspace explorer toggle in ~/paseo (24x24 viewBox, stroke width 2).
class _SourceControlPanelIcon extends StatelessWidget {
  const _SourceControlPanelIcon();

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 24,
      child: CustomPaint(
        painter: _SourceControlPanelIconPainter(
          color: IconTheme.of(context).color,
        ),
      ),
    );
  }
}

class _SourceControlPanelIconPainter extends CustomPainter {
  const _SourceControlPanelIconPainter({required this.color});

  final Color? color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24;
    final paint = Paint()
      ..color = color ?? const Color(0xFF171717)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(3 * scale, 3 * scale, 18 * scale, 18 * scale),
        Radius.circular(2 * scale),
      ),
      paint,
    );
    canvas.drawLine(
      Offset(9 * scale, 9.5 * scale),
      Offset(15 * scale, 9.5 * scale),
      paint,
    );
    canvas.drawLine(
      Offset(12 * scale, 6.5 * scale),
      Offset(12 * scale, 12.5 * scale),
      paint,
    );
    canvas.drawLine(
      Offset(9 * scale, 16 * scale),
      Offset(15 * scale, 16 * scale),
      paint,
    );
  }

  @override
  bool shouldRepaint(_SourceControlPanelIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _TopBarSelectorLabel extends StatelessWidget {
  const _TopBarSelectorLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: const Color(0xFF222222)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF171717),
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 2),
          const Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 20,
            color: Color(0xFF737373),
          ),
        ],
      ),
    );
  }
}

class _TopBarAttachmentIcon extends StatelessWidget {
  const _TopBarAttachmentIcon({
    required this.hasAttachments,
    required this.newCount,
  });

  final bool hasAttachments;
  final int newCount;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(
          hasAttachments ? Icons.snippet_folder_rounded : Icons.folder_outlined,
          key: Key(
            hasAttachments
                ? 'conversation_attachments_icon_filled'
                : 'conversation_attachments_icon_empty',
          ),
        ),
        if (newCount > 0)
          Positioned(
            right: -8,
            top: -8,
            child: Container(
              key: const Key('conversation_attachments_badge'),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              alignment: Alignment.center,
              child: Text(
                newCount > 99 ? '99+' : '$newCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
