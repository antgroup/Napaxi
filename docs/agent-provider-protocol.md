# Agent Provider Protocol

Agent Provider SDK is the provider-side integration surface for apps that want
to expose app-owned actions to an Agent host. The host turns user intent into an
auditable `ActionProposal`. The provider app confirms, risk-checks, executes,
and returns a trusted `ActionResult`.

This SDK intentionally avoids brand-prefixed public API names. Provider apps use
functional names such as `AgentProvider`, `AgentPackage`, `AgentAction`,
`ActionProposal`, and `ActionResult`.

## Roles

- Host: owns the Agent runtime, proposal creation, capability policy, and model
  tool loop.
- Provider app: owns user confirmation, login state, risk controls, business
  execution, and result authenticity.
- Agent Provider SDK: helps provider apps define packages, parse handoff
  intents, validate proposals, and build results.

The SDK does not provide silent cross-app execution and does not store provider
credentials.

## Package

A provider app declares one `AgentPackage` with one or more actions:

```json
{
  "provider_id": "provider.test",
  "agent_id": "provider.agent",
  "display_name": "Provider Agent",
  "description": "Agent backed by a provider app.",
  "system_prompt": "Handle provider actions.",
  "actions": [
    {
      "action_id": "provider.order.create",
      "tool_name": "app_action_provider_order_create",
      "description": "Create an order proposal.",
      "parameters": { "type": "object", "properties": {} },
      "result_schema": { "type": "object" },
      "risk": "high",
      "confirmation_policy": "provider_required",
      "execution_modes": ["app_handoff"],
      "timeout_seconds": 600
    }
  ],
  "handoff": {},
  "result": {}
}
```

Provider action tool names continue to use the host-side
`app_action_` prefix so descriptor and invocation admission can map to the
compiled Agent App Action capability.

## Android Handoff

Provider apps expose two Android entry points:

- Install entry: receives trusted install requests and returns an
  `AgentPackage`.
- Action entry: receives an `ActionProposal` after the Agent has been installed
  and bound to the app identity.

Install entry:

- Intent action: `agent.provider.action.INSTALL_AGENT`
- Request extra: `agent.provider.extra.INSTALL_REQUEST_JSON`
- Result extra: `agent.provider.extra.INSTALL_RESULT_JSON`

The install request contains `protocol_version`, `request_id`, `nonce`,
`host_package_name`, `created_at`, and `expires_at`. Protocol v2 also includes
`host_signing_cert_sha256`, `host_instance_id`, and `host_shared_secret` for
trusted proposal signing. The install result must echo `request_id` and
`nonce` and include the package under `package`.

```kotlin
val request = AgentProvider.parseInstallRequest(intent) ?: return
setResult(
    Activity.RESULT_OK,
    AgentProvider.buildInstallResultIntent(packageDef, request),
)
finish()
```

For actions that may run without provider UI, use the trusted install helper:

```kotlin
setResult(
    Activity.RESULT_OK,
    AgentProviderSecurity.handleTrustedInstallRequest(
        activity = this,
        packageDef = packageDef,
        store = TrustedHostStore(this, providerId),
    ),
)
finish()
```

The host ignores any `install_binding` returned by the provider. It reads the
Android package name, action Activity, and signing certificate digest from the
system and writes that trusted binding before registering the package.

Host to provider app:

- Intent action: `agent.provider.action.HANDLE_PROPOSAL`
- Proposal extra: `agent.provider.extra.PROPOSAL_JSON`
- Optional package extra: `agent.provider.extra.PACKAGE_JSON`
- Optional action extra: `agent.provider.extra.ACTION_JSON`

Provider app code:

```kotlin
val proposal = AgentProvider.parseProposal(intent) ?: return
val validation = AgentProvider.validateProposal(
    proposal = proposal,
    packageDef = packageDef,
    nowMillis = System.currentTimeMillis(),
)
if (!validation.isValid) {
    return
}
```

The provider app then performs its own UI confirmation, risk checks, and
business execution.

`validateProposal` is basic schema validation only. It does not prove that the
proposal came from the trusted host. Silent, quiet, high-risk, or no-UI actions
must use trusted validation:

```kotlin
val trust = AgentProviderSecurity.validateTrustedProposal(
    activity = this,
    proposal = proposal,
    packageDef = packageDef,
    store = TrustedHostStore(this, providerId),
    nowMillis = System.currentTimeMillis(),
)
```

Trusted validation checks the Android caller package/signature, proposal HMAC
signature, expiry, nonce/idempotency fields, and local replay store. Untrusted
requests may be downgraded to explicit provider confirmation or rejected, but
must not run silently.

## Result Return

Provider app returns an `ActionResult` through Activity result or a callback URI:

```kotlin
val result = ActionResult(
    requestId = proposal.requestId,
    status = ActionResultStatus.SUCCEEDED,
    resultJson = """{"order_id":"order-1"}""",
    completedAt = Instant.now().toString(),
)
setResult(Activity.RESULT_OK, AgentProvider.buildResultIntent(result))
finish()
```

Result intent:

- Intent action: `agent.provider.action.RESULT`
- Result extra: `agent.provider.extra.RESULT_JSON`

Callback URI helpers append the encoded result JSON under the `result` query
parameter. Hosts that issue callback URIs must bind callbacks to the original
pending proposal.

## Validation Rules

Provider apps should reject proposals when:

- `provider_id` does not match the package.
- `agent_id` does not match the package.
- `action_id` is not declared by the package.
- `tool_name` is present and does not match the action.
- `expires_at` is invalid or already expired.
- `nonce` is missing.
- `idempotency_key` is missing.
- trusted execution is requested but host binding, caller signature, proposal
  signature, or replay checks fail.

