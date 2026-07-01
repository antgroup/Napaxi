import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Whether mutating browser actions require user approval before running.
enum BrowserMutationPolicy {
  /// Risky/mutating actions must be approved before execution.
  requireApproval,

  /// All actions run without prompting for approval.
  allowAll,
}

/// Rendering profile used when loading a page in the embedded browser.
enum BrowserViewportMode {
  /// Emulate a desktop viewport and user agent.
  desktop,

  /// Use the default mobile viewport and user agent.
  mobile,
}

/// When a page screenshot should be captured alongside a snapshot.
enum BrowserScreenshotMode {
  /// Capture only when appropriate (e.g. on explicit snapshots).
  auto,

  /// Never capture a screenshot.
  never,

  /// Always capture a screenshot when supported.
  always,
}

/// Feature flags describing what a [NapaxiBrowserBackend] implementation supports.
class BrowserBackendCapabilities {
  /// Creates a capability set; all flags default to the conservative baseline.
  const BrowserBackendCapabilities({
    this.supportsScreenshot = false,
    this.supportsCoordinateClick = true,
    this.supportsEarlyScriptInjection = false,
    this.supportsCdpSelectorMap = false,
  });

  /// Whether the backend can capture page screenshots.
  final bool supportsScreenshot;

  /// Whether the backend supports clicking at viewport coordinates.
  final bool supportsCoordinateClick;

  /// Whether scripts can be injected before page load.
  final bool supportsEarlyScriptInjection;

  /// Whether the backend exposes a CDP-based selector map.
  final bool supportsCdpSelectorMap;

  /// Serializes the capability flags to a JSON map.
  Map<String, dynamic> toJson() => {
        'supports_screenshot': supportsScreenshot,
        'supports_coordinate_click': supportsCoordinateClick,
        'supports_early_script_injection': supportsEarlyScriptInjection,
        'supports_cdp_selector_map': supportsCdpSelectorMap,
      };
}

/// Metadata for a screenshot captured from the browser, stored in the sandbox.
class NapaxiBrowserScreenshot {
  /// Creates screenshot metadata for an image written to [sandboxPath].
  const NapaxiBrowserScreenshot({
    required this.sandboxPath,
    required this.width,
    required this.height,
    this.mimeType = 'image/png',
  });

  /// Sandbox-relative path of the captured image file.
  final String sandboxPath;

  /// Image width in pixels.
  final int width;

  /// Image height in pixels.
  final int height;

  /// MIME type of the captured image (defaults to PNG).
  final String mimeType;

  /// Serializes the screenshot metadata to a JSON map.
  Map<String, dynamic> toJson() => {
        'sandbox_path': sandboxPath,
        'mime_type': mimeType,
        'width': width,
        'height': height,
      };
}

/// Desktop user agent string applied when running in desktop viewport mode.
const String napaxiDesktopUserAgent =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

/// Immutable observation of the browser page at a point in time, including
/// extracted text, interactive elements, viewport map, and optional screenshot.
class NapaxiBrowserSnapshot {
  /// Creates a snapshot from already-collected page observation values.
  const NapaxiBrowserSnapshot({
    required this.url,
    required this.title,
    required this.loading,
    required this.browserMode,
    required this.userAgent,
    required this.text,
    required this.elements,
    required this.pageState,
    required this.viewportMap,
    required this.pageChangeToken,
    required this.lastActionEffect,
    required this.backendCapabilities,
    this.screenshot,
  });

  /// Current page URL.
  final String url;

  /// Current page title.
  final String title;

  /// Whether the page is still loading.
  final bool loading;

  /// Viewport rendering mode the snapshot was taken in.
  final BrowserViewportMode browserMode;

  /// Effective user agent for the current mode, if known.
  final String? userAgent;

  /// Truncated visible page text.
  final String text;

  /// Interactive elements detected on the page, each as a JSON-like map.
  final List<Map<String, dynamic>> elements;

  /// Full structured page state (url, title, scroll, elements, viewport, etc.).
  final Map<String, dynamic> pageState;

  /// Map of viewport-visible content used for coordinate-based reasoning.
  final Map<String, dynamic> viewportMap;

  /// Stable hash of page content used to detect whether an action changed it.
  final String pageChangeToken;

  /// Summary of the effect of the most recent action, if any.
  final Map<String, dynamic>? lastActionEffect;

  /// Capabilities of the backend that produced this snapshot.
  final BrowserBackendCapabilities backendCapabilities;

  /// Captured screenshot metadata, when one was taken.
  final NapaxiBrowserScreenshot? screenshot;

  /// Serializes the snapshot to the JSON map returned to tool callers.
  Map<String, dynamic> toJson() => {
        'url': url,
        'title': title,
        'loading': loading,
        'browser_mode': browserMode.name,
        if (userAgent != null) 'user_agent': userAgent,
        'text': text,
        'elements': elements,
        'page_state': pageState,
        'viewport_map': viewportMap,
        'page_change_token': pageChangeToken,
        'backend_capabilities': backendCapabilities.toJson(),
        'screenshot_available': screenshot != null,
        if (screenshot != null) 'screenshot': screenshot!.toJson(),
        if (lastActionEffect != null) 'last_action_effect': lastActionEffect,
      };
}

/// Abstract embedded-browser backend the controller drives.
///
/// Implementations wrap a concrete web view (e.g. WebView, CDP) and expose
/// navigation, scripting, and capture primitives.
abstract class NapaxiBrowserBackend {
  /// Builds the platform web view widget for this backend.
  Widget buildWidget();

  /// Features this backend supports; defaults to the conservative baseline.
  BrowserBackendCapabilities get capabilities =>
      const BrowserBackendCapabilities();

  /// Whether the backend reports the page as loading.
  bool get loading => false;

  /// Load progress in the range 0..100, or 0 if unknown.
  int get progress => 0;

  /// Reason the last navigation was blocked, if any.
  String? get blockedNavigation => null;

  /// Navigates the web view to [url].
  Future<void> loadUrl(String url);

  /// Overrides the user agent, or restores the default when [userAgent] is null.
  Future<void> setUserAgent(String? userAgent) async {}

  /// Captures a screenshot per [mode], or null if unsupported.
  Future<NapaxiBrowserScreenshot?> captureScreenshot(
    BrowserScreenshotMode mode,
  ) async =>
      null;

  /// Reloads the current page.
  Future<void> reload();

  /// Returns the current page URL, if available.
  Future<String?> currentUrl();

  /// Returns the current page title, if available.
  Future<String?> title();

  /// Whether the web view has back history to navigate to.
  Future<bool> canGoBack();

  /// Navigates back one entry in history.
  Future<void> goBack();

  /// Runs [javaScript] without returning a result.
  Future<void> runJavaScript(String javaScript);

  /// Runs [javaScript] and returns its evaluated result.
  Future<Object?> runJavaScriptReturningResult(String javaScript);

  /// Clears the web view's HTTP/resource cache.
  Future<void> clearCache();

  /// Clears local storage for the current origin.
  Future<void> clearLocalStorage();
}

/// Drives an embedded browser session: serializes tool calls onto a queue,
/// tracks page state, and exposes it to the UI as a [ChangeNotifier].
class NapaxiBrowserController extends ChangeNotifier {
  /// Creates a controller that drives the given [backend].
  NapaxiBrowserController({required NapaxiBrowserBackend backend})
      : _backend = backend;

  final NapaxiBrowserBackend _backend;
  Future<void> _queue = Future<void>.value();
  NapaxiBrowserSnapshot? _latestSnapshot;
  Map<String, Map<String, dynamic>> _latestElementById = {};
  String? _url;
  String? _title;
  String? _blockedNavigation;
  Map<String, dynamic>? _lastActionEffect;
  String? _lastPageChangeToken;
  BrowserViewportMode _browserMode = BrowserViewportMode.mobile;
  BrowserViewportMode? _appliedBrowserMode;
  bool _loading = false;
  int _progress = 0;
  bool _hasPage = false;
  bool _debugHighlightEnabled = false;

  /// Current page URL, if a page is loaded.
  String? get url => _url;

  /// Current page title, if known.
  String? get title => _title;

  /// Reason the most recent navigation was blocked, if any.
  String? get blockedNavigation =>
      _backend.blockedNavigation ?? _blockedNavigation;

  /// Whether the page (backend or controller) is currently loading.
  bool get loading => _backend.loading || _loading;

  /// Load progress in the range 0..100.
  int get progress => _backend.progress > 0 ? _backend.progress : _progress;

  /// Whether a page is currently open in the session.
  bool get hasPage => _hasPage;

  /// Whether interactive elements are visually highlighted for debugging.
  bool get debugHighlightEnabled => _debugHighlightEnabled;

  /// Active viewport rendering mode.
  BrowserViewportMode get browserMode => _browserMode;

  /// Effective user agent for the active mode, if overridden.
  String? get userAgent => _userAgentForMode(_browserMode);

