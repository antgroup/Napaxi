import 'package:flutter_test/flutter_test.dart';
import 'package:napaxi_flutter/napaxi_flutter.dart';

/// `GroupInfo` and `GroupMessage` are decoded from JSON the Rust group runtime
/// produces (over the bridge and persisted thread state). Their `fromMap`
/// factories are defensive — every field has a default — so a renamed key fails
/// silently by falling back to a default rather than throwing. These tests pin
/// the snake_case wire keys and the `GroupMessageType` discriminant mapping so
/// such a drift is caught here.
void main() {
  group('GroupInfo.fromMap', () {
    test('decodes a fully populated group', () {
      final info = GroupInfo.fromMap({
        'id': 'g1',
        'name': 'Research',
        'members': ['alice', 'bob'],
        'coordinator': 'lead',
        'created_at': '2026-06-02T00:00:00Z',
        'message_count': 42,
        'last_message_preview': 'see you tomorrow',
        'last_message_time': '2026-06-02T11:00:00Z',
        'custom_prompt': 'be concise',
      });
      expect(info.id, 'g1');
      expect(info.name, 'Research');
      expect(info.members, ['alice', 'bob']);
      expect(info.coordinator, 'lead');
      expect(info.createdAt, '2026-06-02T00:00:00Z');
      expect(info.messageCount, 42);
      expect(info.lastMessagePreview, 'see you tomorrow');
      expect(info.lastMessageTime, '2026-06-02T11:00:00Z');
      expect(info.customPrompt, 'be concise');
    });

    test('applies defaults for a minimal payload', () {
      final info = GroupInfo.fromMap({'id': 'g1', 'name': 'Solo'});
      expect(info.members, isEmpty);
      // Default coordinator is the runtime name, not empty.
      expect(info.coordinator, 'napaxi');
      expect(info.messageCount, 0);
      expect(info.lastMessagePreview, isNull);
      expect(info.customPrompt, isNull);
    });

    test('round-trips through fromJson', () {
      final info = GroupInfo.fromJson(
        '{"id":"g2","name":"FromJson","members":["x"],"message_count":3}',
      );
      expect(info.id, 'g2');
      expect(info.name, 'FromJson');
      expect(info.members, ['x']);
      expect(info.messageCount, 3);
    });
  });

  group('GroupMessage.fromMap', () {
    test('decodes a tool-call delegation message', () {
      final msg = GroupMessage.fromMap({
        'id': 'm1',
        'group_id': 'g1',
        'sender': 'lead',
        'content': 'delegating',
        'type': 'tool_call',
        'timestamp': '2026-06-02T10:00:00Z',
        'tool_call_id': 'tc1',
        'tool_name': 'delegate',
        'target_agent': 'helper',
      });
      expect(msg.id, 'm1');
      expect(msg.groupId, 'g1');
      expect(msg.sender, 'lead');
      expect(msg.messageType, GroupMessageType.toolCall);
      expect(msg.toolCallId, 'tc1');
      expect(msg.toolName, 'delegate');
      expect(msg.targetAgent, 'helper');
      // A message with a target agent is a delegation.
      expect(msg.isDelegation, isTrue);
    });

    test('classifies user and system senders', () {
      final user = GroupMessage.fromMap({'sender': 'user', 'content': 'hi'});
      expect(user.isUser, isTrue);
      expect(user.isSystem, isFalse);
      expect(user.messageType, GroupMessageType.text);

      final system = GroupMessage.fromMap({'sender': 'system', 'content': 'x'});
      expect(system.isSystem, isTrue);
      expect(system.isDelegation, isFalse);
    });
  });

  group('GroupMessageType.fromString', () {
    test('maps known snake_case discriminants', () {
      expect(GroupMessageType.fromString('tool_call'), GroupMessageType.toolCall);
      expect(
          GroupMessageType.fromString('tool_result'), GroupMessageType.toolResult);
      expect(GroupMessageType.fromString('system'), GroupMessageType.system);
      expect(GroupMessageType.fromString('text'), GroupMessageType.text);
    });

    test('falls back to text for unknown values', () {
      expect(GroupMessageType.fromString('mystery'), GroupMessageType.text);
    });
  });
}
