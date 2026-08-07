import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napaxi_flutter/api/agent_provider_install_api.dart';
import 'package:napaxi_flutter/models/agent_app.dart';
import 'package:napaxi_flutter/models/agent_provider_install.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('AgentProviderSelection encodes one-turn canonical marker', () {
    const selection = AgentProviderSelection(providerId: 'demo.notes');

    expect(
      selection.applyToMessage('create a note'),
      '@{provider:demo.notes} create a note',
    );
  });

  const channel = MethodChannel('com.napaxi.flutter/background');

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('discoverProviderForPackage resolves an installed provider', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'listAgentProviders') {
            return <Map<String, Object>>[
              {
                'packageName': 'demo.generated.notes',
                'installActivityName': 'InstallActivity',
                'activityName': 'ActionActivity',
                'label': 'Generated Notes',
                'packageVersionCode': 7,
                'packageLastUpdateTimeMs': 123456,
                'trustedRefreshSupported': true,
              },
            ];
          }
          return null;
        });
    final api = AgentProviderInstallApi(registerPackage: (package) => package);

    final provider = await api.discoverProviderForPackage(
      'demo.generated.notes',
    );

    expect(provider?.label, 'Generated Notes');
    expect(provider?.packageVersionCode, 7);
    expect(provider?.packageLastUpdateTimeMs, 123456);
    expect(provider?.trustedRefreshSupported, isTrue);
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
            return {'packageName': 'host.app', 'signingCertSha256': 'host123'};
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
            return {'packageName': 'host.app', 'signingCertSha256': 'host123'};
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
            expect(
              request['callback_url'],
              'agent-host://agent-provider/install-callback',
            );
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

  test('requestInstall reuses one stable host instance id', () async {
    final requests = <Map<String, dynamic>>[];
    final api = AgentProviderInstallApi(
      registerPackage: (package) => package,
      channel: channel,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getAgentProviderHostInfo') {
            return {'packageName': 'host.app', 'signingCertSha256': 'host123'};
          }
          if (call.method == 'requestAgentProviderInstall') {
            final args = Map<String, dynamic>.from(call.arguments as Map);
            final request = Map<String, dynamic>.from(
              jsonDecode(args['requestJson'] as String) as Map,
            );
            requests.add(request);
            return _installResponse(request);
          }
          fail('unexpected method ${call.method}');
        });

    const provider = AgentProviderDescriptor(
      packageName: 'trusted.app',
      installActivityName: 'trusted.InstallActivity',
      activityName: 'trusted.Activity',
    );
    await api.requestInstall(provider);
    await api.requestInstall(provider);

    expect(requests, hasLength(2));
    expect(requests[0]['host_instance_id'], requests[1]['host_instance_id']);
    expect(
      requests[0]['host_shared_secret'],
      isNot(requests[1]['host_shared_secret']),
    );
  });

  test(
    'restoreBinding preserves trusted identity and does not reregister',
    () async {
      var registrations = 0;
      Map<String, dynamic>? restoreRequest;
      final api = AgentProviderInstallApi(
        registerPackage: (package) {
          registrations += 1;
          return package;
        },
        channel: channel,
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'listAgentProviders') {
              return <Map<String, String>>[
                {
                  'packageName': 'trusted.app',
                  'installActivityName': 'trusted.InstallActivity',
                  'activityName': 'trusted.Activity',
                  'label': 'Provider Agent',
                  'signingCertSha256': 'provider123',
                },
              ];
            }
            if (call.method == 'getAgentProviderHostInfo') {
              return {
                'packageName': 'host.app',
                'signingCertSha256': 'host123',
              };
            }
            if (call.method == 'requestAgentProviderInstall') {
              final args = Map<String, dynamic>.from(call.arguments as Map);
              restoreRequest = Map<String, dynamic>.from(
                jsonDecode(args['requestJson'] as String) as Map,
              );
              return _installResponse(restoreRequest!);
            }
            fail('unexpected method ${call.method}');
          });
      const installed = AgentAppPackage(
        providerId: 'provider',
        agentId: 'provider.agent',
        displayName: 'Provider Agent',
        installBinding: const AgentAppInstallBinding(
          platform: 'android',
          appPackageName: 'trusted.app',
          activityName: 'trusted.Activity',
          signingCertSha256: 'provider123',
          installedAt: '2026-05-26T00:00:00Z',
          installRequestId: 'install-1',
          protocolVersion: 2,
          hostPackageName: 'host.app',
          hostSigningCertSha256: 'host123',
          hostInstanceId: 'host-instance-existing',
          hostSharedSecret: 'host-secret-existing',
        ),
      );

      await api.restoreBinding(installed);

      expect(restoreRequest?['host_instance_id'], 'host-instance-existing');
      expect(restoreRequest?['host_shared_secret'], 'host-secret-existing');
      expect(registrations, 0);
    },
  );

  test(
    'refreshBinding preserves identity and registers latest manifest',
    () async {
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
            if (call.method == 'listAgentProviders') {
              return <Map<String, Object>>[
                {
                  'packageName': 'trusted.app',
                  'installActivityName': 'trusted.InstallActivity',
                  'activityName': 'trusted.Activity',
                  'signingCertSha256': 'provider123',
                  'packageVersionCode': 2,
                  'packageLastUpdateTimeMs': 2000,
                  'trustedRefreshSupported': true,
                },
              ];
            }
            if (call.method == 'getAgentProviderHostInfo') {
              return {
                'packageName': 'host.app',
                'signingCertSha256': 'host123',
              };
            }
            if (call.method == 'requestAgentProviderInstall') {
              final args = Map<String, dynamic>.from(call.arguments as Map);
              final request = Map<String, dynamic>.from(
                jsonDecode(args['requestJson'] as String) as Map,
              );
              return _installResponse(
                request,
                appVersionCode: 2,
                appLastUpdateTimeMs: 2000,
                trustedRefreshSupported: true,
              );
            }
            fail('unexpected method ${call.method}');
          });
      const installed = AgentAppPackage(
        providerId: 'provider',
        agentId: 'provider.agent',
        displayName: 'Provider Agent',
        installBinding: const AgentAppInstallBinding(
          platform: 'android',
          appPackageName: 'trusted.app',
          activityName: 'trusted.Activity',
          signingCertSha256: 'provider123',
          installedAt: '2026-05-26T00:00:00Z',
          installRequestId: 'install-1',
          protocolVersion: 2,
          hostPackageName: 'host.app',
          hostSigningCertSha256: 'host123',
          hostInstanceId: 'host-instance-existing',
          hostSharedSecret: 'host-secret-existing',
        ),
      );

      final refreshed = await api.refreshBinding(installed);

      expect(registered, same(refreshed));
      expect(refreshed.installBinding?.appVersionCode, 2);
      expect(refreshed.installBinding?.appLastUpdateTimeMs, 2000);
      expect(refreshed.installBinding?.trustedRefreshSupported, isTrue);
    },
  );

  test(
    'action executor restores host binding and retries exactly once',
    () async {
      var actionAttempts = 0;
      var repairs = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'executeAgentProviderAction');
            actionAttempts += 1;
            return {
              'resultJson': jsonEncode({
                'request_id': 'request-1',
                'status': actionAttempts == 1 ? 'failed' : 'succeeded',
                'result': actionAttempts == 1 ? {} : {'ok': true},
                if (actionAttempts == 1)
                  'error': 'host_not_bound: No trusted Host binding exists.',
                'completed_at': '2026-05-26T00:00:00Z',
              }),
            };
          });
      final executor = AndroidAgentProviderActionExecutor(
        channel: channel,
        repairBinding: _TestBindingRepair((request) async {
          repairs += 1;
          expect(request.proposal.requestId, 'request-1');
          return true;
        }),
      );

      final result = await executor.execute(_actionRequest());

      expect(result.status, 'succeeded');
      expect(actionAttempts, 2);
      expect(repairs, 1);
    },
  );

  test(
    'action executor repairs a rejected signature and retries exactly once',
    () async {
      var actionAttempts = 0;
      var repairs = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'executeAgentProviderAction');
            actionAttempts += 1;
            return {
              'resultJson': jsonEncode({
                'request_id': 'request-1',
                'status': actionAttempts == 1 ? 'failed' : 'succeeded',
                'result': actionAttempts == 1 ? {} : {'ok': true},
                if (actionAttempts == 1)
                  'error': 'signature_invalid: Proposal signature is invalid.',
                'completed_at': '2026-05-26T00:00:00Z',
              }),
            };
          });
      final executor = AndroidAgentProviderActionExecutor(
        channel: channel,
        repairBinding: _TestBindingRepair((request) async {
          repairs += 1;
          expect(request.proposal.requestId, 'request-1');
          return true;
        }),
      );

      final result = await executor.execute(_actionRequest());

      expect(result.status, 'succeeded');
      expect(actionAttempts, 2);
      expect(repairs, 1);
    },
  );

  test('structured host_not_bound error is normalized for recovery', () {
    final result = AgentAppActionResult.fromMap({
      'request_id': 'request-1',
      'status': 'failed',
      'result': <String, dynamic>{},
      'error': {
        'code': 'host_not_bound',
        'message': 'No trusted Host binding exists.',
        'phase': 'pre_execution',
        'retryable': true,
      },
      'completed_at': '2026-05-26T00:00:00Z',
    });

    expect(result.errorCode, 'host_not_bound');
    expect(result.isHostBindingMissing, isTrue);
    expect(result.isTrustedBindingRejected, isTrue);
  });

  test('signature_invalid is safe for one trusted binding repair', () {
    final result = AgentAppActionResult.fromMap({
      'request_id': 'request-1',
      'status': 'failed',
      'result': <String, dynamic>{},
      'error': 'signature_invalid: Proposal signature is invalid.',
      'completed_at': '2026-05-26T00:00:00Z',
    });

    expect(result.errorCode, 'signature_invalid');
    expect(result.isHostBindingMissing, isFalse);
    expect(result.isTrustedBindingRejected, isTrue);
  });

  test('listDiagnostics decodes trusted provider crash reports', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'listAgentProviderDiagnostics');
          final args = Map<String, dynamic>.from(call.arguments as Map);
          final package = jsonDecode(args['packageJson'] as String) as Map;
          expect(package['provider_id'], 'provider');
          expect(args['operation'], 'list');
          expect(args['detailedLogging'], isFalse);
          return {
            'supported': true,
            'responseJson': jsonEncode({
              'status': 'succeeded',
              'request_id': 'diagnostics-1',
              'reports': [
                {
                  'id': 'crash-1',
                  'kind': 'java_crash',
                  'timestamp': '2026-08-05T01:00:00Z',
                  'app_package': 'trusted.app',
                  'version_name': '1.0',
                  'version_code': 1,
                  'exception_type': 'java.lang.NullPointerException',
                  'message': 'boom',
                  'stack_trace': 'MainActivity.java:42',
                },
              ],
              'logs': [
                {
                  'id': 'log-1',
                  'timestamp': '2026-08-05T00:59:59Z',
                  'level': 'error',
                  'module': 'storage',
                  'event': 'save_failed',
                  'message': 'Unable to save',
                  'trace_id': 'trace-1',
                },
              ],
              'detailed_logging_enabled': true,
            }),
          };
        });
    final api = AgentProviderInstallApi(
      registerPackage: (package) => package,
      channel: channel,
    );

    final snapshot = await api.listDiagnostics(_installedPackage());

    expect(snapshot.supported, isTrue);
    expect(snapshot.reports, hasLength(1));
    expect(snapshot.reports.single.id, 'crash-1');
    expect(snapshot.reports.single.summary, contains('NullPointerException'));
    expect(snapshot.logs.single.event, 'save_failed');
    expect(snapshot.logs.single.traceId, 'trace-1');
    expect(snapshot.detailedLoggingEnabled, isTrue);
  });

  test('setDetailedDiagnostics sends an explicit configure request', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final args = Map<String, dynamic>.from(call.arguments as Map);
          expect(args['operation'], 'configure');
          expect(args['detailedLogging'], isTrue);
          return {
            'supported': true,
            'responseJson': jsonEncode({
              'status': 'succeeded',
              'reports': <Object>[],
              'logs': <Object>[],
              'detailed_logging_enabled': true,
            }),
          };
        });
    final api = AgentProviderInstallApi(
      registerPackage: (package) => package,
      channel: channel,
    );

    final snapshot = await api.setDetailedDiagnostics(
      _installedPackage(),
      true,
    );

    expect(snapshot.supported, isTrue);
    expect(snapshot.detailedLoggingEnabled, isTrue);
  });

  test('listDiagnostics keeps older providers compatible', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'listAgentProviderDiagnostics');
          return {'supported': false};
        });
    final api = AgentProviderInstallApi(
      registerPackage: (package) => package,
      channel: channel,
    );

    final snapshot = await api.listDiagnostics(_installedPackage());

    expect(snapshot.supported, isFalse);
    expect(snapshot.reports, isEmpty);
  });
}

