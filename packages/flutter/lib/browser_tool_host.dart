import 'dart:convert';

import 'api/json_codec.dart';
import 'browser_controller.dart';
import 'generated/bridge/init.dart' as rust_init;
import 'models/custom_tool.dart';

/// Static catalog of the built-in browser tools and their JSON tool
/// definitions, sourced from the Rust bridge with a Dart fallback.
class BrowserToolProvider {
  BrowserToolProvider._();

  /// Capability identifier that gates the browser tool surface.
  static const capabilityId = 'napaxi.tool.browser';

  /// Recognized browser tool names, derived from [_fallbackToolDefinitions] so
  /// there is a single Dart-side list. The fallback defs themselves are pinned
  /// to the canonical core descriptors via the shared contract fixture (see
  /// test/browser_tool_contract_fixture_test.dart).
  static final Set<String> _fallbackToolNames = _fallbackToolDefinitions
      .map((tool) => tool.name)
      .toSet();

  static List<CustomToolDef>? _cachedToolDefinitions;

  /// Whether [name] is one of the recognized browser tools.
  static bool isBrowserTool(String name) {
    try {
      return rust_init.isBrowserTool(name: name) ||
          _fallbackToolNames.contains(name);
    } catch (_) {
      return _fallbackToolNames.contains(name);
    }
  }

  /// The offline fallback tool definitions, exposed for the contract-fixture
  /// drift guard only (test/browser_tool_contract_fixture_test.dart).
  /// Production reads canonical definitions from core via [getToolDefinitions];
  /// this getter must not be used as a runtime source.
  static List<CustomToolDef> get debugFallbackToolDefinitions =>
      _fallbackToolDefinitions;

  /// Returns the browser tool definitions, caching them after first load.
  static List<CustomToolDef> getToolDefinitions() {
    return _cachedToolDefinitions ??= _loadToolDefinitions();
  }

  static List<CustomToolDef> _loadToolDefinitions() {
    try {
      return decodeJsonObjectList(
        rust_init.browserToolDescriptorsJson(),
        CustomToolDef.fromJson,
      ).where((tool) => tool.name.isNotEmpty).toList(growable: false);
    } catch (_) {
      return _fallbackToolDefinitions;
    }
  }

