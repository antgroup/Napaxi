import 'dart:convert';

/// AI Agent 事件（与 Rust ChatEvent 一一对应）
sealed class ChatEvent {
  const ChatEvent();

  /// 从 JSON 字符串解析事件
  factory ChatEvent.fromJsonString(String jsonStr) {
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    return ChatEvent.fromMap(map);
  }

  /// 从 Map 解析事件
  factory ChatEvent.fromMap(Map<String, dynamic> map) {
    final type = map['type'] as String;
    return switch (type) {
      'run_started' => RunStartedEvent(
          runId: map['run_id'] as String,
          sessionKey: map['session_key'] as String,
          agentId: map['agent_id'] as String,
        ),
      'run_progress' => RunProgressEvent(
          runId: map['run_id'] as String,
          kind: map['kind'] as String,
          message: map['message'] as String,
        ),
      'run_completed' => RunCompletedEvent(
          runId: map['run_id'] as String,
          status: map['status'] as String,
          evidenceKind: map['evidence_kind'] as String,
          verification: map['verification'] as String,
          toolCallCount: map['tool_call_count'] as int? ?? 0,
        ),
      'tool_call' => ToolCallEvent(
          callId: map['call_id'] as String,
          name: map['name'] as String,
          arguments: map['arguments'] as String,
        ),
      'tool_call_delta' => ToolCallDeltaEvent(
          callId: map['call_id'] as String,
          name: map['name'] as String,
          argumentsDelta: map['arguments_delta'] as String,
          argumentsSoFar: map['arguments_so_far'] as String,
        ),
      'tool_result' => ToolResultEvent(
          callId: map['call_id'] as String,
          name: map['name'] as String,
          output: map['output'] as String,
          isError: map['is_error'] as bool,
        ),
      'response' => ResponseEvent(
          content: map['content'] as String,
        ),
      'response_delta' => ResponseDeltaEvent(
          content: map['content'] as String,
        ),
      'reasoning_delta' => ReasoningDeltaEvent(
          content: map['content'] as String,
        ),
      'thinking' => ThinkingEvent(
          content: map['content'] as String,
        ),
      'error' => ErrorEvent(
          message: map['message'] as String,
        ),
      'agent_delegation' => AgentDelegationEvent(
          fromAgent: map['from_agent'] as String,
          toAgent: map['to_agent'] as String,
          message: map['message'] as String,
        ),
      'agent_delegation_result' => AgentDelegationResultEvent(
          fromAgent: map['from_agent'] as String,
          toAgent: map['to_agent'] as String,
          content: map['content'] as String,
          isError: map['is_error'] as bool,
        ),
      'agent_tool_call' => AgentToolCallEvent(
          callId: map['call_id'] as String,
          name: map['name'] as String,
          arguments: map['arguments'] as String,
          agentId: map['agent_id'] as String,
        ),
      'agent_tool_call_delta' => AgentToolCallDeltaEvent(
          callId: map['call_id'] as String,
          name: map['name'] as String,
          argumentsDelta: map['arguments_delta'] as String,
          argumentsSoFar: map['arguments_so_far'] as String,
          agentId: map['agent_id'] as String,
        ),
      'agent_tool_result' => AgentToolResultEvent(
          callId: map['call_id'] as String,
          name: map['name'] as String,
          output: map['output'] as String,
          isError: map['is_error'] as bool,
          agentId: map['agent_id'] as String,
        ),
      'group_delegation' => GroupDelegationEvent(
          groupId: map['group_id'] as String,
          fromAgent: map['from_agent'] as String,
          toAgent: map['to_agent'] as String,
          task: map['task'] as String,
        ),
      'group_delegation_result' => GroupDelegationResultEvent(
          groupId: map['group_id'] as String,
          fromAgent: map['from_agent'] as String,
          toAgent: map['to_agent'] as String,
          result: map['result'] as String,
          isError: map['is_error'] as bool,
        ),
      'image_generated' => ImageGeneratedEvent(
          dataUrl: map['data_url'] as String,
          path: map['path'] as String?,
        ),
      'tool_output_chunk' => ToolOutputChunkEvent(
          callId: map['call_id'] as String,
          content: map['content'] as String,
          stream: map['stream'] as String,
        ),
      'message_injected' => MessageInjectedEvent(
          content: map['content'] as String,
        ),
      'asking_human' => AskingHumanEvent(
          question: map['question'] as String,
          requestId: map['request_id'] as String,
          options: (map['options'] as List?)?.cast<String>() ?? [],
          context: map['context'] as String?,
        ),
      'human_response' => HumanResponseEvent(
          requestId: map['request_id'] as String,
          response: map['response'] as String,
        ),
      'stream_reset' => StreamResetEvent(
          reason: map['reason'] as String? ?? '',
        ),
      'context_compacting' => ContextCompactingEvent(
          usagePercent: (map['usage_percent'] as num).toDouble(),
          strategy: map['strategy'] as String,
        ),
      'context_compacted' => ContextCompactedEvent(
          turnsRemoved: map['turns_removed'] as int,
          tokensBefore: map['tokens_before'] as int,
          tokensAfter: map['tokens_after'] as int,
        ),
      'memory_evolved' => MemoryEvolvedEvent(
          target: map['target'] as String,
          content: map['content'] as String,
        ),
      'skill_evolved' => SkillEvolvedEvent(
          skillName: map['skill_name'] as String,
          action: map['action'] as String,
          summary: map['summary'] as String,
        ),
      'evolution_queued' => EvolutionQueuedEvent(
          reviewTypes: (map['review_types'] as List?)?.cast<String>() ?? [],
          runs: (map['runs'] as List?)
                  ?.whereType<Map>()
                  .map((item) => EvolutionQueuedRun.fromMap(item))
                  .toList(growable: false) ??
              const [],
        ),
      'skill_activated' => SkillActivatedEvent(
          agentId: map['agent_id'] as String? ?? '',
          skills: (map['skills'] as List?)
                  ?.whereType<Map>()
                  .map((item) => ActivatedSkillInfo.fromMap(item))
                  .toList(growable: false) ??
              const [],
        ),
      'action_proposal_created' => ActionProposalCreatedEvent(
          requestId: map['request_id'] as String,
          providerId: map['provider_id'] as String,
          agentId: map['agent_id'] as String,
          actionId: map['action_id'] as String,
          toolName: map['tool_name'] as String,
          risk: map['risk'] as String,
          expiresAt: map['expires_at'] as String,
        ),
      'action_handoff_started' => ActionHandoffStartedEvent(
          requestId: map['request_id'] as String,
          mode: map['mode'] as String,
        ),
      'action_waiting_for_provider' => ActionWaitingForProviderEvent(
          requestId: map['request_id'] as String,
          providerId: map['provider_id'] as String,
        ),
      'action_result_received' => ActionResultReceivedEvent(
          requestId: map['request_id'] as String,
          status: map['status'] as String,
          providerTraceId: map['provider_trace_id'] as String?,
        ),
      'action_expired' => ActionExpiredEvent(
          requestId: map['request_id'] as String,
        ),
      'action_failed' => ActionFailedEvent(
          requestId: map['request_id'] as String,
          message: map['message'] as String,
        ),
      'interrupted' => const InterruptedEvent(),
      _ => ErrorEvent(message: 'Unknown event type: $type'),
    };
  }
}

