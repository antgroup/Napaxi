import 'dart:convert';

import 'capability.dart';

/// Per-turn scene prompt injection configuration.
class ScenePromptConfig {
  final bool enabled;
  final Map<String, String>? hostPolicies;

  const ScenePromptConfig({
    this.enabled = false,
    this.hostPolicies,
  });

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        if (hostPolicies != null) 'host_policies': hostPolicies,
      };

  factory ScenePromptConfig.fromMap(Map<String, dynamic> map) {
    return ScenePromptConfig(
      enabled: map['enabled'] as bool? ?? false,
      hostPolicies: (map['host_policies'] as Map?)
          ?.map((key, value) => MapEntry(key.toString(), value.toString())),
    );
  }
}

/// Long-session context compaction configuration.
class ContextEngineConfig {
  final bool enabled;
  final String engine;
  final double triggerRatio;
  final double targetRatio;
  final int protectHeadMessages;
  final int protectTailMessages;
  final int? contextWindowTokens;
  final int? nativeContextWindowTokens;
  final int? providerContextWindowTokens;
  final int? responseReserveTokens;
  final String compactionStrategy;
  final String? compactionModel;
  final int compactionTimeoutMs;
  final bool preCompactionMemoryFlush;

  const ContextEngineConfig({
    this.enabled = true,
    this.engine = 'compressor',
    this.triggerRatio = 0.85,
    this.targetRatio = 0.45,
    this.protectHeadMessages = 2,
    this.protectTailMessages = 20,
    this.contextWindowTokens,
    this.nativeContextWindowTokens,
    this.providerContextWindowTokens,
    this.responseReserveTokens,
    this.compactionStrategy = 'llm_summary',
    this.compactionModel,
    this.compactionTimeoutMs = 60000,
    this.preCompactionMemoryFlush = false,
  });

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'engine': engine,
        'trigger_ratio': triggerRatio,
        'target_ratio': targetRatio,
        'protect_head_messages': protectHeadMessages,
        'protect_tail_messages': protectTailMessages,
        if (contextWindowTokens != null)
          'context_window_tokens': contextWindowTokens,
        if (nativeContextWindowTokens != null)
          'native_context_window_tokens': nativeContextWindowTokens,
        if (providerContextWindowTokens != null)
          'provider_context_window_tokens': providerContextWindowTokens,
        if (responseReserveTokens != null)
          'response_reserve_tokens': responseReserveTokens,
        'compaction_strategy': compactionStrategy,
        if (compactionModel != null && compactionModel!.trim().isNotEmpty)
          'compaction_model': compactionModel,
        'compaction_timeout_ms': compactionTimeoutMs,
        'pre_compaction_memory_flush': preCompactionMemoryFlush,
      };

  factory ContextEngineConfig.fromMap(Map<String, dynamic> map) {
    return ContextEngineConfig(
      enabled: map['enabled'] as bool? ?? true,
      engine: map['engine'] as String? ?? 'compressor',
      triggerRatio: (map['trigger_ratio'] as num?)?.toDouble() ?? 0.85,
      targetRatio: (map['target_ratio'] as num?)?.toDouble() ?? 0.45,
      protectHeadMessages: map['protect_head_messages'] as int? ?? 2,
      protectTailMessages: map['protect_tail_messages'] as int? ?? 20,
      contextWindowTokens: map['context_window_tokens'] as int?,
      nativeContextWindowTokens: map['native_context_window_tokens'] as int?,
      providerContextWindowTokens:
          map['provider_context_window_tokens'] as int?,
      responseReserveTokens: map['response_reserve_tokens'] as int?,
      compactionStrategy:
          map['compaction_strategy'] as String? ?? 'llm_summary',
      compactionModel: map['compaction_model'] as String?,
      compactionTimeoutMs: map['compaction_timeout_ms'] as int? ?? 60000,
      preCompactionMemoryFlush:
          map['pre_compaction_memory_flush'] as bool? ?? false,
    );
  }
}

const int defaultMaxTokens = 40960;

/// Shell command approval posture. Mirrors the Rust `ShellApprovalMode`.
///
/// The SDK provides the mechanism; the host selects the policy. Every mode
/// shares the same hard gate (destructive / data-exfiltration commands are
/// always rejected); the mode only decides what happens to commands that are
/// not in the known-safe allow-list.
enum ShellApprovalMode {
  /// Only known-safe read-only commands run automatically; everything else
  /// requests host approval (rejected when no bridge is wired).
  readOnlyOnly('read_only_only'),

  /// Known-safe commands run automatically; everything else requests host
  /// approval. SDK default.
  onRequest('on_request'),

  /// Known-safe commands run automatically; everything else runs directly once
  /// it clears the hard gate, without prompting. Used by the demo.
  trustedAllow('trusted_allow'),

