# Main Model Driven Codex Configuration

## Goal

Use the selected main model as the only Codex configuration source and reject stale or incompatible runtime configuration.

## Tasks

- [x] Add typed Core config sync, clear, fingerprint, and runtime preflight behavior.
- [x] Expose matching Flutter, Android, and iOS adapter APIs and contract metadata.
- [x] Sync after main-model persistence/restore and validate before Codex switch/send.
- [x] Add focused Core, adapter, and Flutter tests plus capability documentation.
- [x] Run boundary, parity, Flutter, and Android verification.

## Done When

- [x] Saving or selecting a main model updates the Android sandbox Codex files.
- [x] Codex cannot run with missing, incompatible, or stale main-model configuration.
- [x] Other engines remain usable when Codex synchronization fails.

## Verification Notes

- Codex-focused Core, SDK adapter, Demo preflight, boundary, parity, iOS, and Android checks pass.
- Demo analyze passes with five existing info-level findings.
- The full Demo suite is blocked by existing failures in `channel_slash_contract_test.dart` and two Markdown horizontal-drag tests, plus the existing `pauses auto-follow when user scrolls up during streaming` test that does not complete when run alone.