High and critical risk actions should require provider-owned confirmation. The
host must not be treated as a substitute for provider confirmation.

## Repository Ownership

- `packages/agent_provider/android/`: Android provider-side SDK.
- `packages/agent_provider/ios/`: iOS provider-side SDK.
- `docs/agent-provider-protocol.md`: provider protocol and integration notes.
- `crates/core/` and host adapters continue to own Agent runtime, proposal
  lifecycle, capability policy, and result broker behavior.

Demo apps may later exercise this SDK, but reusable provider-side logic belongs
in `packages/agent_provider/android/` and `packages/agent_provider/ios/`.

## Install Security

The host binds installed Agents to Android identity, not only to
`provider_id`. A trusted install record stores:

- `platform`: `android`
- `app_package_name`
- `activity_name`
- `signing_cert_sha256`
- `installed_at`
- `install_request_id`
- `protocol_version`

Before every action handoff, the host re-reads the provider app signing
certificate and rejects execution if the digest no longer matches. Provider apps
may also launch the host with `agent.host.action.INSTALL_PROVIDER_AGENT`, but the
host must still perform the reverse install request and must not trust inline
package JSON from the launch intent.

## iOS Handoff

iOS V1 uses foreground URL handoff. The host does not scan installed apps and
does not read another app's signing certificate. Provider apps should use
Universal Links for production handoff and may use custom URL schemes only for
demo or development flows.

Provider-initiated install:

- Provider opens the host with `install_url`, `action_url`,
  `universal_link_domain`, and optional `ios_bundle_id` / `ios_team_id`.
- The host creates a protocol v2 `AgentInstallRequest` with `request_id`,
  `nonce`, `host_instance_id`, `host_shared_secret`, host bundle metadata, and
  `callback_url`.
- The host opens the provider `install_url` with an `install_request` query
  parameter containing the request JSON.
- The provider SDK stores the trusted host binding and returns an
  `install_result` query parameter to the callback URL.
- The host registers the returned `AgentPackage` with an iOS install binding.

Action handoff:

- The host opens the provider `action_url` with `proposal`, `action`, `package`,
  and `callback_url` query parameters.
- The provider validates the proposal and, for quiet or high-risk flows, must
  call trusted validation before executing without an explicit confirmation UI.
- The provider returns an `ActionResult` in the callback URL `result` query
  parameter.

An iOS install binding stores:

- `platform`: `ios`
- `ios_bundle_id`
- `ios_team_id`
- `install_url`
- `action_url`
- `universal_link_domain`
- `host_bundle_id`
- `host_team_id`
- `host_callback_scheme`
- `host_instance_id`

The host keeps `host_shared_secret` for proposal signing, but must not include
it in action dispatch payloads sent back to the provider.

## App-to-Agent Triggers

Installed providers can also request an Agent turn. V1 has a cross-platform
foreground handoff, and Android may additionally use a background ingress
service when the host advertised it during install.

Providers send an `AgentTriggerRequest` with protocol v2 fields:

- `request_id`, `provider_id`, `agent_id`, `message`, `source`, `event_type`.
- `payload`, `created_at`, `expires_at`, `nonce`, and `idempotency_key`.
- `host_instance_id`, `signature_algorithm = "hmac-sha256-v1"`, and
  `signature`.

The signature uses the `host_shared_secret` established during install and
covers the request identity, provider/agent ids, message, source, event type,
canonical payload hash, timestamps, nonce, idempotency key, and host instance.
The host accepts automatic execution only when the trigger matches an installed
Agent package binding, is unexpired, has not been replayed, and has a valid
signature. A provider can only trigger its own bound Agent; ordinary deep links
must not enter this automatic execution path.

Android providers use `agent.host.action.TRIGGER_AGENT` with
`agent.provider.extra.TRIGGER_REQUEST_JSON`. iOS providers use
`agent-host://agent-provider/trigger?trigger_request=...`.

iOS quiet execution is not true background execution. A trusted quiet action may
skip the provider confirmation page, but the foreground handoff still switches
to the provider app and then back to the host.

## Android Background Triggers

Android hosts may additionally advertise a background trigger ingress during the
install handshake:

- `background_trigger_supported = true`
- `host_background_trigger_service = "<host package service class>"`

The provider stores these fields in `TrustedHostBinding`. When a foreground
provider event should notify the host without switching apps, call
`AgentProvider.submitBackgroundTrigger(context, request, binding)`. The SDK
signs the request, binds the host service with an explicit component, submits the
trigger JSON over AIDL, reads an acknowledgement, and unbinds.

The host ingress service only receives triggers. It must not execute tools or
accept action results directly. On receipt, the host verifies:

- Binder caller UID resolves to the provider package installed for this Agent.
- The provider signing certificate still matches the install binding.
- The trigger has a valid HMAC signature, host instance, expiry, nonce, and
  idempotency key.
- The provider and agent ids match the installed package binding.

Acknowledgement statuses are:

- `accepted`: the host runtime was active and consumed the trigger.
- `queued`: the trigger was persisted; the host will resume from foreground
  service or notification.
- `rejected`: validation failed.
- `unsupported`: the binding has no background trigger service.
- `host_unavailable`: the host service could not be bound or timed out.

V1 does not promise cold-process, notification-free execution. If the host
runtime is not active, the host should persist the trigger, start or keep its
foreground service when allowed, and show a user-visible notification to continue
execution.