/// 一次对话轮（run）开始
class RunStartedEvent extends ChatEvent {
  final String runId;
  final String sessionKey;
  final String agentId;
  const RunStartedEvent({
    required this.runId,
    required this.sessionKey,
    required this.agentId,
  });
}

/// 对话轮进度更新（携带阶段 [kind] 与人类可读的 [message]）
class RunProgressEvent extends ChatEvent {
  final String runId;
  final String kind;
  final String message;
  const RunProgressEvent({
    required this.runId,
    required this.kind,
    required this.message,
  });
}

/// 对话轮结束，携带最终状态、证据/校验信息及本轮工具调用次数
class RunCompletedEvent extends ChatEvent {
  final String runId;
  final String status;
  final String evidenceKind;
  final String verification;
  final int toolCallCount;
  const RunCompletedEvent({
    required this.runId,
    required this.status,
    required this.evidenceKind,
    required this.verification,
    this.toolCallCount = 0,
  });

  /// 本轮结果是否未经校验
  bool get isUnverified =>
      status == 'unverified' || verification == 'unverified';
}

/// 工具调用中
class ToolCallEvent extends ChatEvent {
  final String callId;
  final String name;
  final String arguments;
  const ToolCallEvent(
      {required this.callId, required this.name, required this.arguments});
}

/// 工具调用参数的流式片段
class ToolCallDeltaEvent extends ChatEvent {
  final String callId;
  final String name;
  final String argumentsDelta;
  final String argumentsSoFar;
  const ToolCallDeltaEvent({
    required this.callId,
    required this.name,
    required this.argumentsDelta,
    required this.argumentsSoFar,
  });
}

/// 工具调用结果
class ToolResultEvent extends ChatEvent {
  final String callId;
  final String name;
  final String output;
  final bool isError;
  const ToolResultEvent(
      {required this.callId,
      required this.name,
      required this.output,
      required this.isError});
}

/// 最终文本回复
class ResponseEvent extends ChatEvent {
  final String content;
  const ResponseEvent({required this.content});
}

