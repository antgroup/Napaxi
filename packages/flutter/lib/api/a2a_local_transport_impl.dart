part of 'a2a_api.dart';

class _A2ALocalTransportApi {
  _A2ALocalTransportApi({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(A2AApi._channelName);

  static const _codec = _A2ALocalTransportCodec();

  final MethodChannel _channel;

  Future<A2ALocalTransportStatus> status() async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'a2aLocalTransportStatus',
    );
    return _codec.decodeStatus(raw);
  }

  Future<bool> checkPermission() async {
    return await _channel.invokeMethod<bool>('checkA2ALocalPermission') ?? true;
  }

  Future<bool> requestPermission() async {
    return await _channel.invokeMethod<bool>('requestA2ALocalPermission') ??
        true;
  }

  Future<A2ALocalTransportStatus> start({
    String peerId = '',
    String agentId = '',
    String displayName = '',
    String publicKey = '',
  }) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'startA2ALocalTransport',
      _codec.startArgs(
        peerId: peerId,
        agentId: agentId,
        displayName: displayName,
        publicKey: publicKey,
      ),
    );
    return _codec.decodeStatus(raw);
  }

  Future<A2ALocalTransportStatus> stop() async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'stopA2ALocalTransport',
    );
    return _codec.decodeStatus(raw);
  }

  Future<_A2ALocalDiscoveryResult> discover({
    int timeoutMs = 5000,
  }) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'discoverA2ALocalPeers',
      _codec.discoverArgs(timeoutMs: timeoutMs),
    );
    return _codec.decodeDiscoveryResult(raw);
  }

  Future<bool> send(
    A2APeerMessage message, {
    required String endpoint,
  }) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'sendA2ALocalMessage',
      _codec.sendArgs(message, endpoint: endpoint),
    );
    return _codec.decodeSendResult(raw);
  }

  Future<List<A2ALocalTransportEvent>> drainEvents() async {
    final raw = await _channel.invokeMethod<List<dynamic>>(
      'drainA2ALocalTransportEvents',
    );
    return (raw ?? const [])
        .map(A2ALocalTransportEvent.fromEvent)
        .where((event) => event.action.startsWith('a2aLocal'))
        .toList(growable: false);
  }
}

class _A2ALocalTransportCodec {
  const _A2ALocalTransportCodec();

  Map<String, dynamic> startArgs({
    String peerId = '',
    String agentId = '',
    String displayName = '',
    String publicKey = '',
  }) {
    return {
      'peerId': peerId,
      'agentId': agentId,
      'displayName': displayName,
      'publicKey': publicKey,
    };
  }

  Map<String, dynamic> discoverArgs({int timeoutMs = 5000}) {
    return {'timeoutMs': timeoutMs};
  }

  Map<String, dynamic> sendArgs(
    A2APeerMessage message, {
    required String endpoint,
  }) {
    return {
      'endpoint': endpoint,
      'messageJson': message.toJsonString(),
    };
  }

  A2ALocalTransportStatus decodeStatus(Object? raw) {
    return A2ALocalTransportStatus.fromJson(dynamicMap(raw));
  }

  _A2ALocalDiscoveryResult decodeDiscoveryResult(Object? raw) {
    final decoded = dynamicMap(raw);
    final peers = (decoded['peers'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => A2ALocalPeerAdvertisement.fromJson(dynamicMap(item)))
        .toList(growable: false);
    return _A2ALocalDiscoveryResult(
      generation: intValue(decoded['generation']),
      peers: peers,
    );
  }

  bool decodeSendResult(Object? raw) {
    final decoded = dynamicMap(raw);
    if (decoded['sent'] == true) return true;
    throw StateError(
      decoded['error']?.toString() ??
          decoded['reason']?.toString() ??
          'A2A local send failed',
    );
  }

  Map<String, dynamic> dynamicMap(Object? raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  int intValue(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }
}

class _A2ALocalDiscoveryResult {
  const _A2ALocalDiscoveryResult({
    required this.generation,
    required this.peers,
  });

  final int generation;
  final List<A2ALocalPeerAdvertisement> peers;
}
