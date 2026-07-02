import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:napaxi_flutter/models/channel.dart';

void main() {
  test('IM channel registration emits core-compatible metadata', () {
    const registration = NapaxiChannelRegistration.im(
      name: 'work-telegram',
      type: 'telegram',
      accountId: 'work',
      endpointKind: NapaxiChannelEndpointKind.direct,
      modalities: [
        NapaxiChannelModality.text,
        NapaxiChannelModality.image,
        NapaxiChannelModality.file,
      ],
      contentFormats: [
        NapaxiChannelContentFormat.plainText,
        NapaxiChannelContentFormat.markdown,
      ],
      transport: 'bot_api',
      config: {
        'allow_from': ['tg:123'],
      },
    );

    final json = registration.toJson();
    expect(json['name'], 'work-telegram');
    expect(json['type'], 'telegram');
    expect(json['account_id'], 'work');
    expect(json['surface_kind'], NapaxiChannelSurfaceKind.im);
    expect(json['endpoint_kind'], NapaxiChannelEndpointKind.direct);
    expect(json['modalities'], [
      NapaxiChannelModality.text,
      NapaxiChannelModality.image,
      NapaxiChannelModality.file,
    ]);
    expect(json['content_formats'], [
      NapaxiChannelContentFormat.plainText,
      NapaxiChannelContentFormat.markdown,
    ]);
    expect(json['transport'], 'bot_api');
    expect((json['config'] as Map)['allow_from'], ['tg:123']);
  });

  test('channel records decode v1 metadata and preserve original config', () {
    final records = decodeChannelRecords(
      jsonEncode([
        {
          'name': 'work-telegram',
          'type': 'telegram',
          'surface_kind': 'im',
          'endpoint_kind': 'direct',
          'modalities': ['text', 'image'],
          'content_formats': ['plain_text', 'markdown'],
          'transport': 'bot_api',
          'capability_id': NapaxiChannelCapability.im,
          'config': {'token': 'redacted'},
          'registered_at': '2026-06-11T00:00:00Z',
          'updated_at': '2026-06-11T00:00:01Z',
        },
      ]),
    );

    expect(records, hasLength(1));
    final record = records.single;
    expect(record.name, 'work-telegram');
    expect(record.type, 'telegram');
    expect(record.surfaceKind, NapaxiChannelSurfaceKind.im);
    expect(record.endpointKind, NapaxiChannelEndpointKind.direct);
    expect(record.modalities, [
      NapaxiChannelModality.text,
      NapaxiChannelModality.image,
    ]);
    expect(record.contentFormats, [
      NapaxiChannelContentFormat.plainText,
      NapaxiChannelContentFormat.markdown,
    ]);
    expect(record.transport, 'bot_api');
    expect(record.capabilityId, NapaxiChannelCapability.im);
    expect(record.config['token'], 'redacted');
    expect(record.registeredAt, '2026-06-11T00:00:00Z');
    expect(record.updatedAt, '2026-06-11T00:00:01Z');
  });

  test('channel adapter messages use stable ingress and outbox wire shape', () {
    const inbound = NapaxiChannelInboundMessage(
      channelName: 'feishu',
      accountId: 'main',
      platformMessageId: 'om_1',
      threadId: 'om_root',
      peer: NapaxiChannelPeer(
        kind: NapaxiChannelEndpointKind.group,
        id: 'oc_group',
        displayName: 'Ops',
      ),
      sender: NapaxiChannelActor(id: 'ou_user', displayName: 'Alice'),
      text: 'ship status?',
      media: [
        NapaxiChannelMedia(
          kind: NapaxiChannelModality.image,
          uri: 'file:///tmp/a.png',
          mimeType: 'image/png',
        ),
      ],
    );
    final inboundJson = inbound.toJson();
    expect(inboundJson['channel_name'], 'feishu');
    expect(
        (inboundJson['peer'] as Map)['kind'], NapaxiChannelEndpointKind.group);
    expect((inboundJson['sender'] as Map)['id'], 'ou_user');
    expect((inboundJson['media'] as List).single['mime_type'], 'image/png');

    final leased = decodeChannelOutboundMessages(
      jsonEncode([
        {
          'id': 'out_1',
          'channel_name': 'qqbot',
          'account_id': 'bot-a',
          'peer': {'kind': 'direct', 'id': 'openid-a'},
          'reply_to_message_id': 'msg_1',
          'text': 'hello',
          'format': 'markdown',
          'lease_id': 'lease_1',
          'status': 'leased',
          'created_at': '2026-06-11T00:00:00Z',
          'updated_at': '2026-06-11T00:00:01Z',
        },
      ]),
    );
    expect(leased.single.channelName, 'qqbot');
    expect(leased.single.peer.id, 'openid-a');
    expect(leased.single.format, NapaxiChannelContentFormat.markdown);
    expect(leased.single.leaseId, 'lease_1');

    final receipt = decodeChannelAcceptedReceipt(
      '{"accepted":true,"id":"in_1","duplicate":true}',
    );
    expect(receipt.accepted, isTrue);
    expect(receipt.duplicate, isTrue);
  });
}