Map<String, dynamic> _installResponse(
  Map<String, dynamic> request, {
  int appVersionCode = 0,
  int appLastUpdateTimeMs = 0,
  bool trustedRefreshSupported = false,
}) => {
  'installResultJson': jsonEncode({
    'status': 'succeeded',
    'request_id': request['request_id'],
    'nonce': request['nonce'],
    'package': jsonDecode(_packageJson()),
    'completed_at': '2026-05-26T00:00:00Z',
  }),
  'installBinding': {
    'platform': 'android',
    'app_package_name': 'trusted.app',
    'activity_name': 'trusted.Activity',
    'signing_cert_sha256': 'provider123',
    if (appVersionCode > 0) 'app_version_code': appVersionCode,
    if (appLastUpdateTimeMs > 0) 'app_last_update_time_ms': appLastUpdateTimeMs,
    if (trustedRefreshSupported)
      'trusted_refresh_supported': trustedRefreshSupported,
    'installed_at': '2026-05-26T00:00:00Z',
    'install_request_id': request['request_id'],
    'protocol_version': request['protocol_version'],
    'host_package_name': request['host_package_name'],
    'host_signing_cert_sha256': request['host_signing_cert_sha256'],
    'host_instance_id': request['host_instance_id'],
    'host_shared_secret': request['host_shared_secret'],
  },
};

