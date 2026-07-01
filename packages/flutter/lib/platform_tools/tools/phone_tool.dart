import 'dart:convert';

import 'package:url_launcher/url_launcher.dart';

/// Platform tool that initiates a phone call or SMS via the system dialer.
class PhoneTool {
  static Future<String> makeCall(String paramsJson) async {
    final params = jsonDecode(paramsJson) as Map<String, dynamic>;
    final number = params['phone_number'] as String? ?? '';
    if (number.isEmpty) {
      return jsonEncode({'success': false, 'error': 'phone_number is required'});
    }
    final uri = Uri(scheme: 'tel', path: number);
    final launched = await launchUrl(uri);
    return jsonEncode({'success': launched, 'phone_number': number});
  }

  static Future<String> sendSms(String paramsJson) async {
    final params = jsonDecode(paramsJson) as Map<String, dynamic>;
    final number = params['phone_number'] as String? ?? '';
    if (number.isEmpty) {
      return jsonEncode({'success': false, 'error': 'phone_number is required'});
    }
    final body = params['body'] as String?;
    final uri = Uri(
      scheme: 'sms',
      path: number,
      queryParameters: body != null ? {'body': body} : null,
    );
    final launched = await launchUrl(uri);
    return jsonEncode({'success': launched, 'phone_number': number});
  }
}
