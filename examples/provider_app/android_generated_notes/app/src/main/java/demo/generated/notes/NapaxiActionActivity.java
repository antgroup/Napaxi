package demo.generated.notes;

import android.app.Activity;
import android.app.AlertDialog;
import android.os.Bundle;

import org.json.JSONObject;

import agent.provider.lite.AgentProviderActionRegistry;
import agent.provider.lite.AgentProviderLite;

public final class NapaxiActionActivity extends Activity {
    private AgentProviderLite.Validation validation;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        validation = AgentProviderLite.validateTrustedProposal(this);
        if (!validation.valid) {
            finishWith(AgentProviderLite.validationFailureResult(validation));
            return;
        }
        if (validation.requiresProviderConfirmation()) {
            new AlertDialog.Builder(this)
                    .setTitle("Confirm Generated Notes action")
                    .setMessage("Allow Napaxi to run " + validation.actionId() + "?")
                    .setNegativeButton("Cancel", (dialog, which) -> finishWith(
                            AgentProviderLite.canceledResult(validation, "Canceled by user.")))
                    .setPositiveButton("Confirm", (dialog, which) -> execute())
                    .setOnCancelListener(dialog -> finishWith(
                            AgentProviderLite.canceledResult(validation, "Canceled by user.")))
                    .show();
        } else {
            execute();
        }
    }

    private void execute() {
        finishWith(actionRegistry().execute(this, validation));
    }

    private static AgentProviderActionRegistry actionRegistry() {
        return new AgentProviderActionRegistry()
                .register("note.create", true, (context, args) -> new JSONObject().put(
                        "note",
                        NoteStore.create(
                                context,
                                args.optString("title", ""),
                                require(args, "content"))))
                .register("note.list", false, (context, args) -> new JSONObject().put(
                        "notes", NoteStore.list(context, args.optString("query", ""))))
                .register("note.get", false, (context, args) -> {
                    JSONObject found = NoteStore.get(context, require(args, "id"));
                    if (found == null) throw new IllegalArgumentException("note_not_found");
                    return new JSONObject().put("note", found);
                })
                .register("note.update", true, (context, args) -> {
                    JSONObject updated = NoteStore.update(
                            context,
                            require(args, "id"),
                            args.has("title") ? args.optString("title") : null,
                            args.has("content") ? args.optString("content") : null);
                    if (updated == null) throw new IllegalArgumentException("note_not_found");
                    return new JSONObject().put("note", updated);
                })
                .register("note.delete", true, (context, args) -> new JSONObject().put(
                        "deleted", NoteStore.delete(context, require(args, "id"))));
    }

    private static String require(JSONObject args, String key) {
        String value = args.optString(key, "").trim();
        if (value.isEmpty()) throw new IllegalArgumentException("missing_" + key);
        return value;
    }

    private void finishWith(android.content.Intent result) {
        setResult(RESULT_OK, result);
        finish();
    }
}
