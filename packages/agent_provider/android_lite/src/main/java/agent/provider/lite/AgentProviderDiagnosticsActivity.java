package agent.provider.lite;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;

import org.json.JSONArray;
import org.json.JSONObject;

import java.time.Instant;

/** Hidden trusted endpoint used by Napaxi to retrieve Provider-owned reports. */
public final class AgentProviderDiagnosticsActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        AgentProviderLite.DiagnosticsValidation validation =
                AgentProviderLite.validateTrustedDiagnosticsRequest(this);
        JSONObject response = new JSONObject();
        try {
            response.put("request_id", validation.requestId());
            response.put("completed_at", Instant.now().toString());
            if (!validation.valid) {
                response.put("status", "failed");
                response.put("error", new JSONObject()
                        .put("code", validation.errorCode)
                        .put("message", validation.errorMessage));
            } else {
                String operation = validation.request.optString("operation", "list");
                JSONArray reports;
                if ("ack".equals(operation)) {
                    reports = AgentProviderDiagnostics.acknowledge(
                            this, validation.request.optJSONArray("report_ids") == null
                                    ? new JSONArray()
                                    : validation.request.optJSONArray("report_ids"));
                } else if ("configure".equals(operation)) {
                    AgentProviderDiagnostics.setDetailedLoggingEnabled(
                            this, validation.request.optBoolean("detailed_logging", false));
                    reports = AgentProviderDiagnostics.reports(this);
                } else {
                    reports = AgentProviderDiagnostics.reports(this);
                }
                response.put("status", "succeeded");
                response.put("reports", reports);
                response.put("logs", AgentProviderDiagnostics.logs(this));
                response.put("detailed_logging_enabled",
                        AgentProviderDiagnostics.isDetailedLoggingEnabled(this));
            }
        } catch (Exception error) {
            try {
                response.put("status", "failed");
                response.put("error", new JSONObject()
                        .put("code", "diagnostics_failed")
                        .put("message", error.getMessage() == null
                                ? "Unable to read diagnostics."
                                : error.getMessage()));
            } catch (Exception ignored) {
                // Primitive JSON writes do not fail.
            }
        }
        setResult(RESULT_OK, new Intent().putExtra(
                AgentProviderLite.EXTRA_DIAGNOSTICS_RESULT_JSON, response.toString()));
        finish();
    }
}
