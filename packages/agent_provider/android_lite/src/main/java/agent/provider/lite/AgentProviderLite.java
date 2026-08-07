package agent.provider.lite;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.Signature;
import android.os.Build;
import android.util.Base64;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Iterator;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

/**
 * Dependency-free Agent App Provider protocol helpers for Napaxi's on-device
 * pure-Java APK template.
 *
 * <p>The reusable protocol and trust logic lives here. Generated apps only
 * provide {@code assets/agent-app.json} and an Activity that maps validated
 * action ids to app-owned domain services.</p>
 */
public final class AgentProviderLite {
    public static final String ACTION_INSTALL_AGENT = "agent.provider.action.INSTALL_AGENT";
    public static final String ACTION_HANDLE_PROPOSAL = "agent.provider.action.HANDLE_PROPOSAL";
    public static final String ACTION_GET_DIAGNOSTICS =
            "agent.provider.action.GET_DIAGNOSTICS";
    public static final String EXTRA_INSTALL_REQUEST_JSON =
            "agent.provider.extra.INSTALL_REQUEST_JSON";
    public static final String EXTRA_INSTALL_RESULT_JSON =
            "agent.provider.extra.INSTALL_RESULT_JSON";
    public static final String EXTRA_PACKAGE_JSON = "agent.provider.extra.PACKAGE_JSON";
    public static final String EXTRA_PROPOSAL_JSON = "agent.provider.extra.PROPOSAL_JSON";
    public static final String EXTRA_RESULT_JSON = "agent.provider.extra.RESULT_JSON";
    public static final String EXTRA_DIAGNOSTICS_REQUEST_JSON =
            "agent.provider.extra.DIAGNOSTICS_REQUEST_JSON";
    public static final String EXTRA_DIAGNOSTICS_RESULT_JSON =
            "agent.provider.extra.DIAGNOSTICS_RESULT_JSON";
    public static final String SIGNATURE_ALGORITHM = "hmac-sha256-v1";
    public static final String PACKAGE_ASSET = "agent-app.json";

    private static final String PREF_PREFIX = "napaxi_agent_provider_";
    private static final String CONSUMED_IDS = "consumed_request_ids";

    private AgentProviderLite() {}

    public static JSONObject readPackage(Context context) throws Exception {
        try (InputStream input = context.getAssets().open(PACKAGE_ASSET)) {
            ByteArrayOutputStream output = new ByteArrayOutputStream();
            byte[] buffer = new byte[4096];
            int read;
            while ((read = input.read(buffer)) >= 0) {
                output.write(buffer, 0, read);
            }
            return new JSONObject(output.toString(StandardCharsets.UTF_8.name()));
        }
    }

    /** Handles a protocol-v2 install request and persists a trusted Host binding. */
    public static Intent handleTrustedInstall(Activity activity) {
        JSONObject request = null;
        try {
            Intent source = activity.getIntent();
            if (source == null || !ACTION_INSTALL_AGENT.equals(source.getAction())) {
                throw new ProtocolException("invalid_install_intent", "Invalid install intent.");
            }
            String raw = source.getStringExtra(EXTRA_INSTALL_REQUEST_JSON);
            if (raw == null || raw.trim().isEmpty()) {
                throw new ProtocolException("missing_install_request", "Install request is missing.");
            }
            request = new JSONObject(raw);
            validateInstallRequest(activity, request);
            JSONObject packageJson = readPackage(activity);
            validatePackage(packageJson);
            saveBinding(activity, packageJson.getString("provider_id"), request);

            JSONObject result = new JSONObject()
                    .put("status", "succeeded")
                    .put("request_id", request.getString("request_id"))
                    .put("nonce", request.getString("nonce"))
                    .put("package", packageJson)
                    .put("completed_at", Instant.now().toString());
            return new Intent()
                    .putExtra(EXTRA_INSTALL_RESULT_JSON, result.toString())
                    .putExtra(EXTRA_PACKAGE_JSON, packageJson.toString());
        } catch (Exception error) {
            String code = error instanceof ProtocolException
                    ? ((ProtocolException) error).code
                    : "install_failed";
            String message = safeMessage(error, "Provider installation failed.");
            JSONObject result = new JSONObject();
            try {
                result.put("status", "failed");
                if (request != null) {
                    result.put("request_id", request.optString("request_id"));
                    result.put("nonce", request.optString("nonce"));
                }
                result.put("error", new JSONObject().put("code", code).put("message", message));
                result.put("completed_at", Instant.now().toString());
            } catch (JSONException ignored) {
                // All inserted values are JSON primitives.
            }
            return new Intent().putExtra(EXTRA_INSTALL_RESULT_JSON, result.toString());
        }
    }

