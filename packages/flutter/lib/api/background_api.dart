import '../background/background_controller.dart';
import '../engine.dart';
import '../models/background.dart';

/// Background API: control the background service and observe background
/// action events.
class BackgroundApi {
  BackgroundApi(this._core);

  final EngineCore _core;

  NapaxiBackgroundController? get controller => _core.backgroundController;

  Stream<BackgroundActionEvent> get onAction => _core.onBackgroundAction;

  Future<void> startService() => _core.startBackgroundService();

  Future<void> stopService() => _core.stopBackgroundService();

  void updateConfig(BackgroundConfig config) {
    _core.updateBackgroundConfig(config);
  }
}
