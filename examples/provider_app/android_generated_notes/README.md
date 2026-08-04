# Generated Notes Provider

Reference output for Napaxi's on-device, pure-Java Android app builder. It has
no Gradle project and is built with the bundled `android-apk-build` script.

The launcher UI and Agent App actions share `NoteStore`. The Provider declares
five actions: `note.create`, `note.list`, `note.get`, `note.update`, and
`note.delete`; update/delete require Provider-owned confirmation.

## V1 acceptance walk-through

1. Build the project with the bundled `android-apk-build` script and install
   the single generated APK.
2. Discover the package and complete the trusted enable handshake from the
   Napaxi Host.
3. Keep Napaxi's default Agent selected and send the message with
   `AgentProviderSelection(providerId: "demo.generated_notes_provider")`, or
   type `@Generated Notes create a note saying hello`.
4. Verify that Core exposes only the selected Provider's action tools, the
   Provider writes through `NoteStore`, and the successful `ActionResult`
   returns to the same turn.
5. Send a delete request and verify that the Provider-owned confirmation UI is
   shown before `NoteStore` is mutated.
