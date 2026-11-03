//! Skill discovery and (re)loading for [`SkillRegistry`].
//!
//! Split out of `registry/mod.rs`: the multi-source discovery walk
//! (`discover_all` / `discover_from_dir`), per-user discovery, reload flows,
//! and the bundled-content loader. The struct definition, constructors,
//! query accessors, and the load/validate free functions stay in `mod.rs`.

use std::path::Component;

use super::*;

impl SkillRegistry {
    /// Discover and load skills from all configured directories.
    ///
    /// Discovery order (earlier wins on name collision):
    /// 1. Workspace skills directory (if set) -- Trusted
    /// 2. User skills directory -- Trusted
    /// 3. Installed skills directory (if set) -- Installed
    // Holds the `self.skills` write guard across the per-directory `.await`s.
    // This is safe: the awaited `discover_from_dir` / `load_bundled_skills`
    // calls never re-acquire `self.skills` (verified — a re-acquire would
    // deadlock the non-reentrant parking_lot lock), and discovery is the only
    // writer path. A finer-grained lock would change the accumulation +
    // companion-check semantics (the post-discovery check intentionally sees
    // pre-existing entries), so that is left as a separate refactor.
    #[allow(clippy::await_holding_lock)]
    pub async fn discover_all(&self, user_id: &str) -> Vec<String> {
        let mut loaded_names: Vec<String> = Vec::new();
        // Dedup key is (name, owner) so same-name skills coexist across owners
        // (e.g. user "common-skill" and bundled "common-skill"), while same-user
        // duplicates from different sources are still deduped by source priority.
        let mut seen: HashSet<(String, String)> = HashSet::new();
        let mut self_skills = self.skills.write();
        let owner = user_id.to_string();
        // 1. Workspace skills (highest priority)
        if let Some(ws_dir) = self.workspace_dir.clone() {
            let cap = MAX_DISCOVERED_SKILLS.saturating_sub(loaded_names.len());
            let skills = self
                .discover_from_dir(
                    &ws_dir,
                    SkillTrust::Trusted,
                    &SkillSource::Workspace,
                    cap,
                    0,
                    user_id,
                )
                .await;
            for (name, mut skill) in skills {
                let key = (name.clone(), owner.clone());
                if seen.contains(&key) {
                    tracing::debug!("Skipping skill '{}' (overridden by workspace)", name);
                    continue;
                }
                skill.owner_user_id = owner.clone();
                seen.insert(key);
                loaded_names.push(name);
                self_skills.push(Arc::new(skill));
            }
        }

        // 2. User skills
        if loaded_names.len() < MAX_DISCOVERED_SKILLS {
            let cap = MAX_DISCOVERED_SKILLS.saturating_sub(loaded_names.len());
            let user_dir = self.user_dir.clone();
            let skills = self
                .discover_from_dir(
                    &user_dir,
                    SkillTrust::Trusted,
                    &SkillSource::User,
                    cap,
                    0,
                    user_id,
                )
                .await;
            for (name, mut skill) in skills {
                let key = (name.clone(), owner.clone());
                if seen.contains(&key) {
                    tracing::debug!("Skipping skill '{}' (overridden by workspace)", name);
                    continue;
                }
                skill.owner_user_id = owner.clone();
                seen.insert(key);
                loaded_names.push(name);
                self_skills.push(Arc::new(skill));
            }
        }

        // 3. Installed skills (registry-installed)
        if loaded_names.len() < MAX_DISCOVERED_SKILLS
            && let Some(inst_dir) = self.installed_dir.clone()
        {
            let cap = MAX_DISCOVERED_SKILLS.saturating_sub(loaded_names.len());
            let skills = self
                .discover_from_dir(
                    &inst_dir,
                    SkillTrust::Installed,
                    &SkillSource::Installed,
                    cap,
                    0,
                    user_id,
                )
                .await;
            for (name, mut skill) in skills {
                let key = (name.clone(), owner.clone());
                if seen.contains(&key) {
                    tracing::debug!(
                        "Skipping skill '{}' (overridden by workspace or user)",
                        name
                    );
                    continue;
                }
                skill.owner_user_id = owner.clone();
                seen.insert(key);
                loaded_names.push(name);
                self_skills.push(Arc::new(skill));
            }
        }

        // 4. Bundled skills (compiled into binary, lowest priority)
        // Bundled skills keep owner_user_id = "" (global, visible to all users).
        // They always load regardless of user-skill name collisions so that
        // other users can still see the global version via find_by_name_for_user.
        if !self.bundled_content.is_empty() {
            let bundled = self.load_bundled_skills().await;
            for (name, skill) in bundled {
                let key = (name.clone(), String::new());
                if seen.contains(&key) {
                    continue;
                }
                seen.insert(key);
                loaded_names.push(name);
                self_skills.push(Arc::new(skill));
            }
        }

        if loaded_names.len() >= MAX_DISCOVERED_SKILLS {
            tracing::warn!(
                "Global skill discovery cap reached ({} skills)",
                MAX_DISCOVERED_SKILLS
            );
        }

        // Post-discovery companion-skill check. `requires.skills` is advisory
        // metadata only (gating does not enforce it), so a user who drops
        // `ceo-assistant/SKILL.md` into their workspace can silently get a
        // degraded experience when its companions (`commitment-triage`,
        // `commitment-digest`, …) aren't present. Walk every loaded skill
        // and warn once per missing companion so the gap is visible in the
        // log without blocking load.
        let loaded_set: HashSet<&str> = loaded_names.iter().map(String::as_str).collect();
        for skill in self_skills.iter() {
            for companion in &skill.manifest.requires.skills {
                if !loaded_set.contains(companion.as_str()) {
                    tracing::warn!(
                        "Skill '{}' declares companion '{}' in `requires.skills`, but it is not loaded. \
                         Install it via `skill_install` or place a SKILL.md for it in ~/.napaxi/skills/ \
                         to avoid a degraded experience.",
                        skill.manifest.name,
                        companion
                    );
                }
            }
        }

        loaded_names
    }

