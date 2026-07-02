part of '../main.dart';

class NapaxiApp extends StatefulWidget {
  const NapaxiApp({
    super.key,
    this.chatClientFactory,
    this.configStore,
    this.preferencesStore,
    this.updateService,
    this.feedbackService,
    this.initialLanguage,
    this.terminalBackendFactory,
  });

  final NapaxiChatClientFactory? chatClientFactory;
  final sdk.NapaxiConfigStore? configStore;
  final DemoPreferencesStore? preferencesStore;
  final DemoUpdateService? updateService;
  final DemoFeedbackService? feedbackService;

  /// 终端后端工厂（测试注入 / 未来 PTY 替换），透传到 [ChatScreen]。
  final TerminalBackend Function()? terminalBackendFactory;

  /// Overrides the starting UI language synchronously, before the async
  /// preferences restore runs. Production leaves this null (defaults to
  /// Chinese); tests pin it so locale-sensitive assertions are stable from the
  /// first frame.
  final AppLanguage? initialLanguage;

  @override
  State<NapaxiApp> createState() => _NapaxiAppState();
}

class _NapaxiAppState extends State<NapaxiApp> {
  final DemoAnalyticsRouteObserver _analyticsObserver =
      DemoAnalyticsRouteObserver();

  late final sdk.NapaxiConfigStore _configStore =
      widget.configStore ??
      (widget.chatClientFactory == null
          ? sdk.NapaxiConfigStore.instance
          : sdk.NapaxiConfigStore.memory());

  late AppLanguage _language = widget.initialLanguage ?? AppLanguage.chinese;
  int _languageRevision = 0;

  DemoPreferencesStore get _preferencesStore {
    return widget.preferencesStore ?? SharedPreferencesDemoPreferencesStore();
  }

  @override
  void initState() {
    super.initState();
    unawaited(_restoreLanguage());
  }

  void _setLanguage(AppLanguage language) {
    if (_language == language) return;
    _languageRevision += 1;
    setState(() => _language = language);
    unawaited(_preferencesStore.saveLanguage(language));
  }

  Future<void> _restoreLanguage() async {
    final revision = _languageRevision;
    final language = await _preferencesStore.loadLanguage();
    if (!mounted ||
        revision != _languageRevision ||
        language == null ||
        language == _language) {
      return;
    }
    setState(() => _language = language);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.forLanguage(_language);

    return _AppLanguageScope(
      language: _language,
      strings: strings,
      child: MaterialApp(
        title: strings.appTitle,
        debugShowCheckedModeBanner: false,
        navigatorObservers: [_analyticsObserver],
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF2563EB),
            brightness: Brightness.light,
          ),
          scaffoldBackgroundColor: const Color(0xFFF7F8FA),
          useMaterial3: true,
        ),
        home: ChatScreen(
          language: _language,
          onLanguageChanged: _setLanguage,
          chatClientFactory: widget.chatClientFactory,
          configStore: _configStore,
          updateService: widget.updateService ?? PgyerDemoUpdateService(),
          feedbackService:
              widget.feedbackService ?? ConfigurableDemoFeedbackService(),
          terminalBackendFactory: widget.terminalBackendFactory,
        ),
      ),
    );
  }
}
