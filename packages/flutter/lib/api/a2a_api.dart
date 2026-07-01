import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../generated/bridge/a2a.dart' as rust_a2a;
import '../models/a2a.dart';
import 'a2a_pairing.dart';

part 'a2a_local_transport_impl.dart';

/// Agent-to-agent (A2A) API: peer messaging, local pairing, and transport
/// events over the background method/event channels.
class A2AApi {
  A2AApi(this._handle, {MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_channelName),
        _localTransport = _A2ALocalTransportApi(channel: channel);

  static const _channelName = 'com.napaxi.flutter/background';
  static const _eventChannelName = 'com.napaxi.flutter/background_events';

  final int Function() _handle;
  final MethodChannel _channel;
  final _A2ALocalTransportApi _localTransport;
  final EventChannel _eventChannel = const EventChannel(_eventChannelName);

  Stream<A2ALocalTransportEvent>? _localTransportEvents;

  String generateLocalPairingSecret({int byteLength = 16}) {
    return A2APairing.generateLocalPairingSecret(byteLength: byteLength);
  }

  String normalizePairingSecret(String value) {
    return A2APairing.normalizePairingSecret(value);
  }

  String formatPairingSecret(String value) {
    return A2APairing.formatPairingSecret(value);
  }

  String pairingCodeFromIdentity(String peerId, String publicKey) {
    return A2APairing.pairingCodeFromIdentity(peerId, publicKey);
  }

  String pairingKey(A2ALocalPeerAdvertisement peer) {
    return A2APairing.pairingKey(
      peerId: peer.peerId,
      publicKey: peer.publicKey,
    );
  }

  String deriveLocalSharedSecret({
    required String localPeerId,
    required String localPublicKey,
    required String localPairingSecret,
    required A2ALocalPeerAdvertisement peer,
    required String remotePairingSecret,
  }) {
    return A2APairing.deriveLocalSharedSecret(
      localPeerId: localPeerId,
      localPublicKey: localPublicKey,
      localPairingSecret: localPairingSecret,
      remotePeerId: peer.peerId,
      remotePublicKey: peer.publicKey,
      remotePairingSecret: remotePairingSecret,
    );
  }

  A2AAgentCard agentCard({String agentId = ''}) {
    return _decode(
      rust_a2a.getA2AAgentCard(handle: _handle(), agentId: agentId),
      A2AAgentCard.fromJson,
    );
  }

  A2APeerInvite createPeerInvite(
    String agentId, {
    Map<String, dynamic> options = const {},
  }) {
    return _decode(
      rust_a2a.createA2APeerInvite(
        handle: _handle(),
        agentId: agentId,
        optionsJson: jsonEncode(options),
      ),
      A2APeerInvite.fromJson,
    );
  }

  A2APeer acceptPeerInvite(A2ADeepLinkEnvelope envelope) {
    return _decode(
      rust_a2a.acceptA2APeerInvite(
        handle: _handle(),
        envelopeJson: envelope.toJsonString(),
      ),
      A2APeer.fromJson,
    );
  }

  List<A2APeer> listPeers({String agentId = ''}) {
    return decodeA2APeers(
      rust_a2a.listA2APeers(handle: _handle(), agentId: agentId),
    );
  }

  bool deletePeer(String peerId) {
    return rust_a2a.deleteA2APeer(handle: _handle(), peerId: peerId);
  }

  A2APeerSession openPeerSession(
    A2APeer peer, {
    String transport = 'lan_websocket',
    String endpoint = '',
    String localPeerId = '',
  }) {
    final peerJson = peer.toJson();
    if (localPeerId.isNotEmpty) peerJson['localPeerId'] = localPeerId;
    return _decode(
      rust_a2a.openA2APeerSession(
        handle: _handle(),
        peerJson: jsonEncode(peerJson),
        transport: transport,
        endpoint: endpoint,
      ),
      A2APeerSession.fromJson,
    );
  }

  List<A2APeerSession> listPeerSessions({String peerId = ''}) {
    return decodeA2APeerSessions(
      rust_a2a.listA2APeerSessions(handle: _handle(), peerId: peerId),
    );
  }

  A2APeerMessage createTaskMessage(
    String sessionId,
    String message, {
    Map<String, dynamic> options = const {},
  }) {
    return _decode(
      rust_a2a.createA2ATaskMessage(
        handle: _handle(),
        sessionId: sessionId,
        message: message,
        optionsJson: jsonEncode(options),
      ),
      A2APeerMessage.fromJson,
    );
  }

  A2APeerMessage createTaskProgressMessage(
    String sessionId,
    String taskId,
    String message, {
    Map<String, dynamic> progress = const {},
  }) {
    return _decode(
      rust_a2a.createA2ATaskProgressMessage(
        handle: _handle(),
        sessionId: sessionId,
        taskId: taskId,
        message: message,
        progressJson: jsonEncode(progress),
      ),
      A2APeerMessage.fromJson,
    );
  }

  A2APeerMessage createTaskResultMessage(
    String sessionId,
    String taskId, {
    Map<String, dynamic> result = const {},
  }) {
    return _decode(
      rust_a2a.createA2ATaskResultMessage(
        handle: _handle(),
        sessionId: sessionId,
        taskId: taskId,
        resultJson: jsonEncode(result),
      ),
      A2APeerMessage.fromJson,
    );
  }

  A2ADeliveryRecord recordPeerMessage(
    A2APeerMessage message, {
    String source = 'local_transport',
  }) {
    return _decode(
      rust_a2a.recordA2APeerMessage(
        handle: _handle(),
        messageJson: message.toJsonString(),
        source: source,
      ),
      A2ADeliveryRecord.fromJson,
    );
  }

  A2ADeliveryRecord recordDeliveryStatus(
    A2APeerMessage message, {
    required String status,
    String error = '',
  }) {
    return _decode(
      rust_a2a.recordA2ADeliveryStatus(
        handle: _handle(),
        messageJson: message.toJsonString(),
        status: status,
        error: error,
      ),
      A2ADeliveryRecord.fromJson,
    );
  }

  List<A2APeerMessage> listPeerMessages(
    String sessionId, {
    int limit = 100,
    int offset = 0,
  }) {
    return decodeA2APeerMessages(
      rust_a2a.listA2APeerMessages(
        handle: _handle(),
        sessionId: sessionId,
        limit: limit,
        offset: offset,
      ),
    );
  }

  List<A2ADeliveryRecord> listDeliveryRecords(
    String sessionId, {
    int limit = 100,
    int offset = 0,
  }) {
    return decodeA2ADeliveryRecords(
      rust_a2a.listA2ADeliveryRecords(
        handle: _handle(),
        sessionId: sessionId,
        limit: limit,
        offset: offset,
      ),
    );
  }

  A2ATaskRecord acceptDeepLink(
    A2ADeepLinkEnvelope envelope, {
    String source = 'deep_link',
  }) {
    return _decode(
      rust_a2a.acceptA2ADeepLink(
        handle: _handle(),
        envelopeJson: envelope.toJsonString(),
        source: source,
      ),
      A2ATaskRecord.fromJson,
    );
  }

  Future<A2ATaskRecord> runTask(
    String taskId, {
    String mode = 'confirm',
  }) async {
    return _decode(
      await rust_a2a.runA2ATask(handle: _handle(), taskId: taskId, mode: mode),
      A2ATaskRecord.fromJson,
    );
  }

  List<A2ATaskRecord> listTasks({
    Map<String, dynamic> filter = const {},
    int limit = 100,
    int offset = 0,
  }) {
    return decodeA2ATasks(
      rust_a2a.listA2ATasks(
        handle: _handle(),
        filterJson: jsonEncode(filter),
        limit: limit,
        offset: offset,
      ),
    );
  }

  A2ATaskRecord? getTask(String taskId) {
    final raw = rust_a2a.getA2ATask(handle: _handle(), taskId: taskId);
    if (raw == 'null') return null;
    return _decode(raw, A2ATaskRecord.fromJson);
  }

  A2AResultLink buildResultLink(String taskId, String callbackUrl) {
    return _decode(
      rust_a2a.buildA2AResultLink(
        handle: _handle(),
        taskId: taskId,
        callbackUrl: callbackUrl,
      ),
      A2AResultLink.fromJson,
    );
  }

  Map<String, dynamic> recordResultEnvelope(A2ADeepLinkEnvelope envelope) {
    return _decode(
      rust_a2a.recordA2AResultEnvelope(
        handle: _handle(),
        envelopeJson: envelope.toJsonString(),
      ),
      (json) => json,
    );
  }

  Future<A2ADeepLinkEnvelope?> consumePendingDeepLink() async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'getPendingA2ADeepLink',
    );
    if (raw == null || raw.isEmpty) return null;
    final envelopeJson = raw['envelopeJson'] as String? ?? '';
    if (envelopeJson.isEmpty) return null;
    return A2ADeepLinkEnvelope.fromJsonString(envelopeJson);
  }

  Future<void> clearPendingDeepLink() async {
    await _channel.invokeMethod<void>('clearPendingA2ADeepLink');
  }

  Future<A2ALocalTransportStatus> localTransportStatus() async {
    return _localTransport.status();
  }

  Future<bool> checkLocalTransportPermission() async {
    return _localTransport.checkPermission();
  }

  Future<bool> requestLocalTransportPermission() async {
    return _localTransport.requestPermission();
  }

  Future<A2ALocalTransportStatus> startLocalTransport({
    String peerId = '',
    String agentId = '',
    String displayName = '',
    String publicKey = '',
  }) async {
    return _localTransport.start(
      peerId: peerId,
      agentId: agentId,
      displayName: displayName,
      publicKey: publicKey,
    );
  }

  Future<A2ALocalTransportStatus> stopLocalTransport() async {
    return _localTransport.stop();
  }

  Future<List<A2ALocalPeerAdvertisement>> discoverLocalPeers({
    int timeoutMs = 5000,
  }) async {
    final discoveryWindowMs = timeoutMs.clamp(500, 30000);
    final found = <String, A2ALocalPeerAdvertisement>{};
    final buffered = <A2ALocalTransportEvent>[];
    int discoveryGeneration = 0;
    var generationKnown = false;

    void recordPeer(A2ALocalTransportEvent event) {
      final peer = event.peer;
      if (peer == null || peer.peerId.trim().isEmpty) return;
      final eventGeneration = _localDiscoveryGeneration(event.payload);
      if (discoveryGeneration > 0 && eventGeneration != discoveryGeneration) {
        return;
      }
      found[peer.peerId] = peer;
    }

    late final StreamSubscription<A2ALocalTransportEvent> subscription;
    subscription = localTransportEvents.listen((event) {
      if (!generationKnown) {
        buffered.add(event);
        return;
      }
      recordPeer(event);
    }, onError: (_) {});
    try {
      final discovery = await _localTransport.discover(
        timeoutMs: discoveryWindowMs,
      );
      discoveryGeneration = discovery.generation;
      generationKnown = true;
      for (final peer in discovery.peers) {
        if (peer.peerId.trim().isNotEmpty) found[peer.peerId] = peer;
      }
      for (final event in buffered) {
        recordPeer(event);
      }
      await Future<void>.delayed(Duration(milliseconds: discoveryWindowMs));
      return found.values.toList(growable: false);
    } finally {
      unawaited(subscription.cancel());
    }
  }

  int? _localDiscoveryGeneration(Map<String, dynamic> payload) {
    final raw = payload['generation'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '');
  }

  Future<bool> sendPeerMessage(
    A2APeerMessage message, {
    required String endpoint,
  }) async {
    try {
      final sent = await _localTransport.send(message, endpoint: endpoint);
      recordDeliveryStatus(
        message,
        status: sent ? 'sent' : 'failed',
        error: sent ? '' : 'local transport send failed',
      );
      return sent;
    } catch (error) {
      recordDeliveryStatus(message, status: 'failed', error: error.toString());
      rethrow;
    }
  }

  Future<bool> sendDiagnosticPeerMessage(
    A2APeerMessage message, {
    required String endpoint,
  }) {
    return _localTransport.send(message, endpoint: endpoint);
  }

  Stream<A2ALocalTransportEvent> get localTransportEvents {
    return _localTransportEvents ??= _createLocalTransportEvents();
  }

  Stream<A2ALocalTransportEvent> _createLocalTransportEvents() {
    StreamSubscription<A2ALocalTransportEvent>? liveSubscription;
    Timer? drainTimer;
    var draining = false;
    late final StreamController<A2ALocalTransportEvent> controller;

    Future<void> drainBacklog() async {
      if (draining || controller.isClosed) return;
      draining = true;
      try {
        for (final event in await _localTransport.drainEvents()) {
          if (!controller.isClosed) controller.add(event);
        }
      } catch (error, stackTrace) {
        if (!controller.isClosed) controller.addError(error, stackTrace);
      } finally {
        draining = false;
      }
    }

    controller = StreamController<A2ALocalTransportEvent>.broadcast(
      onListen: () {
        unawaited(drainBacklog());
        liveSubscription ??= _eventChannel
            .receiveBroadcastStream()
            .map(A2ALocalTransportEvent.fromEvent)
            .where((event) => event.action.startsWith('a2aLocal'))
            .listen(
              controller.add,
              onError: controller.addError,
            );
        drainTimer ??= Timer.periodic(
          const Duration(milliseconds: 500),
          (_) => unawaited(drainBacklog()),
        );
      },
      onCancel: () async {
        drainTimer?.cancel();
        drainTimer = null;
        await liveSubscription?.cancel();
        liveSubscription = null;
      },
    );
    return controller.stream;
  }

  T _decode<T>(String raw, T Function(Map<String, dynamic>) decode) {
    final decoded = jsonDecode(raw);
    if (decoded is Map && decoded['error'] != null) {
      throw StateError(decoded['error'].toString());
    }
    return decode(Map<String, dynamic>.from(decoded as Map));
  }
}
