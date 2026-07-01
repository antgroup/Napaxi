import 'dart:convert';

import '../generated/bridge/channel.dart' as rust_channel;
import '../generated/bridge/channel_agent.dart' as rust_channel_agent;
import '../models/channel.dart';

abstract class NapaxiChannelQueue {
  List<NapaxiChannelRecord> list();
  bool register(NapaxiChannelRegistration registration);
  bool registerJson(String configJson);
  bool unregister(String channelName);
  NapaxiChannelAcceptedReceipt submitInbound(
    NapaxiChannelInboundMessage message,
  );
  NapaxiChannelAcceptedReceipt submitInboundJson(String envelopeJson);
  List<NapaxiChannelInboundMessage> takeInbound(
    String channelName, {
    int limit = 20,
  });
  bool ackInbound(String inboundId);
  bool failInbound(String inboundId, String error);
  bool releaseInbound(String inboundId);
  NapaxiChannelAcceptedReceipt enqueueOutbound(
    NapaxiChannelOutboundMessage message,
  );
  NapaxiChannelAcceptedReceipt enqueueOutboundJson(String outboundJson);
  NapaxiChannelAcceptedReceipt replyInbound(
    String inboundId,
    NapaxiChannelOutboundMessage message,
  );
  NapaxiChannelAcceptedReceipt replyInboundJson(
    String inboundId,
    String replyJson,
  );
  List<NapaxiChannelOutboundMessage> leaseOutbound(
    String channelName, {
    String? accountId,
    int limit = 20,
  });
  bool ackOutbound(String outboundId,
      {Map<String, dynamic> receipt = const {}});
  bool ackOutboundJson(String outboundId, String receiptJson);
  bool failOutbound(String outboundId, String error);
}

class ChannelApi implements NapaxiChannelQueue {
  ChannelApi(this._handle);

  final int Function() _handle;

  @override
  List<NapaxiChannelRecord> list() {
    return decodeChannelRecords(rust_channel.listChannels(handle: _handle()));
  }

  @override
  bool register(NapaxiChannelRegistration registration) {
    return registerJson(registration.toJsonString());
  }

  @override
  bool registerJson(String configJson) {
    return rust_channel.registerChannel(
      handle: _handle(),
      configJson: configJson,
    );
  }

  @override
  bool unregister(String channelName) {
    return rust_channel.unregisterChannel(
      handle: _handle(),
      channelName: channelName,
    );
  }

  @override
  NapaxiChannelAcceptedReceipt submitInbound(
    NapaxiChannelInboundMessage message,
  ) {
    return submitInboundJson(message.toJsonString());
  }

  @override
  NapaxiChannelAcceptedReceipt submitInboundJson(String envelopeJson) {
    return decodeChannelAcceptedReceipt(
      rust_channel.submitChannelInbound(
        handle: _handle(),
        envelopeJson: envelopeJson,
      ),
    );
  }

  @override
  List<NapaxiChannelInboundMessage> takeInbound(
    String channelName, {
    int limit = 20,
  }) {
    return decodeChannelInboundMessages(
      rust_channel.takeChannelInbound(
        handle: _handle(),
        channelName: channelName,
        limit: BigInt.from(limit),
      ),
    );
  }

  @override
  bool ackInbound(String inboundId) {
    return rust_channel.ackChannelInbound(
      handle: _handle(),
      inboundId: inboundId,
    );
  }

  @override
  bool failInbound(String inboundId, String error) {
    return rust_channel.failChannelInbound(
      handle: _handle(),
      inboundId: inboundId,
      error: error,
    );
  }

  @override
  bool releaseInbound(String inboundId) {
    return rust_channel.releaseChannelInbound(
      handle: _handle(),
      inboundId: inboundId,
    );
  }

  @override
  NapaxiChannelAcceptedReceipt enqueueOutbound(
    NapaxiChannelOutboundMessage message,
  ) {
    return enqueueOutboundJson(message.toJsonString());
  }

  @override
  NapaxiChannelAcceptedReceipt enqueueOutboundJson(String outboundJson) {
    return decodeChannelAcceptedReceipt(
      rust_channel.enqueueChannelOutbound(
        handle: _handle(),
        outboundJson: outboundJson,
      ),
    );
  }

  @override
  NapaxiChannelAcceptedReceipt replyInbound(
    String inboundId,
    NapaxiChannelOutboundMessage message,
  ) {
    return replyInboundJson(inboundId, message.toJsonString());
  }

  @override
  NapaxiChannelAcceptedReceipt replyInboundJson(
    String inboundId,
    String replyJson,
  ) {
    return decodeChannelAcceptedReceipt(
      rust_channel.replyChannelInbound(
        handle: _handle(),
        inboundId: inboundId,
        replyJson: replyJson,
      ),
    );
  }

  @override
  List<NapaxiChannelOutboundMessage> leaseOutbound(
    String channelName, {
    String? accountId,
    int limit = 20,
  }) {
    return decodeChannelOutboundMessages(
      rust_channel.leaseChannelOutbound(
        handle: _handle(),
        channelName: channelName,
        accountId: accountId,
        limit: BigInt.from(limit),
      ),
    );
  }

  @override
  bool ackOutbound(String outboundId,
      {Map<String, dynamic> receipt = const {}}) {
    return ackOutboundJson(outboundId, jsonEncode(receipt));
  }

  @override
  bool ackOutboundJson(String outboundId, String receiptJson) {
    return rust_channel.ackChannelOutbound(
      handle: _handle(),
      outboundId: outboundId,
      receiptJson: receiptJson,
    );
  }

  @override
  bool failOutbound(String outboundId, String error) {
    return rust_channel.failChannelOutbound(
      handle: _handle(),
      outboundId: outboundId,
      error: error,
    );
  }
}

class ChannelAgentApi {
  ChannelAgentApi(this._handle);

  final int Function() _handle;

  NapaxiChannelAgentRoute registerRoute(NapaxiChannelAgentRoute route) {
    return registerRouteJson(route.toJsonString());
  }

  NapaxiChannelAgentRoute registerRouteJson(String routeJson) {
    return decodeChannelAgentRoute(
      rust_channel_agent.registerChannelAgentRoute(
        handle: _handle(),
        routeJson: routeJson,
      ),
    );
  }

  List<NapaxiChannelAgentRoute> listRoutes({String? channelName}) {
    return decodeChannelAgentRoutes(
      rust_channel_agent.listChannelAgentRoutes(
        handle: _handle(),
        channelName: channelName,
      ),
    );
  }

  bool removeRoute(String routeId) {
    return rust_channel_agent.removeChannelAgentRoute(
      handle: _handle(),
      routeId: routeId,
    );
  }

  Map<String, dynamic> resolveRouteJson({
    required String bridgeConfigJson,
    required String inboundJson,
  }) {
    final decoded = jsonDecode(
      rust_channel_agent.resolveChannelAgentRoute(
        handle: _handle(),
        bridgeConfigJson: bridgeConfigJson,
        inboundJson: inboundJson,
      ),
    );
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return const {};
  }

  NapaxiChannelAgentStatus status({String? channelName}) {
    return decodeChannelAgentStatus(
      rust_channel_agent.channelAgentStatus(
        handle: _handle(),
        channelName: channelName,
      ),
    );
  }

  Stream<String> streamPump({
    required String configJson,
    required String bridgeConfigJson,
  }) {
    return rust_channel_agent.streamChannelAgentPump(
      handle: _handle(),
      configJson: configJson,
      bridgeConfigJson: bridgeConfigJson,
    );
  }
}
