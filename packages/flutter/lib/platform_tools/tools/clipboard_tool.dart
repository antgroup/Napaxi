import 'dart:convert';

import 'package:flutter/services.dart';

/// Platform tool that reads from and writes to the system clipboard.
class ClipboardTool {
  static Future<String> getClipboard(String paramsJson) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return jsonEncode({
      'text': data?.text ?? '',
      'has_content': data?.text != null && data!.text!.isNotEmpty,
    });
  }

  static Future<String> setClipboard(String paramsJson) async {
    final params = jsonDecode(paramsJson) as Map<String, dynamic>;
    final text = params['text'] as String? ?? '';
    await Clipboard.setData(ClipboardData(text: text));
    return jsonEncode({'success': true, 'copied_length': text.length});
  }
}