    /** Parses and fully validates a signed proposal before app business logic runs. */
    public static Validation validateTrustedProposal(Activity activity) {
        try {
            Intent source = activity.getIntent();
            if (source == null || !ACTION_HANDLE_PROPOSAL.equals(source.getAction())) {
                throw new ProtocolException("invalid_action_intent", "Invalid action intent.");
            }
            String raw = source.getStringExtra(EXTRA_PROPOSAL_JSON);
            if (raw == null || raw.trim().isEmpty()) {
                throw new ProtocolException("missing_proposal", "Action proposal is missing.");
            }
            JSONObject proposal = new JSONObject(raw);
            JSONObject packageJson = readPackage(activity);
            JSONObject action = validateProposalEnvelope(proposal, packageJson);
            String providerId = packageJson.getString("provider_id");
            SharedPreferences prefs = preferences(activity, providerId);
            String requestId = proposal.getString("request_id");
            if (prefs.getStringSet(CONSUMED_IDS, Collections.emptySet()).contains(requestId)) {
                throw new ProtocolException("replayed", "Proposal has already been consumed.");
            }

            String hostInstanceId = requiredString(proposal, "host_instance_id");
            String bindingRaw = prefs.getString("binding_" + hostInstanceId, null);
            if (bindingRaw == null) {
                throw new ProtocolException("host_not_bound", "No trusted Host binding exists.");
            }
            JSONObject binding = new JSONObject(bindingRaw);
            String callerPackage = activity.getCallingPackage();
            if (callerPackage == null || callerPackage.trim().isEmpty()) {
                throw new ProtocolException(
                        "missing_calling_package", "Unable to verify the calling package.");
            }
            if (!callerPackage.equals(binding.optString("host_package_name"))) {
                throw new ProtocolException("caller_mismatch", "Calling package is not trusted.");
            }
            String actualDigest = signingCertSha256(activity, callerPackage);
            if (!actualDigest.equalsIgnoreCase(binding.optString("host_signing_cert_sha256"))) {
                throw new ProtocolException(
                        "caller_signature_mismatch", "Calling package signature is not trusted.");
            }
            if (!SIGNATURE_ALGORITHM.equals(proposal.optString("signature_algorithm"))) {
                throw new ProtocolException(
                        "missing_trust_fields", "Proposal signature algorithm is invalid.");
            }
            String signature = requiredString(proposal, "signature");
            String secret = requiredString(binding, "host_shared_secret");
            String expected = hmacSha256Base64NoPad(secret, proposalSignaturePayload(proposal));
            if (!MessageDigest.isEqual(
                    signature.getBytes(StandardCharsets.UTF_8),
                    expected.getBytes(StandardCharsets.UTF_8))) {
                throw new ProtocolException("signature_invalid", "Proposal signature is invalid.");
            }
            return Validation.success(proposal, packageJson, action);
        } catch (Exception error) {
            String code = error instanceof ProtocolException
                    ? ((ProtocolException) error).code
                    : "invalid_proposal";
            return Validation.failure(code, safeMessage(error, "Invalid action proposal."));
        }
    }

