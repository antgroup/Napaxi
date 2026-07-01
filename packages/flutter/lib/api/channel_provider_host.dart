import 'dart:async';

import 'channel_api.dart';
import '../models/channel.dart';
import '../models/channel_provider.dart';

abstract class NapaxiChannelProvider {
  NapaxiChannelProviderManifest get manifest;

  Future<void> start(NapaxiChannelProviderContext context) async {}

  Future<void> stop() async {}

  Future<NapaxiChannelOutboundDeliveryResult> deliverOutbound(
    NapaxiChannelOutboundMessage message,
  );
}

class NapaxiChannelProviderContext {
  NapaxiChannelProviderContext({
    required this.queue,
    required this.manifest,
  });

  final NapaxiChannelQueue queue;
  final NapaxiChannelProviderManifest manifest;

  NapaxiChannelAcceptedReceipt submitInbound(
    NapaxiChannelInboundMessage message,
  ) {
    return queue.submitInbound(message);
  }

  NapaxiChannelAcceptedReceipt submitTextInbound({
    required NapaxiChannelPeer peer,
    required NapaxiChannelActor sender,
    required String text,
    String? platformMessageId,
    String? threadId,
    Map<String, dynamic>? raw,
  }) {
    return submitInbound(
      NapaxiChannelInboundMessage(
        channelName: manifest.channelName,
        accountId: manifest.accountId,
        peer: peer,
        sender: sender,
        platformMessageId: platformMessageId,
        threadId: threadId,
        text: text,
        raw: raw,
      ),
    );
  }

  List<NapaxiChannelOutboundMessage> leaseOutbound({int limit = 20}) {
    return queue.leaseOutbound(
      manifest.channelName,
      accountId: manifest.accountId,
      limit: limit,
    );
  }

  bool ackOutbound(
    String outboundId, {
    Map<String, dynamic> receipt = const {},
  }) {
    return queue.ackOutbound(outboundId, receipt: receipt);
  }

  bool failOutbound(String outboundId, String error) {
    return queue.failOutbound(outboundId, error);
  }
}

class NapaxiChannelProviderHost {
  NapaxiChannelProviderHost(this.queue);

  final NapaxiChannelQueue queue;
  final Map<String, _RegisteredChannelProvider> _providers = {};
  final StreamController<NapaxiChannelProviderEvent> _events =
      StreamController<NapaxiChannelProviderEvent>.broadcast();

  Stream<NapaxiChannelProviderEvent> get events => _events.stream;

  List<NapaxiChannelProviderManifest> listProviderManifests() {
    return _providers.values
        .map((provider) => provider.provider.manifest)
        .toList(growable: false);
  }

  bool hasProvider(String channelName, {String? accountId}) {
    if (accountId != null) {
      return _providers.containsKey(
        _providerKey(channelName, _normalizedProviderAccountId(accountId)),
      );
    }
    return _providers.values.any(
      (registered) => registered.provider.manifest.channelName == channelName,
    );
  }

  NapaxiChannelProviderManifest? providerManifest(
    String channelName, {
    String? accountId,
  }) {
    if (accountId != null) {
      return _providers[_providerKey(
        channelName,
        _normalizedProviderAccountId(accountId),
      )]
          ?.provider
          .manifest;
    }
    for (final registered in _providers.values) {
      final manifest = registered.provider.manifest;
      if (manifest.channelName == channelName) return manifest;
    }
    return null;
  }

  Future<void> registerProvider(
    NapaxiChannelProvider provider, {
    bool autoPump = false,
    Duration pollInterval = const Duration(seconds: 2),
  }) async {
    final manifest = provider.manifest;
    if (manifest.channelName.trim().isEmpty) {
      throw ArgumentError.value(manifest.channelName, 'channelName');
    }
    final accountId = _normalizedProviderAccountId(manifest.accountId);
    final key = _providerKey(manifest.channelName, accountId);
    if (_providers.containsKey(key)) {
      throw StateError('channel provider already registered: '
          '${manifest.channelName}/$accountId');
    }
    final wasRegistered = _isChannelRegistered(manifest.channelName);
    final registered = queue.register(manifest.toRegistration());
    // Channel registration is provider metadata. A stale persisted record or a
    // transient write miss must not prevent the live transport from attaching;
    // inbound/outbound queue operations still carry channel/account identity.
    final context = NapaxiChannelProviderContext(
      queue: queue,
      manifest: manifest,
    );
    try {
      await provider.start(context);
    } catch (_) {
      if (registered && !wasRegistered) {
        queue.unregister(manifest.channelName);
      }
      rethrow;
    }
    Timer? timer;
    if (autoPump) {
      timer = Timer.periodic(pollInterval, (_) {
        unawaited(pump(manifest.channelName, accountId: accountId));
      });
    }
    _providers[key] = _RegisteredChannelProvider(
      provider: provider,
      context: context,
      timer: timer,
    );
    _emit(
      NapaxiChannelProviderEvent(
        channelName: manifest.channelName,
        providerId: manifest.providerId,
        type: NapaxiChannelProviderEventType.registered,
      ),
    );
  }

