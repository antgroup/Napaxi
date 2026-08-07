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

## Explicit provider selection

A Host can make one installed Provider available to the current default Agent
for a single message without switching Agent identity. The canonical prefix is:

```text
@{provider:<provider_id>} <user request>
```

Core removes the marker before model execution, mounts only that Provider's
actions, and persists a friendly `@<display_name>` mention in history. The
Flutter, Android, and iOS SDKs expose `AgentProviderSelection` as a convenience
for constructing this one-turn selection. It does not change the current
Agent, session, or memory scope and does not carry over to the next message.
Human-readable names resolve only when unique; duplicate display names produce
an ambiguity error listing canonical provider ids instead of choosing one. An
unknown canonical provider id fails before model execution.

Protocol v2 packages and proposals retain their legacy `agent_id` for Provider
validation compatibility, but Provider registration no longer creates an
`AgentDefinition` and the action can be invoked by the current default Agent.
Packages are stored by `provider_id`; legacy agent-keyed files migrate on read.

## Providers generated on-device

New Android apps produced by the bundled `android-apk-build` skill include an
`assets/agent-app.json` declaration, trusted install entry, and action Activity
by default. A dependency-free Java Lite SDK owns caller-certificate, HMAC,
expiry, nonce, idempotency, and replay validation; generated apps must not copy
or reimplement that reusable protocol logic.

Generated action activities start from bundled templates and route declared
actions through `AgentProviderActionRegistry`. The build validator checks that
every package action has exactly one source registration. Provider support is
default-on for newly generated apps, can be explicitly disabled, and does not
prevent legacy projects without a declaration from rebuilding.

The launcher UI and Provider action Activity must call the same app-owned
domain service. High and critical risk actions require Provider-owned
confirmation UI. After APK installation, the Host discovers the Provider and
runs the trusted enable handshake only after user consent; installation is not
silent authorization.

The Napaxi V1 product journey is:

1. The user describes and generates any Android app in Napaxi. The skill emits
   a provider package and handlers for that app's actual domain; it is not tied
   to a notes, tasks, or other fixed example.
2. The user installs the APK through Android's package installer. When Napaxi
   resumes or next launches, the Host discovers apps declaring the provider
   protocol and asks whether to enable them.
3. Settings > Connected apps always lists available, enabled, and now-missing
   apps. Disabling removes the Napaxi connection but neither uninstalls the app
   nor deletes app-owned data.
4. Once connected, the user types `@` and chooses from Agent apps that are both
   connected and still installed. The Host inserts `@<display_name>` to select
   that app explicitly. V1 does not perform natural-language auto-selection or
   change the current Agent, session, or memory scope.

Repository provider examples are protocol/build fixtures, not prebuilt apps
required by product acceptance. End-to-end acceptance starts by generating a
new domain app inside Napaxi.

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
      "display_name": "Create order",
      "localized_display_names": {"zh-CN": "创建订单"},
      "description": "Create an order proposal.",
      "localized_descriptions": {"zh-CN": "在应用中创建一个新订单。"},
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

`display_name`, `localized_display_names`, and `localized_descriptions` are
optional for wire compatibility but should be supplied by every new Provider.
The Host uses them to render the Agent App capability detail page. Locale keys
use BCP 47-style tags such as `zh-CN` and `en`; when no localized value matches,
the Host falls back to `display_name` and `description`.

`confirmation_policy` accepts `none` and `provider_required`. Hosts and the
Lite Provider SDK normalize the legacy value `provider` to
`provider_required` so existing manifests remain fail-closed, but newly built
Provider apps must not emit that legacy alias. Unknown values are rejected.

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

One host installation reuses a stable `host_instance_id`; each provider still
receives an independent shared secret. If trusted validation returns
`host_not_bound` before provider business logic starts, the host may resend an
explicit `INSTALL_AGENT` request with the existing host instance id and shared
secret, then retry the unchanged proposal once. Restore is allowed only while
the provider package/bundle identity and signing identity still match the
stored install binding. It must not loop after a second failure or silently
trust a changed provider identity.

Generated Android Providers opt into trusted in-place manifest refresh with
the application metadata key `agent.provider.TRUSTED_REFRESH_SUPPORTED=true`.
After a package replacement, the Host may repeat the install handshake and
register the returned manifest only when the OS package name and signing
certificate still match the stored binding and the returned `provider_id` and
`agent_id` are unchanged. The Host preserves its existing instance id/shared
secret and Core-owned auto-invoke/usage state. Package version code and last
update time are change detectors, not trust anchors. A missing package or a
changed signing/Provider/Agent identity remains unavailable until an explicit
reconnect.

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

## Android Runtime Diagnostics

New Android apps generated on-device include a private, bounded runtime
diagnostics store. It captures uncaught Java exceptions, relevant Android
historical process-exit reasons (including ANR and native crash when exposed by
the OS), small action-lifecycle breadcrumbs, and structured app runtime logs.
Log levels are `debug`, `info`, `warning`, `error`, and `crash`; debug collection
is off by default. Logs are capped at 300 entries or 512 KiB, expire after three
days, and are further capped to 256 KiB per Host response. Reports and logs are
sanitized and remain in the Provider app's private storage; they are not copied
into chat, memory, workspace files, or model context.

Napaxi retrieves reports from the Agent App detail page through a third,
model-hidden Android entry point:

- Intent action: `agent.provider.action.GET_DIAGNOSTICS`
- Request extra: `agent.provider.extra.DIAGNOSTICS_REQUEST_JSON`
- Result extra: `agent.provider.extra.DIAGNOSTICS_RESULT_JSON`

Diagnostics protocol v1 supports `list`, `ack`, and `configure`. `configure`
changes only debug-level collection; info, warning, error, and crash collection
remain enabled. Every request identifies the `provider_id`, `host_instance_id`,
operation, report-id list, detailed-log setting, timestamp, expiry, and nonce,
and is signed with `hmac-sha256-v1` using the Provider's
existing trusted Host binding. The Provider validates the caller package and
certificate, binding, expiry, and signature before returning data. Diagnostics
must not be declared in `AgentPackage.actions`, mounted as a tool, or invoked by
natural-language routing.

Generated app domain code should emit small semantic events rather than mirror
raw `logcat`: module, event name, short message, optional trace id, and bounded
metadata. A trace id should connect one user operation across UI, domain,
storage/network, and outcome. Providers must not record credentials, full
payloads, raw user content, or arbitrary WebView console output.

This first version is implemented by the Android Lite SDK and Flutter Android
Host bridge. Older Android Provider apps and iOS return an explicit unsupported
state without affecting their existing actions.

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