    /** Validates a Host-signed, model-hidden diagnostics request. */
    public static DiagnosticsValidation validateTrustedDiagnosticsRequest(Activity activity) {
        JSONObject request = null;
        try {
            Intent source = activity.getIntent();
            if (source == null || !ACTION_GET_DIAGNOSTICS.equals(source.getAction())) {
                throw new ProtocolException(
                        "invalid_diagnostics_intent", "Invalid diagnostics intent.");
            }
            String raw = source.getStringExtra(EXTRA_DIAGNOSTICS_REQUEST_JSON);
            if (raw == null || raw.trim().isEmpty()) {
                throw new ProtocolException(
                        "missing_diagnostics_request", "Diagnostics request is missing.");
            }
            request = new JSONObject(raw);
            if (request.optInt("protocol_version", 0) != 1) {
                throw new ProtocolException(
                        "unsupported_diagnostics_protocol", "Diagnostics protocol v1 is required.");
            }
            requiredString(request, "request_id");
            String providerId = requiredString(request, "provider_id");
            JSONObject packageJson = readPackage(activity);
            if (!providerId.equals(requiredString(packageJson, "provider_id"))) {
                throw new ProtocolException(
                        "provider_mismatch", "Diagnostics provider does not match this app.");
            }
            String operation = requiredString(request, "operation");
            if (!"list".equals(operation)
                    && !"ack".equals(operation)
                    && !"configure".equals(operation)) {
                throw new ProtocolException(
                        "unsupported_diagnostics_operation", "Diagnostics operation is unsupported.");
            }
            requiredString(request, "nonce");
            ensureNotExpired(requiredString(request, "expires_at"), "diagnostics_expired");
            String hostInstanceId = requiredString(request, "host_instance_id");
            SharedPreferences prefs = preferences(activity, providerId);
            String bindingRaw = prefs.getString("binding_" + hostInstanceId, null);
            if (bindingRaw == null) {
                throw new ProtocolException("host_not_bound", "No trusted Host binding exists.");
            }
            JSONObject binding = new JSONObject(bindingRaw);
            String callerPackage = activity.getCallingPackage();
            if (callerPackage == null || callerPackage.trim().isEmpty()) {
                throw new ProtocolException(
                        "missing_calling_package", "Unable to verify the calling package.");
            }
            if (!callerPackage.equals(binding.optString("host_package_name"))) {
                throw new ProtocolException("caller_mismatch", "Calling package is not trusted.");
            }
            String actualDigest = signingCertSha256(activity, callerPackage);
            if (!actualDigest.equalsIgnoreCase(
                    binding.optString("host_signing_cert_sha256"))) {
                throw new ProtocolException(
                        "caller_signature_mismatch", "Calling package signature is not trusted.");
            }
            if (!SIGNATURE_ALGORITHM.equals(request.optString("signature_algorithm"))) {
                throw new ProtocolException(
                        "missing_trust_fields", "Diagnostics signature algorithm is invalid.");
            }
            String signature = requiredString(request, "signature");
            String secret = requiredString(binding, "host_shared_secret");
            String expected = hmacSha256Base64NoPad(
                    secret, diagnosticsSignaturePayload(request));
            if (!MessageDigest.isEqual(
                    signature.getBytes(StandardCharsets.UTF_8),
                    expected.getBytes(StandardCharsets.UTF_8))) {
                throw new ProtocolException(
                        "signature_invalid", "Diagnostics signature is invalid.");
            }
            return DiagnosticsValidation.success(request);
        } catch (Exception error) {
            String code = error instanceof ProtocolException
                    ? ((ProtocolException) error).code
                    : "invalid_diagnostics_request";
            String requestId = request == null ? "" : request.optString("request_id");
            return DiagnosticsValidation.failure(
                    requestId, code, safeMessage(error, "Invalid diagnostics request."));
        }
    }