  /// After the hard gate, classification is delegated to a host policy hook.
  custom('custom');

  const ShellApprovalMode(this.wireName);

  /// snake_case value carried over the wire to the Rust core.
  final String wireName;

  static ShellApprovalMode fromWire(String? value) {
    return ShellApprovalMode.values.firstWhere(
      (mode) => mode.wireName == value,
      orElse: () => ShellApprovalMode.onRequest,
    );
  }
}

/// Shell command security configuration. Mirrors the Rust `ShellSecurityConfig`.
class ShellSecurityConfig {
  final ShellApprovalMode approvalMode;

  const ShellSecurityConfig({
    this.approvalMode = ShellApprovalMode.onRequest,
  });

  Map<String, dynamic> toMap() => {
        'approval_mode': approvalMode.wireName,
      };

  factory ShellSecurityConfig.fromMap(Map<String, dynamic> map) {
    return ShellSecurityConfig(
      approvalMode: ShellApprovalMode.fromWire(map['approval_mode'] as String?),
    );
  }
}

/// Provider config for a single capability slot.
class LlmCapabilityConfig {
  final String provider;
  final String apiKey;
  final String? baseUrl;
  final String model;
  final int? maxTokens;
  final String? extraHeaders;
  final String? imageBase64UrlFormat;

  const LlmCapabilityConfig({
    required this.provider,
    required this.apiKey,
    required this.model,
    this.baseUrl,
    this.maxTokens,
    this.extraHeaders,
    this.imageBase64UrlFormat,
  });

  Map<String, dynamic> toMap() => {
        'provider': provider,
        'api_key': apiKey,
        'base_url': baseUrl,
        'model': model,
        if (maxTokens != null) 'max_tokens': maxTokens,
        if (extraHeaders != null) 'extra_headers': extraHeaders,
        if (imageBase64UrlFormat != null)
          'image_base64_url_format': imageBase64UrlFormat,
      };

  factory LlmCapabilityConfig.fromMap(Map<String, dynamic> map) {
    return LlmCapabilityConfig(
      provider: map['provider'] as String? ?? '',
      apiKey: map['api_key'] as String? ?? '',
      baseUrl: map['base_url'] as String?,
      model: map['model'] as String? ?? '',
      maxTokens: map['max_tokens'] as int?,
      extraHeaders: map['extra_headers'] as String?,
      imageBase64UrlFormat: map['image_base64_url_format'] as String?,
    );
  }
}

/// Git execution mode for the mobile development scenario.
enum GitMode {
  /// Redirect shell `git` to dedicated structured tools (`git_clone`, …).
  /// Historical default.
  structured,
  /// Run shell `git` directly against the real `git` binary baked into the
  /// sandbox rootfs (paseo-style). The read-only allow-list and the shell
  /// approval posture still gate it.
  native;

  String toWire() => switch (this) {
        GitMode.structured => 'structured',
        GitMode.native => 'native',
      };

  /// Fail-safe: unknown/missing values fall back to [GitMode.structured].
  static GitMode fromWire(String? raw) =>
      switch (raw?.trim().toLowerCase()) {
        'native' => GitMode.native,
        _ => GitMode.structured,
      };
}

/// Git commit identity written to the sandbox rootfs `~/.gitconfig` `[user]`.
class GitIdentity {
  /// `user.name`.
  final String name;
  /// `user.email`.
  final String email;

  const GitIdentity({required this.name, required this.email});

  Map<String, dynamic> toMap() => {'name': name, 'email': email};

  factory GitIdentity.fromMap(Map<String, dynamic> map) => GitIdentity(
        name: (map['name'] as String? ?? '').trim(),
        email: (map['email'] as String? ?? '').trim(),
      );
}

/// Git configuration: execution mode and optional commit identity.
class GitConfig {
  /// Execution mode. Defaults to [GitMode.structured].
  final GitMode mode;

  /// Commit identity written to the sandbox rootfs `~/.gitconfig`.
  final GitIdentity? identity;

  const GitConfig({this.mode = GitMode.structured, this.identity});

  /// Convenience for enabling native sandbox-git execution.
  const GitConfig.native({this.identity}) : mode = GitMode.native;

  Map<String, dynamic> toMap() => {
        'mode': mode.toWire(),
        if (identity != null) 'identity': identity!.toMap(),
      };

  factory GitConfig.fromMap(Map<String, dynamic> map) => GitConfig(
        mode: GitMode.fromWire(map['mode'] as String?),
        identity: map['identity'] is Map
            ? GitIdentity.fromMap(
                Map<String, dynamic>.from(map['identity'] as Map),
              )
            : null,
      );
}

/// LLM provider configuration.
class LlmConfig {
  /// Provider identifier: anthropic, openai, gemini, glm, openai_compatible.
  final String provider;

  /// API key.
  final String apiKey;

