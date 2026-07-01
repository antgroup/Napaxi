import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:napaxi/assistant_markdown.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:napaxi_flutter/napaxi_flutter.dart' as sdk;
import 'package:napaxi_flutter/advanced.dart' as sdk;
import 'package:napaxi_flutter/convenience.dart' as sdk;
import 'package:napaxi/widgets/web_preview_page.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart' as share;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umeng_common_sdk/umeng_common_sdk.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:xterm/xterm.dart';

import 'demo_client/demo_git_provider.dart';

part 'models/demo_agent.dart';
part 'app/analytics.dart';
part 'app/app.dart';
part 'app/preferences.dart';
part 'app/scenario_settings.dart';
part 'app/feedback_service.dart';
part 'app/update_service.dart';
part 'demo_client/napaxi_chat_client.dart';
part 'demo_client/demo_qq_channel_provider.dart';
part 'demo_client/cli_engine_bridge.dart';
part 'app/language_scope.dart';
part 'app/strings.dart';
part 'models/chat_models.dart';
part 'models/llm_models.dart';
part 'screens/chat_screen.dart';
part 'screens/chat_screen_channel.dart';
part 'screens/chat_screen_a2a.dart';
part 'screens/chat_attachment_widgets.dart';
part 'screens/chat_browser_widgets.dart';
part 'screens/chat_context_status_widgets.dart';
part 'screens/chat_top_bar_widgets.dart';
part 'screens/agent_manager.dart';
part 'widgets/chat_message.dart';
part 'widgets/chat_tool_trace.dart';
part 'widgets/chat_tool_read_file.dart';
part 'widgets/chat_tool_write_file.dart';
part 'panels/skills_panel.dart';
part 'panels/files_panel.dart';
part 'panels/session_history.dart';
part 'panels/scenarios_panel.dart';
part 'panels/environment_panel.dart';
part 'panels/repo_workbench_panel.dart';
part 'panels/workbench_drawer.dart';
part 'widgets/chat_input.dart';
part 'screens/config_screen.dart';
part 'terminal/terminal_backend.dart';
part 'terminal/repl_terminal_backend.dart';
part 'terminal/fake_terminal_backend.dart';
part 'terminal/pty_terminal_backend.dart';
part 'terminal/sandbox_pty_events.dart';
part 'terminal/sandbox_terminal_screen.dart';
part 'terminal/terminal_toolbar.dart';
part 'terminal/terminal_view_wrapper.dart';

@pragma('vm:entry-point')
Future<void> napaxiAutomationBackgroundMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  ui.DartPluginRegistrant.ensureInitialized();

  const backgroundChannel = MethodChannel('com.napaxi.flutter/background');
  sdk.NapaxiEngine? engine;
  try {
    final config = await _loadBackgroundAutomationConfig();
    if (config == null) {
      throw StateError('No selected model profile is available.');
    }
    engine = await sdk.NapaxiEngine.create(
      config: config,
      enablePlatformTools: true,
      backgroundConfig: NapaxiSdkChatClient._androidBackgroundConfig,
    );

    final sync = await engine.automationScheduler?.sync(
      exact: true,
      catchUpLimit: 10,
    );
    final runs = sync?.runs ?? const <sdk.AutomationRun>[];
    final failed = runs.where((run) => run.status == 'failed').toList();
    if (failed.isNotEmpty) {
      await backgroundChannel.invokeMethod<bool>('showErrorNotification', {
        'title': 'Napaxi Scheduled Task',
        'message': failed.first.error ?? 'Scheduled task failed.',
      });
    } else {
      await backgroundChannel.invokeMethod<bool>('showCompletionNotification', {
        'title': 'Napaxi Scheduled Task',
        'message': _automationRunMessage(
          runs.isEmpty ? null : runs.last,
          fallback: runs.isEmpty
              ? 'No scheduled task was due.'
              : 'Scheduled task completed.',
        ),
      });
    }
  } catch (error) {
    await backgroundChannel.invokeMethod<bool>('showErrorNotification', {
      'title': 'Napaxi Scheduled Task',
      'message': 'Scheduled task failed: $error',
    });
  } finally {
    engine?.dispose();
    await backgroundChannel.invokeMethod<bool>('stopForegroundService');
  }
}

Future<sdk.LlmConfig?> _loadBackgroundAutomationConfig() async {
  final store = sdk.NapaxiConfigStore.instance;
  final selection = await store.loadSelection();
  final selectedId = selection.selectedProfileId;
  if (selectedId != null && selectedId.trim().isNotEmpty) {
    final config = await store.resolveConfig(selectedId);
    if (config != null) return config;
  }
  final profiles = await store.loadProfiles();
  if (profiles.isEmpty) return null;
  return store.resolveConfig(profiles.first.id);
}

String _automationRunMessage(
  sdk.AutomationRun? run, {
  required String fallback,
}) {
  final summary = run?.summary?.trim();
  if (summary != null && summary.isNotEmpty) return summary;
  final error = run?.error?.trim();
  if (error != null && error.isNotEmpty) return error;
  return fallback;
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  DemoAnalytics.initialize();
  runApp(const NapaxiApp());
}