/// 最终文本回复的增量片段
class ResponseDeltaEvent extends ChatEvent {
  final String content;
  const ResponseDeltaEvent({required this.content});
}

/// LLM 思考/推理内容的增量片段
class ReasoningDeltaEvent extends ChatEvent {
  final String content;
  const ReasoningDeltaEvent({required this.content});
}

/// LLM 思考/推理内容
class ThinkingEvent extends ChatEvent {
  final String content;
  const ThinkingEvent({required this.content});
}

/// 错误
class ErrorEvent extends ChatEvent {
  final String message;
  const ErrorEvent({required this.message});
}

/// Agent 委托任务给另一个 Agent
class AgentDelegationEvent extends ChatEvent {
  final String fromAgent;
  final String toAgent;
  final String message;
  const AgentDelegationEvent(
      {required this.fromAgent, required this.toAgent, required this.message});
}

/// Agent 委托结果
class AgentDelegationResultEvent extends ChatEvent {
  final String fromAgent;
  final String toAgent;
  final String content;
  final bool isError;
  const AgentDelegationResultEvent(
      {required this.fromAgent,
      required this.toAgent,
      required this.content,
      required this.isError});
}

/// 委托 Agent 的工具调用
class AgentToolCallEvent extends ChatEvent {
  final String callId;
  final String name;
  final String arguments;
  final String agentId;
  const AgentToolCallEvent(
      {required this.callId,
      required this.name,
      required this.arguments,
      required this.agentId});
}

/// 委托 Agent 的工具调用参数流式片段
class AgentToolCallDeltaEvent extends ChatEvent {
  final String callId;
  final String name;
  final String argumentsDelta;
  final String argumentsSoFar;
  final String agentId;
  const AgentToolCallDeltaEvent({
    required this.callId,
    required this.name,
    required this.argumentsDelta,
    required this.argumentsSoFar,
    required this.agentId,
  });
}

/// 委托 Agent 的工具结果
class AgentToolResultEvent extends ChatEvent {
  final String callId;
  final String name;
  final String output;
  final bool isError;
  final String agentId;
  const AgentToolResultEvent(
      {required this.callId,
      required this.name,
      required this.output,
      required this.isError,
      required this.agentId});
}

/// 群组内 Agent 委托
class GroupDelegationEvent extends ChatEvent {
  final String groupId;
  final String fromAgent;
  final String toAgent;
  final String task;
  const GroupDelegationEvent(
      {required this.groupId,
      required this.fromAgent,
      required this.toAgent,
      required this.task});
}

/// 群组内委托结果
class GroupDelegationResultEvent extends ChatEvent {
  final String groupId;
  final String fromAgent;
  final String toAgent;
  final String result;
  final bool isError;
  const GroupDelegationResultEvent(
      {required this.groupId,
      required this.fromAgent,
      required this.toAgent,
      required this.result,
      required this.isError});
}

/// 图片生成事件（由 image_generate / image_edit 工具触发）
class ImageGeneratedEvent extends ChatEvent {
  final String dataUrl;
  final String? path;
  const ImageGeneratedEvent({required this.dataUrl, this.path});
}

/// 工具执行过程中的流式输出块（如 shell 命令的 stdout/stderr）
class ToolOutputChunkEvent extends ChatEvent {
  final String callId;
  final String content;

  /// "stdout" 或 "stderr"
  final String stream;
  const ToolOutputChunkEvent(
      {required this.callId, required this.content, required this.stream});
}

/// 用户消息已注入到 Agent 上下文（HITL Phase 1）
class MessageInjectedEvent extends ChatEvent {
  final String content;
  const MessageInjectedEvent({required this.content});
}

/// Agent 正在向用户提问（HITL Phase 2）
class AskingHumanEvent extends ChatEvent {
  final String question;
  final String requestId;
  final List<String> options;
  final String? context;
  const AskingHumanEvent(
      {required this.question,
      required this.requestId,
      this.options = const [],
      this.context});
}

/// 用户已回答 Agent 的提问
class HumanResponseEvent extends ChatEvent {
  final String requestId;
  final String response;
  const HumanResponseEvent({required this.requestId, required this.response});
}

/// 进行中的 LLM 流连接断开或卡死，正在自动重连。UI 收到后应丢弃当前轮已流式
/// 显示的部分回复/推理内容，等待重连后的流重新填充。此时尚未产生任何历史副作用。
class StreamResetEvent extends ChatEvent {
  final String reason;
  const StreamResetEvent({required this.reason});
}

/// 上下文压缩正在进行（自动触发）
class ContextCompactingEvent extends ChatEvent {
  final double usagePercent;
  final String strategy;
  const ContextCompactingEvent(
      {required this.usagePercent, required this.strategy});
}

