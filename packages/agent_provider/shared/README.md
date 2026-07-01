# Agent Provider Parity Fixtures

This directory contains shared behavioural fixtures used by both the iOS (Swift)
and Android (Kotlin) Agent Provider test suites to verify identical validation
behaviour.

## Files

- `parity_fixtures.json` — JSON array of test cases covering install proposal
  validation, trusted proposal validation, and trigger validation. Each fixture
  specifies the input, expected provider/agent IDs, and whether validation
  should pass or fail (with the specific failure reason).

## Usage

### iOS (Swift)

Load the JSON fixture file in `AgentProviderHostTests.swift` and iterate over
the `fixtures` array, calling `AgentProvider.validateProposal` (or
`validateTrustedProposal`) for each entry and asserting the expected result.

### Android (Kotlin)

Load the JSON fixture file in `AgentProviderHostProtocolTest.kt` and iterate
over the `fixtures` array, calling `AgentProvider.validateProposal` for each
entry and asserting the expected result.

New validation test cases should be added to `parity_fixtures.json` so that
both platforms benefit from the same coverage.