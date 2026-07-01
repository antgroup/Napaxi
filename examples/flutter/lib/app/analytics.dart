part of '../main.dart';

class DemoAnalytics {
  static const _enabled = bool.fromEnvironment(
    'NAPA_UMENG_ENABLED',
    defaultValue: true,
  );
  static const _androidAppKey = String.fromEnvironment(
    'NAPA_UMENG_ANDROID_APP_KEY',
    defaultValue: '6a0d20019a7f376488e27748',
  );
  static const _iosAppKey = String.fromEnvironment(
    'NAPA_UMENG_IOS_APP_KEY',
    defaultValue: '6a0d20539a7f376488e277fd',
  );
  static const _channel = String.fromEnvironment(
    'NAPA_UMENG_CHANNEL',
    defaultValue: 'debug',
  );

  static bool _isInitialized = false;

  static void initialize() {
    if (!_enabled || (!_isAndroid && !_isIOS)) return;
    if (_androidAppKey.isEmpty || _iosAppKey.isEmpty || _channel.isEmpty) {
      return;
    }

    try {
      UmengCommonSdk.setPageCollectionModeManual();
      UmengCommonSdk.initCommon(_androidAppKey, _iosAppKey, _channel);
      _isInitialized = true;
    } on Object catch (error, stackTrace) {
      debugPrint('Umeng initialization failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  static void onPageStart(String pageName) {
    if (!_isInitialized) return;
    UmengCommonSdk.onPageStart(pageName);
  }

  static void onPageEnd(String pageName) {
    if (!_isInitialized) return;
    UmengCommonSdk.onPageEnd(pageName);
  }

  static bool get _isAndroid {
    try {
      return Platform.isAndroid;
    } on UnsupportedError {
      return false;
    }
  }

  static bool get _isIOS {
    try {
      return Platform.isIOS;
    } on UnsupportedError {
      return false;
    }
  }
}

class DemoAnalyticsRouteObserver extends NavigatorObserver {
  final Map<Route<dynamic>, String> _activePages = {};

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _end(previousRoute);
    _start(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _end(route);
    _start(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _end(oldRoute);
    _start(newRoute);
  }

  void _start(Route<dynamic>? route) {
    final pageName = _pageName(route);
    if (route == null || pageName == null) return;
    _activePages[route] = pageName;
    DemoAnalytics.onPageStart(pageName);
  }

  void _end(Route<dynamic>? route) {
    if (route == null) return;
    final pageName = _activePages.remove(route) ?? _pageName(route);
    if (pageName == null) return;
    DemoAnalytics.onPageEnd(pageName);
  }

  String? _pageName(Route<dynamic>? route) {
    final settingsName = route?.settings.name;
    if (settingsName != null && settingsName.isNotEmpty) {
      return settingsName;
    }
    if (route is PageRoute) {
      return route.runtimeType.toString();
    }
    return null;
  }
}
