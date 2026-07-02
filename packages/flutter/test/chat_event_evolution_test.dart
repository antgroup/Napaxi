import 'package:flutter_test/flutter_test.dart';
import 'package:napaxi_flutter/napaxi_flutter.dart';

/// Evolution and skill-activation events carry nested object lists (`runs`,
/// `skills`) that go through their own `fromMap` factories. These decoders are
/// easy to break silently — a renamed nested key leaves the parent event intact
/// but empties the list. These tests pin both the parent `type` discriminants
/// and the nested `EvolutionQueuedRun`/`ActivatedSkillInfo` field names against
/// the Rust wire contract.
void main() {
  group('memory / skill evolution events', () {
    test('memory_evolved decodes target and content', () {
      final event = ChatEvent.fromMap({
        'type': 'memory_evolved',
        'target': 'MEMORY.md',
        'content': 'user prefers dark mode',
      });
      expect(event, isA<MemoryEvolvedEvent>());
      final e = event as MemoryEvolvedEvent;
      expect(e.target, 'MEMORY.md');
      expect(e.content, 'user prefers dark mode');
    });

    test('skill_evolved decodes skill name, action, and summary', () {
      final event = ChatEvent.fromMap({
        'type': 'skill_evolved',
        'skill_name': 'pdf-export',
        'action': 'created',
        'summary': 'new skill for PDF export',
      });
      expect(event, isA<SkillEvolvedEvent>());
      final e = event as SkillEvolvedEvent;
      expect(e.skillName, 'pdf-export');
      expect(e.action, 'created');
      expect(e.summary, 'new skill for PDF export');
    });
  });

  group('evolution_queued event', () {
    test('decodes review types and nested runs', () {
      final event = ChatEvent.fromMap({
        'type': 'evolution_queued',
        'review_types': ['memory', 'skill'],
        'runs': [
          {'id': 'run-1', 'review_type': 'memory'},
          {'id': 'run-2', 'review_type': 'skill'},
        ],
      });
      expect(event, isA<EvolutionQueuedEvent>());
      final e = event as EvolutionQueuedEvent;
      expect(e.reviewTypes, ['memory', 'skill']);
      expect(e.runs, hasLength(2));
      expect(e.runs.first.id, 'run-1');
      expect(e.runs.first.reviewType, 'memory');
      // Convenience accessor flattens nested run ids.
      expect(e.runIds, ['run-1', 'run-2']);
    });

    test('defaults to empty lists when runs/review_types are absent', () {
      final event = ChatEvent.fromMap({'type': 'evolution_queued'});
      final e = event as EvolutionQueuedEvent;
      expect(e.reviewTypes, isEmpty);
      expect(e.runs, isEmpty);
      expect(e.runIds, isEmpty);
    });

    test('skips non-object entries in the runs list', () {
      final event = ChatEvent.fromMap({
        'type': 'evolution_queued',
        'review_types': ['memory'],
        'runs': [
          {'id': 'run-1', 'review_type': 'memory'},
          'garbage',
        ],
      });
      final e = event as EvolutionQueuedEvent;
      expect(e.runs, hasLength(1));
      expect(e.runs.single.id, 'run-1');
    });
  });

  group('skill_activated event', () {
    test('decodes agent id and nested skill info with defaults', () {
      final event = ChatEvent.fromMap({
        'type': 'skill_activated',
        'agent_id': 'coder',
        'skills': [
          {
            'name': 'pdf-export',
            'version': '1.2.0',
            'description': 'export to PDF',
            'trust': 'trusted',
            'reason': 'user requested PDF',
          },
          // Only `name` present — the rest must fall back to '' defaults.
          {'name': 'minimal'},
        ],
      });
      expect(event, isA<SkillActivatedEvent>());
      final e = event as SkillActivatedEvent;
      expect(e.agentId, 'coder');
      expect(e.skills, hasLength(2));

      final full = e.skills.first;
      expect(full.name, 'pdf-export');
      expect(full.version, '1.2.0');
      expect(full.trust, 'trusted');
      expect(full.reason, 'user requested PDF');

      final minimal = e.skills.last;
      expect(minimal.name, 'minimal');
      expect(minimal.version, '');
      expect(minimal.description, '');
      expect(minimal.trust, '');
      expect(minimal.reason, '');
    });

    test('defaults agent id and skills when absent', () {
      final event = ChatEvent.fromMap({'type': 'skill_activated'});
      final e = event as SkillActivatedEvent;
      expect(e.agentId, '');
      expect(e.skills, isEmpty);
    });
  });
}