/// 上下文压缩完成
class ContextCompactedEvent extends ChatEvent {
  final int turnsRemoved;
  final int tokensBefore;
  final int tokensAfter;
  const ContextCompactedEvent(
      {required this.turnsRemoved,
      required this.tokensBefore,
      required this.tokensAfter});
}

/// 记忆进化：记忆文件被写入或更新
class MemoryEvolvedEvent extends ChatEvent {
  final String target;
  final String content;
  const MemoryEvolvedEvent({required this.target, required this.content});
}

/// 技能进化：技能文件被创建或更新
class SkillEvolvedEvent extends ChatEvent {
  final String skillName;
  final String action;
  final String summary;
  const SkillEvolvedEvent(
      {required this.skillName, required this.action, required this.summary});
}

/// 自进化复盘已进入后台队列
class EvolutionQueuedEvent extends ChatEvent {
  final List<String> reviewTypes;
  final List<EvolutionQueuedRun> runs;
  const EvolutionQueuedEvent({
    required this.reviewTypes,
    this.runs = const [],
  });

  List<String> get runIds => runs.map((run) => run.id).toList(growable: false);
}

/// 进化队列中单次复盘 run 的标识与类型
class EvolutionQueuedRun {
  final String id;
  final String reviewType;
  const EvolutionQueuedRun({required this.id, required this.reviewType});

  factory EvolutionQueuedRun.fromMap(Map<dynamic, dynamic> map) {
    return EvolutionQueuedRun(
      id: map['id'] as String,
      reviewType: map['review_type'] as String,
    );
  }
}

/// 一个被激活的技能的元信息（名称、版本、信任级别及激活原因）
class ActivatedSkillInfo {
  final String name;
  final String version;
  final String description;
  final String trust;
  final String reason;

  const ActivatedSkillInfo({
    required this.name,
    this.version = '',
    this.description = '',
    this.trust = '',
    this.reason = '',
  });

  factory ActivatedSkillInfo.fromMap(Map<dynamic, dynamic> map) {
    return ActivatedSkillInfo(
      name: map['name'] as String? ?? '',
      version: map['version'] as String? ?? '',
      description: map['description'] as String? ?? '',
      trust: map['trust'] as String? ?? '',
      reason: map['reason'] as String? ?? '',
    );
  }
}

/// Agent 为本轮激活了一组技能
class SkillActivatedEvent extends ChatEvent {
  final String agentId;
  final List<ActivatedSkillInfo> skills;

  const SkillActivatedEvent({
    required this.agentId,
    required this.skills,
  });
}

/// 已创建一个待处理的动作提案，需移交给 Provider 执行（含风险等级与过期时间）
class ActionProposalCreatedEvent extends ChatEvent {
  final String requestId;
  final String providerId;
  final String agentId;
  final String actionId;
  final String toolName;
  final String risk;
  final String expiresAt;

  const ActionProposalCreatedEvent({
    required this.requestId,
    required this.providerId,
    required this.agentId,
    required this.actionId,
    required this.toolName,
    required this.risk,
    required this.expiresAt,
  });
}

/// 动作移交流程已启动（[mode] 表示移交方式）
class ActionHandoffStartedEvent extends ChatEvent {
  final String requestId;
  final String mode;

  const ActionHandoffStartedEvent({
    required this.requestId,
    required this.mode,
  });
}

/// 正在等待指定 Provider 返回动作执行结果
class ActionWaitingForProviderEvent extends ChatEvent {
  final String requestId;
  final String providerId;

  const ActionWaitingForProviderEvent({
    required this.requestId,
    required this.providerId,
  });
}

/// 已收到 Provider 的动作执行结果（含状态及可选的 Provider 追踪 ID）
class ActionResultReceivedEvent extends ChatEvent {
  final String requestId;
  final String status;
  final String? providerTraceId;

  const ActionResultReceivedEvent({
    required this.requestId,
    required this.status,
    this.providerTraceId,
  });
}

/// 动作提案在被处理前已过期
class ActionExpiredEvent extends ChatEvent {
  final String requestId;

  const ActionExpiredEvent({required this.requestId});
}

/// 动作执行失败（携带失败原因 [message]）
class ActionFailedEvent extends ChatEvent {
  final String requestId;
  final String message;

  const ActionFailedEvent({
    required this.requestId,
    required this.message,
  });
}

/// 用户中断当前轮（点击暂停/停止）后由 Rust 发出的终止帧。
///
/// 与 `ErrorEvent` 区分：表示主动停止，不是失败。UI 收到后应将仍在 "运行中"
/// 的工具卡片翻成 "已取消"，并把整段会话状态标为 cancelled。
class InterruptedEvent extends ChatEvent {
  const InterruptedEvent();
}