    public static void markConsumed(Context context, Validation validation) throws Exception {
        if (!validation.valid || validation.proposal == null || validation.packageJson == null) {
            return;
        }
        String providerId = validation.packageJson.optString("provider_id");
        String requestId = validation.proposal.optString("request_id");
        if (providerId.isEmpty() || requestId.isEmpty()) {
            return;
        }
        SharedPreferences prefs = preferences(context, providerId);
        Set<String> current = prefs.getStringSet(CONSUMED_IDS, Collections.emptySet());
        Set<String> next = new HashSet<>(current);
        next.add(requestId);
        if (!prefs.edit().putStringSet(CONSUMED_IDS, next).commit()) {
            throw new ProtocolException(
                    "replay_state_persist_failed", "Unable to persist proposal replay state.");
        }
    }

    public static Intent successResult(Validation validation, JSONObject result) {
        return resultIntent(validation, "succeeded", result, null, null);
    }

    public static Intent failedResult(Validation validation, String code, String message) {
        return resultIntent(validation, "failed", JSONObject.NULL, code, message);
    }

    public static Intent canceledResult(Validation validation, String message) {
        return resultIntent(validation, "canceled", JSONObject.NULL, "user_canceled", message);
    }

    public static Intent validationFailureResult(Validation validation) {
        return failedResult(validation, validation.errorCode, validation.errorMessage);
    }

    private static Intent resultIntent(
            Validation validation,
            String status,
            Object result,
            String errorCode,
            String errorMessage) {
        JSONObject payload = new JSONObject();
        try {
            payload.put("request_id", validation.requestId());
            payload.put("status", status);
            payload.put("result", result == null ? JSONObject.NULL : result);
            // Core v2 currently expects a string error. Keep this wire shape
            // until the shared structured error contract is adopted.
            if (errorMessage != null && !errorMessage.isEmpty()) {
                payload.put("error", errorCode == null || errorCode.isEmpty()
                        ? errorMessage
                        : errorCode + ": " + errorMessage);
            } else {
                payload.put("error", JSONObject.NULL);
            }
            payload.put("completed_at", Instant.now().toString());
        } catch (JSONException ignored) {
            // All inserted values are valid JSON primitives/objects.
        }
        return new Intent().putExtra(EXTRA_RESULT_JSON, payload.toString());
    }

    private static void validatePackage(JSONObject packageJson) throws Exception {
        requiredString(packageJson, "provider_id");
        requiredString(packageJson, "agent_id");
        requiredString(packageJson, "display_name");
        JSONArray actions = packageJson.optJSONArray("actions");
        if (actions == null || actions.length() == 0) {
            throw new ProtocolException("missing_actions", "Provider must declare an action.");
        }
        for (int index = 0; index < actions.length(); index++) {
            JSONObject action = actions.getJSONObject(index);
            requiredString(action, "action_id");
            String toolName = requiredString(action, "tool_name");
            if (!toolName.startsWith("app_action_")) {
                throw new ProtocolException(
                        "invalid_tool_name", "Provider tool names must start with app_action_.");
            }
            String confirmationPolicy = normalizeConfirmationPolicy(action);
            action.put("confirmation_policy", confirmationPolicy);
            String risk = action.optString("risk", "high");
            if (("high".equals(risk) || "critical".equals(risk))
                    && !"provider_required".equals(confirmationPolicy)) {
                throw new ProtocolException(
                        "unsafe_confirmation_policy",
                        "High-risk actions require provider confirmation.");
            }
        }
    }

    private static String normalizeConfirmationPolicy(JSONObject action) throws Exception {
        String value = action.optString("confirmation_policy", "provider_required").trim();
        if (value.isEmpty() || "provider_required".equals(value) || "provider".equals(value)) {
            return "provider_required";
        }
        if ("none".equals(value)) return "none";
        throw new ProtocolException(
                "unsupported_confirmation_policy",
                "confirmation_policy must be none or provider_required.");
    }

