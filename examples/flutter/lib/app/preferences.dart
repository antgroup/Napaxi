part of '../main.dart';

abstract class DemoPreferencesStore {
  Future<AppLanguage?> loadLanguage();

  Future<void> saveLanguage(AppLanguage language);
}

class SharedPreferencesDemoPreferencesStore implements DemoPreferencesStore {
  static const _languageKey = 'napaxi.demo.language.v1';

  @override
  Future<AppLanguage?> loadLanguage() async {
    final preferences = await SharedPreferences.getInstance();
    final code = preferences.getString(_languageKey);
    return _languageFromCode(code);
  }

  @override
  Future<void> saveLanguage(AppLanguage language) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_languageKey, language.code);
  }
}

class MemoryDemoPreferencesStore implements DemoPreferencesStore {
  AppLanguage? _language;

  @override
  Future<AppLanguage?> loadLanguage() async => _language;

  @override
  Future<void> saveLanguage(AppLanguage language) async {
    _language = language;
  }
}

AppLanguage? _languageFromCode(String? code) {
  if (code == null) return null;
  for (final language in AppLanguage.values) {
    if (language.code == code) return language;
  }
  return null;
}
