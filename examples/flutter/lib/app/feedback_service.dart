part of '../main.dart';

class DemoFeedbackRequest {
  const DemoFeedbackRequest({
    required this.content,
    required this.contact,
    required this.appVersion,
    required this.language,
  });

  final String content;
  final String contact;
  final DemoAppVersion appVersion;
  final AppLanguage language;

  Map<String, dynamic> toJson() {
    return {
      'content': content,
      if (contact.isNotEmpty) 'contact': contact,
      'appVersion': appVersion.display,
      'platform': Platform.operatingSystem,
      'osVersion': Platform.operatingSystemVersion,
      'language': language.code,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
  }

  String toShareText(AppStrings strings) {
    final buffer = StringBuffer()
      ..writeln(strings.feedbackShareTitle)
      ..writeln()
      ..writeln(content)
      ..writeln()
      ..writeln('${strings.currentVersion}: ${appVersion.display}')
      ..writeln('Platform: ${Platform.operatingSystem}');
    if (contact.isNotEmpty) {
      buffer.writeln('${strings.feedbackContactLabel}: $contact');
    }
    return buffer.toString();
  }
}

class DemoFeedbackResult {
  const DemoFeedbackResult({required this.success, this.message});

  final bool success;
  final String? message;
}

abstract class DemoFeedbackService {
  Future<DemoFeedbackResult> submit(
    DemoFeedbackRequest request,
    AppStrings strings,
  );
}

class ConfigurableDemoFeedbackService implements DemoFeedbackService {
  ConfigurableDemoFeedbackService({http.Client? client}) : _client = client;

  static const _endpoint = String.fromEnvironment('FEEDBACK_ENDPOINT');

  http.Client? _client;

  @override
  Future<DemoFeedbackResult> submit(
    DemoFeedbackRequest request,
    AppStrings strings,
  ) async {
    if (_endpoint.isEmpty) {
      await share.Share.share(
        request.toShareText(strings),
        subject: strings.feedbackShareTitle,
      );
      return const DemoFeedbackResult(success: true);
    }

    final response = await _loadClient().post(
      Uri.parse(_endpoint),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(request.toJson()),
    ).timeout(
      const Duration(seconds: 12),
      onTimeout: () => http.Response('Feedback request timed out.', 408),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return DemoFeedbackResult(
        success: false,
        message: response.body.trim().isEmpty
            ? 'HTTP ${response.statusCode}'
            : response.body.trim(),
      );
    }
    return const DemoFeedbackResult(success: true);
  }

  http.Client _loadClient() {
    return _client ??= http.Client();
  }
}