    private static void validateInstallRequest(Activity activity, JSONObject request)
            throws Exception {
        if (request.optInt("protocol_version", 1) < 2) {
            throw new ProtocolException("unsupported_protocol", "Protocol v2 is required.");
        }
        requiredString(request, "request_id");
        requiredString(request, "nonce");
        String hostPackage = requiredString(request, "host_package_name");
        String hostCert = requiredString(request, "host_signing_cert_sha256");
        requiredString(request, "host_instance_id");
        requiredString(request, "host_shared_secret");
        ensureNotExpired(requiredString(request, "expires_at"), "install_expired");
        String callerPackage = activity.getCallingPackage();
        if (callerPackage == null || !callerPackage.equals(hostPackage)) {
            throw new ProtocolException("caller_mismatch", "Calling package does not match Host.");
        }
        String digest = signingCertSha256(activity, callerPackage);
        if (!digest.equalsIgnoreCase(hostCert)) {
            throw new ProtocolException(
                    "caller_signature_mismatch", "Calling package signature does not match Host.");
        }
    }

    private static JSONObject validateProposalEnvelope(
            JSONObject proposal, JSONObject packageJson) throws Exception {
        validatePackage(packageJson);
        String requestId = requiredString(proposal, "request_id");
        if (requestId.isEmpty()) {
            throw new ProtocolException("missing_request_id", "Proposal request id is missing.");
        }
        if (!requiredString(proposal, "provider_id")
                .equals(packageJson.getString("provider_id"))) {
            throw new ProtocolException("provider_mismatch", "Proposal provider does not match.");
        }
        if (!requiredString(proposal, "agent_id").equals(packageJson.getString("agent_id"))) {
            throw new ProtocolException("agent_mismatch", "Proposal Agent does not match.");
        }
        requiredString(proposal, "nonce");
        requiredString(proposal, "idempotency_key");
        ensureNotExpired(requiredString(proposal, "expires_at"), "expired");
        String actionId = requiredString(proposal, "action_id");
        String toolName = requiredString(proposal, "tool_name");
        JSONArray actions = packageJson.getJSONArray("actions");
        for (int index = 0; index < actions.length(); index++) {
            JSONObject action = actions.getJSONObject(index);
            if (actionId.equals(action.optString("action_id"))) {
                if (!toolName.equals(action.optString("tool_name"))) {
                    throw new ProtocolException("tool_mismatch", "Proposal tool does not match.");
                }
                return action;
            }
        }
        throw new ProtocolException("action_not_found", "Proposal action is not declared.");
    }

    private static void saveBinding(Context context, String providerId, JSONObject request)
            throws Exception {
        JSONObject binding = new JSONObject()
                .put("host_package_name", request.getString("host_package_name"))
                .put("host_signing_cert_sha256", request.getString("host_signing_cert_sha256"))
                .put("host_instance_id", request.getString("host_instance_id"))
                .put("host_shared_secret", request.getString("host_shared_secret"))
                .put("protocol_version", request.getInt("protocol_version"))
                .put("installed_at", Instant.now().toString());
        String id = binding.getString("host_instance_id");
        boolean saved = preferences(context, providerId).edit()
                .putString("binding_" + id, binding.toString())
                .putString("latest_host_instance_id", id)
                .commit();
        if (!saved) {
            throw new ProtocolException(
                    "binding_persist_failed", "Unable to persist trusted Host binding.");
        }
    }

    private static SharedPreferences preferences(Context context, String providerId) {
        return context.getApplicationContext().getSharedPreferences(
                PREF_PREFIX + providerId.replaceAll("[^A-Za-z0-9_.-]", "_"),
                Context.MODE_PRIVATE);
    }

