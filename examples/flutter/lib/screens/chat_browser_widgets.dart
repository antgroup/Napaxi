part of '../main.dart';

class _BrowserMobileDock extends StatelessWidget {
  const _BrowserMobileDock({
    required this.controller,
    required this.onExpand,
    required this.onClose,
  });

  final sdk.NapaxiBrowserController? controller;
  final VoidCallback onExpand;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final browser = controller;
    if (browser == null) return const SizedBox.shrink();

    final media = MediaQuery.of(context);
    const collapsedHeight = 72.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      height: collapsedHeight,
      padding: EdgeInsets.only(
        left: 0,
        right: 0,
        bottom: media.padding.bottom > 0 ? 0 : 2,
      ),
      decoration: const BoxDecoration(color: Colors.black),
      child: _BrowserMiniBar(
        controller: browser,
        onExpand: onExpand,
        onClose: onClose,
      ),
    );
  }
}

class _BrowserFullscreenPanel extends StatelessWidget {
  const _BrowserFullscreenPanel({
    required this.controller,
    required this.onMinimize,
  });

  final sdk.NapaxiBrowserController? controller;
  final VoidCallback onMinimize;

  @override
  Widget build(BuildContext context) {
    final browser = controller;
    if (browser == null) return const SizedBox.shrink();

    return Material(
      color: Colors.black,
      child: SafeArea(
        bottom: false,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: Material(
            color: Colors.white,
            child: AnimatedBuilder(
              animation: browser,
              builder: (context, _) {
                return Column(
                  children: [
                    _BrowserFullscreenHeader(
                      controller: browser,
                      onMinimize: onMinimize,
                    ),
                    if (browser.loading)
                      LinearProgressIndicator(
                        minHeight: 2,
                        value: browser.progress <= 0 || browser.progress >= 100
                            ? null
                            : browser.progress / 100,
                      )
                    else
                      const SizedBox(height: 2),
                    if (browser.blockedNavigation != null)
                      MaterialBanner(
                        content: Text(
                          'Blocked unsupported link: ${browser.blockedNavigation}',
                        ),
                        actions: [
                          TextButton(
                            onPressed: onMinimize,
                            child: Text(
                              MaterialLocalizations.of(
                                context,
                              ).closeButtonLabel,
                            ),
                          ),
                        ],
                      ),
                    Expanded(
                      child: sdk.NapaxiBrowserSurface(
                        controller: browser,
                        placeholder: const _BrowserEmptyState(),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _BrowserFullscreenHeader extends StatelessWidget {
  const _BrowserFullscreenHeader({
    required this.controller,
    required this.onMinimize,
  });

  final sdk.NapaxiBrowserController controller;
  final VoidCallback onMinimize;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final label = _browserDockTitle(
      controller.title?.trim(),
      controller.url?.trim(),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) > 650) onMinimize();
      },
      onVerticalDragUpdate: (details) {
        if ((details.primaryDelta ?? 0) > 8) onMinimize();
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
        child: Row(
          children: [
            _BrowserCircleButton(
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              icon: Icons.close_rounded,
              onPressed: onMinimize,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Container(
                height: 58,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F8F8),
                  borderRadius: BorderRadius.circular(29),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      _browserModeLabel(strings, controller.browserMode),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            _BrowserMenuButton(controller: controller),
          ],
        ),
      ),
    );
  }
}

class _BrowserMenuButton extends StatelessWidget {
  const _BrowserMenuButton({required this.controller});

  final sdk.NapaxiBrowserController controller;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return PopupMenuButton<String>(
      tooltip: strings.browserOptionsTooltip,
      color: Colors.white,
      elevation: 12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: (value) {
        switch (value) {
          case 'reload':
            unawaited(controller.reload());
          case 'debug':
            unawaited(
              controller.setDebugHighlightEnabled(
                !controller.debugHighlightEnabled,
              ),
            );
          case 'clear':
            unawaited(controller.clearSession());
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(value: 'reload', child: Text(strings.browserReload)),
        CheckedPopupMenuItem(
          value: 'debug',
          checked: controller.debugHighlightEnabled,
          child: Text(strings.browserDebugHighlight),
        ),
        PopupMenuItem(value: 'clear', child: Text(strings.browserClearSession)),
      ],
      child: const Material(
        color: Color(0xFFF8F8F8),
        shape: CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 60,
          height: 60,
          child: Icon(Icons.more_horiz_rounded, color: Colors.black, size: 30),
        ),
      ),
    );
  }
}

class _BrowserCircleButton extends StatelessWidget {
  const _BrowserCircleButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF8F8F8),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
        color: Colors.black,
        iconSize: 30,
        padding: const EdgeInsets.all(14),
        constraints: const BoxConstraints.tightFor(width: 60, height: 60),
      ),
    );
  }
}

class _BrowserMiniBar extends StatelessWidget {
  const _BrowserMiniBar({
    required this.controller,
    required this.onExpand,
    required this.onClose,
  });

  final sdk.NapaxiBrowserController controller;
  final VoidCallback onExpand;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragUpdate: (details) {
        if ((details.primaryDelta ?? 0) < -8) onExpand();
      },
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) < 0) onExpand();
      },
      child: Material(
        elevation: 0,
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final title = controller.title?.trim();
            final url = controller.url?.trim();
            final label = _browserDockTitle(title, url);
            final strings = AppStrings.of(context);
            return InkWell(
              onTap: onExpand,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: MaterialLocalizations.of(
                            context,
                          ).closeButtonTooltip,
                          onPressed: onClose,
                          icon: const Icon(Icons.close_rounded),
                          color: const Color(0xFF111827),
                          visualDensity: VisualDensity.compact,
                        ),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFF111827),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                _browserModeLabel(
                                  strings,
                                  controller.browserMode,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFF6B7280),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Expand',
                          onPressed: onExpand,
                          icon: const Icon(Icons.keyboard_arrow_up_rounded),
                          color: const Color(0xFF111827),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Container(
                      width: 96,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5E7EB),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _BrowserSidePanel extends StatelessWidget {
  const _BrowserSidePanel({required this.controller, required this.onClose});

  final sdk.NapaxiBrowserController? controller;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final browser = controller;
    if (browser == null) return const SizedBox.shrink();
    return Material(
      elevation: 14,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(12),
      child: _BrowserPanelFrame(controller: browser, onClose: onClose),
    );
  }
}

