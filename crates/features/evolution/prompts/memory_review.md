Review the conversation above and consider saving to memory if appropriate.

## Existing memory awareness

The current contents of each memory file are shown above your conversation snapshot.
You MUST compare any candidate information against those existing contents before saving.

- If the information is **already present** (even in different wording), **skip it entirely**.
- If new information **contradicts or updates** an existing entry, prefix your content with `[UPDATE]` to replace the outdated entry rather than appending a duplicate.
- If an existing entry is **clearly obsolete** (the user has explicitly changed their mind or the fact is no longer true), prefix your content with `[DELETE]` followed by the key phrase from the entry to remove.
- If the information is **genuinely new** and not present in any form, write it with no prefix (default: append).

## Substance filter

Before saving, ask yourself:
- Is the conversation substantial enough to contain durable insights? Skip trivial or purely transactional exchanges (e.g., simple Q&A, one-off commands).

## What to look for

1. Has the user revealed things about themselves — their persona, desires, preferences, or personal details worth remembering?
2. Has the user expressed expectations about how you should behave, their work style, or ways they want you to operate?

## Choosing `entry_type`

- `user_profile`: personal traits, preferences, communication style, role, goals — anything about WHO the user is
- `project`: project-specific conventions, architecture decisions, tech stack choices — anything about WHAT is being built
- `environment`: tooling constraints, platform quirks, workflow patterns — anything about HOW work gets done

## Calling the tool

If something stands out, save it using the `review_memory` tool with:
- `entry_type`: environment, user_profile, or project
- `content`: the information to remember (be concise and specific). Use `[UPDATE] ...` to replace a similar existing entry, `[DELETE] key phrase` to remove an obsolete entry, or no prefix to append new information.
- `confidence`: high (explicit statement), medium (inferred), or low (possible)
- `reasoning`: brief explanation of why this is worth remembering

If nothing worth saving is found, do not call any tool — just reply "none".
