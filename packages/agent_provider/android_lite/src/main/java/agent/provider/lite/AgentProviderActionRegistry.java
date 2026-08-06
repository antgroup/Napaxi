package agent.provider.lite;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.Set;

/**
 * Generic action routing for generated Provider apps.
 *
 * <p>Generated apps register only app-owned domain handlers. This class checks
 * that the registry exactly matches {@code assets/agent-app.json}, consumes
 * replay state before non-idempotent work, and constructs the protocol result.</p>
 */
public final class AgentProviderActionRegistry {
    @FunctionalInterface
    public interface Handler {
        JSONObject execute(Context context, JSONObject arguments) throws Exception;
    }

    private static final class Entry {
        final boolean nonIdempotent;
        final Handler handler;

        Entry(boolean nonIdempotent, Handler handler) {
            this.nonIdempotent = nonIdempotent;
            this.handler = handler;
        }
    }

    private final Map<String, Entry> entries = new LinkedHashMap<>();

    public AgentProviderActionRegistry register(
            String actionId,
            boolean nonIdempotent,
            Handler handler) {
        String id = actionId == null ? "" : actionId.trim();
        if (id.isEmpty()) throw new IllegalArgumentException("actionId must not be empty");
        if (handler == null) throw new IllegalArgumentException("handler must not be null");
        if (entries.put(id, new Entry(nonIdempotent, handler)) != null) {
            throw new IllegalArgumentException("Duplicate Agent App action handler: " + id);
        }
        return this;
    }

    public void validateAgainstPackage(JSONObject packageJson) throws Exception {
        JSONArray actions = packageJson == null ? null : packageJson.optJSONArray("actions");
        if (actions == null || actions.length() == 0) {
            throw new IllegalArgumentException("Provider package has no declared actions");
        }
        Set<String> declared = new LinkedHashSet<>();
        for (int index = 0; index < actions.length(); index++) {
            String actionId = actions.getJSONObject(index).optString("action_id", "").trim();
            if (actionId.isEmpty()) {
                throw new IllegalArgumentException("Provider action_id must not be empty");
            }
            if (!declared.add(actionId)) {
                throw new IllegalArgumentException("Duplicate declared action: " + actionId);
            }
        }
        if (!declared.equals(entries.keySet())) {
            throw new IllegalArgumentException(
                    "Declared actions and registered handlers differ; declared="
                            + declared + ", handlers=" + entries.keySet());
        }
    }

    public Intent execute(Activity activity, AgentProviderLite.Validation validation) {
        if (validation == null) {
            throw new IllegalArgumentException("validation must not be null");
        }
        if (!validation.valid) {
            return AgentProviderLite.validationFailureResult(validation);
        }
        try {
            JSONObject actionMetadata = new JSONObject()
                    .put("action_id", validation.actionId())
                    .put("request_id", validation.requestId());
            AgentProviderDiagnostics.recordBreadcrumb(
                    activity, "agent_action", "started:" + validation.actionId());
            AgentProviderDiagnostics.log(
                    activity,
                    AgentProviderDiagnostics.LEVEL_INFO,
                    "agent_action",
                    "action_started",
                    "Agent App action started.",
                    actionMetadata,
                    validation.requestId());
            validateAgainstPackage(validation.packageJson);
            Entry entry = entries.get(validation.actionId());
            if (entry == null) {
                AgentProviderDiagnostics.log(
                        activity,
                        AgentProviderDiagnostics.LEVEL_ERROR,
                        "agent_action",
                        "handler_not_found",
                        "No handler is registered for the action.",
                        actionMetadata,
                        validation.requestId());
                return AgentProviderLite.failedResult(
                        validation, "handler_not_found", "No handler is registered for the action.");
            }
            if (entry.nonIdempotent) {
                AgentProviderLite.markConsumed(activity, validation);
            }
            JSONObject result = entry.handler.execute(activity, validation.arguments());
            AgentProviderDiagnostics.recordBreadcrumb(
                    activity, "agent_action", "succeeded:" + validation.actionId());
            AgentProviderDiagnostics.log(
                    activity,
                    AgentProviderDiagnostics.LEVEL_INFO,
                    "agent_action",
                    "action_succeeded",
                    "Agent App action completed.",
                    actionMetadata,
                    validation.requestId());
            return AgentProviderLite.successResult(
                    validation, result == null ? new JSONObject() : result);
        } catch (Exception error) {
            JSONObject metadata = new JSONObject();
            try {
                metadata.put("action_id", validation.actionId());
                metadata.put("request_id", validation.requestId());
            } catch (Exception ignored) {
                // Primitive JSON writes do not fail.
            }
            AgentProviderDiagnostics.recordCaughtException(
                    activity, "agent_action_failure", error, metadata);
            String message = error.getMessage();
            return AgentProviderLite.failedResult(
                    validation,
                    "action_failed",
                    message == null || message.trim().isEmpty() ? "Action failed." : message);
        }
    }
}