  /// Page-change token from the latest snapshot, used to detect mutations.
  String? get pageChangeToken => _lastPageChangeToken;

  /// Most recently captured page snapshot, if any.
  NapaxiBrowserSnapshot? get latestSnapshot => _latestSnapshot;

  /// Builds the backend's web view widget.
  Widget buildWebView() => _backend.buildWidget();

  /// Notifies listeners that the backend's state changed externally.
  void notifyBackendStateChanged() {
    notifyListeners();
  }

  /// Runs the browser tool [toolName] with JSON [paramsJson], serialized onto
  /// the action queue, and returns a JSON-encoded result.
  Future<String> executeTool(String toolName, String paramsJson) async {
    final params = _decodeParams(paramsJson);
    return _enqueue(() async {
      try {
        final result = switch (toolName) {
          'browser_open' => await _open(params),
          'browser_snapshot' => await _snapshotResult(
              'snapshot',
              params: params,
            ),
          'browser_click' => await _click(params),
          'browser_type' => await _type(params),
          'browser_scroll' => await _scroll(params),
          'browser_wait' => await _wait(params),
          'browser_find_text' => await _findText(params),
          'browser_keys' => await _keys(params),
          'browser_back' => await _back(),
          'browser_close' => await _close(params),
          _ => _error('unknown', 'Unknown browser tool: $toolName'),
        };
        return jsonEncode(result);
      } catch (error) {
        return jsonEncode(_error(toolName, error.toString()));
      }
    });
  }

  /// Reloads the current page, if one is open.
  Future<void> reload() => _enqueueVoid(() async {
        if (!_hasPage) return;
        await _backend.reload();
        await _settle();
      });

  /// Navigates back one history entry, if possible.
  Future<void> goBack() => _enqueueVoid(() async {
        if (!await _backend.canGoBack()) return;
        await _backend.goBack();
        await _settle();
      });

  /// Clears cache and local storage, blanks the page, and resets all state.
  Future<void> clearSession() => _enqueueVoid(() async {
        await _backend.clearCache();
        await _backend.clearLocalStorage();
        await _backend.loadUrl('about:blank');
        _latestSnapshot = null;
        _latestElementById = {};
        _url = null;
        _title = null;
        _blockedNavigation = null;
        _lastActionEffect = null;
        _lastPageChangeToken = null;
        _hasPage = false;
        _loading = false;
        _progress = 0;
        notifyListeners();
      });

  /// Toggles the visual highlight overlay on detected interactive elements.
  Future<void> setDebugHighlightEnabled(bool enabled) => _enqueueVoid(() async {
        _debugHighlightEnabled = enabled;
        if (_hasPage) {
          await _safeJs(_debugHighlightScript(enabled));
        }
        notifyListeners();
      });

