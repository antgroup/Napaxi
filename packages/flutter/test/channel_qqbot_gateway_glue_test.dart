import 'package:napaxi_flutter/api/channel_api.dart';
import 'package:napaxi_flutter/api/channel_provider_host.dart';
import 'package:napaxi_flutter/convenience/channel_qqbot_provider.dart';
import 'package:napaxi_flutter/models/channel.dart';
import 'package:test/test.dart';

import 'support/contract_fixtures.dart';

// Covers the Dart gateway action-INTERPRETATION glue without FFI.
//
// The core sans-IO reducer (qqbot_gateway_step) is verified in Rust against
// gateway.json. This test takes the SAME fixture's pre-computed `actions`
// arrays — the exact output the reducer emits — and replays them through the
// adapter's pure-Dart applier (QqBotChannelProvider.applyGatewayActions),
// asserting the adapter turns each action into the right side effect (frame
// written to the socket sink, heartbeat interval captured, ready-waiter
// completed, inbound submitted to the channel context). Flutter unit tests do
// not load the native library, so the reducer itself is not called here; this
// pins the half of the path that lives in Dart.
//
// contract-fixture: fixtures/channel/qqbot/gateway.json
void main() {
  final fixture = contractFixtureObject('channel/qqbot/gateway.json');
  final lifecycle = contractObjectList(fixture['lifecycle']);

  late QqBotChannelProvider provider;
  late List<Map<String, dynamic>> sentFrames;
  late List<bool> reconnectRequests;
  late _CapturingQueue queue;

  setUp(() {
    provider = QqBotChannelProvider(
      const QqBotChannelCredentials(
        appId: 'bot-app',
        appSecret: 'secret',
        agentId: 'agent.qq',
      ),
    );
    sentFrames = [];
    reconnectRequests = [];
    queue = _CapturingQueue();
    provider.armGatewayReadyWaiterForTest();
    provider.configureForGatewayGlueTest(
      frameSink: sentFrames.add,
      reconnectSink: reconnectRequests.add,
      context: NapaxiChannelProviderContext(
        queue: queue,
        manifest: provider.manifest,
      ),
    );
  });

  List<dynamic> actionsFor(String eventType, {int skip = 0}) {
    final matches = lifecycle
        .where((c) => (c['event'] as Map)['type'] == eventType)
        .toList();
    return (matches[skip]['actions'] as List);
  }

  test('hello actions send the identify frame and capture heartbeat interval',
      () {
    // First lifecycle frame in the fixture is HELLO -> [send_frame, start_heartbeat].
    provider.applyGatewayActions(lifecycle.first['actions'] as List);

    expect(sentFrames.single['op'], 2, reason: 'identify frame op:2');
    expect(sentFrames.single['d']['token'], 'QQBot tok-123');
    expect(provider.lastHeartbeatIntervalMs, 40000);
  });

  test('ready actions emit initial heartbeat and complete the ready waiter',
      () {
    final readyActions = lifecycle[1]['actions'] as List; // READY step
    expect(provider.isGatewayReadyCompleted, isFalse);

    provider.applyGatewayActions(readyActions);

    // READY -> [send_frame (heartbeat op:1), mark_ready]
    expect(sentFrames.single['op'], 1);
    expect(provider.isGatewayReadyCompleted, isTrue);
  });

  test('heartbeat_due action writes a heartbeat frame with the last seq', () {
    provider.applyGatewayActions(actionsFor('heartbeat_due'));
    expect(sentFrames.single['op'], 1);
    expect(sentFrames.single['d'], 1);
  });

  test('submit_inbound action delivers a normalized message to the context',
      () {
    // The fixture's dispatch step is a GROUP_AT_MESSAGE_CREATE.
    final dispatch = lifecycle.firstWhere(
      (c) => (c['actions'] as List)
          .any((a) => (a as Map)['type'] == 'submit_inbound'),
    );
    provider.applyGatewayActions(dispatch['actions'] as List);

    final inbound = queue.inbound.single;
    expect(inbound.peer.kind, NapaxiChannelEndpointKind.group);
    expect(inbound.peer.id, 'g1');
    expect(inbound.sender.id, 'u1');
    expect(inbound.text, 'yo');
    expect(sentFrames, isEmpty, reason: 'inbound does not write a frame');
  });

  test('reconnect action requests transport reconnect without writing a frame',
      () {
    final reconnect = lifecycle.firstWhere(
      (c) =>
          (c['actions'] as List).any((a) => (a as Map)['type'] == 'reconnect'),
    );
    provider.applyGatewayActions(reconnect['actions'] as List);

    expect(provider.isGatewayReadyCompleted, isTrue);
    expect(reconnectRequests, [true]);
    expect(sentFrames, isEmpty);
  });
}

/// Minimal queue fake that records submitted inbound messages.
class _CapturingQueue implements NapaxiChannelQueue {
  final List<NapaxiChannelInboundMessage> inbound = [];

  @override
  NapaxiChannelAcceptedReceipt submitInbound(
      NapaxiChannelInboundMessage message) {
    inbound.add(message);
    return const NapaxiChannelAcceptedReceipt(accepted: true, id: 'in-test');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not needed for gateway glue test');
}
