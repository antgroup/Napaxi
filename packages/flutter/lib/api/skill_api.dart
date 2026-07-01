import 'dart:convert';
import 'dart:io';

import '../generated/bridge/evolution.dart' as rust_evolution;
import '../generated/bridge/skill.dart' as rust_skill;
import '../models/config.dart';
import '../models/evolution.dart';
import '../models/skill.dart';
import 'json_codec.dart';

/// Skill API: list installed skills and inspect their status and sources.
///
/// Owns its logic and calls the core bridge directly (handle + config supplied
/// by the engine as closures). `NapaxiEngine`'s flat skill methods forward to
/// this facade. Reference shape: [AgentApi], [GroupApi].
class SkillApi {
  SkillApi(this._handle, {required LlmConfig Function() config})
      : _config = config;

  final int Function() _handle;
  final LlmConfig Function() _config;

  static const String _clawHubBaseUrl = 'https://wry-manatee-359.convex.site';

  List<SkillInfo> list({String agentId = ''}) {
    final json = rust_skill.listSkills(handle: _handle(), agentId: agentId);
    return decodeJsonObjectList(json, SkillInfo.fromMap);
  }

  SkillStatusReport status({String agentId = ''}) {
    final json =
        rust_skill.listSkillStatus(handle: _handle(), agentId: agentId);
    return SkillStatusReport.fromJson(json);
  }

  SkillSourceReport sources({String agentId = ''}) {
    final json =
        rust_skill.listSkillSources(handle: _handle(), agentId: agentId);
    return SkillSourceReport.fromJson(json);
  }

  Future<SkillRefreshResult> recordSourceChanged(
    String sourceId, {
    String agentId = '',
  }) async {
    final json = await rust_skill.recordSkillSourceChanged(
      handle: _handle(),
      agentId: agentId,
      sourceId: sourceId,
    );
    return SkillRefreshResult.fromJson(json);
  }

  SkillStatusReport check({String agentId = ''}) {
    final json = rust_skill.checkSkills(handle: _handle(), agentId: agentId);
    return SkillStatusReport.fromJson(json);
  }

  SkillCommandReport commands({String agentId = ''}) {
    final json = rust_skill.listSkillCommands(
      handle: _handle(),
      agentId: agentId,
    );
    return SkillCommandReport.fromJson(json);
  }

  SkillCommandResolution resolveCommand(
    String text, {
    String agentId = '',
  }) {
    final json = rust_skill.resolveSkillCommand(
      handle: _handle(),
      agentId: agentId,
      text: text,
    );
    return SkillCommandResolution.fromJson(json);
  }

  Future<SkillCommandRun> runCommand(
    String commandName, {
    String agentId = '',
    String? args,
  }) async {
    final json = await rust_skill.runSkillCommand(
      handle: _handle(),
      agentId: agentId,
      commandName: commandName,
      args: args,
      sessionKeyJson: null,
    );
    return SkillCommandRun.fromJson(json);
  }

  Future<String> setEnabled(
    String skillName, {
    String agentId = '',
    required bool enabled,
  }) {
    return rust_skill.setSkillEnabled(
      handle: _handle(),
      agentId: agentId,
      skillName: skillName,
      enabled: enabled,
    );
  }

  Future<String> updateConfig(
    String skillKey,
    Map<String, dynamic> patch, {
    String agentId = '',
  }) {
    return rust_skill.updateSkillConfig(
      handle: _handle(),
      agentId: agentId,
      skillKey: skillKey,
      patchJson: jsonEncode(patch),
    );
  }

