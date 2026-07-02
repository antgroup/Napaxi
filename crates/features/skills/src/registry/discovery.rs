//! Skill discovery and (re)loading for [`SkillRegistry`].
//!
//! Split out of `registry/mod.rs`: the multi-source discovery walk
//! (`discover_all` / `discover_from_dir`), per-user discovery, reload flows,
//! and the bundled-content loader. The struct definition, constructors,
//! query accessors, and the load/validate free functions stay in `mod.rs`.

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

    /// Reload skills for a specific user only.
    /// Retains skills owned by other users and global skills.
    pub async fn reload_for_user(&mut self, user_id: &str) -> Vec<String> {
        // Only remove this user's skills, preserve others and global
        {
            self.skills.write().retain(|s| s.owner_user_id != user_id);
        }
        self.discover_all(user_id).await
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
