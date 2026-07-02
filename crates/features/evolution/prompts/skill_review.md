Review the conversation above and consider saving or updating a skill if appropriate.

Focus on: was a non-trivial approach used to complete a task that required trial and error, or changing course due to experiential findings along the way, or did the user expect or desire a different method or outcome?

## Existing Skills

Before proposing a skill, check if a relevant skill already exists from the list below:

{{SKILL_LIST}}

## Action Guidelines

**CRITICAL: Patch before create**

Before creating a new skill, analyze if the new functionality is already covered by an existing skill:
- If the new skill would duplicate or overlap with existing skill capabilities → **patch the existing skill** to add the new use case
- If the existing skill covers the general area but misses a specific use case → **patch** to add that use case
- Prefer patching the skill that was active or directly mentioned in the conversation.
- Only create a new skill if the functionality is truly distinct from all existing skills and there is no umbrella skill that should absorb it.

- If a relevant skill **already exists** and needs modification:
  - Use "edit" to completely replace the skill content
  - Use "patch" to make targeted changes (provide old_string and new_string) - **preferred for small additions**
- If no relevant skill exists and the approach is reusable:
  - Use "create" to create a new skill
- **Avoid creating skills with duplicate or overlapping functionality**
- Do not turn temporary environment failures, one-off dependency outages, or accidental local state into permanent skill constraints.
- For "create" and "edit", `content` must be the complete `SKILL.md` text, including YAML frontmatter delimited by `---` at the start. At minimum include `name` and `description` in frontmatter, and make the frontmatter `name` exactly match the `name` field passed to `review_skill`.

## IMPORTANT: How to use "patch" action

When using "patch" to modify an existing skill, copy the smallest relevant text from the skill's `<details>` section above as your `old_string`. The runtime can apply fuzzy patches, but `old_string` must still be specific enough to match only one location unless you intentionally set `replace_all`.

For example, if adding a new step to "explore_rust_project_structure":
1. Find the exact text you want to replace in the `<details>` section
2. Use that exact text as `old_string`
3. Use your updated version as `new_string`

When calling `review_skill`, include:
- `action`: create, edit, patch, delete, write_file, or remove_file
- `name`: the skill name
- `content`: the skill content (for create/edit) or file content (for write_file)
- For "patch": provide `old_string` (MUST be exact text from skill's `<details>` above) and `new_string`
- `confidence`: high (explicit user instruction), medium (clear pattern), or low (possible pattern)
- `reasoning`: brief explanation of why this skill is worth saving or updating

If nothing is worth saving, simply reply with "none".

IMPORTANT: Do NOT continue the conversation or answer the user's question. Your task is ONLY to review the conversation for skill evolution opportunities.
