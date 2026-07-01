import 'dart:convert';

/// 群组信息
class GroupInfo {
  final String id;
  final String name;
  final List<String> members;
  final String coordinator;
  final String createdAt;
  final int messageCount;
  final String? lastMessagePreview;
  final String? lastMessageTime;
  final String? customPrompt;

  const GroupInfo({
    required this.id,
    required this.name,
    this.members = const [],
    this.coordinator = 'napaxi',
    this.createdAt = '',
    this.messageCount = 0,
    this.lastMessagePreview,
    this.lastMessageTime,
    this.customPrompt,
  });

  factory GroupInfo.fromMap(Map<String, dynamic> map) {
    return GroupInfo(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      members: (map['members'] as List?)?.cast<String>() ?? [],
      coordinator: map['coordinator'] as String? ?? 'napaxi',
      createdAt: map['created_at'] as String? ?? '',
      messageCount: map['message_count'] as int? ?? 0,
      lastMessagePreview: map['last_message_preview'] as String?,
      lastMessageTime: map['last_message_time'] as String?,
      customPrompt: map['custom_prompt'] as String?,
    );
  }

  factory GroupInfo.fromJson(String jsonStr) {
    return GroupInfo.fromMap(jsonDecode(jsonStr) as Map<String, dynamic>);
  }

  @override
  String toString() => 'GroupInfo($id: $name, ${members.length} members)';
}

/// 群组消息
class GroupMessage {
  final String id;
  final String groupId;
  final String sender;
  final String content;
  final GroupMessageType messageType;
  final String timestamp;
  final String? toolCallId;
  final String? toolName;
  final String? targetAgent;

  const GroupMessage({
    required this.id,
    required this.groupId,
    required this.sender,
    required this.content,
    this.messageType = GroupMessageType.text,
    this.timestamp = '',
    this.toolCallId,
    this.toolName,
    this.targetAgent,
  });

  factory GroupMessage.fromMap(Map<String, dynamic> map) {
    return GroupMessage(
      id: map['id'] as String? ?? '',
      groupId: map['group_id'] as String? ?? '',
      sender: map['sender'] as String? ?? '',
      content: map['content'] as String? ?? '',
      messageType: GroupMessageType.fromString(map['type'] as String? ?? 'text'),
      timestamp: map['timestamp'] as String? ?? '',
      toolCallId: map['tool_call_id'] as String?,
      toolName: map['tool_name'] as String?,
      targetAgent: map['target_agent'] as String?,
    );
  }

  bool get isUser => sender == 'user';
  bool get isSystem => sender == 'system';
  bool get isDelegation => targetAgent != null;

  @override
  String toString() => 'GroupMessage($sender: ${content.length > 50 ? '${content.substring(0, 50)}...' : content})';
}

/// 群组消息类型
enum GroupMessageType {
  text,
  toolCall,
  toolResult,
  system;

  static GroupMessageType fromString(String s) {
    return switch (s) {
      'tool_call' => GroupMessageType.toolCall,
      'tool_result' => GroupMessageType.toolResult,
      'system' => GroupMessageType.system,
      _ => GroupMessageType.text,
    };
  }
}