  /// Custom base URL (optional; null uses the provider default).
  final String? baseUrl;

  /// Model name, e.g. "claude-sonnet-4-6".
  final String model;

  /// System prompt.
  final String systemPrompt;

  /// Preferred response language. Supported values: en, zh.
  final String responseLanguage;

  /// Maximum token count.
  final int maxTokens;

  /// Maximum tool loop iterations. 0 uses the SDK default; negative means approximately unlimited.
  final int maxToolIterations;

  /// Extra HTTP headers, format "Key1:Value1,Key2:Value2".
  final String? extraHeaders;

  /// IANA timezone for interpreting user-local date/time intent.
  ///
  /// Wire values, storage, and timestamps remain UTC/epoch based.
  final String? userTimezone;

  /// Allowed model whitelist for the switch_model tool.
  /// Each element is {"name": "display name", "id": "model ID"}.
  /// null or empty means unrestricted.
  final List<Map<String, String>>? allowedModels;

  /// Image generation model ID (e.g. "dall-e-3"); null disables the image tool.
  final String? imageModel;

  /// Image analysis model ID (compatibility field). New logic prefers [capabilityConfigs] to register tools.
  final String? imageAnalysisModel;

  /// Vision chat completions image_url Base64 representation: data_url or raw.
  final String? imageBase64UrlFormat;

  /// Video generation model ID; null disables the video tool.
  final String? videoModel;

  /// Audio analysis model ID; null disables the audio analysis tool.
  final String? audioModel;

  /// Full provider configuration per capability slot. Key is the capability name, e.g. imageAnalysis.
  final Map<String, LlmCapabilityConfig>? capabilityConfigs;

  /// Per-turn scene prompt injection configuration.
  final ScenePromptConfig? scenePromptConfig;

  /// Long-session context compaction configuration.
  final ContextEngineConfig contextEngine;

  /// Shell command security posture (approval mode + hard gate).
  final ShellSecurityConfig shellSecurity;

  /// Runtime capability selection carried by the active scene/profile.
  final NapaxiCapabilitySelection? capabilitySelection;

  /// Git configuration for the mobile development scenario: execution mode
  /// (structured tools vs. native sandbox `git`) and optional commit identity.
  final GitConfig? git;

  const LlmConfig({
    required this.provider,
    required this.apiKey,
    required this.model,
    this.baseUrl,
    this.systemPrompt = 'You are a helpful assistant.',
    this.responseLanguage = 'en',
    this.maxTokens = defaultMaxTokens,
    this.maxToolIterations = 50,
    this.extraHeaders,
    this.userTimezone,
    this.allowedModels,
    this.imageModel,
    this.imageAnalysisModel,
    this.imageBase64UrlFormat,
    this.videoModel,
    this.audioModel,
    this.capabilityConfigs,
    this.scenePromptConfig,
    this.contextEngine = const ContextEngineConfig(),
    this.shellSecurity = const ShellSecurityConfig(),
    this.capabilitySelection,
    this.git,
  });

  LlmConfig copyWith({
    String? provider,
    String? apiKey,
    String? baseUrl,
    String? model,
    String? systemPrompt,
    String? responseLanguage,
    int? maxTokens,
    int? maxToolIterations,
    String? extraHeaders,
    String? userTimezone,
    List<Map<String, String>>? allowedModels,
    String? imageModel,
    String? imageAnalysisModel,
    String? imageBase64UrlFormat,
    String? videoModel,
    String? audioModel,
    Map<String, LlmCapabilityConfig>? capabilityConfigs,
    ScenePromptConfig? scenePromptConfig,
    ContextEngineConfig? contextEngine,
    ShellSecurityConfig? shellSecurity,
    NapaxiCapabilitySelection? capabilitySelection,
    GitConfig? git,
  }) {
    return LlmConfig(
      provider: provider ?? this.provider,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      baseUrl: baseUrl ?? this.baseUrl,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      responseLanguage: responseLanguage ?? this.responseLanguage,
      maxTokens: maxTokens ?? this.maxTokens,
      maxToolIterations: maxToolIterations ?? this.maxToolIterations,
      extraHeaders: extraHeaders ?? this.extraHeaders,
      userTimezone: userTimezone ?? this.userTimezone,
      allowedModels: allowedModels ?? this.allowedModels,
      imageModel: imageModel ?? this.imageModel,
      imageAnalysisModel: imageAnalysisModel ?? this.imageAnalysisModel,
      imageBase64UrlFormat: imageBase64UrlFormat ?? this.imageBase64UrlFormat,
      videoModel: videoModel ?? this.videoModel,
      audioModel: audioModel ?? this.audioModel,
      capabilityConfigs: capabilityConfigs ?? this.capabilityConfigs,
      scenePromptConfig: scenePromptConfig ?? this.scenePromptConfig,
      contextEngine: contextEngine ?? this.contextEngine,
      shellSecurity: shellSecurity ?? this.shellSecurity,
      capabilitySelection: capabilitySelection ?? this.capabilitySelection,
      git: git ?? this.git,
    );
  }

