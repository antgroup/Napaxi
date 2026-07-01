import 'package:flutter_test/flutter_test.dart';
import 'package:napaxi_flutter/models/chat_event.dart';
import 'package:napaxi_flutter/models/skill.dart';
import 'dart:convert';
import 'dart:typed_data';

void main() {
  test('catalog package page parses ClawHub object-shaped fields', () {
    const json = '''
{
  "items": [
    {
      "slug": "steipete/markdown-writer",
      "displayName": "Markdown Writer",
      "summary": "Write markdown docs",
      "tags": { "latest": "1.2.3" },
      "stats": {
        "stars": 142,
        "downloads": 8400,
        "installsCurrent": 55,
        "installsAllTime": 200
      },
      "updatedAt": 1700000000000,
      "latestVersion": {
        "version": "1.2.3",
        "createdAt": 1700000000000,
        "changelog": ""
      },
      "owner": {
        "handle": "steipete",
        "displayName": "Peter S."
      }
    }
  ],
  "nextCursor": null
}
''';

    final page = CatalogPackagePage.fromJson(json);
    final skill = page.items.single;

    expect(skill.slug, 'steipete/markdown-writer');
    expect(skill.name, 'Markdown Writer');
    expect(skill.description, 'Write markdown docs');
    expect(skill.version, '1.2.3');
    expect(skill.stars, 142);
    expect(skill.downloads, 8400);
    expect(skill.installsCurrent, 55);
    expect(skill.installsAllTime, 200);
    expect(skill.owner, 'steipete');
    expect(skill.ownerName, 'Peter S.');
    expect(skill.tags, isEmpty);
    expect(skill.updatedAt, DateTime.fromMillisecondsSinceEpoch(1700000000000));
  });

  test('catalog search result parses flat ClawHub search fields', () {
    const json = '''
{
  "results": [
    {
      "score": 0.123,
      "slug": "gifgrep",
      "displayName": "GifGrep",
      "summary": "Search GIFs",
      "version": "1.2.3",
      "updatedAt": 1730000000000
    }
  ]
}
''';

    final result = CatalogSearchResult.fromJson(json);
    final skill = result.results.single;

    expect(skill.slug, 'gifgrep');
    expect(skill.name, 'GifGrep');
    expect(skill.description, 'Search GIFs');
    expect(skill.version, '1.2.3');
    expect(skill.score, 0.123);
  });

  test('skill install input encodes bundle payload with extra files', () {
    final payload = SkillInstallInput(
      skillMd: '---\nname: demo\n---\n',
      extraFiles: [
        SkillInstallExtraFile(
          path: 'scripts/helper.py',
          bytes: Uint8List.fromList(utf8.encode('print("hi")\n')),
        ),
      ],
    ).toInstallPayloadJson();

    final decoded = jsonDecode(payload) as Map<String, dynamic>;
    expect(decoded['skill_md'], '---\nname: demo\n---\n');
    final files = decoded['extra_files'] as List<dynamic>;
    expect(files, hasLength(1));
    expect(files.single['path'], 'scripts/helper.py');
    expect(files.single['content_base64'],
        base64Encode(utf8.encode('print("hi")\n')));
  });

  test('skill status report parses readiness diagnostics', () {
    final report = SkillStatusReport.fromJson('''
{
  "ready": 1,
  "disabled": 0,
  "blocked": 1,
  "missing_requirements": 1,
  "parse_error": 0,
  "security_blocked": 0,
  "too_large": 0,
  "entries": [
    {
      "name": "calendar",
      "description": "Calendar helper",
      "source_kind": "installed",
      "source": "/agent_runtime/skills/installed/napaxi/calendar",
      "trust": "installed",
      "enabled": true,
      "eligible": false,
      "status": "missing_requirements",
      "requirements": {
        "bins": [],
        "any_bins": ["node", "bun"],
        "env": ["CALENDAR_TOKEN"],
        "config": [],
        "os": ["android"],
        "capabilities": ["napaxi.platform_tool.open_url"],
        "skills": []
      },
      "missing": {
        "env": ["CALENDAR_TOKEN"]
      },
      "install_options": [{"type": "download", "url": "https://example.invalid"}],
      "warnings": ["dynamic_code_execution: contains eval"],
      "error": "required env var not set: CALENDAR_TOKEN",
      "lifecycle": {"state": "active", "pinned": true},
      "metadata": {
        "user_invocable": true,
        "disable_model_invocation": true,
        "command_dispatch": "tool",
        "command_tool": "calendar_tool",
        "primary_env": "CALENDAR_TOKEN"
      },
      "provenance": {
        "source_kind": "catalog_installed",
        "trust": "installed",
        "managed_by": "core",
        "legacy": false
      },
      "remediation_actions": [
        {
          "id": "env:calendar:CALENDAR_TOKEN",
          "kind": "env",
          "label": "Configure environment key CALENDAR_TOKEN",
          "requirement": "CALENDAR_TOKEN",
          "host_handled": true,
          "danger_level": "medium"
        }
      ]
    }
  ]
}
''');

    expect(report.ready, 1);
    expect(report.blocked, 1);
    final entry = report.entries.single;
    expect(entry.name, 'calendar');
    expect(entry.isBlocked, isTrue);
    expect(entry.requirements.anyBins, ['node', 'bun']);
    expect(entry.missing.env, ['CALENDAR_TOKEN']);
    expect(entry.installOptions.single['type'], 'download');
    expect(entry.lifecycle.pinned, isTrue);
    expect(entry.metadata.disableModelInvocation, isTrue);
    expect(entry.metadata.commandTool, 'calendar_tool');
    expect(entry.provenance.sourceKind, 'catalog_installed');
    expect(entry.remediationActions.single.kind, 'env');
  });

  test('skill command models parse command resolution and run payloads', () {
    final report = SkillCommandReport.fromJson('''
{
  "total": 1,
  "commands": [
    {
      "name": "calendar",
      "skill_name": "calendar-skill",
      "description": "Calendar helper",
      "dispatch": {"kind": "tool", "tool_name": "calendar_tool"},
      "arg_mode": "raw",
      "eligible": true
    }
  ]
}
''');

    expect(report.commands.single.name, 'calendar');
    expect(report.commands.single.dispatch?.toolName, 'calendar_tool');

    final resolution = SkillCommandResolution.fromJson('''
{
  "matched": true,
  "command": {
    "name": "calendar",
    "skill_name": "calendar-skill",
    "description": "Calendar helper",
    "eligible": true
  },
  "args": "today"
}
''');
    expect(resolution.matched, isTrue);
    expect(resolution.command?.skillName, 'calendar-skill');
    expect(resolution.args, 'today');

    final run = SkillCommandRun.fromJson('''
{
  "success": true,
  "status": "agent_turn_required",
  "command_name": "calendar",
  "skill_name": "calendar-skill",
  "args": "today",
  "message": "/calendar-skill today"
}
''');
    expect(run.success, isTrue);
    expect(run.message, '/calendar-skill today');
  });

  test(
      'skill operational parity models parse source snapshot secret and remediation payloads',
      () {
    final sources = SkillSourceReport.fromJson('''
{
  "agent_id": "agent-1",
  "sources": [
    {
      "id": "agent_created",
      "kind": "agent_created",
      "root": "/agent_runtime/skills/agents/agent-1",
      "priority": 0,
      "trust": "trusted",
      "exists": true,
      "version": 2,
      "updated_at": "2026-06-01T00:00:00Z"
    }
  ]
}
''');
    expect(sources.sources.single.id, 'agent_created');
    expect(sources.sources.single.version, 2);

    final snapshot = SkillSnapshot.fromJson('''
{
  "snapshot_id": "snap-1",
  "agent_id": "agent-1",
  "purpose": "session_turn",
  "source_versions": {"agent_created": 2},
  "catalog_entries": [
    {
      "name": "calendar",
      "version": "1.0.0",
      "description": "Calendar helper",
      "trust": "trusted",
      "activation_hint": "matched candidate",
      "content_hash": "abc"
    }
  ],
  "command_entries": [
    {"name": "calendar", "skill_name": "calendar", "eligible": false, "disabled_reason": "reserved_name"}
  ],
  "status_counts": {"ready": 1},
  "catalog_plan": {"included": 1, "omitted": 0},
  "created_at": "2026-06-01T00:00:00Z"
}
''');
    expect(snapshot.catalogEntries.single.contentHash, 'abc');
    expect(snapshot.commandEntries.single.disabledReason, 'reserved_name');
    expect(snapshot.sourceVersions['agent_created'], 2);

    final secrets = SkillSecretRequirementReport.fromJson('''
{
  "requirements": [
    {
      "skill_name": "calendar",
      "skill_key": "calendar",
      "key": "CALENDAR_TOKEN",
      "source": "host",
      "available": false
    }
  ]
}
''');
    expect(secrets.requirements.single.available, isFalse);

    final runs = SkillRemediationRunList.fromJson('''
{
  "total": 1,
  "runs": [
    {
      "run_id": "run-1",
      "agent_id": "agent-1",
      "skill_name": "calendar",
      "action_id": "env:calendar:CALENDAR_TOKEN",
      "status": "requested",
      "requested_at": "2026-06-01T00:00:00Z",
      "updated_at": "2026-06-01T00:00:00Z",
      "result": {"acknowledged": true}
    }
  ]
}
''');
    expect(runs.runs.single.status, 'requested');
    expect(runs.runs.single.result?['acknowledged'], isTrue);
  });

  test('skill activated event parses safe skill metadata', () {
    final event = ChatEvent.fromMap({
      'type': 'skill_activated',
      'agent_id': 'napaxi',
      'skills': [
        {
          'name': 'research',
          'trust': 'installed',
          'reason': 'loaded',
        },
      ],
    });

    expect(event, isA<SkillActivatedEvent>());
    final skillEvent = event as SkillActivatedEvent;
    expect(skillEvent.agentId, 'napaxi');
    expect(skillEvent.skills.single.name, 'research');
    expect(skillEvent.skills.single.version, '');
    expect(skillEvent.skills.single.description, '');
    expect(skillEvent.skills.single.trust, 'installed');
    expect(skillEvent.skills.single.reason, 'loaded');
  });

  test('skill activated event defaults optional fields', () {
    final event = ChatEvent.fromMap({
      'type': 'skill_activated',
      'agent_id': 'napaxi',
      'skills': [
        {'name': 'research'},
      ],
    });

    final skill = (event as SkillActivatedEvent).skills.single;
    expect(skill.version, '');
    expect(skill.description, '');
    expect(skill.trust, '');
    expect(skill.reason, '');
  });
}