    /// Dedup and absorb discovered skills into the registry.
    /// Discover skills from a single directory, recursing into bundle directories.
    ///
    /// Supports three layouts:
    /// - Flat: `dir/SKILL.md` (skill name derived from parent dir or file stem)
    /// - Subdirectory: `dir/<name>/SKILL.md`
    /// - Bundle: `dir/<bundle>/<name>/SKILL.md` (bundle has no `SKILL.md`, recursed into)
    async fn discover_from_dir<F>(
        &self,
        dir: &Path,
        trust: SkillTrust,
        make_source: &F,
        remaining_cap: usize,
        current_depth: usize,
        user_id: &str,
    ) -> Vec<(String, LoadedSkill)>
    where
        F: Fn(PathBuf) -> SkillSource + Send + Sync,
    {
        let afs = match get_afs(user_id) {
            Ok(a) => a,
            Err(_) => return Vec::new(),
        };

        let mut results = Vec::new();
        let entries = match afs.read_dir(dir).await {
            Ok(entries) => entries,
            Err(e) => {
                if matches!(e, AfsError::NotFound(_)) {
                    tracing::debug!("Skills directory does not exist: {:?}", dir);
                } else {
                    tracing::warn!("Failed to read skills directory {:?}: {}", dir, e);
                }
                return results;
            }
        };

        let mut count = 0usize;
        for entry in entries.iter() {
            if count >= remaining_cap {
                tracing::warn!(
                    "Skill discovery cap reached ({} skills in this scan), skipping remaining",
                    count
                );
                break;
            }

            let path = entry.path();
            let meta = match afs.symlink_metadata(&path).await {
                Ok(m) => m,
                Err(e) => {
                    tracing::debug!("Failed to stat {:?}: {}", path, e);
                    continue;
                }
            };

            if meta.is_symlink() {
                tracing::warn!(
                    "Skipping symlink in skills directory: {:?}",
                    path.file_name().unwrap_or_default()
                );
                continue;
            }

            // Case 1: Subdirectory containing SKILL.md
            if meta.is_dir() {
                let skill_md = path.join("SKILL.md");
                if afs.physical_exists(&skill_md) {
                    count += 1;
                    let source = make_source(path.clone());
                    match self.load_skill_md(&skill_md, trust, source, user_id).await {
                        Ok((name, skill)) => {
                            tracing::debug!("Loaded skill: {}", name);
                            results.push((name, skill));
                        }
                        Err(e) => {
                            tracing::warn!(
                                "Failed to load skill from {:?}: {}",
                                path.file_name().unwrap_or_default(),
                                e
                            );
                        }
                    }
                } else if current_depth < self.max_scan_depth {
                    tracing::debug!(
                        "Recursing into bundle directory {:?} (depth {})",
                        path.file_name().unwrap_or_default(),
                        current_depth + 1
                    );
                    let nested = Box::pin(self.discover_from_dir(
                        &path,
                        trust,
                        make_source,
                        remaining_cap.saturating_sub(count),
                        current_depth + 1,
                        user_id,
                    ))
                    .await;
                    count += nested.len();
                    results.extend(nested);
                }
                continue;
            }

            // Case 2: Flat SKILL.md directly in the directory
            if meta.is_file()
                && let Some(fname) = path.file_name().and_then(|f| f.to_str())
                && fname == "SKILL.md"
            {
                count += 1;
                let source = make_source(dir.to_path_buf());
                match self.load_skill_md(&path, trust, source, user_id).await {
                    Ok((name, skill)) => {
                        tracing::debug!("Loaded skill: {}", name);
                        results.push((name, skill));
                    }
                    Err(e) => {
                        tracing::warn!("Failed to load skill from {:?}: {}", fname, e);
                    }
                }
            }
        }

        results
    }

