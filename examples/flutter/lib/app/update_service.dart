part of '../main.dart';

String _pgyerString(Object? value) {
  return value?.toString() ?? '';
}

int? _pgyerInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

bool _pgyerBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }
  return false;
}

class DemoAppVersion {
  const DemoAppVersion({required this.version, required this.buildNumber});

  final String version;
  final String buildNumber;

  String get display => buildNumber.isEmpty ? version : '$version+$buildNumber';
}

class DemoUpdateInfo {
  const DemoUpdateInfo({
    required this.buildKey,
    required this.buildVersion,
    required this.buildVersionNo,
    required this.buildBuildVersion,
    required this.needForceUpdate,
    required this.downloadUrl,
    required this.appUrl,
    required this.updateDescription,
    required this.fileSizeBytes,
  });

  factory DemoUpdateInfo.fromMap(Map<String, dynamic> map) {
    return DemoUpdateInfo(
      buildKey: _pgyerString(map['buildKey']),
      buildVersion: _pgyerString(map['buildVersion']),
      buildVersionNo: _pgyerString(map['buildVersionNo']),
      buildBuildVersion: _pgyerInt(map['buildBuildVersion']),
      needForceUpdate: _pgyerBool(map['needForceUpdate']),
      downloadUrl: _pgyerString(map['downloadURL']),
      appUrl: _pgyerString(map['appURl'] ?? map['appURL']),
      updateDescription: _pgyerString(map['buildUpdateDescription']),
      fileSizeBytes: _pgyerInt(map['buildFileSize']),
    );
  }

  final String buildKey;
  final String buildVersion;
  final String buildVersionNo;
  final int? buildBuildVersion;
  final bool needForceUpdate;
  final String downloadUrl;
  final String appUrl;
  final String updateDescription;
  final int? fileSizeBytes;

  String get identity {
    if (buildKey.isNotEmpty) return buildKey;
    return [
      buildVersion,
      buildVersionNo,
      if (buildBuildVersion != null) buildBuildVersion.toString(),
    ].where((part) => part.isNotEmpty).join(':');
  }
}

class DemoUpdateCheckResult {
  const DemoUpdateCheckResult({
    required this.currentVersion,
    this.update,
    this.message,
    this.skipped = false,
    this.unconfigured = false,
    this.unsupported = false,
  });

  final DemoAppVersion currentVersion;
  final DemoUpdateInfo? update;
  final String? message;
  final bool skipped;
  final bool unconfigured;
  final bool unsupported;

  bool get hasUpdate => update != null;
}

class DemoUpdateInstallResult {
  const DemoUpdateInstallResult({
    required this.success,
    this.permissionRequired = false,
    this.installerOpened = false,
    this.message,
  });

  final bool success;
  final bool permissionRequired;
  final bool installerOpened;
  final String? message;
}

abstract class DemoUpdateService {
  bool get supportsUpdateCheck;
  bool get supportsExternalUpdatePage;

  Future<DemoAppVersion> currentVersion();

  Future<DemoUpdateCheckResult> checkForUpdate({
    required bool respectSkippedVersion,
  });

  Future<void> skipUpdate(DemoUpdateInfo update);

  Future<DemoUpdateInstallResult> downloadAndInstall(
    DemoUpdateInfo update, {
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  });

  Future<bool> openInstallPage(DemoUpdateInfo update);
  Future<bool> openExternalUpdatePage();
}

class PgyerDemoUpdateService implements DemoUpdateService {
  PgyerDemoUpdateService({http.Client? client, SharedPreferences? preferences})
    : _client = client,
      _preferences = preferences;

  static const _apiKey = String.fromEnvironment('PGYER_API_KEY');
  static const _appKey = String.fromEnvironment('PGYER_APP_KEY');
  static const _channelKey = String.fromEnvironment('PGYER_CHANNEL_KEY');
  static const _buildPassword = String.fromEnvironment('PGYER_BUILD_PASSWORD');
  static const _githubReleasesUrl = String.fromEnvironment(
    'GITHUB_RELEASES_URL',
    defaultValue: 'https://github.com/antgroup/Napaxi/releases',
  );
  static const _skippedBuildKey = 'napaxi.pgyer.skipped_build_key.v1';
  static const _requestTimeout = Duration(seconds: 15);
  static const _downloadChunkTimeout = Duration(seconds: 15);
  static final _checkUri = Uri.parse('https://www.pgyer.com/apiv2/app/check');

  http.Client? _client;
  SharedPreferences? _preferences;
  DemoAppVersion? _cachedVersion;

  bool get _isConfigured => _apiKey.isNotEmpty && _appKey.isNotEmpty;

  @override
  bool get supportsUpdateCheck => Platform.isAndroid;

  @override
  bool get supportsExternalUpdatePage =>
      Platform.isAndroid && _externalUpdateUri != null;

  @override
  Future<DemoAppVersion> currentVersion() async {
    final cached = _cachedVersion;
    if (cached != null) return cached;
    final info = await PackageInfo.fromPlatform();
    return _cachedVersion = DemoAppVersion(
      version: info.version,
      buildNumber: info.buildNumber,
    );
  }

