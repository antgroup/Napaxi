# Generated Tasks Provider

Second cross-domain acceptance output for the same on-device pure-Java builder
and Agent Provider Lite SDK used by Generated Notes.

The launcher UI and Agent actions share `TaskStore`. Declared actions are
`task.add`, `task.list`, `task.complete`, and `task.delete`; complete/delete
require Provider-owned confirmation. No reusable Provider protocol logic is
copied into this app.
