# Naming Migration

Napaxi previously used legacy `Mobile*` and `mobile_*` names on parts of the
SDK-facing surface. Those names are retired before the first public release.

## Current Rule

Use mobile-generic Napaxi names for public APIs, package docs, generated
adapter surfaces, and examples. Do not introduce new public `Mobile*` types or
legacy `mobile_*` helper names.

The repository enforces this through:

- `tools/scripts/build.sh check-hygiene`
- `tools/scripts/rename-mobile.sh`

Historical migration plans and work logs are not part of the public
documentation tree. If a new public API needs a platform-specific name, document
the platform boundary in `docs/architecture.md` or the relevant module doc
instead of reviving the legacy naming scheme.
