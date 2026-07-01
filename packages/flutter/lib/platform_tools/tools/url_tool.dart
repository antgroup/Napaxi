import 'dart:convert';

import 'package:url_launcher/url_launcher.dart';

/// Platform tool that opens a URL in the system browser or default handler.
class UrlTool {
  static Future<String> execute(String paramsJson) async {
    final params = jsonDecode(paramsJson) as Map<String, dynamic>;
    final urlStr = params['url'] as String? ?? '';
    final uri = Uri.tryParse(urlStr);
    if (uri == null) {
      return jsonEncode({'success': false, 'error': 'Invalid URL: $urlStr'});
    }
    final launched =
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    return jsonEncode({'success': launched, 'url': urlStr});
  }
}