  Future<NapaxiChannelProviderPumpResult> pump(
    String channelName, {
    String? accountId,
    int limit = 20,
  }) async {
    final providers = _registeredProviders(channelName, accountId: accountId);
    if (providers.isEmpty) {
      final suffix = accountId == null ? '' : '/$accountId';
      throw StateError(
        'channel provider is not registered: $channelName$suffix',
      );
    }
    var leased = 0;
    var delivered = 0;
    var failed = 0;
    for (final registered in providers) {
      final outbound = registered.context.leaseOutbound(limit: limit);
      leased += outbound.length;
      for (final message in outbound) {
        final result = await registered.provider.deliverOutbound(message);
        if (result.delivered) {
          registered.context.ackOutbound(
            message.id,
            receipt: result.receipt ?? const {},
          );
          delivered += 1;
          _emit(
            NapaxiChannelProviderEvent(
              channelName: channelName,
              providerId: registered.provider.manifest.providerId,
              type: NapaxiChannelProviderEventType.outboundDelivered,
              outboundId: message.id,
            ),
          );
        } else {
          registered.context.failOutbound(
            message.id,
            result.error ?? 'delivery_failed',
          );
          failed += 1;
          _emit(
            NapaxiChannelProviderEvent(
              channelName: channelName,
              providerId: registered.provider.manifest.providerId,
              type: NapaxiChannelProviderEventType.outboundFailed,
              outboundId: message.id,
              error: result.error,
            ),
          );
        }
      }
    }
    return NapaxiChannelProviderPumpResult(
      channelName: channelName,
      leased: leased,
      delivered: delivered,
      failed: failed,
    );
  }

  Future<void> unregisterProvider(
    String channelName, {
    String? accountId,
    bool unregisterChannel = true,
  }) async {
    final registered = accountId == null
        ? _removeFirstProvider(channelName)
        : _providers.remove(
            _providerKey(
              channelName,
              _normalizedProviderAccountId(accountId),
            ),
          );
    if (registered == null) return;
    registered.timer?.cancel();
    await registered.provider.stop();
    if (unregisterChannel && !hasProvider(channelName)) {
      queue.unregister(channelName);
    }
    _emit(
      NapaxiChannelProviderEvent(
        channelName: channelName,
        providerId: registered.provider.manifest.providerId,
        type: NapaxiChannelProviderEventType.unregistered,
      ),
    );
  }

  void dispose() {
    for (final registered in _providers.values) {
      registered.timer?.cancel();
      unawaited(registered.provider.stop());
    }
    _providers.clear();
    unawaited(_events.close());
  }

  void _emit(NapaxiChannelProviderEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  bool _isChannelRegistered(String channelName) {
    return queue.list().any((channel) => channel.name == channelName);
  }

  List<_RegisteredChannelProvider> _registeredProviders(
    String channelName, {
    String? accountId,
  }) {
    if (accountId != null) {
      final registered = _providers[_providerKey(
        channelName,
        _normalizedProviderAccountId(accountId),
      )];
      return registered == null
          ? const <_RegisteredChannelProvider>[]
          : <_RegisteredChannelProvider>[registered];
    }
    return _providers.values
        .where(
          (registered) =>
              registered.provider.manifest.channelName == channelName,
        )
        .toList(growable: false);
  }

  _RegisteredChannelProvider? _removeFirstProvider(String channelName) {
    for (final entry in _providers.entries) {
      if (entry.value.provider.manifest.channelName == channelName) {
        return _providers.remove(entry.key);
      }
    }
    return null;
  }

  static String _providerKey(String channelName, String accountId) {
    return '$channelName\x1F$accountId';
  }

  static String _normalizedProviderAccountId(String accountId) {
    final normalized = accountId.trim();
    return normalized.isEmpty ? 'default' : normalized;
  }
}

class _RegisteredChannelProvider {
  _RegisteredChannelProvider({
    required this.provider,
    required this.context,
    required this.timer,
  });

  final NapaxiChannelProvider provider;
  final NapaxiChannelProviderContext context;
  final Timer? timer;
}