    /// Load a single SKILL.md file.
    async fn load_skill_md(
        &self,
        path: &Path,
        trust: SkillTrust,
        source: SkillSource,
        user_id: &str,
    ) -> Result<(String, LoadedSkill), SkillRegistryError> {
        load_and_validate_skill(path, trust, source, user_id).await
    }

    /// Load bundled skills from in-memory content.
    async fn load_bundled_skills(&self) -> Vec<(String, LoadedSkill)> {
        let mut results = Vec::new();
        for (name, content) in self.bundled_content {
            match load_from_content(
                content,
                SkillTrust::Trusted,
                SkillSource::Bundled(PathBuf::from(name)),
            )
            .await
            {
                Ok((loaded_name, skill)) => {
                    tracing::debug!("Loaded bundled skill: {}", loaded_name);
                    results.push((loaded_name, skill));
                }
                Err(e) => {
                    tracing::debug!("Skipping bundled skill '{}': {}", name, e);
                }
            }
        }
        results
    }

    /// Clear all loaded skills and re-discover from disk.
    #[deprecated(note = "Use reload_for_user() instead to avoid clearing other users' skills")]
    pub async fn reload(&mut self, user_id: &str) -> Vec<String> {
        {
            self.skills.write().clear();
        }
        self.discover_all(user_id).await
    }

    pub async fn reload_for_user(&mut self, user_id: &str) -> Vec<String> {
        // Only remove this user's skills, preserve others and global
        {
            self.skills.write().retain(|s| s.owner_user_id != user_id);
        }
        self.discover_all(user_id).await
    }
}

// ── Bounded companion reads ──────────────────────────────────────────────
//
// Re-implemented from OpenClaw (MIT) design notes (workitem #189165): read
// companion files under a placement-owner-pinned `resource_root` via a
// bounded relative-path API that rejects `..`, absolute, `~`, drive-letter,
// symlink, hardlink, NUL, and non-UTF-8 inputs. No OpenClaw source code is
// ported — the Napaxi implementation rewrites the boundary rules from
// scratch under GPL-3.0-or-later. See `THIRD-PARTY-LICENSES.md`.
//
// Per AGENTS.md, `crates/features/* must not depend on crates/core`, so the
// pure-path rules are mirrored locally here (kept deliberately short and
// commented) instead of being imported from
// `crates/core/src/skills/paths.rs`. The fs-level mirror (symlink +
// hardlink + canonicalize containment) is implemented through the existing
// AFS trait, which already exposes a per-file `nlink` count.

/// Companion file size cap — mirrors `crates/core/src/skills/limits.rs`'s
/// `MAX_EXTRA_FILE_SIZE` (1 MiB). Feature crates cannot import it from
/// `crates/core`; this constant is kept in sync manually.
const MAX_COMPANION_FILE_SIZE: u64 = 1024 * 1024;