class _BrowserPanelFrame extends StatelessWidget {
  const _BrowserPanelFrame({required this.controller, required this.onClose});

  final sdk.NapaxiBrowserController controller;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('browser_panel'),
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final url = controller.url?.trim();
          final title = controller.title?.trim();
          final strings = AppStrings.of(context);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: Row(
                  children: [
                    const Icon(Icons.public_rounded, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title?.isNotEmpty == true ? title! : 'Browser',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF171717),
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            [
                              _browserModeLabel(
                                strings,
                                controller.browserMode,
                              ),
                              url?.isNotEmpty == true ? url! : 'No page open',
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF6B7280),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Back',
                      onPressed: controller.hasPage
                          ? () => unawaited(controller.goBack())
                          : null,
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    IconButton(
                      tooltip: 'Reload',
                      onPressed: controller.hasPage
                          ? () => unawaited(controller.reload())
                          : null,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                    IconButton(
                      tooltip: 'Clear session',
                      onPressed: () => unawaited(controller.clearSession()),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                    IconButton(
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).closeButtonTooltip,
                      onPressed: onClose,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              if (controller.loading)
                LinearProgressIndicator(
                  value: controller.progress <= 0 || controller.progress >= 100
                      ? null
                      : controller.progress / 100,
                )
              else
                const Divider(height: 1),
              if (controller.blockedNavigation != null)
                MaterialBanner(
                  content: Text(
                    'Blocked unsupported link: ${controller.blockedNavigation}',
                  ),
                  actions: [
                    TextButton(onPressed: onClose, child: const Text('Close')),
                  ],
                ),
              Expanded(
                child: sdk.NapaxiBrowserSurface(
                  controller: controller,
                  placeholder: const _BrowserEmptyState(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BrowserEmptyState extends StatelessWidget {
  const _BrowserEmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.public_rounded, color: Color(0xFF9CA3AF), size: 34),
            SizedBox(height: 12),
            Text(
              'Ask Napaxi to open a website',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF171717),
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'This panel keeps the same browser session while Napaxi opens, reads, clicks, and waits.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF6B7280),
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
