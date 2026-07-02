# Skills

Skills are `SKILL.md` files — YAML frontmatter plus a markdown prompt — that
extend an agent's behavior at the prompt level. The skill subsystem spans **two
crates**, and knowing which half owns what is the key to working in it:

```text
crates/features/skills/   domain logic: types, SKILL.md parsing, validation,
                          selection/scoring, gating, filesystem registry, catalog
        |
        v   (depended on by core; feature crate must NOT depend on core)
crates/core/src/skills/   runtime management: install/lifecycle/curator/status,
                          private-skill gating, secrets, prompt assembly, the
                          hidden skill_load tool, per-session skill state
        |
        v
crates/core/src/api/skill.rs   adapter-facing handles (Flutter/Android/iOS)
```

The dependency direction is one-way: `features/skills` is pure domain code with
no knowledge of the runtime; `core/src/skills` adapts it to the file-backed
mobile runtime; adapters only ever see `napaxi_core::api::skill`.

## `features/skills` — Domain

This crate (`napaxi_skills`) is the source of truth for what a skill *is*:

- **`types`** — `SkillManifest`, `LoadedSkill`, `ActivationCriteria`,
  `GatingRequirements`, credential specs, and `SkillTrust` (the trust enum).
- **`parser`** — Parses `SKILL.md` (frontmatter + prompt body).
- **`validation`** — Name/content escaping, credential-spec validation.
- **`selector`** *(v1)* — Deterministic Rust-side scoring (`prefilter_skills`).
- **`gating`** *(v1)* — Binary/env/config requirement checks at load time.
- **`registry`** *(v1, feature `registry`)* — Filesystem discovery + install /
  remove. See [`module-evolution.md`](module-evolution.md) for how skills also
  flow through evolution.
- **`catalog`** *(v1, feature `catalog`)* — ClawHub HTTP catalog queries.
- **`v2`** — Data structures for the v2 engine.
- **`afs_traits`** — Abstract filesystem accessor traits, so the domain code
  reads/writes through an injected accessor rather than `std::fs` directly.
- **`security`** — Skill-package security scanning.

### v1 vs v2 engine

The crate doc (`features/skills/src/lib.rs`) is explicit about a migration in
flight. In the **v2 engine**, skill *selection and scoring* happen in the Python
orchestrator, not in Rust — v2 uses this crate only for `types`, `v2`, `parser`,
and `validation`. The **v1** modules (`selector`, `gating`, `registry`,
`catalog`) are used only by the v1 agent and are slated for removal or
feature-gating once the migration completes. Treat the v1 modules as legacy:
don't build new behavior on them without checking the migration state.

### Trust model

`SkillTrust` (`features/skills/src/types/mod.rs`) has two states whose ordering
is security-relevant (`Installed < Trusted`, derived from discriminants — do not
reorder):

- **Trusted** — user-placed skills (local or workspace). Full tool access.
- **Installed** — registry/external skills. Restricted to read-only tools.

Trust-based tool filtering is enforced by the runtime: an Installed skill
cannot widen its own tool access. In v2 this is handled by the Python
orchestrator's trust labels plus the policy engine via capability leases.
(Some inherited doc comments still reference a v1 `attenuation` module by its
original upstream path; that file is not part of this extracted repository.)

## `core/src/skills` — Runtime Management

This is the mobile runtime's skill manager. It composes the domain crate into
file-backed operations and owns everything stateful or host-facing:

- **`install`** — Install paths: raw markdown, JSON bundle, ZIP, URL, ClawHub.
- **`lifecycle`** — list / get / pin / archive / restore, with
  backup-and-rollback.
- **`curator`** — Stale → archive curator, and evolution action dispatch.
- **`status`** — Skill readiness/status reporting and remediation actions.
- **`remediation`** — Remediation requests and run tracking.
- **`secrets`** — Per-skill secret requirements and availability.
- **`private_skill`** — Private-skill protocol gate (leak detection, gating).
- **`skill_load`** — The hidden `skill_load` tool descriptor + runtime handler
  the model uses to pull a skill's prompt on demand.
- **`prompt`** — Prompt assembly for active and explicitly-loaded skills.
- **`session`** — Per-thread skill session state.
- **`source_registry`** — Skill source tracking and refresh.
- **`snapshots`** — Skill snapshots.
- **`usage`** — Usage-record persistence and lifecycle JSON.
- **`config`** — Per-skill config.
- **`paths`** / **`limits`** / **`afs`** — Path policy + agent-id normalization,
  numeric limits and well-known names, and the local `AfsAccessor` + registry
  factory that wires the domain crate to the mobile filesystem.

## Adapter Boundary

`crates/core/src/api/skill.rs` re-exports the `*_handle` functions and DTOs that
adapters call — `install_skill_handle`, `list_skills_handle`,
`get_skill_status_handle`, `archive_skill_handle`, `run_skill_curator_handle`,
`run_skill_command_handle`, and so on. Adapters must enter through these; they
must not call `core::skills::*` internals or depend on `features/skills`
directly. Adding an adapter-visible skill operation means adding a handle here
plus the matching adapter surface (see `docs/sdk-adapter-parity.md`).

## Where to Make a Change

- New `SKILL.md` field, parsing rule, or validation → `features/skills`
  (`types` / `parser` / `validation`).
- New way to install or manage an installed skill → `core/src/skills`
  (`install` / `lifecycle`) + an `api/skill.rs` handle.
- New skill-readiness or remediation surface → `core/src/skills`
  (`status` / `remediation` / `secrets`).
- Anything adapters should see → it must land in `api/skill.rs`.
