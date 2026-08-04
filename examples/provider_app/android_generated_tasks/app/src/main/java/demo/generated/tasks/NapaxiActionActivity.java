package demo.generated.tasks;

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
                    .setTitle("Confirm Generated Tasks action")
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
                .register("task.add", true, (context, args) -> new JSONObject().put(
                        "task", TaskStore.add(context, require(args, "title"))))
                .register("task.list", false, (context, args) -> new JSONObject().put(
                        "tasks",
                        TaskStore.list(
                                context,
                                args.has("completed") ? args.optBoolean("completed") : null)))
                .register("task.complete", true, (context, args) -> {
                    JSONObject task = TaskStore.complete(context, require(args, "id"));
                    if (task == null) throw new IllegalArgumentException("task_not_found");
                    return new JSONObject().put("task", task);
                })
                .register("task.delete", true, (context, args) -> new JSONObject().put(
                        "deleted", TaskStore.delete(context, require(args, "id"))));
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
