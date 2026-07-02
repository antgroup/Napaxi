# Releasing Napaxi

This document covers cutting a release of Napaxi and its Flutter SDK package.
Audience: maintainers with push access to the canonical repository and to the
public Flutter SDK release repository (`napaxi_flutter_release`).

For repository layout see [`docs/architecture.md`](docs/architecture.md). For
the SDK build flow see [`docs/sdk-integration.md`](docs/sdk-integration.md).

## Versioning

Napaxi uses [Semantic Versioning](https://semver.org/). The workspace shares a
single version cadence:

- `napaxi-core`, `napaxi_skills`, `napaxi_evolution`, `napaxi_api_bridge` carry
  the same Cargo `version`.
- `napaxi_flutter` (`packages/flutter/pubspec.yaml`) follows the same
  `MAJOR.MINOR.PATCH`.

Until `1.0.0`, breaking changes may land in a `0.MINOR.0` bump. The
`Mobile*` naming retirement is scheduled for `0.2.0` per
[`docs/naming-migration.md`](docs/naming-migration.md); do not ship a
breaking rename outside that planned window.

## Pre-release checklist

Run from a clean working tree on the default release branch:

```sh
git status                                               # must be clean
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo check --workspace
cargo test --workspace --no-fail-fast
./tools/scripts/build.sh check-boundary
NAPAXI_RELEASE=1 ./tools/scripts/build.sh check-hygiene    # placeholder check enforced
cargo deny check
cargo audit
( cd packages/flutter && flutter analyze && flutter test )
( cd examples/flutter && flutter analyze && flutter test )
cargo bench --workspace -- --quick                       # eyeball against baseline
```

`NAPAXI_RELEASE=1` flips `check_release_placeholders` from warn to fail; if it
trips, fix the placeholder before bumping the version.

## Cut a release

1. **Bump versions** in `Cargo.toml` for `napaxi-core`, `napaxi_skills`,
   `napaxi_evolution`, `napaxi_api_bridge`, and in `packages/flutter/pubspec.yaml`.
   Run `cargo check --workspace` once to refresh `Cargo.lock`.
2. **Promote CHANGELOG**: move the `## Unreleased` section under a new
   `## [X.Y.Z] - YYYY-MM-DD` heading; start a fresh empty `## Unreleased`.
3. **Build native artifacts** from a clean tree:
   ```sh
   ./tools/scripts/build.sh release android
   ./tools/scripts/build.sh release ios
   ```
   The outputs land under
   `packages/flutter/android/jniLibs/*/libnapaxi_api_bridge.so` and
   `packages/flutter/ios/Frameworks/napaxi_api_bridge.xcframework`.
4. **Sync the public Flutter SDK repo** (`napaxi_flutter_release`):
   ```sh
   ./tools/scripts/sync_prebuilt_to_release_repo.sh           # uses ../napaxi_flutter_release by default
   ./tools/scripts/sync_prebuilt_to_release_repo.sh path/to/napaxi_flutter_release
   ```
   Then in the release repo: `git status --short`, commit, tag `vX.Y.Z`, push.
5. **Tag this repo** and push:
   ```sh
   git commit -am "release: X.Y.Z"
   git tag -a vX.Y.Z -m "Napaxi X.Y.Z"
   git push origin HEAD
   git push origin vX.Y.Z
   ```
6. **Publish a GitHub Release** against the tag. Paste the CHANGELOG section.
   Attach any pre-built artifacts maintainers want to advertise. Crate
   publishing to crates.io is not part of the default release flow; the
   workspace currently sets `package.metadata.dist.dist = false` on
   `napaxi-core`.

## Post-release

- Open a follow-up PR that:
  - Adds the new `## Unreleased` section to `CHANGELOG.md` (already done in
    step 2, but verify).
  - Bumps versions to `X.Y.(Z+1)-dev` if you use a `-dev` suffix convention,
    or leaves them at `X.Y.Z` until the next bump (current convention).
- Announce in the repository discussions / project channel.

## Emergency / hotfix

Hotfixes branch from the most recent release tag, not from the default
development branch. Cherry-pick the fix, bump the patch version, run the
pre-release checklist, repeat steps 3–6 above.

## Related

- [`CHANGELOG.md`](CHANGELOG.md): canonical history; promoted by step 2.
- [`docs/naming-migration.md`](docs/naming-migration.md): controls when
  breaking `Mobile*` renames can ship.
- [`vendor/libsql-patched/README.md`](vendor/libsql-patched/README.md):
  rebase cadence for the patched dependency; check before any minor release.
- [`tools/scripts/sync_prebuilt_to_release_repo.sh`](tools/scripts/sync_prebuilt_to_release_repo.sh):
  the script invoked in step 4.
