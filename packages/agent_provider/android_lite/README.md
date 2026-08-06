# Android Agent Provider Lite

This source-only, dependency-free Java facade is compiled into small Android
APKs produced by Napaxi's on-device `android-apk-build` skill. The package owns
the reusable install/proposal trust logic; generated apps only provide an
`assets/agent-app.json` declaration and app-local action handlers.

Generated action activities use `AgentProviderActionRegistry` so declared
action ids and app handlers must match exactly. Non-idempotent handlers are
marked consumed before their domain operation begins.

New generated apps also install a private diagnostics collector before
application startup. It keeps a bounded set of sanitized Java exceptions,
Android process-exit reasons, ANR traces when Android makes them available,
lightweight action breadcrumbs, and structured runtime logs in app-private
storage. Logs use `debug`, `info`, `warning`, `error`, and `crash` levels;
`debug` collection is opt-in, while the other levels remain enabled. Storage is
bounded to 300 entries or 512 KiB and expires after three days. Napaxi reads
the data only through a Host-signed diagnostics Activity backed by the existing
trusted install binding. The endpoint is not an Agent action and is never
mounted as a model tool. Apps generated before this endpoint remain compatible
and report diagnostics as unsupported.

It intentionally uses Android framework APIs and `org.json` only so the phone
build pipeline does not need Gradle, Maven, Kotlin, AndroidX, or network access.