    private static String proposalSignaturePayload(JSONObject proposal) throws Exception {
        JSONObject arguments = proposal.optJSONObject("arguments");
        if (arguments == null) {
            arguments = new JSONObject();
        }
        String argumentsHash = sha256Base64NoPad(
                canonicalJson(arguments).getBytes(StandardCharsets.UTF_8));
        return "request_id=" + proposal.getString("request_id") + "\n"
                + "provider_id=" + proposal.getString("provider_id") + "\n"
                + "agent_id=" + proposal.getString("agent_id") + "\n"
                + "action_id=" + proposal.getString("action_id") + "\n"
                + "tool_name=" + proposal.getString("tool_name") + "\n"
                + "arguments_sha256=" + argumentsHash + "\n"
                + "created_at=" + proposal.getString("created_at") + "\n"
                + "expires_at=" + proposal.getString("expires_at") + "\n"
                + "nonce=" + proposal.getString("nonce") + "\n"
                + "idempotency_key=" + proposal.getString("idempotency_key") + "\n"
                + "risk=" + proposal.getString("risk") + "\n"
                + "confirmation_policy=" + proposal.getString("confirmation_policy") + "\n"
                + "host_instance_id=" + proposal.getString("host_instance_id");
    }

    private static String diagnosticsSignaturePayload(JSONObject request) throws Exception {
        JSONArray reportIds = request.optJSONArray("report_ids");
        if (reportIds == null) reportIds = new JSONArray();
        String reportIdsHash = sha256Base64NoPad(
                canonicalJson(reportIds).getBytes(StandardCharsets.UTF_8));
        return "request_id=" + request.getString("request_id") + "\n"
                + "provider_id=" + request.getString("provider_id") + "\n"
                + "operation=" + request.getString("operation") + "\n"
                + "report_ids_sha256=" + reportIdsHash + "\n"
                + "detailed_logging=" + request.optBoolean("detailed_logging", false) + "\n"
                + "created_at=" + request.getString("created_at") + "\n"
                + "expires_at=" + request.getString("expires_at") + "\n"
                + "nonce=" + request.getString("nonce") + "\n"
                + "host_instance_id=" + request.getString("host_instance_id");
    }

    private static String canonicalJson(Object value) throws Exception {
        if (value == null || value == JSONObject.NULL) {
            return "null";
        }
        if (value instanceof JSONObject) {
            JSONObject object = (JSONObject) value;
            List<String> keys = new ArrayList<>();
            Iterator<String> iterator = object.keys();
            while (iterator.hasNext()) {
                keys.add(iterator.next());
            }
            Collections.sort(keys);
            StringBuilder result = new StringBuilder("{");
            for (int index = 0; index < keys.size(); index++) {
                if (index > 0) result.append(',');
                String key = keys.get(index);
                result.append(JSONObject.quote(key))
                        .append(':')
                        .append(canonicalJson(object.get(key)));
            }
            return result.append('}').toString();
        }
        if (value instanceof JSONArray) {
            JSONArray array = (JSONArray) value;
            StringBuilder result = new StringBuilder("[");
            for (int index = 0; index < array.length(); index++) {
                if (index > 0) result.append(',');
                result.append(canonicalJson(array.get(index)));
            }
            return result.append(']').toString();
        }
        if (value instanceof String) {
            return JSONObject.quote((String) value);
        }
        if (value instanceof Boolean || value instanceof Number) {
            return String.valueOf(value);
        }
        throw new ProtocolException("invalid_json_value", "Unsupported JSON value.");
    }