/// Pure-string validation of a relative `relative_path` against a pinned
/// resource root. Mirrors `crates/core/src/skills/paths.rs`'s
/// `safe_companion_relative_path` exactly — the two copies are intentional
/// (feature crates cannot depend on `crates/core`); update both together.
///
/// Rejected inputs:
/// - any NUL byte;
/// - a leading `~`, leading `/`, leading `\`, or `[a-zA-Z]:` drive prefix;
/// - any `..` / `.` / root / prefix `Component` (only `Normal` accepted).
fn validate_companion_relative_path(relative_path: &str) -> Result<PathBuf, String> {
    if relative_path.as_bytes().contains(&0u8) {
        return Err(format!(
            "companion path contains NUL byte: {relative_path:?}"
        ));
    }
    if has_unsafe_companion_prefix(relative_path) {
        return Err(format!(
            "companion path has unsafe prefix (~, absolute, or drive-letter): {relative_path:?}"
        ));
    }
    let path = Path::new(relative_path);
    let mut out = PathBuf::new();
    for component in path.components() {
        match component {
            Component::Normal(part) => out.push(part),
            _ => return Err(format!("unsafe companion path: {relative_path:?}")),
        }
    }
    if out.as_os_str().is_empty() {
        return Err(format!("unsafe companion path: {relative_path:?}"));
    }
    Ok(out)
}

/// String-level prefix guard, mirroring `has_unsafe_prefix` in
/// `crates/core/src/skills/paths.rs`.
fn has_unsafe_companion_prefix(input: &str) -> bool {
    let trimmed = input.trim_start_matches(' ');
    if trimmed.starts_with('~') {
        return true;
    }
    if trimmed.starts_with('/') || trimmed.starts_with('\\') {
        return true;
    }
    let bytes = trimmed.as_bytes();
    if bytes.len() >= 2 && bytes[0].is_ascii_alphabetic() && bytes[1] == b':' {
        return true;
    }
    false
}

impl SkillRegistry {
    /// Read companion files for a skill under a pinned `resource_root`,
    /// applying the same boundary rules as `crates/core/src/skills/paths.rs`'s
    /// `safe_companion_relative_path` + `validate_companion_target`.
    ///
    /// A missing `resource_root` degrades gracefully: `AfsError::NotFound`
    /// is logged at `tracing::debug` and an empty `Vec` is returned,
    /// consistent with `discover_from_dir`'s existing NotFound handling.
    /// Per-file symlink and hardlink (nlink > 1) entries are silently
    /// skipped (not raised), matching the per-entry `symlink_metadata` skip
    /// in `discover_from_dir`. The size cap is `MAX_COMPANION_FILE_SIZE` (mirrors
    /// `crates/core/src/skills/limits.rs::MAX_EXTRA_FILE_SIZE`).
    pub async fn companion_files_in_root(
        &self,
        user_id: &str,
        resource_root: &Path,
    ) -> Vec<(PathBuf, Vec<u8>)> {
        let afs = match get_afs(user_id) {
            Ok(afs) => afs,
            Err(error) => {
                tracing::debug!(
                    "Companion read skipped — no AFS accessor for {}: {}",
                    user_id,
                    error
                );
                return Vec::new();
            }
        };

        let entries = match afs.read_dir(resource_root).await {
            Ok(entries) => entries,
            Err(error) => {
                if matches!(error, AfsError::NotFound(_)) {
                    tracing::debug!(
                        "Companion resource root does not exist: {:?}",
                        resource_root
                    );
                } else {
                    tracing::warn!(
                        "Failed to read companion resource root {:?}: {}",
                        resource_root,
                        error
                    );
                }
                return Vec::new();
            }
        };

        let mut out = Vec::new();
        for entry in entries.iter() {
            let rel_name = match entry.file_name().and_then(|s| s.to_str()) {
                Some(name) => name,
                None => {
                    tracing::debug!("Skipping non-UTF-8 companion entry in {:?}", resource_root);
                    continue;
                }
            };
            // String-level guard mirrors `safe_companion_relative_path`.
            let validated = match validate_companion_relative_path(rel_name) {
                Ok(rel) => rel,
                Err(reason) => {
                    tracing::debug!("Skipping companion entry: {reason}");
                    continue;
                }
            };
            let target = resource_root.join(&validated);

            // fs-level guard mirrors `validate_companion_target`.
            let meta = match afs.symlink_metadata(&target).await {
                Ok(meta) => meta,
                Err(error) => {
                    tracing::debug!("Skipping companion {:?}: {}", target, error);
                    continue;
                }
            };
            if meta.is_symlink() {
                tracing::debug!("Skipping companion symlink: {:?}", target);
                continue;
            }
            if !meta.is_file() {
                tracing::debug!("Skipping non-file companion: {:?}", target);
                continue;
            }
            if meta.nlink() > 1 {
                tracing::debug!("Skipping companion hardlink (nlink > 1): {:?}", target);
                continue;
            }

            let bytes = match afs.read(&target).await {
                Ok(bytes) => bytes,
                Err(error) => {
                    tracing::debug!("Skipping companion {:?} read: {}", target, error);
                    continue;
                }
            };
            if bytes.len() as u64 > MAX_COMPANION_FILE_SIZE {
                tracing::debug!(
                    "Skipping oversized companion: {:?} ({} bytes > {} cap)",
                    target,
                    bytes.len(),
                    MAX_COMPANION_FILE_SIZE
                );
                continue;
            }
            out.push((validated, bytes));
        }
        out
    }

