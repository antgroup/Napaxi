import 'package:flutter_test/flutter_test.dart';
import 'package:napaxi_flutter/api/channel_api.dart';
import 'package:napaxi_flutter/api/channel_provider_host.dart';
import 'package:napaxi_flutter/models/channel.dart';
import 'package:napaxi_flutter/models/channel_provider.dart';

void main() {
  test('channel provider host registers, submits inbound, and pumps outbox',
      () async {
    final queue = _FakeChannelQueue();
    final provider = _FakeChannelProvider();
    final host = NapaxiChannelProviderHost(queue);

    await host.registerProvider(provider);

    expect(queue.registrations.single.name, 'qqbot');
    expect(provider.started, isTrue);

    final inbound = provider.submitDemoInbound('hello from qq');
    expect(inbound.accepted, isTrue);
    expect(queue.inbound.single.text, 'hello from qq');
    expect(queue.inbound.single.channelName, 'qqbot');

    queue.seedOutbound(
      const NapaxiChannelOutboundMessage(
        id: 'out-1',
        channelName: 'qqbot',
        accountId: 'demo-bot',
        peer: NapaxiChannelPeer(
          kind: NapaxiChannelEndpointKind.group,
          id: 'group-openid',
        ),
        text: 'hello qq',
        format: NapaxiChannelContentFormat.markdown,
      ),
    );

    final pump = await host.pump('qqbot');

    expect(pump.leased, 1);
    expect(pump.delivered, 1);
    expect(queue.ackedOutboundIds, ['out-1']);
    expect(provider.delivered.single.text, 'hello qq');
    expect(
        provider.delivered.single.format, NapaxiChannelContentFormat.markdown);

    host.dispose();
    expect(provider.stopped, isTrue);
  });

  test('channel provider host unregisters channel when provider start fails',
      () async {
    final queue = _FakeChannelQueue();
    final host = NapaxiChannelProviderHost(queue);

    await expectLater(
      host.registerProvider(_FailingChannelProvider()),
      throwsStateError,
    );

    expect(queue.registrations.single.name, 'qqbot');
    expect(queue.unregisteredChannelNames, ['qqbot']);
    expect(host.hasProvider('qqbot'), isFalse);
  });

  test('channel provider host tolerates existing core channel on register miss',
      () async {
    final queue = _FakeChannelQueue(
      existingChannels: const [
        NapaxiChannelRecord(name: 'qqbot'),
      ],
      registerResult: false,
    );
    final provider = _FakeChannelProvider();
    final host = NapaxiChannelProviderHost(queue);

    await host.registerProvider(provider);

    expect(queue.registrations.single.name, 'qqbot');
    expect(provider.started, isTrue);
    expect(host.hasProvider('qqbot'), isTrue);
  });

  test(
      'channel provider host keeps transport live when metadata register misses',
      () async {
    final queue = _FakeChannelQueue(registerResult: false);
    final provider = _FakeChannelProvider();
    final host = NapaxiChannelProviderHost(queue);

    await host.registerProvider(provider);

    expect(queue.registrations.single.name, 'qqbot');
    expect(provider.started, isTrue);
    expect(host.hasProvider('qqbot'), isTrue);
  });

  test('channel provider host supports multiple accounts per channel',
      () async {
    final queue = _FakeChannelQueue();
    final host = NapaxiChannelProviderHost(queue);
    final providerA = _FakeChannelProvider(accountId: 'bot-a');
    final providerB = _FakeChannelProvider(accountId: 'bot-b');

    await host.registerProvider(providerA);
    await host.registerProvider(providerB);

    expect(host.hasProvider('qqbot'), isTrue);
    expect(host.hasProvider('qqbot', accountId: 'bot-a'), isTrue);
    expect(host.hasProvider('qqbot', accountId: 'bot-b'), isTrue);
    expect(host.listProviderManifests().map((item) => item.accountId), [
      'bot-a',
      'bot-b',
    ]);

    queue.seedOutbound(
      const NapaxiChannelOutboundMessage(
        id: 'out-a',
        channelName: 'qqbot',
        accountId: 'bot-a',
        peer: NapaxiChannelPeer(
          kind: NapaxiChannelEndpointKind.group,
          id: 'group-a',
        ),
        text: 'hello bot a',
      ),
    );
    queue.seedOutbound(
      const NapaxiChannelOutboundMessage(
        id: 'out-b',
        channelName: 'qqbot',
        accountId: 'bot-b',
        peer: NapaxiChannelPeer(
          kind: NapaxiChannelEndpointKind.group,
          id: 'group-b',
        ),
        text: 'hello bot b',
      ),
    );

    final botAPump = await host.pump('qqbot', accountId: 'bot-a');
    expect(botAPump.delivered, 1);
    expect(providerA.delivered.single.id, 'out-a');
    expect(providerB.delivered, isEmpty);

    final allPump = await host.pump('qqbot');
    expect(allPump.delivered, 1);
    expect(providerB.delivered.single.id, 'out-b');

    await host.unregisterProvider('qqbot', accountId: 'bot-a');
    expect(providerA.stopped, isTrue);
    expect(host.hasProvider('qqbot'), isTrue);
    expect(host.hasProvider('qqbot', accountId: 'bot-a'), isFalse);
    expect(queue.unregisteredChannelNames, isEmpty);

    await host.unregisterProvider('qqbot', accountId: 'bot-b');
    expect(queue.unregisteredChannelNames, ['qqbot']);
  });
}

