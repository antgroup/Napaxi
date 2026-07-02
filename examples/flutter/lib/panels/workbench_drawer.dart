part of '../main.dart';

/// Right-side dev-workbench drawer content for the `mobile_development` scenario.
///
/// Slides in from the right edge over the chat screen (the slide animation and
/// backdrop live on `_ChatScreenState`, mirroring the session-history drawer).
/// The body embeds [`_SourceControlWorkbench`]: a tabbed source-control panel
/// (recursive Files tree with git status badges + a Changes view with stage /
/// unstage / discard / commit). The scenarios client is reused both to resolve
/// the scenario UI contribution and to back the workbench, matching how the
/// session-history menu opens the full-screen [`_RepoWorkbenchBrowser`].
class _WorkbenchRightDrawerPanel extends StatefulWidget {
  const _WorkbenchRightDrawerPanel({
    required this.agentId,
    required this.activeScenarioId,
    required this.createScenariosClientFuture,
    required this.onClose,
  });

  final String agentId;
  final String activeScenarioId;
  final Future<NapaxiChatClient> Function() createScenariosClientFuture;
  final VoidCallback onClose;

  @override
  State<_WorkbenchRightDrawerPanel> createState() =>
      _WorkbenchRightDrawerPanelState();
}

class _WorkbenchRightDrawerPanelState extends State<_WorkbenchRightDrawerPanel> {
  late final Future<NapaxiChatClient> _clientFuture;
  late final Future<sdk.NapaxiScenarioUiContribution?> _contributionFuture;
  sdk.NapaxiScenarioUiContribution? _fallbackContribution;

  @override
  void initState() {
    super.initState();
    _clientFuture = widget.createScenariosClientFuture();
    _fallbackContribution =
        _normalizeDemoScenarioId(widget.activeScenarioId) ==
            _mobileDevelopmentScenarioId
        ? _fallbackRepoWorkbenchContribution
        : null;
    // Reuse the already-resolved client future so contribution lookup and the
    // embedded workbench share one scenarios client.
    _contributionFuture = loadRepoWorkbenchContribution(
      createScenariosClientFuture: () => _clientFuture,
      activeScenarioId: widget.activeScenarioId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _configSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WorkbenchDrawerHeader(onClose: widget.onClose),
          const Divider(height: 1, thickness: 1, color: _configBorderFaint),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return FutureBuilder<NapaxiChatClient>(
      future: _clientFuture,
      builder: (context, clientSnapshot) {
        if (clientSnapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (clientSnapshot.hasError || clientSnapshot.data == null) {
          return _WorkbenchDrawerMessage(
            icon: Icons.error_outline_rounded,
            message: _repoWorkbenchLoadFailed(context, clientSnapshot.error),
          );
        }
        final client = clientSnapshot.data!;
        return FutureBuilder<sdk.NapaxiScenarioUiContribution?>(
          future: _contributionFuture,
          builder: (context, contributionSnapshot) {
            final contribution =
                contributionSnapshot.data ?? _fallbackContribution;
            if (contribution == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return _SourceControlWorkbench(
              client: client,
              agentId: widget.agentId,
              contribution: contribution,
            );
          },
        );
      },
    );
  }
}

class _WorkbenchDrawerHeader extends StatelessWidget {
  const _WorkbenchDrawerHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Workbench',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _configTextPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox.square(
              dimension: 40,
              child: IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonLabel,
                padding: EdgeInsets.zero,
                onPressed: onClose,
                icon: const Icon(
                  Icons.close_rounded,
                  color: _configTextSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkbenchDrawerMessage extends StatelessWidget {
  const _WorkbenchDrawerMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: _configTextSecondary),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _configTextSecondary, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
