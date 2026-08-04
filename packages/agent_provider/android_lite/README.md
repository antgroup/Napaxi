# Android Agent Provider Lite

This source-only, dependency-free Java facade is compiled into small Android
APKs produced by Napaxi's on-device `android-apk-build` skill. The package owns
the reusable install/proposal trust logic; generated apps only provide an
`assets/agent-app.json` declaration and app-local action handlers.

Generated action activities use `AgentProviderActionRegistry` so declared
action ids and app handlers must match exactly. Non-idempotent handlers are
marked consumed before their domain operation begins.

It intentionally uses Android framework APIs and `org.json` only so the phone
build pipeline does not need Gradle, Maven, Kotlin, AndroidX, or network access.
