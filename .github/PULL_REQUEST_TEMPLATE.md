<!--
Thanks for contributing to Napaxi! Please complete this template — fields marked
with * are required. See CONTRIBUTING.md for the full PR expectations.
-->

## Summary *

<!-- One or two sentences describing the change and the user impact. -->

## Motivation

<!-- Linked issue, design discussion, or short description of why. Use
"Fixes #123" / "Refs #123" to auto-link. -->

## Scope *

- [ ] Core (`crates/core/`)
- [ ] Feature crate (`crates/features/`)
- [ ] Bridge (`packages/api_bridge/`)
- [ ] Flutter SDK (`packages/flutter/`)
- [ ] Agent Provider (`packages/agent_provider/`)
- [ ] Demo (`examples/`)
- [ ] Docs / scripts only

## Test Plan *

<!-- What did you run locally? Paste the commands and outcomes. -->

- [ ] `./tools/scripts/build.sh check-boundary`
- [ ] `cargo check --workspace`
- [ ] `cargo test --workspace` (if behavior changed)
- [ ] `cd packages/flutter && flutter analyze --no-fatal-infos && flutter test` (if Flutter SDK changed)
- [ ] `cd examples/flutter && flutter analyze --no-fatal-infos && flutter test` (if demo changed)

## Contributor License Agreement *

<!-- External contributors must complete the applicable CLA before merge. See CLA.md. -->

- [ ] I have completed the applicable CLA, or this PR is from a maintainer using
      already-approved project-owned code.
- [ ] If this contribution is owned or controlled by my employer or another
      legal entity, the Corporate CLA requirement has been addressed.

## Capability / API Surface

<!-- If this adds or changes an LLM provider, built-in tool, platform tool, MCP
surface, policy hook, or background service: -->

- [ ] Capability defined in `crates/core/src/capabilities/`
- [ ] Adapter wrapper in `crates/core/src/api/`
- [ ] `docs/mobile-capabilities.md` updated
- [ ] Public Dart SDK surface in `packages/flutter/lib/napaxi_flutter.dart` unchanged
      (or breaking change is called out below and added to `CHANGELOG.md`)

## Generated Code

- [ ] No hand edits to `packages/flutter/lib/generated/`, `packages/api_bridge/generated/`,
      or `packages/flutter/ios/Classes/frb_generated.h`
- [ ] If bridge regenerated, ran `./tools/scripts/build.sh codegen`

## Notes for Reviewer

<!-- Anything else worth flagging: known follow-ups, alternative approaches
considered, areas needing extra scrutiny. -->