    /// Discover and load skills for a specific user into this registry.
    /// Skills loaded this way are tagged with owner_user_id.
    /// Returns names of newly loaded skills.
    ///
    /// IMPORTANT: This method is idempotent — it scans the disk every time
    /// but only loads skills not already present in the registry for this user.
    /// It does NOT short-circuit on "user already has some skills", because
    /// the disk may have new skills added since the last call.
    ///
    /// Priority: user skill and global (bundled) skill with the same name can
    /// coexist in the registry. `find_by_name_for_user()` resolves the priority
    /// at query time (user-owned > global). This avoids removing global skills
    /// that other users still need.
    pub async fn discover_for_user(&self, user_id: &str) -> Vec<String> {
        let mut loaded_names = Vec::new();

        // seen only contains skills already loaded for this user (not global).
        // User skill with same name as global can coexist; query-time resolution
        // via find_by_name_for_user() handles priority.
        let mut seen: HashSet<String> = self
            .skills
            .read()
            .iter()
            .filter(|s| s.owner_user_id == user_id)
            .map(|s| s.manifest.name.clone())
            .collect();

        // Load user skills
        let cap = MAX_DISCOVERED_SKILLS.saturating_sub(self.skills.read().len());
        if cap > 0 {
            let user_skills = self
                .discover_from_dir(
                    self.user_dir.as_path(),
                    SkillTrust::Trusted,
                    &SkillSource::User,
                    MAX_DISCOVERED_SKILLS,
                    0,
                    user_id,
                )
                .await;
            for (name, mut skill) in user_skills {
                if seen.contains(&name) {
                    continue;
                }
                skill.owner_user_id = user_id.to_string();

                seen.insert(name.clone());
                loaded_names.push(name.clone());
                self.skills.write().push(Arc::new(skill));
            }
        }

        // Load installed skills
        let cap = MAX_DISCOVERED_SKILLS.saturating_sub(self.skills.read().len());
        if cap > 0
            && let Some(inst_dir) = self.installed_dir.as_ref()
        {
            let inst_skills = self
                .discover_from_dir(
                    inst_dir,
                    SkillTrust::Installed,
                    &SkillSource::Installed,
                    MAX_DISCOVERED_SKILLS,
                    0,
                    user_id,
                )
                .await;
            for (name, mut skill) in inst_skills {
                if seen.contains(&name) {
                    continue;
                }
                skill.owner_user_id = user_id.to_string();

                seen.insert(name.clone());
                loaded_names.push(name.clone());
                self.skills.write().push(Arc::new(skill));
            }
        }

        if !loaded_names.is_empty() {
            tracing::debug!(
                "Loaded {} skill(s) for user '{}'",
                loaded_names.len(),
                user_id
            );
        }

        loaded_names
    }
}
