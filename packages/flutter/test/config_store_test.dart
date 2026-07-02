import 'package:napaxi_flutter/convenience.dart';
import 'package:test/test.dart';

class FakeStringStore
    implements NapaxiConfigKeyValueStore, NapaxiConfigSecretStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

void main() {
  test('saves profiles without writing API keys to plain storage', () async {
    final plainStore = FakeStringStore();
    final secretStore = FakeStringStore();
    final store = NapaxiConfigStore(
      keyValueStore: plainStore,
      secretStore: secretStore,
    );

    await store.saveProfile(
      const NapaxiConfigProfile(
        id: 'primary',
        name: 'Primary',
        provider: 'openai',
        model: 'gpt-test',
        userTimezone: 'Asia/Shanghai',
        imageAnalysisModel: 'vision-test',
        contextEngine: ContextEngineConfig(
          nativeContextWindowTokens: 1000000,
          contextWindowTokens: 200000,
          responseReserveTokens: 8192,
          compactionModel: 'gpt-compact',
          preCompactionMemoryFlush: true,
        ),
      ),
      apiKey: 'sk-secret',
    );

    final profiles = await store.loadProfiles();
    final config = await store.resolveConfig('primary');
    final plainValues = plainStore.values.values.join('\n');

    expect(profiles.single.model, 'gpt-test');
    expect(profiles.single.userTimezone, 'Asia/Shanghai');
    expect(profiles.single.imageAnalysisModel, 'vision-test');
    expect(profiles.single.contextEngine.nativeContextWindowTokens, 1000000);
    expect(profiles.single.contextEngine.contextWindowTokens, 200000);
    expect(profiles.single.contextEngine.responseReserveTokens, 8192);
    expect(config?.imageAnalysisModel, 'vision-test');
    expect(config?.userTimezone, 'Asia/Shanghai');
    expect(config?.contextEngine.nativeContextWindowTokens, 1000000);
    expect(config?.contextEngine.contextWindowTokens, 200000);
    expect(config?.contextEngine.compactionModel, 'gpt-compact');
    expect(config?.contextEngine.preCompactionMemoryFlush, isTrue);
    expect(config?.apiKey, 'sk-secret');
    expect(plainValues, isNot(contains('sk-secret')));
    expect(secretStore.values.values.single, 'sk-secret');
  });

  test('deletes profile data and API key together', () async {
    final plainStore = FakeStringStore();
    final secretStore = FakeStringStore();
    final store = NapaxiConfigStore(
      keyValueStore: plainStore,
      secretStore: secretStore,
    );

    await store.saveProfile(
      const NapaxiConfigProfile(
        id: 'primary',
        name: 'Primary',
        provider: 'openai',
        model: 'gpt-test',
      ),
      apiKey: 'sk-secret',
    );
    await store.saveSelection(
      const NapaxiConfigSelection(
        selectedProfileId: 'primary',
        selectedProfileIdByCapability: {'chat': 'primary'},
        systemPrompt: 'Global prompt',
        maxToolIterations: 77,
      ),
    );

    await store.deleteProfile('primary');

    expect(await store.loadProfiles(), isEmpty);
    expect(await store.resolveConfig('primary'), isNull);
    expect(secretStore.values, isEmpty);
    expect((await store.loadSelection()).selectedProfileId, isNull);
    expect(
      (await store.loadSelection()).selectedProfileIdByCapability,
      isEmpty,
    );
    expect((await store.loadSelection()).systemPrompt, 'Global prompt');
    expect((await store.loadSelection()).maxToolIterations, 77);
  });

  test('normalizes stale profile selections', () async {
    final store = NapaxiConfigStore.memory();

    await store.saveProfile(
      const NapaxiConfigProfile(
        id: 'primary',
        name: 'Primary',
        provider: 'openai',
        model: 'gpt-test',
      ),
    );
    await store.saveSelection(
      const NapaxiConfigSelection(
        selectedProfileId: 'missing',
        selectedProfileIdByCapability: {
          'chat': 'primary',
          'imageGeneration': 'missing',
        },
        systemPrompt: 'Global prompt',
        maxToolIterations: -1,
      ),
    );

    final selection = await store.loadSelection();

    expect(selection.selectedProfileId, isNull);
    expect(selection.selectedProfileIdByCapability, {'chat': 'primary'});
    expect(selection.systemPrompt, 'Global prompt');
    expect(selection.maxToolIterations, -1);
  });
}
