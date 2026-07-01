import 'channel.dart';

class NapaxiChannelProviderManifest {
  final String providerId;
  final String channelName;
  final String displayName;
  final String description;
  final String accountId;
  final String surfaceKind;
  final List<String> endpointKinds;
  final List<String> modalities;
  final List<String> contentFormats;
  final String transport;
  final List<String> authRequirements;
  final List<String> backgroundRequirements;
  final Map<String, dynamic> config;

  const NapaxiChannelProviderManifest({
    required this.providerId,
    required this.channelName,
    required this.displayName,
    this.description = '',
    this.accountId = 'default',
    this.surfaceKind = NapaxiChannelSurfaceKind.custom,
    this.endpointKinds = const [NapaxiChannelEndpointKind.direct],
    this.modalities = const [NapaxiChannelModality.text],
    this.contentFormats = const [NapaxiChannelContentFormat.plainText],
    this.transport = 'host_adapter',
    this.authRequirements = const [],
    this.backgroundRequirements = const [],
    this.config = const {},
  });

  const NapaxiChannelProviderManifest.im({
    required this.providerId,
    required this.channelName,
    required this.displayName,
    this.description = '',
    this.accountId = 'default',
    this.endpointKinds = const [NapaxiChannelEndpointKind.direct],
    this.modalities = const [NapaxiChannelModality.text],
    this.contentFormats = const [NapaxiChannelContentFormat.plainText],
    this.transport = 'host_adapter',
    this.authRequirements = const [],
    this.backgroundRequirements = const [],
    this.config = const {},
  }) : surfaceKind = NapaxiChannelSurfaceKind.im;

  NapaxiChannelRegistration toRegistration() {
    return NapaxiChannelRegistration(
      name: channelName,
      type: channelName,
      accountId: accountId,
      surfaceKind: surfaceKind,
      endpointKind: endpointKinds.isEmpty ? null : endpointKinds.first,
      modalities: modalities,
      contentFormats: contentFormats,
      transport: transport,
      config: toJson(),
    );
  }

  Map<String, dynamic> toJson() => {
        'provider_id': providerId,
        'channel_name': channelName,
        'display_name': displayName,
        if (description.isNotEmpty) 'description': description,
        'account_id': accountId,
        'surface_kind': surfaceKind,
        if (endpointKinds.isNotEmpty) 'endpoint_kinds': endpointKinds,
        if (modalities.isNotEmpty) 'modalities': modalities,
        if (contentFormats.isNotEmpty) 'content_formats': contentFormats,
        'transport': transport,
        if (authRequirements.isNotEmpty) 'auth_requirements': authRequirements,
        if (backgroundRequirements.isNotEmpty)
          'background_requirements': backgroundRequirements,
        if (config.isNotEmpty) 'config': config,
      };
}

class NapaxiChannelOutboundDeliveryResult {
  final bool delivered;
  final Map<String, dynamic>? receipt;
  final String? error;

  const NapaxiChannelOutboundDeliveryResult._({
    required this.delivered,
    this.receipt,
    this.error,
  });

  const NapaxiChannelOutboundDeliveryResult.delivered({
    Map<String, dynamic> receipt = const {},
  }) : this._(delivered: true, receipt: receipt);

  const NapaxiChannelOutboundDeliveryResult.failed(String error)
      : this._(delivered: false, error: error);
}

class NapaxiChannelProviderPumpResult {
  final String channelName;
  final int leased;
  final int delivered;
  final int failed;

  const NapaxiChannelProviderPumpResult({
    required this.channelName,
    required this.leased,
    required this.delivered,
    required this.failed,
  });

  bool get hadWork => leased > 0;
}

class NapaxiChannelProviderEventType {
  static const registered = 'registered';
  static const unregistered = 'unregistered';
  static const outboundDelivered = 'outbound_delivered';
  static const outboundFailed = 'outbound_failed';

  const NapaxiChannelProviderEventType._();
}

class NapaxiChannelProviderEvent {
  final String channelName;
  final String providerId;
  final String type;
  final String? outboundId;
  final String? error;

  const NapaxiChannelProviderEvent({
    required this.channelName,
    required this.providerId,
    required this.type,
    this.outboundId,
    this.error,
  });
}
