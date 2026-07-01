import 'dart:convert';

import 'package:napaxi_flutter/models/capability.dart';
import 'package:napaxi_flutter/models/config.dart';
import 'package:test/test.dart';

// Covers models/config.dart — the LlmConfig that is serialized and handed to
// the Rust engine on every init/update. The wire shape is snake_case JSON, so
// these tests pin the toJson/fromJson contract, the nested sub-configs, the
// defaults, and the conditional field omission that a wire drift would break.
void main() {
  group('ScenePromptConfig', () {
    test('round-trips host policies via snake_case host_policies', () {
      const config = ScenePromptConfig(
        enabled: true,
        hostPolicies: {'tone': 'formal'},
      );
      final map = config.toMap();
      expect(map['enabled'], isTrue);
      expect(map['host_policies'], {'tone': 'formal'});

      final decoded = ScenePromptConfig.fromMap(map);
      expect(decoded.enabled, isTrue);
      expect(decoded.hostPolicies, {'tone': 'formal'});
    });

    test('omits host_policies when null and defaults enabled to false', () {
      final map = const ScenePromptConfig().toMap();
      expect(map.containsKey('host_policies'), isFalse);
      expect(ScenePromptConfig.fromMap({}).enabled, isFalse);
      expect(ScenePromptConfig.fromMap({}).hostPolicies, isNull);
    });

    test('coerces non-string host policy values to strings', () {
      final decoded = ScenePromptConfig.fromMap({
        'host_policies': {'limit': 5},
      });
      expect(decoded.hostPolicies, {'limit': '5'});
    });
  });

  group('ContextEngineConfig', () {
    test('applies documented defaults when absent', () {
      final c = ContextEngineConfig.fromMap({});
      expect(c.enabled, isTrue);
      expect(c.engine, 'compressor');
      expect(c.triggerRatio, 0.85);
      expect(c.targetRatio, 0.45);
      expect(c.protectHeadMessages, 2);
      expect(c.protectTailMessages, 20);
      expect(c.compactionStrategy, 'llm_summary');
      expect(c.compactionTimeoutMs, 60000);
      expect(c.preCompactionMemoryFlush, isFalse);
      expect(c.contextWindowTokens, isNull);
    });

    test('decodes snake_case fields and coerces int ratios to double', () {
      final c = ContextEngineConfig.fromMap({
        'trigger_ratio': 1, // int on the wire
        'target_ratio': 0,
        'protect_head_messages': 5,
        'context_window_tokens': 128000,
        'compaction_strategy': 'truncate',
      });
      expect(c.triggerRatio, 1.0);
      expect(c.targetRatio, 0.0);
      expect(c.protectHeadMessages, 5);
      expect(c.contextWindowTokens, 128000);
      expect(c.compactionStrategy, 'truncate');
    });

    test('toMap omits empty compaction_model but keeps a set one', () {
      expect(
        const ContextEngineConfig(compactionModel: '   ')
            .toMap()
            .containsKey('compaction_model'),
        isFalse,
      );
      expect(
        const ContextEngineConfig(compactionModel: 'fast')
            .toMap()['compaction_model'],
        'fast',
      );
    });
  });

  group('LlmCapabilityConfig', () {
    test('round-trips through toMap/fromMap', () {
      const cfg = LlmCapabilityConfig(
        provider: 'openai',
        apiKey: 'sk-1',
        model: 'gpt-image',
        baseUrl: 'https://api.example',
        maxTokens: 1024,
      );
      final decoded = LlmCapabilityConfig.fromMap(cfg.toMap());
      expect(decoded.provider, 'openai');
      expect(decoded.apiKey, 'sk-1');
      expect(decoded.model, 'gpt-image');
      expect(decoded.baseUrl, 'https://api.example');
      expect(decoded.maxTokens, 1024);
    });

    test('defaults required strings to empty when missing', () {
      final cfg = LlmCapabilityConfig.fromMap({});
      expect(cfg.provider, '');
      expect(cfg.apiKey, '');
      expect(cfg.model, '');
      expect(cfg.maxTokens, isNull);
    });
  });

  group('LlmConfig.toJson / fromJson', () {
    test('round-trips a fully populated config', () {
      const config = LlmConfig(
        provider: 'openai',
        apiKey: 'sk-abc',
        model: 'gpt-4',
        baseUrl: 'https://api.example/v1',
        systemPrompt: 'be concise',
        responseLanguage: 'zh',
        maxTokens: 8192,
        maxToolIterations: 12,
        extraHeaders: 'X-A:1',
        userTimezone: 'Asia/Shanghai',
        allowedModels: [
          {'name': 'GPT 4', 'id': 'gpt-4'},
        ],
        imageModel: 'dall-e-3',
        imageBase64UrlFormat: 'data_url',
        capabilityConfigs: {
          'imageAnalysis': LlmCapabilityConfig(
            provider: 'openai',
            apiKey: 'sk-img',
            model: 'gpt-vision',
          ),
        },
        scenePromptConfig: ScenePromptConfig(enabled: true),
        contextEngine: ContextEngineConfig(triggerRatio: 0.9),
        capabilitySelection: NapaxiCapabilitySelection(
          enabledCapabilities: ['napaxi.tool.git'],
          disabledCapabilities: ['napaxi.tool.shell'],
          config: {'scenario_id': 'napaxi.scenario.mobile_development'},
        ),
      );

      final decoded = LlmConfig.fromJson(config.toJson());

      expect(decoded.provider, 'openai');
      expect(decoded.apiKey, 'sk-abc');
      expect(decoded.model, 'gpt-4');
      expect(decoded.baseUrl, 'https://api.example/v1');
      expect(decoded.systemPrompt, 'be concise');
      expect(decoded.responseLanguage, 'zh');
      expect(decoded.maxTokens, 8192);
      expect(decoded.maxToolIterations, 12);
      expect(decoded.userTimezone, 'Asia/Shanghai');
      expect(decoded.allowedModels, [
        {'name': 'GPT 4', 'id': 'gpt-4'},
      ]);
      expect(decoded.imageModel, 'dall-e-3');
      expect(decoded.capabilityConfigs!['imageAnalysis']!.model, 'gpt-vision');
      expect(decoded.scenePromptConfig!.enabled, isTrue);
      expect(decoded.contextEngine.triggerRatio, 0.9);
      expect(decoded.capabilitySelection!.enabledCapabilities, [
        'napaxi.tool.git',
      ]);
      expect(decoded.capabilitySelection!.disabledCapabilities, [
        'napaxi.tool.shell',
      ]);
      expect(
        decoded.capabilitySelection!.config['scenario_id'],
        'napaxi.scenario.mobile_development',
      );
    });

    test('uses snake_case keys on the wire', () {
      final map = jsonDecode(
        const LlmConfig(
          provider: 'openai',
          apiKey: 'k',
          model: 'm',
          userTimezone: 'Asia/Shanghai',
        ).toJson(),
      ) as Map<String, dynamic>;
      expect(map.containsKey('api_key'), isTrue);
      expect(map.containsKey('response_language'), isTrue);
      expect(map.containsKey('max_tokens'), isTrue);
      expect(map.containsKey('max_tool_iterations'), isTrue);
      expect(map['user_timezone'], 'Asia/Shanghai');
      expect(map.containsKey('context_engine'), isTrue);
      expect(map.containsKey('capability_selection'), isFalse);
    });

    test('localizes default system prompt when response language is Chinese',
        () {
      final map = jsonDecode(
        const LlmConfig(
          provider: 'openai',
          apiKey: 'k',
          model: 'm',
          responseLanguage: 'zh',
        ).toJson(),
      ) as Map<String, dynamic>;
      expect(map['system_prompt'], '你是一个有帮助的 AI 助手。');

      final custom = jsonDecode(
        const LlmConfig(
          provider: 'openai',
          apiKey: 'k',
          model: 'm',
          systemPrompt: 'Use host policy.',
          responseLanguage: 'zh',
        ).toJson(),
      ) as Map<String, dynamic>;
      expect(custom['system_prompt'], 'Use host policy.');
    });

    test('accepts user timezone aliases from older host payloads', () {
      final decoded = LlmConfig.fromJson(
        jsonEncode({
          'provider': 'openai',
          'api_key': 'k',
          'model': 'm',
          'timeZoneId': 'Europe/Vienna',
        }),
      );
      expect(decoded.userTimezone, 'Europe/Vienna');
    });

    test('applies defaults for a minimal payload', () {
      final decoded = LlmConfig.fromJson('{}');
      expect(decoded.provider, 'anthropic');
      expect(decoded.apiKey, '');
      expect(decoded.responseLanguage, 'en');
      expect(decoded.maxTokens, defaultMaxTokens);
      expect(decoded.maxToolIterations, 50);
      expect(decoded.allowedModels, isNull);
      expect(decoded.capabilityConfigs, isNull);
      expect(decoded.scenePromptConfig, isNull);
      // contextEngine always materializes, even when absent.
      expect(decoded.contextEngine.enabled, isTrue);
    });

    test('omits optional fields from the wire when null', () {
      final map = jsonDecode(
        const LlmConfig(provider: 'anthropic', apiKey: 'k', model: 'm')
            .toJson(),
      ) as Map<String, dynamic>;
      expect(map.containsKey('image_model'), isFalse);
      expect(map.containsKey('allowed_models'), isFalse);
      expect(map.containsKey('user_timezone'), isFalse);
      expect(map.containsKey('capability_configs'), isFalse);
      expect(map.containsKey('scene_prompt_config'), isFalse);
    });

    test('tolerates a non-map context_engine by falling back to default', () {
      final decoded = LlmConfig.fromJson(
        jsonEncode({'provider': 'openai', 'context_engine': 'nope'}),
      );
      expect(decoded.contextEngine.enabled, isTrue);
      expect(decoded.contextEngine.engine, 'compressor');
    });

    test('defaults shell_security to on_request and emits it on the wire', () {
      final decoded = LlmConfig.fromJson(jsonEncode({'provider': 'openai'}));
      expect(decoded.shellSecurity.approvalMode, ShellApprovalMode.onRequest);

      final wire = jsonDecode(
        LlmConfig(provider: 'openai', apiKey: 'k', model: 'm').toJson(),
      ) as Map<String, dynamic>;
      expect(
        (wire['shell_security'] as Map)['approval_mode'],
        'on_request',
      );
    });

    test('shell_security round-trips trusted_allow via snake_case wire', () {
      final json = LlmConfig(
        provider: 'openai',
        apiKey: 'k',
        model: 'm',
        shellSecurity: const ShellSecurityConfig(
          approvalMode: ShellApprovalMode.trustedAllow,
        ),
      ).toJson();
      expect(
        (jsonDecode(json)['shell_security'] as Map)['approval_mode'],
        'trusted_allow',
      );
      expect(
        LlmConfig.fromJson(json).shellSecurity.approvalMode,
        ShellApprovalMode.trustedAllow,
      );
    });

    test('shell_security falls back to on_request for unknown wire values', () {
      final decoded = LlmConfig.fromJson(
        jsonEncode({
          'provider': 'openai',
          'shell_security': {'approval_mode': 'bogus'},
        }),
      );
      expect(decoded.shellSecurity.approvalMode, ShellApprovalMode.onRequest);
    });
  });
}