    private static String signingCertSha256(Context context, String packageName) throws Exception {
        PackageManager manager = context.getPackageManager();
        PackageInfo info;
        Signature[] signatures;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info = manager.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES);
            signatures = info.signingInfo == null
                    ? new Signature[0]
                    : info.signingInfo.getApkContentsSigners();
        } else {
            info = manager.getPackageInfo(packageName, PackageManager.GET_SIGNATURES);
            signatures = info.signatures == null ? new Signature[0] : info.signatures;
        }
        if (signatures.length == 0) {
            throw new ProtocolException(
                    "caller_signature_unavailable", "Unable to read calling package signature.");
        }
        byte[] digest = MessageDigest.getInstance("SHA-256").digest(signatures[0].toByteArray());
        StringBuilder hex = new StringBuilder();
        for (byte value : digest) {
            hex.append(String.format("%02x", value & 0xff));
        }
        return hex.toString();
    }

    private static String hmacSha256Base64NoPad(String secret, String payload) throws Exception {
        Mac mac = Mac.getInstance("HmacSHA256");
        mac.init(new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
        return Base64.encodeToString(
                mac.doFinal(payload.getBytes(StandardCharsets.UTF_8)),
                Base64.NO_WRAP | Base64.NO_PADDING);
    }

    private static String sha256Base64NoPad(byte[] value) throws Exception {
        return Base64.encodeToString(
                MessageDigest.getInstance("SHA-256").digest(value),
                Base64.NO_WRAP | Base64.NO_PADDING);
    }

    private static void ensureNotExpired(String timestamp, String code) throws Exception {
        if (Instant.now().isAfter(Instant.parse(timestamp))) {
            throw new ProtocolException(code, "Request has expired.");
        }
    }

    private static String requiredString(JSONObject object, String key) throws Exception {
        String value = object.optString(key, "").trim();
        if (value.isEmpty()) {
            throw new ProtocolException("missing_" + key, "Missing required field: " + key);
        }
        return value;
    }

    private static String safeMessage(Exception error, String fallback) {
        String message = error.getMessage();
        return message == null || message.trim().isEmpty() ? fallback : message;
    }

    private static final class ProtocolException extends Exception {
        final String code;

        ProtocolException(String code, String message) {
            super(message);
            this.code = code;
        }
    }

    public static final class Validation {
        public final boolean valid;
        public final JSONObject proposal;
        public final JSONObject packageJson;
        public final JSONObject action;
        public final String errorCode;
        public final String errorMessage;

        private Validation(
                boolean valid,
                JSONObject proposal,
                JSONObject packageJson,
                JSONObject action,
                String errorCode,
                String errorMessage) {
            this.valid = valid;
            this.proposal = proposal;
            this.packageJson = packageJson;
            this.action = action;
            this.errorCode = errorCode == null ? "" : errorCode;
            this.errorMessage = errorMessage == null ? "" : errorMessage;
        }

        static Validation success(JSONObject proposal, JSONObject packageJson, JSONObject action) {
            return new Validation(true, proposal, packageJson, action, null, null);
        }

        static Validation failure(String code, String message) {
            return new Validation(false, null, null, null, code, message);
        }

        public String requestId() {
            return proposal == null ? "" : proposal.optString("request_id");
        }

        public String actionId() {
            return proposal == null ? "" : proposal.optString("action_id");
        }

        public JSONObject arguments() {
            JSONObject arguments = proposal == null ? null : proposal.optJSONObject("arguments");
            return arguments == null ? new JSONObject() : arguments;
        }

        public boolean requiresProviderConfirmation() {
            if (action == null) return true;
            String risk = action.optString("risk", "high");
            String confirmationPolicy =
                    action.optString("confirmation_policy", "provider_required");
            return "provider_required".equals(confirmationPolicy)
                    || "provider".equals(confirmationPolicy)
                    || "high".equals(risk)
                    || "critical".equals(risk);
        }
    }

    public static final class DiagnosticsValidation {
        public final boolean valid;
        public final JSONObject request;
        public final String errorCode;
        public final String errorMessage;
        private final String failedRequestId;

        private DiagnosticsValidation(
                boolean valid,
                JSONObject request,
                String failedRequestId,
                String errorCode,
                String errorMessage) {
            this.valid = valid;
            this.request = request;
            this.failedRequestId = failedRequestId == null ? "" : failedRequestId;
            this.errorCode = errorCode == null ? "" : errorCode;
            this.errorMessage = errorMessage == null ? "" : errorMessage;
        }

        static DiagnosticsValidation success(JSONObject request) {
            return new DiagnosticsValidation(true, request, null, null, null);
        }

        static DiagnosticsValidation failure(String requestId, String code, String message) {
            return new DiagnosticsValidation(false, null, requestId, code, message);
        }

        public String requestId() {
            return request == null ? failedRequestId : request.optString("request_id");
        }
    }
}