  // Offline fallback definitions. These MUST mirror the canonical core
  // descriptors in crates/core/src/tools/browser.rs; both are pinned to the
  // shared fixture packages/api_contract/fixtures/browser/tool_descriptors.json
  // (verified by browser_tool_contract_fixture_test.dart on the Dart side and
  // descriptors_match_shared_contract_fixture on the Rust side). Do not edit
  // descriptions/schemas here without regenerating the fixture from core.
  static const _fallbackToolDefinitions = [
    CustomToolDef(
      name: 'browser_open',
      description:
          "Only open an absolute http:// or https:// URL in the persistent visible in-app browser session. Defaults to mobile browser mode, using the app WebView's normal mobile profile. Reuses the current page when the URL and browser mode already match unless force_reload is true. Never use this for file:// URLs, local filesystem paths, workspace paths, sandbox paths, generated HTML files, or files you just created; use file tools or the generated attachment instead.",
      effect: 'external',
      parameters: {
        'type': 'object',
        'properties': {
          'url': {
            'type': 'string',
            'pattern': '^https?://',
            'description':
                'Absolute http:// or https:// URL to open. Do not pass file:// URLs, local paths, workspace paths, sandbox paths, generated HTML files, or files you just created.',
          },
          'mode': {
            'type': 'string',
            'enum': ['desktop', 'mobile'],
            'description':
                'Browser rendering profile. Defaults to mobile. Use desktop only when the user asks for a desktop page or a mobile page is blocked/limited.',
          },
          'force_reload': {
            'type': 'boolean',
            'description': 'Reload even when the current URL already matches.',
          },
        },
        'required': ['url'],
      },
    ),
    CustomToolDef(
      name: 'browser_snapshot',
      description:
          'Read the current visible browser page state. Returns browser_mode, user_agent, page_state, viewport_map, page_change_token, backend_capabilities, optional screenshot metadata, and last_action_effect. Use viewport_map when DOM text is incomplete: it contains visible text blocks, clickable element positions, overlays, bbox, center points, nearby text, action hints, and diagnostics. If screenshot metadata is present and image_analyze is available, analyze the screenshot for visual understanding; otherwise use the JSON state and do not claim visual inspection.',
      effect: 'read',
      parameters: {
        'type': 'object',
        'properties': {
          'screenshot_mode': {
            'type': 'string',
            'enum': ['auto', 'never', 'always'],
            'description':
                'Optional screenshot capture preference. Defaults to auto. Screenshots are an optional visual aid; the JSON viewport_map is the non-visual fallback.',
          },
        },
      },
    ),
    CustomToolDef(
      name: 'browser_click',
      description:
          'Click an element in the current browser page. Prefer element_id from the latest browser_snapshot page_state. Legacy index, CSS selector, visible text, and accessibility label are still accepted; text/label clicks may use a visible text ancestor fallback for dynamic JavaScript components. For high-confidence viewport_map targets, click_point may be used as a coordinate fallback. The host verifies the click effect and may perform one safe recovery retry; failures include structured failure_code values such as no_effect_after_click, obscured, site_restricted, login_required, and target_unstable.',
      effect: 'external',
      parameters: {
        'type': 'object',
        'properties': {
          'element_id': {
            'type': 'string',
            'description':
                'Stable element id from browser_snapshot page_state.elements. Preferred target.',
          },
          'index': {
            'type': 'integer',
            'description':
                'Legacy element index from browser_snapshot interactive elements.',
          },
          'selector': {
            'type': 'string',
            'description': 'CSS selector for the element to click.',
          },
          'text': {
            'type': 'string',
            'description': 'Visible text contained by the element to click.',
          },
          'label': {
            'type': 'string',
            'description':
                'Accessible label, aria-label, placeholder, or title for the element to click.',
          },
          'click_point': {
            'type': 'object',
            'description':
                'High-confidence viewport coordinate fallback from viewport_map center/clickable_point. Prefer element_id when possible.',
            'properties': {
              'x': {'type': 'number'},
              'y': {'type': 'number'},
            },
            'required': ['x', 'y'],
          },
        },
      },
    ),
    CustomToolDef(
      name: 'browser_type',
      description:
          'Type text into an input or editable element in the current browser page. Prefer element_id from the latest browser_snapshot page_state.',
      effect: 'external',
      parameters: {
        'type': 'object',
        'properties': {
          'text': {
            'type': 'string',
            'description': 'Text to enter.',
          },
          'index': {
            'type': 'integer',
            'description':
                'Legacy element index from browser_snapshot interactive elements.',
          },
          'element_id': {
            'type': 'string',
            'description':
                'Stable element id from browser_snapshot page_state.elements. Preferred target.',
          },
          'selector': {
            'type': 'string',
            'description': 'CSS selector for the editable element.',
          },
          'label': {
            'type': 'string',
            'description':
                'Accessible label, aria-label, placeholder, or title for the editable element.',
          },
          'submit': {
            'type': 'boolean',
            'description':
                'Submit/press Enter after typing. Requires approval for high-risk flows.',
          },
          'clear_first': {
            'type': 'boolean',
            'description':
                'Clear existing field value before typing. Defaults to true.',
          },
        },
        'required': ['text'],
      },
    ),
    CustomToolDef(
      name: 'browser_scroll',
      description: 'Scroll the current browser page.',
      effect: 'external',
      parameters: {
        'type': 'object',
        'properties': {
          'direction': {
            'type': 'string',
            'enum': ['up', 'down', 'left', 'right'],
            'description': 'Scroll direction. Defaults to down.',
          },
          'amount': {
            'type': 'integer',
            'description':
                'Approximate scroll amount in pixels. Defaults to 700.',
          },
        },
      },
    ),
    CustomToolDef(
      name: 'browser_wait',
      description:
          'Wait for the browser page to load, settle, or contain expected text. When scroll_to_text is true, the host may scroll the text into view.',
      effect: 'read',
      parameters: {
        'type': 'object',
        'properties': {
          'milliseconds': {
            'type': 'integer',
            'description':
                'Maximum wait duration in milliseconds. Defaults to 1000.',
            'minimum': 0,
            'maximum': 30000,
          },
          'text': {
            'type': 'string',
            'description': 'Optional visible text to wait for.',
          },
          'scroll_to_text': {
            'type': 'boolean',
            'description':
                'If text is provided, scroll the first matching text into view when possible.',
          },
        },
      },
    ),
    CustomToolDef(
      name: 'browser_find_text',
      description:
          'Find visible text on the current page and scroll the first match into view.',
      effect: 'read',
      parameters: {
        'type': 'object',
        'properties': {
          'text': {
            'type': 'string',
            'description': 'Text to find and bring into view.',
          },
        },
        'required': ['text'],
      },
    ),
    CustomToolDef(
      name: 'browser_keys',
      description:
          'Send simple keyboard keys to the focused browser element. Supported keys are Enter, Escape, Tab, ArrowUp, ArrowDown, ArrowLeft, and ArrowRight.',
      effect: 'external',
      parameters: {
        'type': 'object',
        'properties': {
          'keys': {
            'type': 'string',
            'description':
                'Key name or plus-separated key sequence such as Enter, Escape, Tab, ArrowDown.',
          },
        },
        'required': ['keys'],
      },
    ),
    CustomToolDef(
      name: 'browser_back',
      description: 'Navigate the persistent browser session back if possible.',
      effect: 'external',
      parameters: {'type': 'object', 'properties': {}},
    ),
    CustomToolDef(
      name: 'browser_close',
      description:
          'Close or clear the persistent browser session. Hiding the UI does not call this tool.',
      effect: 'external',
      parameters: {
        'type': 'object',
        'properties': {
          'clear_storage': {
            'type': 'boolean',
            'description':
                'Clear browser cookies and local storage for this app WebView session.',
          },
        },
      },
    ),
  ];
}

