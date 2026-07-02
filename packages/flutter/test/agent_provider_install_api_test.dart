import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napaxi_flutter/api/agent_provider_install_api.dart';
import 'package:napaxi_flutter/models/agent_app.dart';
import 'package:napaxi_flutter/models/agent_provider_install.dart';

void main() {
  const channel = MethodChannel('com.napaxi.flutter/background');

  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('requestInstall overrides provider supplied binding', () async {
    AgentAppPackage? registered;
    final api = AgentProviderInstallApi(
      registerPackage: (package) {
        registered = package;
        return package;
      },
      channel: channel,
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAgentProviderHostInfo') {
        return {
          'packageName': 'host.app',
          'signingCertSha256': 'host123',
        };
      }
      if (call.method == 'requestAgentProviderInstall') {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final request = jsonDecode(args['requestJson'] as String) as Map;
        final package = _packageJson(
          installBinding: const AgentAppInstallBinding(
            platform: 'android',
            appPackageName: 'forged.app',
            activityName: 'forged.Activity',
            signingCertSha256: 'forged',
            installedAt: '2026-05-26T00:00:00Z',
            installRequestId: 'forged',
            protocolVersion: 1,
          ),
        );
        return {
          'installResultJson': jsonEncode({
            'status': 'succeeded',
            'request_id': request['request_id'],
            'nonce': request['nonce'],
            'package': jsonDecode(package),
            'completed_at': '2026-05-26T00:00:00Z',
          }),
          'installBinding': {
            'platform': 'android',
            'app_package_name': 'trusted.app',
            'activity_name': 'trusted.Activity',
            'signing_cert_sha256': 'abc123',
            'installed_at': '2026-05-26T00:00:00Z',
            'install_request_id': request['request_id'],
            'protocol_version': request['protocol_version'],
            'host_package_name': request['host_package_name'],
            'host_signing_cert_sha256': request['host_signing_cert_sha256'],
            'host_instance_id': request['host_instance_id'],
            'host_shared_secret': request['host_shared_secret'],
          },
        };
      }
      fail('unexpected method ${call.method}');
    });

    final installed = await api.requestInstall(
      const AgentProviderDescriptor(
        packageName: 'trusted.app',
        installActivityName: 'trusted.InstallActivity',
        activityName: 'trusted.Activity',
      ),
    );

    expect(installed.installBinding?.appPackageName, 'trusted.app');
    expect(installed.installBinding?.activityName, 'trusted.Activity');
    expect(installed.installBinding?.protocolVersion, 2);
    expect(installed.installBinding?.hostPackageName, 'host.app');
    expect(installed.installBinding?.hostSigningCertSha256, 'host123');
    expect(installed.installBinding?.hostSharedSecret.isNotEmpty, isTrue);
    expect(registered?.installBinding?.appPackageName, 'trusted.app');
  });

  test('requestInstall rejects mismatched nonce', () async {
    final api = AgentProviderInstallApi(
      registerPackage: (package) => package,
      channel: channel,
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAgentProviderHostInfo') {
        return {
          'packageName': 'host.app',
          'signingCertSha256': 'host123',
        };
      }
      if (call.method == 'requestAgentProviderInstall') {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final request = jsonDecode(args['requestJson'] as String) as Map;
        return {
          'installResultJson': jsonEncode({
            'status': 'succeeded',
            'request_id': request['request_id'],
            'nonce': 'other',
            'package': jsonDecode(_packageJson()),
            'completed_at': '2026-05-26T00:00:00Z',
          }),
          'installBinding': {
            'platform': 'android',
            'app_package_name': 'trusted.app',
            'activity_name': 'trusted.Activity',
            'signing_cert_sha256': 'abc123',
            'installed_at': '2026-05-26T00:00:00Z',
            'install_request_id': request['request_id'],
            'protocol_version': 1,
          },
        };
      }
      fail('unexpected method ${call.method}');
    });

    await expectLater(
      api.requestInstall(
        const AgentProviderDescriptor(
          packageName: 'trusted.app',
          installActivityName: 'trusted.InstallActivity',
          activityName: 'trusted.Activity',
        ),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('requestInstall maps iOS provider callback binding', () async {
    final api = AgentProviderInstallApi(
      registerPackage: (package) => package,
      channel: channel,
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAgentProviderHostInfo') {
        return {
          'bundleId': 'host.app',
          'teamId': 'HOST123456',
          'callbackScheme': 'agent-host',
        };
      }
      if (call.method == 'requestAgentProviderInstall') {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final provider = Map<String, dynamic>.from(args['provider'] as Map);
        final request = jsonDecode(args['requestJson'] as String) as Map;
        expect(request['host_bundle_id'], 'host.app');
        expect(request['host_team_id'], 'HOST123456');
        expect(request['host_callback_scheme'], 'agent-host');
        expect(request['callback_url'],
            'agent-host://agent-provider/install-callback');
        return {
          'installResultJson': jsonEncode({
            'status': 'succeeded',
            'request_id': request['request_id'],
            'nonce': request['nonce'],
            'package': jsonDecode(_packageJson()),
            'completed_at': '2026-05-26T00:00:00Z',
          }),
          'installBinding': {
            'platform': 'ios',
            'app_package_name': '',
            'activity_name': '',
            'signing_cert_sha256': '',
            'installed_at': '2026-05-26T00:00:00Z',
            'install_request_id': request['request_id'],
            'protocol_version': request['protocol_version'],
            'host_instance_id': request['host_instance_id'],
            'host_shared_secret': request['host_shared_secret'],
            'ios_bundle_id': provider['iosBundleId'],
            'ios_team_id': provider['iosTeamId'],
            'install_url': provider['installUrl'],
            'action_url': provider['actionUrl'],
            'universal_link_domain': provider['universalLinkDomain'],
            'host_bundle_id': request['host_bundle_id'],
            'host_team_id': request['host_team_id'],
            'host_callback_scheme': request['host_callback_scheme'],
          },
        };
      }
      fail('unexpected method ${call.method}');
    });

    final installed = await api.requestInstall(
      const AgentProviderDescriptor(
        platform: 'ios',
        packageName: '',
        installActivityName: '',
        activityName: '',
        label: 'Wallet Agent',
        installUrl: 'https://wallet.example.com/agent/install',
        actionUrl: 'https://wallet.example.com/agent/action',
        universalLinkDomain: 'wallet.example.com',
        iosBundleId: 'demo.wallet.provider',
        iosTeamId: 'TEAM123456',
      ),
    );

    expect(installed.installBinding?.platform, 'ios');
    expect(installed.installBinding?.iosBundleId, 'demo.wallet.provider');
    expect(
      installed.installBinding?.actionUrl,
      'https://wallet.example.com/agent/action',
    );
    expect(installed.installBinding?.hostBundleId, 'host.app');
    expect(installed.installBinding?.hostCallbackScheme, 'agent-host');
    expect(installed.installBinding?.hostSharedSecret.isNotEmpty, isTrue);
  });
}

String _packageJson({AgentAppInstallBinding? installBinding}) {
  return AgentAppPackage(
    providerId: 'provider',
    agentId: 'provider.agent',
    displayName: 'Provider Agent',
    actions: const [
      AgentAppActionManifest(
        actionId: 'provider.order.create',
        toolName: 'app_action_order_create',
        description: 'Create an order.',
      ),
    ],
    installBinding: installBinding,
  ).toJsonString();
}