  /// Serialize to JSON string (passed to the Rust layer).
  String toJson() {
    return jsonEncode({
      'provider': provider,
      'api_key': apiKey,
      'base_url': baseUrl,
      'model': model,
      'system_prompt': _effectiveSystemPrompt(systemPrompt, responseLanguage),
      'response_language': responseLanguage,
      'max_tokens': maxTokens,
      'max_tool_iterations': maxToolIterations,
      'extra_headers': extraHeaders,
      if (userTimezone != null && userTimezone!.trim().isNotEmpty)
        'user_timezone': userTimezone,
      if (allowedModels != null) 'allowed_models': allowedModels,
      if (imageModel != null) 'image_model': imageModel,
      if (imageAnalysisModel != null)
        'image_analysis_model': imageAnalysisModel,
      if (imageBase64UrlFormat != null)
        'image_base64_url_format': imageBase64UrlFormat,
      if (videoModel != null) 'video_model': videoModel,
      if (audioModel != null) 'audio_model': audioModel,
      if (capabilityConfigs != null)
        'capability_configs': capabilityConfigs!.map(
          (key, value) => MapEntry(key, value.toMap()),
        ),
      if (scenePromptConfig != null)
        'scene_prompt_config': scenePromptConfig!.toMap(),
      'context_engine': contextEngine.toMap(),
      'shell_security': shellSecurity.toMap(),
      if (capabilitySelection != null)
        'capability_selection': capabilitySelection!.toJson(),
      if (git != null) 'git': git!.toMap(),
    });
  }

  /// Deserialize from JSON string.
  factory LlmConfig.fromJson(String jsonStr) {
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    return LlmConfig(
      provider: map['provider'] as String? ?? 'anthropic',
      apiKey: map['api_key'] as String? ?? '',
      baseUrl: map['base_url'] as String?,
      model: map['model'] as String? ?? '',
      systemPrompt: map['system_prompt'] as String? ?? '',
      responseLanguage: map['response_language'] as String? ?? 'en',
      maxTokens: map['max_tokens'] as int? ?? defaultMaxTokens,
      maxToolIterations: map['max_tool_iterations'] as int? ?? 50,
      extraHeaders: map['extra_headers'] as String?,
      userTimezone: map['user_timezone'] as String? ??
          map['userTimeZone'] as String? ??
          map['timeZoneId'] as String?,
      allowedModels: (map['allowed_models'] as List?)
          ?.map((e) => Map<String, String>.from(e as Map))
          .toList(),
      imageModel: map['image_model'] as String?,
      imageAnalysisModel: map['image_analysis_model'] as String?,
      imageBase64UrlFormat: map['image_base64_url_format'] as String?,
      videoModel: map['video_model'] as String?,
      audioModel: map['audio_model'] as String?,
      capabilityConfigs: (map['capability_configs'] as Map?)?.map(
        (key, value) => MapEntry(
          key.toString(),
          LlmCapabilityConfig.fromMap(Map<String, dynamic>.from(value as Map)),
        ),
      ),
      scenePromptConfig: map['scene_prompt_config'] is Map
          ? ScenePromptConfig.fromMap(
              Map<String, dynamic>.from(map['scene_prompt_config'] as Map),
            )
          : null,
      contextEngine: map['context_engine'] is Map
          ? ContextEngineConfig.fromMap(
              Map<String, dynamic>.from(map['context_engine'] as Map),
            )
          : const ContextEngineConfig(),
      shellSecurity: map['shell_security'] is Map
          ? ShellSecurityConfig.fromMap(
              Map<String, dynamic>.from(map['shell_security'] as Map),
            )
          : const ShellSecurityConfig(),
      capabilitySelection: map['capability_selection'] is Map
          ? NapaxiCapabilitySelection.fromJson(
              Map<String, dynamic>.from(map['capability_selection'] as Map),
            )
          : null,
      git: map['git'] is Map
          ? GitConfig.fromMap(Map<String, dynamic>.from(map['git'] as Map))
          : null,
    );
  }
}

String _effectiveSystemPrompt(String systemPrompt, String responseLanguage) {
  if (systemPrompt == 'You are a helpful assistant.' &&
      _normalizedResponseLanguage(responseLanguage) == 'zh') {
    return '你是一个有帮助的 AI 助手。';
  }
  return systemPrompt;
}

String _normalizedResponseLanguage(String language) {
  final normalized = language.trim().toLowerCase();
  return normalized == 'zh' || normalized == 'zh-cn' || normalized == 'chinese'
      ? 'zh'
      : 'en';
}