  Future<T> _enqueue<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    _queue = _queue.then((_) async {
      if (completer.isCompleted) return;
      try {
        completer.complete(await task());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> _enqueueVoid(Future<void> Function() task) => _enqueue(task);

  Map<String, dynamic> _decodeParams(String paramsJson) {
    if (paramsJson.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(paramsJson);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
  }

  Future<Map<String, dynamic>> _open(Map<String, dynamic> params) async {
    final url = (params['url'] as String? ?? '').trim();
    if (url.isEmpty) return _error('open', 'browser_open requires url');
    final requestedMode = _parseBrowserMode(params['mode']);
    if (requestedMode == null) {
      return _error(
        'open',
        'browser_open mode must be "desktop" or "mobile".',
        failureCode: 'invalid_browser_mode',
      );
    }
    final uri = Uri.tryParse(url);
    if (_looksLikeLocalFileTarget(url, uri)) {
      return _error(
        'open',
        'browser_open only supports HTTP/HTTPS URLs. Local files, workspace paths, sandbox paths, file:// URLs, generated HTML files, and files you just created are not supported. Do not retry browser_open for this target; use file reading tools or the generated attachment instead.',
        failureCode: 'local_file_not_supported',
      );
    }
    if (uri == null || uri.scheme.isEmpty) {
      return _error(
        'open',
        'browser_open requires an absolute HTTP or HTTPS URL.',
        failureCode: 'invalid_url',
      );
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return _error(
        'open',
        'browser_open only supports http and https URLs.',
        failureCode: 'unsupported_scheme',
      );
    }

    final current = await _backend.currentUrl();
    final forceReload = params['force_reload'] == true;
    final modeChanged =
        requestedMode != _browserMode || _appliedBrowserMode != requestedMode;
    if (modeChanged) {
      _latestSnapshot = null;
      _latestElementById = {};
    }
    await _applyBrowserMode(requestedMode);
    if (forceReload || modeChanged || !_sameUrl(current, url)) {
      _loading = true;
      _hasPage = true;
      _url = url;
      _blockedNavigation = null;
      notifyListeners();
      await _backend.loadUrl(url);
      await _settle();
    }
    return _snapshotResult('open');
  }

  Future<Map<String, dynamic>> _click(Map<String, dynamic> params) async {
    if (!_hasPage) return _error('click', 'browser session is not open');
    final before = await _rawObservationMap();
    final beforeToken = _pageChangeTokenFrom(
      _pageStateFromSnapshotMap(before),
      before,
    );
    final resolvedParams = _paramsWithElementFingerprint(params);
    final js = _targetedScript(resolvedParams, 'click');
    final raw = await _backend.runJavaScriptReturningResult(js);
    final result = _jsonFromJs(raw);
    if (result['success'] != true) {
      return _mergeResult('click', result);
    }
    await _settle();
    final after = await _rawObservationMap();
    final afterState = _pageStateFromSnapshotMap(after);
    final afterToken = _pageChangeTokenFrom(afterState, after);
    final effect = _actionEffect(
      action: 'click',
      beforeToken: beforeToken,
      afterToken: afterToken,
      before: before,
      after: after,
      result: result,
      recovered: false,
    );
    _lastActionEffect = effect;
    if (!_effectHasMeaningfulChange(effect)) {
      final siteSignal = effect['site_signal'];
      if (siteSignal is String && siteSignal.isNotEmpty) {
        return _mergeResult(
          'click',
          {
            'success': false,
            'failure_code': siteSignal,
            'error':
                'click did not change the page and the page indicates $siteSignal',
            'target': result['target'],
            'hit_test': result['hit_test'],
            'last_action_effect': effect,
          },
        );
      }
      final recovery = await _recoverClick(resolvedParams, beforeToken);
      if (recovery != null && recovery['success'] == true) {
        return _snapshotResult('click');
      }
      if (recovery != null) {
        return _mergeResult(
          'click',
          {
            ...recovery,
            'failure_code': recovery['failure_code'] ?? 'no_effect_after_click',
            'error': recovery['error'] ??
                'click completed but did not produce a detectable page change',
            'last_action_effect': _lastActionEffect,
          },
        );
      }
    }
    return _snapshotResult('click');
  }

  Future<Map<String, dynamic>> _type(Map<String, dynamic> params) async {
    if (!_hasPage) return _error('type', 'browser session is not open');
    final text = params['text'] as String? ?? '';
    final resolvedParams = _paramsWithElementFingerprint(params);
    final js = _targetedScript(
      resolvedParams,
      'type',
      text: text,
      submit: params['submit'] == true,
      clearFirst: params['clear_first'] != false,
    );
    final raw = await _backend.runJavaScriptReturningResult(js);
    final result = _jsonFromJs(raw);
    if (result['success'] != true) {
      return _mergeResult('type', result);
    }
    await _settle();
    return _snapshotResult('type');
  }

  Future<Map<String, dynamic>> _scroll(Map<String, dynamic> params) async {
    if (!_hasPage) return _error('scroll', 'browser session is not open');
    final direction = (params['direction'] as String? ?? 'down').toLowerCase();
    final amount = (params['amount'] as num?)?.toInt() ?? 700;
    final x = switch (direction) {
      'left' => -amount,
      'right' => amount,
      _ => 0,
    };
    final y = switch (direction) {
      'up' => -amount,
      'down' => amount,
      _ => 0,
    };
    await _backend.runJavaScript('window.scrollBy($x, $y);');
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return _snapshotResult('scroll');
  }

  Future<Map<String, dynamic>> _wait(Map<String, dynamic> params) async {
    final text = (params['text'] as String? ?? '').trim();
    final milliseconds = math.min(
        math.max((params['milliseconds'] as num?)?.toInt() ?? 1000, 0), 30000);
    if (text.isEmpty) {
      await Future<void>.delayed(Duration(milliseconds: milliseconds));
    } else {
      await _waitForText(text, Duration(milliseconds: milliseconds));
      if (params['scroll_to_text'] == true) {
        await _scrollTextIntoView(text);
      }
    }
    return _snapshotResult('wait');
  }

  Future<Map<String, dynamic>> _findText(Map<String, dynamic> params) async {
    if (!_hasPage) return _error('find_text', 'browser session is not open');
    final text = (params['text'] as String? ?? '').trim();
    if (text.isEmpty) {
      return _error('find_text', 'browser_find_text requires text');
    }
    final result = _jsonFromJs(await _safeJs(_findTextScript(text)));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (result['success'] != true) return _mergeResult('find_text', result);
    return _snapshotResult('find_text');
  }

  Future<Map<String, dynamic>> _keys(Map<String, dynamic> params) async {
    if (!_hasPage) return _error('keys', 'browser session is not open');
    final keys = (params['keys'] as String? ?? '').trim();
    if (keys.isEmpty) return _error('keys', 'browser_keys requires keys');
    final result = _jsonFromJs(await _safeJs(_keysScript(keys)));
    if (result['success'] != true) return _mergeResult('keys', result);
    await _settle();
    return _snapshotResult('keys');
  }

  Future<Map<String, dynamic>> _back() async {
    if (!await _backend.canGoBack()) {
      return _mergeResult(
          'back', {'success': false, 'error': 'no back history'});
    }
    await _backend.goBack();
    await _settle();
    return _snapshotResult('back');
  }

  Future<Map<String, dynamic>> _close(Map<String, dynamic> params) async {
    if (params['clear_storage'] == true) {
      await _backend.clearCache();
      await _backend.clearLocalStorage();
    }
    await _backend.loadUrl('about:blank');
    _latestSnapshot = null;
    _latestElementById = {};
    _url = null;
    _title = null;
    _blockedNavigation = null;
    _lastActionEffect = null;
    _lastPageChangeToken = null;
    _hasPage = false;
    _loading = false;
    _progress = 0;
    notifyListeners();
    return {'success': true, 'action': 'close', 'closed': true};
  }

  Future<Map<String, dynamic>> _snapshotResult(
    String action, {
    Map<String, dynamic> params = const {},
  }) async {
    final screenshotMode = _parseScreenshotMode(params['screenshot_mode']);
    if (screenshotMode == null) {
      return _error(
        action,
        'browser_snapshot screenshot_mode must be "auto", "never", or "always".',
        failureCode: 'invalid_screenshot_mode',
      );
    }
    final currentUrl = await _backend.currentUrl();
    final currentTitle = await _backend.title();
    _url = currentUrl ?? _url;
    _title = currentTitle ?? _title;

    if (_hasPage) {
      await _safeJs(_listenerRecorderScript);
    }
    final raw = _hasPage ? await _safeJs(_snapshotScript(_browserMode)) : null;
    if (_hasPage && _debugHighlightEnabled) {
      await _safeJs(_debugHighlightScript(true));
    }
    final map = raw == null ? <String, dynamic>{} : _jsonFromJs(raw);
    final pageState = _pageStateFromSnapshotMap(map);
    final viewportMap = _mapFrom(pageState['viewport_map']) ??
        _mapFrom(map['viewport_map']) ??
        <String, dynamic>{};
    final elements = _elementList(pageState['elements']);
    final observedUserAgent = (map['user_agent'] as String?) ??
        (pageState['user_agent'] as String?) ??
        _userAgentForMode(_browserMode);
    final pageChangeToken = _pageChangeTokenFrom(pageState, map);
    final screenshot = await _maybeCaptureScreenshot(screenshotMode, action);
    _latestElementById = {
      for (final element in elements)
        if (element['element_id'] is String)
          element['element_id'] as String: element,
    };
    _lastPageChangeToken = pageChangeToken;
    final snapshot = NapaxiBrowserSnapshot(
      url: (map['url'] as String?) ?? _url ?? '',
      title: (map['title'] as String?) ?? _title ?? '',
      loading: _loading,
      browserMode: _browserMode,
      userAgent: observedUserAgent,
      text: _truncate((map['text'] as String?) ?? '', 6000),
      elements: elements,
      pageState: pageState,
      viewportMap: viewportMap,
      pageChangeToken: pageChangeToken,
      lastActionEffect: _lastActionEffect,
      backendCapabilities: _backend.capabilities,
      screenshot: screenshot,
    );
    _latestSnapshot = snapshot;
    _hasPage = snapshot.url.isNotEmpty || _hasPage;
    notifyListeners();
    return {
      'success': true,
      'action': action,
      ...snapshot.toJson(),
      if (_blockedNavigation != null)
        'blocked_or_approval_reason':
            'Blocked unsupported navigation: $_blockedNavigation',
    };
  }

  Map<String, dynamic> _mergeResult(
      String action, Map<String, dynamic> result) {
    return {
      'success': result['success'] == true,
      'action': action,
      if (result['failure_code'] != null)
        'failure_code': result['failure_code'],
      if (result['error'] != null)
        'blocked_or_approval_reason': result['error'],
      if (result['candidates'] != null) 'candidates': result['candidates'],
      if (result['text_candidates'] != null)
        'text_candidates': result['text_candidates'],
      if (result['target'] != null) 'target': result['target'],
      if (result['hit_test'] != null) 'hit_test': result['hit_test'],
      if (result['last_action_effect'] != null)
        'last_action_effect': result['last_action_effect'],
      if (result['next_step'] != null) 'next_step': result['next_step'],
      if (_url != null) 'url': _url,
      if (_title != null) 'title': _title,
      'browser_mode': _browserMode.name,
      if (_userAgentForMode(_browserMode) != null)
        'user_agent': _userAgentForMode(_browserMode),
      'loading': _loading,
    };
  }

  Map<String, dynamic> _error(
    String action,
    String message, {
    String? failureCode,
  }) =>
      {
        'success': false,
        'action': action,
        if (failureCode != null) 'failure_code': failureCode,
        'blocked_or_approval_reason': message,
        'error': message,
        'browser_mode': _browserMode.name,
        if (_userAgentForMode(_browserMode) != null)
          'user_agent': _userAgentForMode(_browserMode),
        if (_url != null) 'url': _url,
        if (_title != null) 'title': _title,
        'loading': _loading,
      };

  Future<Map<String, dynamic>> _rawObservationMap() async {
    if (!_hasPage) return <String, dynamic>{};
    await _safeJs(_listenerRecorderScript);
    final raw = await _safeJs(_snapshotScript(_browserMode));
    return raw == null ? <String, dynamic>{} : _jsonFromJs(raw);
  }

  Future<Map<String, dynamic>?> _recoverClick(
    Map<String, dynamic> params,
    String beforeToken,
  ) async {
    final recoveryParams = <String, dynamic>{
      ...params,
      'recovery': true,
      'prefer_click_point': true,
    };
    final raw = await _backend.runJavaScriptReturningResult(
      _targetedScript(recoveryParams, 'click'),
    );
    final result = _jsonFromJs(raw);
    if (result['success'] != true) {
      return {
        ...result,
        'next_step':
            'Inspect viewport_map/text_candidates, ask the user to handle login or site restrictions if indicated, or choose a different element_id.',
      };
    }
    await _settle();
    final after = await _rawObservationMap();
    final afterState = _pageStateFromSnapshotMap(after);
    final afterToken = _pageChangeTokenFrom(afterState, after);
    final effect = _actionEffect(
      action: 'click',
      beforeToken: beforeToken,
      afterToken: afterToken,
      before: const <String, dynamic>{},
      after: after,
      result: result,
      recovered: true,
    );
    _lastActionEffect = effect;
    if (_effectHasMeaningfulChange(effect)) return result;
    return {
      'success': false,
      'failure_code':
          _siteRestrictionCode(afterState) ?? 'no_effect_after_click',
      'error':
          'click retry completed but did not produce a detectable page change',
      'target': result['target'],
      'hit_test': result['hit_test'],
      'last_action_effect': effect,
      'next_step':
          'Use browser_snapshot to review viewport_map and page text before trying another target.',
    };
  }

  Map<String, dynamic> _actionEffect({
    required String action,
    required String beforeToken,
    required String afterToken,
    required Map<String, dynamic> before,
    required Map<String, dynamic> after,
    required Map<String, dynamic> result,
    required bool recovered,
  }) {
    final beforeUrl = before['url'] as String?;
    final afterUrl = after['url'] as String?;
    final beforeTitle = before['title'] as String?;
    final afterTitle = after['title'] as String?;
    final afterState = _pageStateFromSnapshotMap(after);
    final restriction = _siteRestrictionCode(afterState);
    return {
      'action': action,
      'changed': beforeToken != afterToken,
      'recovered': recovered,
      'before_token': beforeToken,
      'after_token': afterToken,
      'url_changed':
          beforeUrl != null && afterUrl != null && beforeUrl != afterUrl,
      'title_changed': beforeTitle != null &&
          afterTitle != null &&
          beforeTitle != afterTitle,
      if (restriction != null) 'site_signal': restriction,
      if (result['match_method'] != null)
        'match_method': result['match_method'],
      if (result['warning'] != null) 'warning': result['warning'],
      if (result['target'] != null) 'target': result['target'],
      if (result['hit_test'] != null) 'hit_test': result['hit_test'],
    };
  }

  bool _effectHasMeaningfulChange(Map<String, dynamic> effect) {
    if (effect['changed'] == true) return true;
    if (effect['url_changed'] == true || effect['title_changed'] == true) {
      return true;
    }
    return false;
  }

  Future<void> _settle() async {
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final state = _jsonFromJs(
        await _safeJs(
          'JSON.stringify({ready:document.readyState,url:location.href,title:document.title})',
        ),
      );
      _url = state['url'] as String? ?? _url;
      _title = state['title'] as String? ?? _title;
      if (state['ready'] == 'complete') break;
    }
    if (_browserMode == BrowserViewportMode.desktop) {
      await _safeJs(_desktopViewportScript);
    }
    await _safeJs(_listenerRecorderScript);
    _loading = false;
    _progress = 100;
    notifyListeners();
  }

  Future<void> _waitForText(String text, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final found = await _backend
          .runJavaScriptReturningResult(
            'document.body && document.body.innerText.includes(${jsonEncode(text)})',
          )
          .catchError((_) => false);
      if (found == true || found == 'true') return;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  Future<void> _scrollTextIntoView(String text) async {
    await _safeJs(_findTextScript(text));
  }

  bool _looksLikeLocalFileTarget(String url, Uri? uri) {
    final lower = url.toLowerCase();
    if (uri?.scheme.toLowerCase() == 'file') return true;
    if (url.startsWith('/') || url.startsWith('./') || url.startsWith('../')) {
      return true;
    }
    if (lower.startsWith('workspace/') ||
        lower.startsWith('sandbox/') ||
        lower.startsWith('file:')) {
      return true;
    }
    if (!url.contains('://') &&
        (lower.endsWith('.html') || lower.endsWith('.htm'))) {
      return true;
    }
    return false;
  }

  Map<String, dynamic> _paramsWithElementFingerprint(
    Map<String, dynamic> params,
  ) {
    final elementId = params['element_id'];
    if (elementId is! String || elementId.trim().isEmpty) return params;
    final element = _latestElementById[elementId];
    if (element == null) return params;
    return {
      ...params,
      'target_fingerprint': {
        'element_id': elementId,
        'tag': element['tag'],
        'role': element['role'],
        'kind': element['kind'],
        'label': element['label'],
        'text': element['text'],
        'value_hint': element['value_hint'],
        'name': element['name'],
        'type': element['type'],
      },
    };
  }

  Map<String, dynamic> _pageStateFromSnapshotMap(Map<String, dynamic> map) {
    final rawPageState = map['page_state'];
    final pageState = rawPageState is Map
        ? Map<String, dynamic>.from(rawPageState)
        : <String, dynamic>{
            'url': map['url'],
            'title': map['title'],
            'text': map['text'],
            'elements': map['elements'],
          };
    pageState['url'] ??= map['url'] ?? _url ?? '';
    pageState['title'] ??= map['title'] ?? _title ?? '';
    pageState['text'] = _truncate((pageState['text'] as String?) ?? '', 6000);
    pageState['elements'] = _elementList(pageState['elements']);
    pageState['viewport_map'] = _mapFrom(pageState['viewport_map']) ??
        _mapFrom(map['viewport_map']) ??
        <String, dynamic>{};
    pageState['page_change_token'] ??= map['page_change_token'];
    pageState['browser_mode'] = _browserMode.name;
    pageState['user_agent'] ??= _userAgentForMode(_browserMode);
    return pageState;
  }

  BrowserScreenshotMode? _parseScreenshotMode(Object? value) {
    if (value == null) return BrowserScreenshotMode.auto;
    if (value is! String) return null;
    return switch (value.trim().toLowerCase()) {
      'auto' => BrowserScreenshotMode.auto,
      'never' => BrowserScreenshotMode.never,
      'always' => BrowserScreenshotMode.always,
      _ => null,
    };
  }

  BrowserViewportMode? _parseBrowserMode(Object? value) {
    if (value == null) return BrowserViewportMode.mobile;
    if (value is! String) return null;
    return switch (value.trim().toLowerCase()) {
      'desktop' => BrowserViewportMode.desktop,
      'mobile' => BrowserViewportMode.mobile,
      _ => null,
    };
  }

  Future<void> _applyBrowserMode(BrowserViewportMode mode) async {
    if (_appliedBrowserMode == mode) {
      _browserMode = mode;
      return;
    }
    await _backend.setUserAgent(_userAgentForMode(mode));
    _browserMode = mode;
    _appliedBrowserMode = mode;
  }

  String? _userAgentForMode(BrowserViewportMode mode) {
    return mode == BrowserViewportMode.desktop ? napaxiDesktopUserAgent : null;
  }

  Future<NapaxiBrowserScreenshot?> _maybeCaptureScreenshot(
    BrowserScreenshotMode mode,
    String action,
  ) async {
    if (!_hasPage || mode == BrowserScreenshotMode.never) return null;
    if (!_backend.capabilities.supportsScreenshot) return null;
    if (mode == BrowserScreenshotMode.auto && action != 'snapshot') {
      return null;
    }
    try {
      return await _backend.captureScreenshot(mode);
    } catch (_) {
      return null;
    }
  }

  String _pageChangeTokenFrom(
    Map<String, dynamic> pageState,
    Map<String, dynamic> map,
  ) {
    final existing = pageState['page_change_token'] ?? map['page_change_token'];
    if (existing is String && existing.isNotEmpty) return existing;
    final elements = _elementList(pageState['elements']);
    final summary = {
      'url': pageState['url'] ?? map['url'] ?? '',
      'title': pageState['title'] ?? map['title'] ?? '',
      'scroll': pageState['scroll'],
      'text': _truncate((pageState['text'] as String?) ?? '', 1200),
      'elements': elements
          .take(40)
          .map((element) => [
                element['element_id'],
                element['text'],
                element['label'],
                element['action_hint'],
                element['bbox'],
              ])
          .toList(growable: false),
    };
    return _stableHash(jsonEncode(summary));
  }

  String _stableHash(String value) {
    var hash = 2166136261;
    for (var i = 0; i < value.length; i++) {
      hash ^= value.codeUnitAt(i);
      hash = (hash * 16777619) & 0xffffffff;
    }
    return hash.toRadixString(36);
  }

  String? _siteRestrictionCode(Map<String, dynamic> pageState) {
    final text = ((pageState['text'] as String?) ?? '').toLowerCase();
    const loginTerms = ['login', 'sign in', '登录', '请登录', '账号'];
    if (loginTerms.any(text.contains)) return 'login_required';
    const restrictionTerms = [
      'captcha',
      'verification',
      '验证码',
      '安全验证',
      '打开app',
      '打开 app',
      '客户端',
      '无法访问',
      '访问受限',
      '风险',
    ];
    if (restrictionTerms.any(text.contains)) return 'site_restricted';
    return null;
  }

  bool _sameUrl(String? left, String right) {
    if (left == null || left.trim().isEmpty) return false;
    final a = Uri.tryParse(left);
    final b = Uri.tryParse(right);
    if (a == null || b == null) return left == right;
    return a.removeFragment() == b.removeFragment();
  }

  Map<String, dynamic> _jsonFromJs(Object? raw) {
    if (raw == null) return <String, dynamic>{};
    if (raw is Map<String, dynamic>) return raw;
    Object? decoded = raw;
    if (raw is String) {
      try {
        decoded = jsonDecode(raw);
        if (decoded is String && _looksJson(decoded)) {
          decoded = jsonDecode(decoded);
        }
      } catch (_) {
        return <String, dynamic>{};
      }
    }
    return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
  }

  bool _looksJson(String value) {
    final trimmed = value.trimLeft();
    return trimmed.startsWith('{') || trimmed.startsWith('[');
  }

  List<Map<String, dynamic>> _elementList(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  Map<String, dynamic>? _mapFrom(Object? value) {
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  String _truncate(String value, int maxChars) {
    if (value.length <= maxChars) return value;
    return '${value.substring(0, maxChars)}...';
  }

  Future<Object?> _safeJs(String javaScript) async {
    try {
      return await _backend.runJavaScriptReturningResult(javaScript);
    } catch (_) {
      return null;
    }
  }
}

String _targetedScript(
  Map<String, dynamic> params,
  String action, {
  String text = '',
  bool submit = false,
  bool clearFirst = true,
}) {
  return '''
(function() {
  const params = ${jsonEncode(params)};
  const action = ${jsonEncode(action)};
  const text = ${jsonEncode(text)};
  const submit = ${jsonEncode(submit)};
  const clearFirst = ${jsonEncode(clearFirst)};
  $_browserRuntimeScript
  return JSON.stringify(window.__napaxiBrowser.runTarget(params, action, {text, submit, clearFirst}));
})()
''';
}

String _findTextScript(String text) => '''
(function() {
  const text = ${jsonEncode(text)};
  $_browserRuntimeScript
  return JSON.stringify(window.__napaxiBrowser.findText(text));
})()
''';

String _keysScript(String keys) => '''
(function() {
  const keys = ${jsonEncode(keys)};
  $_browserRuntimeScript
  return JSON.stringify(window.__napaxiBrowser.sendKeys(keys));
})()
''';

String _debugHighlightScript(bool enabled) => '''
(function() {
  const enabled = ${jsonEncode(enabled)};
  const styleId = 'napaxi-browser-debug-highlight-style';
  let style = document.getElementById(styleId);
  if (!enabled) {
    if (style) style.remove();
    document.querySelectorAll('[data-napaxi-element-id]').forEach((el) => {
      el.removeAttribute('data-napaxi-debug-highlight');
    });
    return true;
  }
  if (!style) {
    style = document.createElement('style');
    style.id = styleId;
    document.head && document.head.appendChild(style);
  }
  style.textContent = [
    '[data-napaxi-element-id]{outline:2px solid rgba(37,99,235,.75)!important;outline-offset:2px!important;}',
    '[data-napaxi-element-id][data-napaxi-debug-highlight="risk"]{outline-color:rgba(220,38,38,.8)!important;}'
  ].join('\\n');
  document.querySelectorAll('[data-napaxi-element-id]').forEach((el) => {
    const risk = (el.getAttribute('data-napaxi-risk-hint') || '').trim();
    el.setAttribute('data-napaxi-debug-highlight', risk ? 'risk' : 'normal');
  });
  return true;
})()
''';

String _snapshotScript(BrowserViewportMode mode) => '''
(function() {
  const browserMode = ${jsonEncode(mode.name)};
  const configuredUserAgent = ${jsonEncode(mode == BrowserViewportMode.desktop ? napaxiDesktopUserAgent : null)};
  $_browserRuntimeScript
  const result = window.__napaxiBrowser.snapshot();
  result.browser_mode = browserMode;
  result.user_agent = configuredUserAgent || navigator.userAgent;
  result.page_state = result.page_state || {};
  result.page_state.browser_mode = browserMode;
  result.page_state.user_agent = configuredUserAgent || navigator.userAgent;
  result.page_state.viewport = result.page_state.viewport || {};
  result.page_state.viewport.browser_mode = browserMode;
  if (browserMode === 'desktop') result.page_state.viewport.emulated_width = 1280;
  return JSON.stringify(result);
})()
''';

const String _desktopViewportScript = r'''
(function() {
  const width = '1280';
  let viewport = document.querySelector('meta[name="viewport"]');
  if (!viewport) {
    viewport = document.createElement('meta');
    viewport.setAttribute('name', 'viewport');
    document.head && document.head.appendChild(viewport);
  }
  if (viewport) {
    viewport.setAttribute('content', 'width=' + width + ', initial-scale=1.0');
  }
  return true;
})()
''';

const String _listenerRecorderScript = r'''
(function() {
  const events = new Set(['click', 'mousedown', 'mouseup', 'pointerdown', 'pointerup', 'touchstart', 'touchend']);
  const existing = window.__napaxiBrowserListenerRecorder;
  if (existing && existing.version === 1) return true;
  const listenerElements = existing && existing._elements ? existing._elements : new WeakSet();
  const originalAdd = existing && existing._originalAdd
    ? existing._originalAdd
    : EventTarget.prototype.addEventListener;
  function mark(target, type) {
    try {
      if (events.has(String(type).toLowerCase()) && target && target.nodeType === Node.ELEMENT_NODE) {
        listenerElements.add(target);
      }
    } catch (_) {}
  }
  if (!existing || existing.version !== 1) {
    EventTarget.prototype.addEventListener = function(type) {
      mark(this, type);
      return originalAdd.apply(this, arguments);
    };
  }
  window.__napaxiBrowserListenerRecorder = {
    version: 1,
    _elements: listenerElements,
    _originalAdd: originalAdd,
    has: function(el) {
      try {
        return listenerElements.has(el);
      } catch (_) {
        return false;
      }
    }
  };
  return true;
})()
''';

const String _browserRuntimeScript = r'''
(function() {
  const version = 2;
  const listenerEvents = new Set(['click', 'mousedown', 'mouseup', 'pointerdown', 'pointerup', 'touchstart', 'touchend']);
  function installListenerRecorder() {
    const existing = window.__napaxiBrowserListenerRecorder;
    if (existing && existing.version === 1) return existing;
    const listenerElements = existing && existing._elements ? existing._elements : new WeakSet();
    const originalAdd = existing && existing._originalAdd
      ? existing._originalAdd
      : EventTarget.prototype.addEventListener;
    function mark(target, type) {
      try {
        if (listenerEvents.has(String(type).toLowerCase()) && target && target.nodeType === Node.ELEMENT_NODE) {
          listenerElements.add(target);
        }
      } catch (_) {}
    }
    if (!existing || existing.version !== 1) {
      EventTarget.prototype.addEventListener = function(type) {
        mark(this, type);
        return originalAdd.apply(this, arguments);
      };
    }
    window.__napaxiBrowserListenerRecorder = {
      version: 1,
      _elements: listenerElements,
      _originalAdd: originalAdd,
      has: function(el) {
        try {
          return listenerElements.has(el);
        } catch (_) {
          return false;
        }
      }
    };
    return window.__napaxiBrowserListenerRecorder;
  }
  installListenerRecorder();
  if (window.__napaxiBrowser && window.__napaxiBrowser.version === version) {
    return;
  }
  const dataAttr = 'data-napaxi-element-id';
  const roleSet = new Set([
    'button',
    'link',
    'textbox',
    'searchbox',
    'combobox',
    'checkbox',
    'radio',
    'switch',
    'menuitem',
    'option',
    'tab',
    'slider',
    'spinbutton',
    'row',
    'cell',
    'gridcell'
  ]);
  const eventAttrs = [
    'onclick',
    'onmousedown',
    'onmouseup',
    'onpointerdown',
    'onpointerup',
    'ontouchstart',
    'ontouchend',
    'onkeydown',
    'onkeyup'
  ];
  const actionTerms = [
    'add to cart',
    'cart',
    'basket',
    'buy',
    'purchase',
    'checkout',
    'submit',
    'confirm',
    'order',
    'action',
    'button',
    '加入购物车',
    '加入购物袋',
    '加购',
    '购物车',
    '立即购买',
    '马上购买',
    '购买',
    '下单',
    '提交',
    '确认',
    '去结算',
    '结算'
  ];
  const actionAttrTerms = [
    ...actionTerms,
    'add',
    'addcart',
    'add-cart',
    'buybtn',
    'buy-button',
    'cart-button',
    'submit-btn',
    'confirm-btn',
    'data-click',
    'data-action'
  ];
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
    '立即购买',
    '付款',
    '支付',
    '提交订单',
    '删除',
    '确认'
  ];
  const sensitiveTerms = [
    'password',
    'passwd',
    'passcode',
    'otp',
    'captcha',
    'verification',
    'verify code',
    'security code',
    '密码',
    '验证码',
    '动态码'
  ];
  function compact(value) {
    return (value || '').toString().replace(/\s+/g, ' ').trim();
  }
  function norm(value) {
    return compact(value).toLowerCase();
  }
  function hasAny(haystack, terms) {
    const normalized = norm(haystack);
    return terms.find((term) => normalized.includes(norm(term))) || '';
  }
  function hash(value) {
    let h = 2166136261;
    for (let i = 0; i < value.length; i++) {
      h ^= value.charCodeAt(i);
      h = Math.imul(h, 16777619);
    }
    return (h >>> 0).toString(36);
  }
  function visible(el) {
    if (!el || el.nodeType !== Node.ELEMENT_NODE) return false;
    const style = window.getComputedStyle(el);
    const rect = el.getBoundingClientRect();
    return !!style &&
      style.visibility !== 'hidden' &&
      style.display !== 'none' &&
      Number(style.opacity || '1') > 0.01 &&
      rect.width > 0 &&
      rect.height > 0 &&
      rect.bottom >= 0 &&
      rect.right >= 0 &&
      rect.top <= window.innerHeight &&
      rect.left <= window.innerWidth;
  }
  function allRoots() {
    const roots = [document];
    const seen = new Set(roots);
    function scan(root) {
      let nodes = [];
      try {
        nodes = Array.from(root.querySelectorAll('*'));
      } catch (_) {
        return;
      }
      for (const node of nodes) {
        if (node.shadowRoot && !seen.has(node.shadowRoot)) {
          seen.add(node.shadowRoot);
          roots.push(node.shadowRoot);
          scan(node.shadowRoot);
        }
        if (node.tagName === 'IFRAME') {
          try {
            const doc = node.contentDocument;
            if (doc && !seen.has(doc)) {
              seen.add(doc);
              roots.push(doc);
              scan(doc);
            }
          } catch (_) {}
        }
      }
    }
    scan(document);
    return roots;
  }
  function allElements() {
    const out = [];
    const seen = new Set();
    for (const root of allRoots()) {
      let nodes = [];
      try {
        nodes = Array.from(root.querySelectorAll('*'));
      } catch (_) {}
      for (const node of nodes) {
        if (!seen.has(node)) {
          seen.add(node);
          out.push(node);
        }
      }
    }
    return out;
  }
  function queryFirst(selector) {
    for (const root of allRoots()) {
      try {
        const found = root.querySelector(selector);
        if (found) return found;
      } catch (_) {}
    }
    return null;
  }
  function explicitLabel(el) {
    const parts = [
      el.getAttribute('aria-label'),
      el.getAttribute('placeholder'),
      el.getAttribute('title'),
      el.getAttribute('alt'),
      el.getAttribute('name')
    ];
    if (el.id) {
      try {
        const labels = Array.from(document.querySelectorAll('label[for="' + CSS.escape(el.id) + '"]'));
        parts.push(...labels.map((label) => label.innerText));
      } catch (_) {}
    }
    if (el.labels) {
      try {
        parts.push(...Array.from(el.labels).map((label) => label.innerText));
      } catch (_) {}
    }
    return compact(parts.filter(Boolean).join(' '));
  }
  function textOf(el) {
    const aria = explicitLabel(el);
    const own = compact(el.innerText || el.textContent || '');
    const value = 'value' in el ? compact(el.value) : '';
    return compact([aria, own || value].filter(Boolean).join(' '));
  }
  function attributeText(el) {
    const parts = [
      el.id,
      el.className && typeof el.className === 'string' ? el.className : '',
      el.getAttribute('role'),
      el.getAttribute('aria-label'),
      el.getAttribute('title'),
      el.getAttribute('name'),
      el.getAttribute('type'),
      el.getAttribute('data-action'),
      el.getAttribute('data-click'),
      el.getAttribute('data-spm'),
      el.getAttribute('data-testid'),
      el.getAttribute('data-test'),
      el.getAttribute('href')
    ];
    try {
      for (const attr of Array.from(el.attributes || [])) {
        if (attr.name.startsWith('data-')) parts.push(attr.name, attr.value);
      }
    } catch (_) {}
    return compact(parts.filter(Boolean).join(' '));
  }
  function roleOf(el) {
    const role = compact(el.getAttribute('role')).toLowerCase();
    if (role) return role;
    const tag = el.tagName.toLowerCase();
    const type = (el.getAttribute('type') || '').toLowerCase();
    if (tag === 'a') return 'link';
    if (tag === 'button' || type === 'button' || type === 'submit') return 'button';
    if (tag === 'textarea') return 'textbox';
    if (tag === 'select') return 'combobox';
    if (tag === 'input') {
      if (type === 'checkbox') return 'checkbox';
      if (type === 'radio') return 'radio';
      if (type === 'search') return 'searchbox';
      return 'textbox';
    }
    if (el.isContentEditable) return 'textbox';
    return tag;
  }
  function kindOf(el) {
    const role = roleOf(el);
    const type = (el.getAttribute('type') || '').toLowerCase();
    if (type === 'password') return 'password';
    if (role === 'textbox' || role === 'searchbox') return 'text';
    if (role === 'button') return 'button';
    if (role === 'link') return 'link';
    return role;
  }
  function cssPath(el) {
    const parts = [];
    let cur = el;
    while (cur && cur.nodeType === Node.ELEMENT_NODE && cur !== document.documentElement) {
      let part = cur.tagName.toLowerCase();
      if (cur.id) {
        part += '#' + cur.id;
        parts.unshift(part);
        break;
      }
      let index = 1;
      let sib = cur;
      while ((sib = sib.previousElementSibling)) {
        if (sib.tagName === cur.tagName) index += 1;
      }
      part += ':nth-of-type(' + index + ')';
      parts.unshift(part);
      cur = cur.parentElement;
    }
    return parts.join('>');
  }
  function isSensitive(el, labelText) {
    const haystack = norm([
      el.getAttribute('type'),
      el.getAttribute('name'),
      el.getAttribute('autocomplete'),
      labelText
    ].filter(Boolean).join(' '));
    return sensitiveTerms.some((term) => haystack.includes(term));
  }
  function riskHint(labelText) {
    const haystack = norm(labelText);
    return riskyTerms.find((term) => haystack.includes(term)) || '';
  }
  function listenerRecorderHas(el) {
    try {
      const recorder = window.__napaxiBrowserListenerRecorder;
      return !!(recorder && typeof recorder.has === 'function' && recorder.has(el));
    } catch (_) {
      return false;
    }
  }
  function actionHintFor(el, combinedText, attrText) {
    const haystack = compact([combinedText, attrText].join(' '));
    const term = hasAny(haystack, actionTerms);
    if (term) return term;
    const role = roleOf(el);
    if (role === 'button') return 'button';
    if (role === 'link') return 'link';
    if (role === 'searchbox') return 'search';
    return '';
  }
  function clickabilityInfo(el) {
    if (!visible(el)) {
      return {interactive: false, score: 0, source: '', reason: '', action_hint: ''};
    }
    const tag = el.tagName.toLowerCase();
    const role = roleOf(el);
    const style = window.getComputedStyle(el);
    const combinedText = textOf(el);
    const attrText = attributeText(el);
    const ownAndNearbyText = compact([
      combinedText,
      el.parentElement ? el.parentElement.innerText : ''
    ].join(' '));
    const actionHint = actionHintFor(el, ownAndNearbyText, attrText);
    const reasons = [];
    let score = 0;
    let source = '';
    if (['a', 'button', 'input', 'textarea', 'select', 'summary', 'details', 'option'].includes(tag)) {
      score += 100;
      if (!source) source = 'native';
      reasons.push('native_control');
    }
    if (el.isContentEditable) {
      score += 80;
      if (!source) source = 'editable';
      reasons.push('contenteditable');
    }
    if (roleSet.has(role)) {
      score += 75;
      if (!source) source = 'aria_role';
      reasons.push('aria_role:' + role);
    }
    if (eventAttrs.some((attr) => el.hasAttribute(attr))) {
      score += 75;
      if (!source) source = 'event_attribute';
      reasons.push('event_attribute');
    }
    if (listenerRecorderHas(el)) {
      score += 85;
      if (!source) source = 'js_listener';
      reasons.push('js_listener');
    }
    const tabindex = el.getAttribute('tabindex');
    if (tabindex !== null && tabindex !== '-1') {
      score += 45;
      if (!source) source = 'tabindex';
      reasons.push('tabindex');
    }
    if (style && style.cursor === 'pointer') {
      score += 55;
      if (!source) source = 'cursor';
      reasons.push('cursor:pointer');
    }
    if (hasAny(attrText, actionAttrTerms)) {
      score += 40;
      if (!source) source = 'action_attribute';
      reasons.push('action_attribute');
    }
    if (actionHint && ['div', 'span', 'label', 'li', 'section', 'p'].includes(tag)) {
      score += 35;
      if (!source) source = 'action_text';
      reasons.push('action_text:' + actionHint);
    }
    return {
      interactive: score >= 35,
      score,
      source,
      reason: reasons.join(','),
      action_hint: actionHint
    };
  }
  function isInteractive(el) {
    return clickabilityInfo(el).interactive;
  }
  function elementRecord(el, index) {
    const rect = el.getBoundingClientRect();
    const labelText = explicitLabel(el);
    const combinedText = textOf(el);
    const sensitive = isSensitive(el, combinedText);
    const kind = kindOf(el);
    const info = clickabilityInfo(el);
    const fingerprint = {
      tag: el.tagName.toLowerCase(),
      role: roleOf(el),
      kind,
      type: (el.getAttribute('type') || '').toLowerCase(),
      name: el.getAttribute('name') || '',
      label: labelText.slice(0, 180),
      text: sensitive ? '[redacted sensitive field]' : combinedText.slice(0, 220),
      path: cssPath(el)
    };
    const elementId = 'e_' + hash(JSON.stringify(fingerprint));
    try {
      el.setAttribute(dataAttr, elementId);
    } catch (_) {}
    const parentText = compact(el.parentElement ? el.parentElement.innerText : '');
    const risk = riskHint(combinedText);
    try {
      if (risk) el.setAttribute('data-napaxi-risk-hint', risk);
      else el.removeAttribute('data-napaxi-risk-hint');
    } catch (_) {}
    return {
      index,
      element_id: elementId,
      role: fingerprint.role,
      kind,
      tag: fingerprint.tag,
      type: fingerprint.type,
      name: fingerprint.name,
      label: fingerprint.label,
      text: fingerprint.text,
      value_hint: sensitive ? '[redacted sensitive field]' : (('value' in el) ? compact(el.value).slice(0, 120) : ''),
      enabled: !(el.disabled || el.getAttribute('aria-disabled') === 'true'),
      visible: visible(el),
      bbox: {
        x: Math.round(rect.left),
        y: Math.round(rect.top),
        width: Math.round(rect.width),
        height: Math.round(rect.height)
      },
      clickable_point: {
        x: Math.round(rect.left + rect.width / 2),
        y: Math.round(rect.top + rect.height / 2)
      },
      nearby_text: sensitive ? '' : parentText.slice(0, 260),
      risk_hint: risk,
      action_hint: info.action_hint,
      interaction_source: info.source,
      clickable_score: info.score,
      clickable_reason: info.reason,
      fingerprint
    };
  }
  function interactiveElements() {
    return allElements()
      .filter(isInteractive)
      .sort((a, b) => clickabilityInfo(b).score - clickabilityInfo(a).score)
      .slice(0, 160);
  }
  function snapshot() {
    const elements = interactiveElements().map(elementRecord);
    const pageText = compact(document.body ? document.body.innerText : '').slice(0, 10000);
    const viewportMap = viewportObservation(elements);
    const pageChangeToken = hash(JSON.stringify({
      url: location.href,
      title: document.title || '',
      scrollY: Math.round(window.scrollY || 0),
      text: pageText.slice(0, 1800),
      elements: elements.slice(0, 80).map((item) => [
        item.element_id,
        item.text,
        item.label,
        item.action_hint,
        item.bbox
      ])
    }));
    const pageState = {
      url: location.href,
      title: document.title || '',
      viewport: {
        width: window.innerWidth,
        height: window.innerHeight,
        device_pixel_ratio: window.devicePixelRatio || 1
      },
      scroll: {
        x: Math.round(window.scrollX || 0),
        y: Math.round(window.scrollY || 0),
        max_y: Math.max(
          document.body ? document.body.scrollHeight : 0,
          document.documentElement ? document.documentElement.scrollHeight : 0
        )
      },
      text: pageText,
      elements,
      viewport_map: viewportMap,
      page_change_token: pageChangeToken
    };
    return {
      url: pageState.url,
      title: pageState.title,
      text: pageText,
      elements,
      viewport_map: viewportMap,
      page_change_token: pageChangeToken,
      page_state: pageState
    };
  }
  function viewportObservation(elements) {
    const textBlocks = visibleTextBlocks();
    const overlays = overlayCandidates();
    return {
      width: window.innerWidth,
      height: window.innerHeight,
      scroll_x: Math.round(window.scrollX || 0),
      scroll_y: Math.round(window.scrollY || 0),
      visible_text_blocks: textBlocks,
      visible_clickable_elements: elements.slice(0, 80).map((item) => ({
        element_id: item.element_id,
        role: item.role,
        kind: item.kind,
        tag: item.tag,
        text: item.text,
        label: item.label,
        action_hint: item.action_hint,
        interaction_source: item.interaction_source,
        clickable_score: item.clickable_score,
        clickable_reason: item.clickable_reason,
        bbox: item.bbox,
        center: item.clickable_point,
        nearby_text: item.nearby_text,
        risk_hint: item.risk_hint
      })),
      overlays,
      diagnostics: pageDiagnostics(textBlocks, overlays)
    };
  }
  function visibleTextBlocks() {
    const out = [];
    const seen = new Set();
    const walker = document.createTreeWalker(document.body || document.documentElement, NodeFilter.SHOW_TEXT);
    let node = walker.nextNode();
    while (node && out.length < 120) {
      const text = compact(node.nodeValue);
      const parent = node.parentElement;
      if (text && parent && visible(parent) && !seen.has(text + cssPath(parent))) {
        const rect = parent.getBoundingClientRect();
        seen.add(text + cssPath(parent));
        out.push({
          text: text.slice(0, 180),
          bbox: {
            x: Math.round(rect.left),
            y: Math.round(rect.top),
            width: Math.round(rect.width),
            height: Math.round(rect.height)
          },
          center: {
            x: Math.round(rect.left + rect.width / 2),
            y: Math.round(rect.top + rect.height / 2)
          },
          near_action: actionHintFor(parent, text, attributeText(parent))
        });
      }
      node = walker.nextNode();
    }
    return out;
  }
  function overlayCandidates() {
    return allElements()
      .filter((el) => {
        if (!visible(el)) return false;
        const style = window.getComputedStyle(el);
        const rect = el.getBoundingClientRect();
        const z = Number.parseInt(style.zIndex || '0', 10) || 0;
        const fixed = style.position === 'fixed' || style.position === 'sticky';
        const large = rect.width >= window.innerWidth * 0.45 && rect.height >= window.innerHeight * 0.12;
        return (fixed || z >= 10) && large;
      })
      .slice(0, 12)
      .map((el) => {
        const rect = el.getBoundingClientRect();
        return {
          tag: el.tagName.toLowerCase(),
          role: roleOf(el),
          text: textOf(el).slice(0, 220),
          z_index: window.getComputedStyle(el).zIndex || '',
          position: window.getComputedStyle(el).position || '',
          bbox: {
            x: Math.round(rect.left),
            y: Math.round(rect.top),
            width: Math.round(rect.width),
            height: Math.round(rect.height)
          }
        };
      });
  }
  function pageDiagnostics(textBlocks, overlays) {
    const text = norm(textBlocks.map((item) => item.text).join(' '));
    const diagnostics = [];
    if (['登录', '请登录', 'login', 'sign in'].some((term) => text.includes(norm(term)))) {
      diagnostics.push('login_required');
    }
    if (['验证码', '安全验证', 'captcha', 'verification', '打开app', '客户端', '访问受限', '风险'].some((term) => text.includes(norm(term)))) {
      diagnostics.push('site_restricted');
    }
    if (overlays.length) diagnostics.push('overlay_or_fixed_layer_present');
    return diagnostics;
  }
  function scoreElement(el, target) {
    const fp = target || {};
    const labelText = explicitLabel(el);
    const combinedText = textOf(el);
    let score = 0;
    if (fp.tag && fp.tag === el.tagName.toLowerCase()) score += 8;
    if (fp.role && fp.role === roleOf(el)) score += 12;
    if (fp.kind && fp.kind === kindOf(el)) score += 8;
    if (fp.name && fp.name === (el.getAttribute('name') || '')) score += 8;
    if (fp.type && fp.type === (el.getAttribute('type') || '').toLowerCase()) score += 6;
    if (fp.label && norm(labelText).includes(norm(fp.label))) score += 24;
    if (fp.text && fp.text.indexOf('[redacted') !== 0 && norm(combinedText).includes(norm(fp.text))) score += 22;
    return score;
  }
  function candidatesFor(params) {
    const target = params.target_fingerprint || {};
    return interactiveElements()
      .map((el, index) => ({el, index, score: scoreElement(el, target)}))
      .filter((item) => item.score > 0)
      .sort((a, b) => b.score - a.score)
      .slice(0, 5)
      .map((item, index) => {
        const record = elementRecord(item.el, item.index);
        record.match_score = item.score;
        record.candidate_rank = index;
        return record;
      });
  }
  function textActionCandidates(text) {
    const wanted = norm(text);
    if (!wanted) return [];
    const out = [];
    const seen = new Set();
    const root = document.body || document.documentElement;
    if (!root) return out;
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    let node = walker.nextNode();
    while (node) {
      if (norm(node.nodeValue).includes(wanted)) {
        const parent = node.parentElement;
        const el = parent ? findActionAncestor(parent, wanted) : null;
        if (el && !seen.has(el)) {
          seen.add(el);
          const record = elementRecord(el, -1);
          record.match_method = 'text_ancestor';
          record.match_text = compact(node.nodeValue).slice(0, 180);
          out.push(record);
          if (out.length >= 6) break;
        }
      }
      node = walker.nextNode();
    }
    return out;
  }
  function findActionAncestor(start, wantedNorm) {
    let cur = start;
    let depth = 0;
    let fallback = null;
    while (cur && cur.nodeType === Node.ELEMENT_NODE && depth < 7) {
      if (visible(cur)) {
        const info = clickabilityInfo(cur);
        const haystack = norm([textOf(cur), attributeText(cur)].join(' '));
        const textMatches = !wantedNorm || haystack.includes(wantedNorm);
        if (info.interactive && textMatches) return cur;
        if (!fallback && textMatches && (info.action_hint || hasAny(haystack, actionTerms))) {
          fallback = cur;
        }
      }
      cur = cur.parentElement;
      depth += 1;
    }
    return fallback;
  }
  function findTarget(params) {
    let el = null;
    if (params.click_point) {
      const point = params.click_point;
      const x = Number(point.x);
      const y = Number(point.y);
      if (Number.isFinite(x) && Number.isFinite(y)) {
        try {
          el = document.elementFromPoint(x, y);
        } catch (_) {}
        if (el && visible(el)) return {el, method: 'click_point', point: {x, y}};
      }
    }
    if (params.element_id) {
      try {
        el = queryFirst('[' + dataAttr + '="' + CSS.escape(params.element_id) + '"]');
      } catch (_) {}
      if (el && visible(el)) return {el, method: 'element_id'};
    }
    if (params.selector) {
      try {
        el = queryFirst(params.selector);
      } catch (_) {}
      if (el && visible(el)) return {el, method: 'selector'};
    }
    const candidates = interactiveElements();
    if (Number.isInteger(params.index) && candidates[params.index]) {
      return {el: candidates[params.index], method: 'index'};
    }
    if (params.text) {
      const wanted = norm(params.text);
      el = candidates.find((item) => norm(item.innerText || item.textContent || item.value).includes(wanted));
      if (el) return {el, method: 'text'};
      const textAncestor = textActionCandidates(params.text)[0];
      if (textAncestor && textAncestor.element_id) {
        try {
          el = queryFirst('[' + dataAttr + '="' + CSS.escape(textAncestor.element_id) + '"]');
        } catch (_) {}
        if (el && visible(el)) return {el, method: 'text_ancestor'};
      }
    }
    if (params.label) {
      const wanted = norm(params.label);
      el = candidates.find((item) => norm(explicitLabel(item)).includes(wanted));
      if (el) return {el, method: 'label'};
      const labelAncestor = textActionCandidates(params.label)[0];
      if (labelAncestor && labelAncestor.element_id) {
        try {
          el = queryFirst('[' + dataAttr + '="' + CSS.escape(labelAncestor.element_id) + '"]');
        } catch (_) {}
        if (el && visible(el)) return {el, method: 'label_text_ancestor'};
      }
    }
    if (params.target_fingerprint) {
      const ranked = candidates
        .map((item) => ({el: item, score: scoreElement(item, params.target_fingerprint)}))
        .sort((a, b) => b.score - a.score);
      if (ranked.length && ranked[0].score >= 18) {
        return {el: ranked[0].el, method: 'fingerprint', score: ranked[0].score};
      }
    }
    return {el: null, method: 'none'};
  }
  function hitTest(el) {
    const rect = el.getBoundingClientRect();
    const x = Math.min(Math.max(rect.left + rect.width / 2, 1), window.innerWidth - 1);
    const y = Math.min(Math.max(rect.top + rect.height / 2, 1), window.innerHeight - 1);
    return hitTestPoint(x, y, el);
  }
  function hitTestPoint(x, y, el) {
    let hit = null;
    try {
      hit = document.elementFromPoint(x, y);
    } catch (_) {}
    return {
      x,
      y,
      hit,
      hit_tag: hit && hit.tagName ? hit.tagName.toLowerCase() : '',
      hit_text: hit ? textOf(hit).slice(0, 160) : '',
      unobscured: !el || !hit || hit === el || el.contains(hit) || hit.contains(el)
    };
  }
  function publicHitTest(hit) {
    return {
      x: Math.round(hit.x),
      y: Math.round(hit.y),
      hit_tag: hit.hit_tag,
      hit_text: hit.hit_text,
      unobscured: hit.unobscured
    };
  }
  function dispatchPointerClick(el, point) {
    const hit = point ? hitTestPoint(point.x, point.y, el) : hitTest(el);
    const eventTarget = point && hit.hit ? hit.hit : el;
    const init = {
      bubbles: true,
      cancelable: true,
      view: window,
      clientX: hit.x,
      clientY: hit.y,
      button: 0,
      buttons: 1
    };
    for (const type of ['pointerover', 'pointerenter', 'mouseover', 'mouseenter', 'pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click']) {
      let event;
      try {
        event = type.startsWith('pointer')
          ? new PointerEvent(type, Object.assign({pointerId: 1, pointerType: 'mouse', isPrimary: true}, init))
          : new MouseEvent(type, init);
      } catch (_) {
        event = new MouseEvent(type.replace(/^pointer/, 'mouse'), init);
      }
      eventTarget.dispatchEvent(event);
    }
    return hit;
  }
  function clickElement(el, point) {
    if (!el) return {success: false, failure_code: 'target_not_found', error: 'target element not found'};
    if (el.disabled || el.getAttribute('aria-disabled') === 'true') {
      return {success: false, failure_code: 'disabled', error: 'target element is disabled'};
    }
    if (!point) el.scrollIntoView({block: 'center', inline: 'center'});
    const hit = dispatchPointerClick(el, point);
    const publicHit = publicHitTest(hit);
    const target = elementRecord(el, -1);
    if (!hit.unobscured) {
      try {
        el.click();
        return {
          success: true,
          warning: 'target was visually obscured; used programmatic click fallback',
          target,
          hit_test: publicHit
        };
      } catch (_) {
        return {
          success: false,
          failure_code: 'obscured',
          error: 'target element is obscured by another element',
          target,
          hit_test: publicHit
        };
      }
    }
    return {success: true, target, hit_test: publicHit};
  }
  function typeElement(el, options) {
    if (!el) return {success: false, failure_code: 'target_not_found', error: 'target element not found'};
    el.scrollIntoView({block: 'center', inline: 'center'});
    el.focus();
    const text = options.text || '';
    const clearFirst = options.clearFirst !== false;
    if ('value' in el) {
      if (clearFirst) el.value = '';
      el.value = (clearFirst ? '' : el.value) + text;
      el.dispatchEvent(new InputEvent('input', {bubbles: true, data: text, inputType: 'insertText'}));
      el.dispatchEvent(new Event('change', {bubbles: true}));
    } else if (el.isContentEditable) {
      if (clearFirst) el.textContent = '';
      document.execCommand('insertText', false, text);
      el.dispatchEvent(new InputEvent('input', {bubbles: true, data: text, inputType: 'insertText'}));
    } else {
      return {success: false, failure_code: 'not_editable', error: 'target element is not editable'};
    }
    if (options.submit) {
      sendKeys('Enter');
    }
    return {success: true};
  }
  function runTarget(params, action, options) {
    const found = findTarget(params || {});
    if (!found.el) {
      const textCandidates = textActionCandidates((params && (params.text || params.label)) || '');
      return {
        success: false,
        failure_code: textCandidates.length ? 'interactive_text_not_indexed' : 'target_not_found',
        error: 'target element not found',
        candidates: candidatesFor(params || {}),
        text_candidates: textCandidates
      };
    }
    if (action === 'click') {
      let point = found.point || null;
      if (!point && params && params.prefer_click_point) {
        const rect = found.el.getBoundingClientRect();
        point = {
          x: Math.round(rect.left + rect.width / 2),
          y: Math.round(rect.top + rect.height / 2)
        };
      }
      const result = clickElement(found.el, point);
      result.match_method = found.method;
      return result;
    }
    if (action === 'type') {
      const result = typeElement(found.el, options || {});
      result.match_method = found.method;
      return result;
    }
    return {success: false, failure_code: 'unsupported_action', error: 'unsupported browser action'};
  }
  function findText(text) {
    const wanted = norm(text);
    if (!wanted) return {success: false, failure_code: 'empty_text', error: 'text is required'};
    const walker = document.createTreeWalker(document.body || document.documentElement, NodeFilter.SHOW_TEXT);
    let node = walker.nextNode();
    while (node) {
      if (norm(node.nodeValue).includes(wanted)) {
        const parent = node.parentElement;
        if (parent) parent.scrollIntoView({block: 'center', inline: 'nearest'});
        return {success: true, text: compact(node.nodeValue).slice(0, 240)};
      }
      node = walker.nextNode();
    }
    return {success: false, failure_code: 'text_not_found', error: 'text not found'};
  }
  function sendKeys(keys) {
    const allowed = new Set(['Enter', 'Escape', 'Tab', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight']);
    const parts = compact(keys).split('+').map((part) => part.trim()).filter(Boolean);
    if (!parts.length) return {success: false, failure_code: 'empty_keys', error: 'keys is required'};
    const target = document.activeElement || document.body;
    for (const key of parts) {
      if (!allowed.has(key)) {
        return {success: false, failure_code: 'unsupported_key', error: 'unsupported key: ' + key};
      }
      target.dispatchEvent(new KeyboardEvent('keydown', {bubbles: true, cancelable: true, key}));
      target.dispatchEvent(new KeyboardEvent('keyup', {bubbles: true, cancelable: true, key}));
      if (key === 'Enter') {
        const form = target.form || (target.closest ? target.closest('form') : null);
        if (form && typeof form.requestSubmit === 'function') form.requestSubmit();
      }
    }
    return {success: true, keys: parts};
  }
  window.__napaxiBrowser = {
    version,
    snapshot,
    runTarget,
    findText,
    sendKeys
  };
})()
''';
