import 'package:napaxi_flutter/browser_tool_host.dart';
import 'package:napaxi_flutter/models/custom_tool.dart';
import 'package:test/test.dart';

import 'support/contract_fixtures.dart';

// Cross-source contract for the built-in browser tool descriptors. The fixture
// packages/api_contract/fixtures/browser/tool_descriptors.json is the single
// source of truth, generated from the canonical core descriptors in
// crates/core/src/tools/browser.rs. The Rust side pins core ⇄ fixture in
// browser.rs (descriptors_match_shared_contract_fixture); this test pins the
// Flutter offline fallback (BrowserToolProvider fallback defs) ⇄ fixture.
// Together they stop the offline fallback from silently drifting from core.
//
// If a browser tool descriptor changes, regenerate the fixture from core and
// update the Dart fallback in browser_tool_host.dart together.
//
// contract-fixture: fixtures/browser/tool_descriptors.json
void main() {
  group('browser tool descriptor contract fixture', () {
    final fixtureEntries = contractObjectList(
      contractFixtureValue('browser/tool_descriptors.json'),
    );
    final fallbackByName = {
      for (final def in BrowserToolProvider.debugFallbackToolDefinitions)
        def.name: def,
    };

    test('fallback defines exactly the canonical tool set', () {
      final fixtureNames =
          fixtureEntries.map((entry) => entry['name'] as String).toList();
      final fallbackNames =
          BrowserToolProvider.debugFallbackToolDefinitions
              .map((def) => def.name)
              .toList();
      expect(fallbackNames, orderedEquals(fixtureNames));
    });

    test('each fallback descriptor matches the fixture wire shape', () {
      for (final entry in fixtureEntries) {
        final name = entry['name'] as String;
        final def = fallbackByName[name];
        expect(def, isNotNull, reason: 'missing fallback for $name');

        // CustomToolDef.fromJson normalizes the canonical wire entry; comparing
        // toJson() round-trips makes the assertion order-insensitive on map
        // keys while still pinning description, effect, and parameters.
        final canonical = CustomToolDef.fromJson(entry).toJson();
        expect(def!.toJson(), equals(canonical),
            reason: '$name fallback drifted from the shared contract fixture');
      }
    });

    test('isBrowserTool recognizes every fixture tool name', () {
      for (final entry in fixtureEntries) {
        final name = entry['name'] as String;
        expect(BrowserToolProvider.isBrowserTool(name), isTrue,
            reason: '$name not recognized by isBrowserTool');
      }
      expect(BrowserToolProvider.isBrowserTool('web_fetch'), isFalse);
    });
  });
}
