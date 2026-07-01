import 'dart:convert';

import 'package:flutter_contacts/flutter_contacts.dart';

/// Platform tool that searches and reads the device's contacts.
class ContactsTool {
  static Future<String> execute(String paramsJson) async {
    final params = jsonDecode(paramsJson) as Map<String, dynamic>;
    final query = params['query'] as String?;
    final limit = (params['limit'] as int?) ?? 20;

    final status =
        await FlutterContacts.permissions.request(PermissionType.read);
    if (status != PermissionStatus.granted &&
        status != PermissionStatus.limited) {
      return jsonEncode({'error': 'Contacts permission denied by user.'});
    }

    List<Contact> contacts;
    if (query != null && query.isNotEmpty) {
      contacts = await FlutterContacts.getAll(
        properties: {ContactProperty.phone, ContactProperty.email},
        filter: ContactFilter.name(query),
        limit: limit,
      );
    } else {
      contacts = await FlutterContacts.getAll(
        properties: {ContactProperty.phone, ContactProperty.email},
        limit: limit,
      );
    }

    final result = contacts.map((c) => {
      'name': c.displayName ?? '',
      'phones': c.phones.map((p) => p.number).toList(),
      'emails': c.emails.map((e) => e.address).toList(),
    }).toList();

    return jsonEncode({'contacts': result, 'total': result.length});
  }
}