class _FakeChannelProvider implements NapaxiChannelProvider {
  _FakeChannelProvider({this.accountId = 'demo-bot'});

  final String accountId;

  @override
  NapaxiChannelProviderManifest get manifest => NapaxiChannelProviderManifest.im(
        providerId: 'napaxi.qqbot.provider',
        channelName: 'qqbot',
        displayName: 'QQBot',
        accountId: accountId,
        endpointKinds: [NapaxiChannelEndpointKind.group],
        modalities: [NapaxiChannelModality.text],
        contentFormats: [
          NapaxiChannelContentFormat.plainText,
          NapaxiChannelContentFormat.markdown,
        ],
        transport: 'fake',
      );

  NapaxiChannelProviderContext? _context;
  final List<NapaxiChannelOutboundMessage> delivered = [];
  bool started = false;
  bool stopped = false;

  @override
  Future<void> start(NapaxiChannelProviderContext context) async {
    started = true;
    _context = context;
  }

  @override
  Future<void> stop() async {
    stopped = true;
  }

  NapaxiChannelAcceptedReceipt submitDemoInbound(String text) {
    return _context!.submitTextInbound(
      peer: const NapaxiChannelPeer(
        kind: NapaxiChannelEndpointKind.group,
        id: 'group-openid',
      ),
      sender: const NapaxiChannelActor(id: 'user-openid'),
      text: text,
      platformMessageId: 'qq-1',
    );
  }

  @override
  Future<NapaxiChannelOutboundDeliveryResult> deliverOutbound(
    NapaxiChannelOutboundMessage message,
  ) async {
    delivered.add(message);
    return const NapaxiChannelOutboundDeliveryResult.delivered(
      receipt: {'qq_message_id': 'sent-1'},
    );
  }
}

class _FailingChannelProvider extends _FakeChannelProvider {
  @override
  Future<void> start(NapaxiChannelProviderContext context) async {
    throw StateError('boom');
  }
}

class _FakeChannelQueue implements NapaxiChannelQueue {
  _FakeChannelQueue({
    this.existingChannels = const [],
    this.registerResult = true,
  });

  final List<NapaxiChannelRecord> existingChannels;
  final bool registerResult;
  final List<NapaxiChannelRegistration> registrations = [];
  final List<NapaxiChannelInboundMessage> inbound = [];
  final List<NapaxiChannelOutboundMessage> outbox = [];
  final List<String> ackedOutboundIds = [];
  final List<String> unregisteredChannelNames = [];

  @override
  List<NapaxiChannelRecord> list() => existingChannels;

  @override
  bool register(NapaxiChannelRegistration registration) {
    registrations.add(registration);
    return registerResult;
  }

  @override
  bool registerJson(String configJson) => true;

  @override
  bool unregister(String channelName) {
    unregisteredChannelNames.add(channelName);
    return true;
  }

  @override
  NapaxiChannelAcceptedReceipt submitInbound(
    NapaxiChannelInboundMessage message,
  ) {
    inbound.add(message);
    return NapaxiChannelAcceptedReceipt(
      accepted: true,
      id: 'in-${inbound.length}',
    );
  }

  @override
  NapaxiChannelAcceptedReceipt submitInboundJson(String envelopeJson) {
    throw UnimplementedError();
  }

  @override
  List<NapaxiChannelInboundMessage> takeInbound(
    String channelName, {
    int limit = 20,
  }) {
    return inbound.take(limit).toList(growable: false);
  }

  @override
  bool ackInbound(String inboundId) => true;

  @override
  bool failInbound(String inboundId, String error) => true;

  @override
  bool releaseInbound(String inboundId) => true;

  void seedOutbound(NapaxiChannelOutboundMessage message) {
    outbox.add(message);
  }

  @override
  NapaxiChannelAcceptedReceipt enqueueOutbound(
    NapaxiChannelOutboundMessage message,
  ) {
    outbox.add(message);
    return NapaxiChannelAcceptedReceipt(
      accepted: true,
      id: message.id,
    );
  }

  @override
  NapaxiChannelAcceptedReceipt enqueueOutboundJson(String outboundJson) {
    throw UnimplementedError();
  }

  @override
  NapaxiChannelAcceptedReceipt replyInbound(
    String inboundId,
    NapaxiChannelOutboundMessage message,
  ) {
    return enqueueOutbound(message);
  }

  @override
  NapaxiChannelAcceptedReceipt replyInboundJson(
    String inboundId,
    String replyJson,
  ) {
    throw UnimplementedError();
  }

  @override
  List<NapaxiChannelOutboundMessage> leaseOutbound(
    String channelName, {
    String? accountId,
    int limit = 20,
  }) {
    final leased = outbox
        .where(
          (message) =>
              message.channelName == channelName &&
              (accountId == null || message.accountId == accountId),
        )
        .take(limit)
        .toList(growable: false);
    outbox.removeWhere((message) => leased.contains(message));
    return leased;
  }

  @override
  bool ackOutbound(
    String outboundId, {
    Map<String, dynamic> receipt = const {},
  }) {
    ackedOutboundIds.add(outboundId);
    return true;
  }

  @override
  bool ackOutboundJson(String outboundId, String receiptJson) {
    ackedOutboundIds.add(outboundId);
    return true;
  }

  @override
  bool failOutbound(String outboundId, String error) => true;
}
