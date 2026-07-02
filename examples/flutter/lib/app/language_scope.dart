part of '../main.dart';

enum AppLanguage {
  english('en', 'English'),
  chinese('zh', '中文');

  const AppLanguage(this.code, this.label);

  final String code;
  final String label;
}

class _AppLanguageScope extends InheritedWidget {
  const _AppLanguageScope({
    required this.language,
    required this.strings,
    required super.child,
  });

  final AppLanguage language;
  final AppStrings strings;

  static AppStrings stringsOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_AppLanguageScope>()!
        .strings;
  }

  static AppLanguage languageOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_AppLanguageScope>()!
        .language;
  }

  @override
  bool updateShouldNotify(_AppLanguageScope oldWidget) {
    return language != oldWidget.language;
  }
}