/// Routes browser tool calls to a [NapaxiBrowserController], gating risky
/// mutating actions through an approval handler based on [mutationPolicy].
class FlutterBrowserToolHost {
  /// Creates a host bound to [controller] with an optional [approvalHandler]
  /// and a [mutationPolicy] that defaults to requiring approval.
  FlutterBrowserToolHost({
    required this.controller,
    this.approvalHandler,
    this.mutationPolicy = BrowserMutationPolicy.requireApproval,
  });

  /// Browser controller that executes the resolved tool calls.
  final NapaxiBrowserController controller;

  /// Callback consulted before running actions that require user approval.
  final McToolApprovalHandler? approvalHandler;

  /// Policy controlling whether mutating browser actions need approval.
  final BrowserMutationPolicy mutationPolicy;

  /// Whether this host can handle the tool named [toolName].
  bool canHandle(String toolName) =>
      BrowserToolProvider.isBrowserTool(toolName);

  /// Executes [toolName] with [paramsJson], requesting approval first when the
  /// mutation policy flags the action as risky.
  Future<String> execute(String toolName, String paramsJson) async {
    final approvalReason = _approvalReason(toolName, paramsJson);
    if (approvalReason != null) {
      final approved = await _requestApproval(
        toolName,
        approvalReason,
        paramsJson,
      );
      if (!approved) {
        return jsonEncode({
          'success': false,
          'action': toolName,
          'blocked_or_approval_reason': 'Browser action requires user approval',
        });
      }
    }
    return controller.executeTool(toolName, paramsJson);
  }

  String? _approvalReason(String toolName, String paramsJson) {
    if (mutationPolicy == BrowserMutationPolicy.allowAll) return null;
    final params = _decodeParams(paramsJson);
    if (toolName == 'browser_type' && params['submit'] == true) {
      return 'Approve browser typing and submit';
    }
    if (toolName != 'browser_click') return null;
    if (params['click_point'] != null && params['element_id'] == null) {
      return 'Approve coordinate browser click';
    }
    final target = [
      params['text'],
      params['label'],
      params['selector'],
      _elementRiskText(params['element_id']),
    ].whereType<String>().join(' ').toLowerCase();
    const riskyTerms = [
      'pay',
      'purchase',
      'buy',
      'order',
      'delete',
      'remove',
      'submit',
      'send',
      'post',
      'confirm',
      'checkout',
      'login',
      'sign in',
    ];
    if (riskyTerms.any(target.contains)) {
      return 'Approve high-risk browser click';
    }
    return null;
  }

  String? _elementRiskText(Object? elementId) {
    if (elementId is! String || elementId.trim().isEmpty) return null;
    final elements = controller.latestSnapshot?.elements ?? const [];
    for (final element in elements) {
      if (element['element_id'] != elementId) continue;
      return [
        element['text'],
        element['label'],
        element['risk_hint'],
      ].whereType<String>().join(' ');
    }
    return null;
  }

  Future<bool> _requestApproval(
    String toolName,
    String description,
    String paramsJson,
  ) async {
    final handler = approvalHandler;
    if (handler == null) return false;
    final response = await handler(
      McToolApprovalRequest(
        requestId: BigInt.from(DateTime.now().microsecondsSinceEpoch),
        toolName: toolName,
        description: description,
        parametersJson: paramsJson,
        allowAlways: false,
      ),
    );
    return response.approved;
  }

  Map<String, dynamic> _decodeParams(String paramsJson) {
    if (paramsJson.trim().isEmpty) return {};
    final decoded = jsonDecode(paramsJson);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
  }
}
