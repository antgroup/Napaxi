import '../engine.dart';
import '../models/custom_tool.dart';

/// Tool API: register custom tool definitions and start the tool-request
/// listener on the engine.
class ToolApi {
  ToolApi(this._core);

  final EngineCore _core;

  bool updateCustomTools(List<CustomToolDef> tools) {
    return _core.updateCustomTools(tools);
  }

  void startRequestListener() {
    _core.startToolRequestListener();
  }
}