AgentAppActionRequest _actionRequest() => const AgentAppActionRequest(
  proposal: const AgentAppActionProposal(
    requestId: 'request-1',
    providerId: 'provider',
    agentId: 'provider.agent',
    actionId: 'provider.order.create',
    toolName: 'app_action_order_create',
    createdAt: '2026-05-26T00:00:00Z',
    expiresAt: '2030-05-26T00:00:00Z',
    nonce: 'nonce-1',
    idempotencyKey: 'request-1',
  ),
  action: const AgentAppActionManifest(
    actionId: 'provider.order.create',
    toolName: 'app_action_order_create',
    description: 'Create an order.',
  ),
  package: const {'provider_id': 'provider', 'agent_id': 'provider.agent'},
);

class _TestBindingRepair implements AgentProviderBindingRepair {
  _TestBindingRepair(this._callback);

  final Future<bool> Function(AgentAppActionRequest request) _callback;

  @override
  Future<bool> repair(AgentAppActionRequest request) => _callback(request);
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

AgentAppPackage _installedPackage() => const AgentAppPackage(
  providerId: 'provider',
  agentId: 'provider.agent',
  displayName: 'Provider Agent',
  installBinding: AgentAppInstallBinding(
    platform: 'android',
    appPackageName: 'trusted.app',
    activityName: 'trusted.Activity',
    signingCertSha256: 'provider123',
    installedAt: '2026-05-26T00:00:00Z',
    installRequestId: 'install-1',
    protocolVersion: 2,
    hostPackageName: 'host.app',
    hostSigningCertSha256: 'host123',
    hostInstanceId: 'host-instance',
    hostSharedSecret: 'host-secret',
  ),
);