  List<SkillRemediationAction> remediationActions(
    String skillName, {
    String agentId = '',
  }) {
    final json = rust_skill.listSkillRemediationActions(
      handle: _handle(),
      agentId: agentId,
      skillName: skillName,
    );
    return decodeJsonArray(json)
        .whereType<Map>()
        .map(
          (item) =>
              SkillRemediationAction.fromMap(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  SkillSnapshotList snapshots({
    String agentId = '',
    int limit = 50,
    int offset = 0,
  }) {
    final json = rust_skill.listSkillSnapshots(
      handle: _handle(),
      agentId: agentId,
      limit: limit,
      offset: offset,
    );
    return SkillSnapshotList.fromJson(json);
  }

  SkillSnapshot? snapshot(String snapshotId) {
    final json = rust_skill.getSkillSnapshot(
      handle: _handle(),
      snapshotId: snapshotId,
    );
    if (json == 'null') return null;
    return SkillSnapshot.fromJson(json);
  }

  SkillSecretRequirementReport secretRequirements({
    String agentId = '',
    String? skillName,
  }) {
    final json = rust_skill.listSkillSecretRequirements(
      handle: _handle(),
      agentId: agentId,
      skillName: skillName,
    );
    return SkillSecretRequirementReport.fromJson(json);
  }

  Future<SkillStatusReport> recordSecretAvailability(
    String skillName,
    String key, {
    String agentId = '',
    required bool available,
    String source = 'host',
  }) async {
    final json = await rust_skill.recordSkillSecretAvailability(
      handle: _handle(),
      agentId: agentId,
      skillName: skillName,
      key: key,
      available: available,
      source: source,
    );
    return SkillStatusReport.fromJson(json);
  }

  Future<SkillRemediationRun> requestRemediation(
    String skillName,
    String actionId, {
    String agentId = '',
  }) async {
    final json = await rust_skill.requestSkillRemediation(
      handle: _handle(),
      agentId: agentId,
      skillName: skillName,
      actionId: actionId,
    );
    return SkillRemediationRun.fromJson(json);
  }

  Future<SkillRemediationRun> updateRemediationRun(
    String runId,
    String status, {
    String agentId = '',
    Map<String, dynamic>? result,
  }) async {
    final json = await rust_skill.updateSkillRemediationRun(
      handle: _handle(),
      agentId: agentId,
      runId: runId,
      status: status,
      resultJson: result == null ? null : jsonEncode(result),
    );
    return SkillRemediationRun.fromJson(json);
  }

  SkillRemediationRunList remediationRuns({
    String agentId = '',
    String? skillName,
    int limit = 50,
    int offset = 0,
  }) {
    final json = rust_skill.listSkillRemediationRuns(
      handle: _handle(),
      agentId: agentId,
      skillName: skillName,
      limit: limit,
      offset: offset,
    );
    return SkillRemediationRunList.fromJson(json);
  }

  Future<String> recordRequirementResolution(
    String skillName,
    String actionId,
    Map<String, dynamic> result, {
    String agentId = '',
  }) {
    return rust_skill.recordSkillRequirementResolution(
      handle: _handle(),
      agentId: agentId,
      skillName: skillName,
      actionId: actionId,
      resultJson: jsonEncode(result),
    );
  }

  SkillStatusEntry? getStatus(String skillName, {String agentId = ''}) {
    final json = rust_skill.getSkillStatus(
      handle: _handle(),
      agentId: agentId,
      skillName: skillName,
    );
    if (json == 'null') return null;
    return SkillStatusEntry.fromMap(decodeJsonObject(json));
  }

  SkillInfo? get(String skillName, {String agentId = ''}) {
    final json = rust_skill.getSkill(
      handle: _handle(),
      agentId: agentId,
      skillName: skillName,
    );
    if (json == 'null') return null;
    return SkillInfo.fromJson(json);
  }

  Future<SkillInstallResult> install(Object skill, {String agentId = ''}) async {
    final payload = switch (skill) {
      String value => value,
      SkillInstallInput value => value.toInstallPayloadJson(),
      _ => throw ArgumentError.value(
          skill,
          'skill',
          'Expected a SKILL.md string or SkillInstallInput',
        ),
    };
    final json = await rust_skill.installSkill(
      handle: _handle(),
      agentId: agentId,
      skillContent: payload,
    );
    return SkillInstallResult.fromJson(json);
  }

  Future<bool> remove(String skillName, {String agentId = ''}) async {
    return rust_skill.removeSkill(
      handle: _handle(),
      agentId: agentId,
      skillName: skillName,
    );
  }

  Future<List<String>> reload({String agentId = ''}) async {
    final json = await rust_skill.reloadSkills(
      handle: _handle(),
      agentId: agentId,
    );
    return decodeJsonArray(json).cast<String>();
  }

  List<SkillUsageRecord> usage({String agentId = ''}) {
    final json = rust_skill.listSkillUsage(handle: _handle(), agentId: agentId);
    return decodeJsonObjectList(json, SkillUsageRecord.fromMap);
  }

  Future<String> pin(String skillName, {String agentId = ''}) {
    return rust_skill.pinSkill(
      handle: _handle(),
      agentId: agentId,
      skillName: skillName,
      pinned: true,
    );
  }

  Future<String> unpin(String skillName, {String agentId = ''}) {
    return rust_skill.pinSkill(
      handle: _handle(),
      agentId: agentId,
      skillName: skillName,
      pinned: false,
    );
  }

  Future<String> archive(String skillName, {String agentId = ''}) async {
    return rust_skill.archiveSkill(
      handle: _handle(),
      agentId: agentId,
      skillName: skillName,
    );
  }

  Future<String> restore(String skillName, {String agentId = ''}) async {
    return rust_skill.restoreSkill(
      handle: _handle(),
      agentId: agentId,
      skillName: skillName,
    );
  }

  Future<CuratorRunSummary> runCurator({
    String agentId = '',
    bool dryRun = true,
  }) async {
    final json = await rust_skill.runSkillCurator(
      handle: _handle(),
      agentId: agentId,
      dryRun: dryRun,
    );
    return CuratorRunSummary.fromJson(json);
  }

  Future<SkillConsolidationReviewResult> runConsolidationReview({
    String agentId = '',
    bool dryRun = true,
  }) async {
    final json = rust_evolution.runSkillConsolidationReview(
      handle: _handle(),
      agentId: agentId,
      configJson: _config().toJson(),
      dryRun: dryRun,
    );
    try {
      return SkillConsolidationReviewResult.fromMap(decodeJsonObject(json));
    } on FormatException {
      // Keep the previous soft-failure behavior for malformed core responses.
    }
    return const SkillConsolidationReviewResult(
      reviewed: false,
      dryRun: true,
      error: 'unexpected consolidation review response',
    );
  }

  Future<SkillSupportFileReadResult> readSupportFile(
    String skillName,
    String filePath, {
    String agentId = '',
  }) async {
    final json = await rust_skill.readSkillSupportFile(
      handle: _handle(),
      agentId: agentId,
      skillName: skillName,
      filePath: filePath,
    );
    return SkillSupportFileReadResult.fromJson(json);
  }

  Future<String> searchCatalog(String query) async {
    return rust_skill.searchCatalog(query: query);
  }

  Future<CatalogPackagePage> listCatalogPackages({
    int limit = 24,
    String? cursor,
  }) async {
    final safeLimit = limit.clamp(1, 100).toInt();
    final params = <String, String>{'limit': '$safeLimit'};
    if (cursor != null && cursor.trim().isNotEmpty) {
      params['cursor'] = cursor.trim();
    }
    final body = await _getClawHubJson('/api/v1/packages', params);
    return CatalogPackagePage.fromJson(body);
  }

  Future<String> getCatalogSkill(String slug) async {
    return rust_skill.getCatalogSkill(slug: slug);
  }

  Future<String> installFromCatalog(String slug, {String agentId = ''}) async {
    return rust_skill.installFromCatalog(
      handle: _handle(),
      agentId: agentId,
      slug: slug,
    );
  }

  Future<String> _getClawHubJson(
    String path,
    Map<String, String> queryParams,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final uri = Uri.parse(
        _clawHubBaseUrl,
      ).replace(path: path, queryParameters: queryParams);
      final request = await client.getUrl(uri);
      request.headers.set('User-Agent', 'napaxi-sdk/1.0');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return jsonEncode({
          'items': [],
          'error': 'HTTP ${response.statusCode}: $body',
        });
      }
      return body;
    } catch (error) {
      return jsonEncode({'items': [], 'error': '$error'});
    } finally {
      client.close(force: true);
    }
  }
}