  @override
  Future<DemoUpdateCheckResult> checkForUpdate({
    required bool respectSkippedVersion,
  }) async {
    final version = await currentVersion();
    if (!Platform.isAndroid) {
      return DemoUpdateCheckResult(
        currentVersion: version,
        unsupported: true,
        message: 'Update checking is only supported on Android.',
      );
    }
    if (!_isConfigured) {
      return DemoUpdateCheckResult(
        currentVersion: version,
        unconfigured: true,
        message: 'Pgyer update checking is not configured.',
      );
    }

    final buildNumber = int.tryParse(version.buildNumber);
    final body = <String, String>{
      '_api_key': _apiKey,
      'appKey': _appKey,
      'buildVersion': version.version,
      if (buildNumber != null) 'buildBuildVersion': buildNumber.toString(),
      if (_channelKey.isNotEmpty) 'channelKey': _channelKey,
    };
    final response = await _loadClient()
        .post(
          _checkUri,
          headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
          body: body,
        )
        .timeout(
          _requestTimeout,
          onTimeout: () => http.Response('Pgyer check timed out.', 408),
        );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Pgyer check failed with HTTP ${response.statusCode}.');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final code = _pgyerInt(decoded['code']) ?? -1;
    if (code != 0) {
      final message = decoded['message']?.toString() ?? 'Unknown Pgyer error';
      throw StateError(message);
    }
    final data = decoded['data'] as Map<String, dynamic>? ?? const {};
    final hasNewVersion = _pgyerBool(data['buildHaveNewVersion']);
    if (!hasNewVersion) {
      return DemoUpdateCheckResult(currentVersion: version);
    }

    final update = DemoUpdateInfo.fromMap(data);
    if (respectSkippedVersion &&
        !update.needForceUpdate &&
        update.identity.isNotEmpty &&
        await _loadSkippedBuildKey() == update.identity) {
      return DemoUpdateCheckResult(
        currentVersion: version,
        update: update,
        skipped: true,
      );
    }
    return DemoUpdateCheckResult(currentVersion: version, update: update);
  }

  @override
  Future<void> skipUpdate(DemoUpdateInfo update) async {
    if (update.needForceUpdate || update.identity.isEmpty) return;
    final preferences = await _loadPreferences();
    await preferences.setString(_skippedBuildKey, update.identity);
  }

  @override
  Future<DemoUpdateInstallResult> downloadAndInstall(
    DemoUpdateInfo update, {
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  }) async {
    if (update.downloadUrl.isEmpty) {
      return const DemoUpdateInstallResult(
        success: false,
        message: 'Pgyer did not return an APK download URL.',
      );
    }

    final uri = Uri.parse(_appendBuildPassword(update.downloadUrl));
    final request = http.Request('GET', uri)..followRedirects = true;
    late final http.StreamedResponse response;
    try {
      response = await _loadClient().send(request).timeout(_requestTimeout);
    } on TimeoutException {
      return const DemoUpdateInstallResult(
        success: false,
        message: 'APK download request timed out.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return DemoUpdateInstallResult(
        success: false,
        message: 'Download failed with HTTP ${response.statusCode}.',
      );
    }

    final tempDir = await getTemporaryDirectory();
    final filename = update.identity.isEmpty ? 'latest' : update.identity;
    final apkFile = File('${tempDir.path}/napaxi-update-$filename.apk');
    final sink = apkFile.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream.timeout(
        _downloadChunkTimeout,
      )) {
        received += chunk.length;
        sink.add(chunk);
        onProgress?.call(received, response.contentLength);
      }
    } on TimeoutException {
      return const DemoUpdateInstallResult(
        success: false,
        message: 'APK download timed out.',
      );
    } finally {
      await sink.close();
    }

    if (received == 0) {
      return const DemoUpdateInstallResult(
        success: false,
        message: 'Downloaded APK was empty.',
      );
    }
    final header = await apkFile.openRead(0, 2).first;
    if (header.length < 2 || header[0] != 0x50 || header[1] != 0x4B) {
      return const DemoUpdateInstallResult(
        success: false,
        message: 'Downloaded file is not a valid APK.',
      );
    }

    final result = await sdk.NapaxiApkInstaller.installApk(apkFile.path);
    return DemoUpdateInstallResult(
      success: result.success,
      installerOpened: result.installerOpened,
      permissionRequired: result.permissionRequired,
      message: result.error,
    );
  }

  @override
  Future<bool> openInstallPage(DemoUpdateInfo update) async {
    if (update.appUrl.isEmpty) return false;
    try {
      return await launchUrl(
        Uri.parse(_appendBuildPassword(update.appUrl)),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> openExternalUpdatePage() async {
    final uri = _externalUpdateUri;
    if (uri == null) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  Future<String?> _loadSkippedBuildKey() async {
    final preferences = await _loadPreferences();
    return preferences.getString(_skippedBuildKey);
  }

  Future<SharedPreferences> _loadPreferences() async {
    final loaded = _preferences;
    if (loaded != null) return loaded;
    final preferences = await SharedPreferences.getInstance();
    _preferences = preferences;
    return preferences;
  }

  http.Client _loadClient() {
    return _client ??= http.Client();
  }

  String _appendBuildPassword(String url) {
    if (_buildPassword.isEmpty) return url;
    final uri = Uri.parse(url);
    if (uri.queryParameters.containsKey('buildPassword')) return url;
    return uri
        .replace(
          queryParameters: {
            ...uri.queryParameters,
            'buildPassword': _buildPassword,
          },
        )
        .toString();
  }

  Uri? get _externalUpdateUri {
    final trimmed = _githubReleasesUrl.trim();
    if (trimmed.isEmpty) return null;
    return Uri.tryParse(trimmed);
  }
}
