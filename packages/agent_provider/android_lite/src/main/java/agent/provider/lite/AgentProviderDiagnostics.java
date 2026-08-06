package agent.provider.lite;

import android.app.ActivityManager;
import android.app.ApplicationExitInfo;
import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.PackageInfo;
import android.os.Build;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.PrintWriter;
import java.io.StringWriter;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Iterator;
import java.util.List;
import java.util.Locale;
import java.util.UUID;

/**
 * Private structured runtime diagnostics for small Agent Apps generated on-device.
 *
 * <p>Reports and logs stay in the Provider app's private storage. They are only
 * exposed through {@link AgentProviderDiagnosticsActivity}, which validates the
 * same trusted Host binding used by Agent App actions.</p>
 */
public final class AgentProviderDiagnostics {
    public static final String LEVEL_DEBUG = "debug";
    public static final String LEVEL_INFO = "info";
    public static final String LEVEL_WARNING = "warning";
    public static final String LEVEL_ERROR = "error";
    public static final String LEVEL_CRASH = "crash";

    private static final String PREFS = "napaxi_agent_provider_diagnostics";
    private static final String REPORTS = "reports";
    private static final String BREADCRUMBS = "breadcrumbs";
    private static final String LOGS = "logs";
    private static final String DETAILED_LOGGING = "detailed_logging";
    private static final String LAST_EXIT_TIMESTAMP = "last_exit_timestamp";
    private static final int MAX_REPORTS = 8;
    private static final int MAX_BREADCRUMBS = 30;
    private static final int MAX_LOGS = 300;
    private static final int MAX_LOG_STORAGE_BYTES = 512 * 1024;
    private static final int MAX_LOG_RESPONSE_BYTES = 256 * 1024;
    private static final int MAX_STACK_CHARS = 32 * 1024;
    private static final int MAX_TRACE_BYTES = 32 * 1024;
    private static final int MAX_METADATA_CHARS = 4 * 1024;
    private static final long LOG_RETENTION_MILLIS = 3L * 24L * 60L * 60L * 1000L;
    private static final Object LOCK = new Object();

    private static volatile boolean installed;

    private AgentProviderDiagnostics() {}

    /** Installs crash collection once per process and imports recent OS exits. */
    public static void install(Context context) {
        Context app = context.getApplicationContext();
        captureHistoricalExits(app);
        if (installed) return;
        synchronized (LOCK) {
            if (installed) return;
            Thread.UncaughtExceptionHandler previous =
                    Thread.getDefaultUncaughtExceptionHandler();
            Thread.setDefaultUncaughtExceptionHandler((thread, error) -> {
                try {
                    recordThrowable(app, "java_crash", error, thread, null);
                } catch (Throwable ignored) {
                    // Crash reporting must never replace the original failure.
                }
                if (previous != null) {
                    previous.uncaughtException(thread, error);
                }
            });
            installed = true;
            recordBreadcrumb(app, "lifecycle", "diagnostics_initialized");
            log(app, LEVEL_INFO, "lifecycle", "process_started",
                    "Application process started.", null, "");
        }
    }

    /**
     * Records one bounded, sanitized structured runtime event.
     *
     * <p>Debug events are ignored unless detailed logging was explicitly enabled
     * by the bound Host. Info and higher levels are recorded by default.</p>
     */
    public static void log(
            Context context,
            String level,
            String module,
            String event,
            String message,
            JSONObject metadata,
            String traceId) {
        String normalizedLevel = normalizeLevel(level);
        if (LEVEL_DEBUG.equals(normalizedLevel) && !isDetailedLoggingEnabled(context)) return;
        synchronized (LOCK) {
            try {
                JSONObject entry = new JSONObject()
                        .put("id", UUID.randomUUID().toString())
                        .put("timestamp", Instant.now().toString())
                        .put("level", normalizedLevel)
                        .put("module", sanitize(module, 100))
                        .put("event", sanitize(event, 120))
                        .put("message", sanitize(message, 2000))
                        .put("trace_id", sanitize(traceId, 160))
                        .put("thread", sanitize(Thread.currentThread().getName(), 120));
                JSONObject safeMetadata = sanitizeMetadata(metadata);
                if (safeMetadata.length() > 0) entry.put("metadata", safeMetadata);
                appendLog(context, entry);
            } catch (Exception ignored) {
                // Runtime logging is best effort and must not affect app behavior.
            }
        }
    }

    /** Convenience overload when no trace id is available. */
    public static void log(
            Context context,
            String level,
            String module,
            String event,
            String message,
            JSONObject metadata) {
        log(context, level, module, event, message, metadata, "");
    }

    /** Adds a bounded, sanitized event that can help reconstruct a failure. */
    public static void recordBreadcrumb(Context context, String category, String message) {
        synchronized (LOCK) {
            try {
                SharedPreferences prefs = preferences(context);
                JSONArray items = parseArray(prefs.getString(BREADCRUMBS, "[]"));
                items.put(new JSONObject()
                        .put("timestamp", Instant.now().toString())
                        .put("category", sanitize(category, 80))
                        .put("message", sanitize(message, 500)));
                items = tail(items, MAX_BREADCRUMBS);
                prefs.edit().putString(BREADCRUMBS, items.toString()).commit();
            } catch (Exception ignored) {
                // Breadcrumbs are best effort.
            }
        }
    }

    /** Records a caught failure, such as a Provider action handler exception. */
    public static void recordCaughtException(
            Context context, String kind, Throwable error, JSONObject metadata) {
        recordThrowable(context, kind, error, Thread.currentThread(), metadata);
    }

    /** Returns reports newest first without removing them. */
    public static JSONArray reports(Context context) {
        captureHistoricalExits(context.getApplicationContext());
        synchronized (LOCK) {
            JSONArray stored = parseArray(preferences(context).getString(REPORTS, "[]"));
            JSONArray newestFirst = new JSONArray();
            for (int index = stored.length() - 1; index >= 0; index--) {
                newestFirst.put(stored.opt(index));
            }
            return newestFirst;
        }
    }

    /** Returns recent structured logs newest first, capped for Binder transport. */
    public static JSONArray logs(Context context) {
        synchronized (LOCK) {
            SharedPreferences prefs = preferences(context);
            JSONArray stored = pruneExpiredLogs(parseArray(prefs.getString(LOGS, "[]")));
            prefs.edit().putString(LOGS, stored.toString()).commit();
            JSONArray newestFirst = new JSONArray();
            int responseBytes = 2;
            for (int index = stored.length() - 1; index >= 0; index--) {
                Object entry = stored.opt(index);
                int entryBytes = utf8Length(String.valueOf(entry)) + 1;
                if (newestFirst.length() > 0
                        && responseBytes + entryBytes > MAX_LOG_RESPONSE_BYTES) {
                    break;
                }
                newestFirst.put(entry);
                responseBytes += entryBytes;
            }
            return newestFirst;
        }
    }

    public static boolean isDetailedLoggingEnabled(Context context) {
        return preferences(context).getBoolean(DETAILED_LOGGING, false);
    }

    /** Changes debug-level collection after a trusted Host request. */
    public static void setDetailedLoggingEnabled(Context context, boolean enabled) {
        preferences(context).edit().putBoolean(DETAILED_LOGGING, enabled).commit();
        log(context, LEVEL_INFO, "diagnostics", "detailed_logging_changed",
                enabled ? "Detailed logging enabled." : "Detailed logging disabled.",
                new JSONObject(), "");
    }

    /** Removes reports acknowledged by the Host and returns the remaining list. */
    public static JSONArray acknowledge(Context context, JSONArray reportIds) {
        synchronized (LOCK) {
            JSONArray stored = parseArray(preferences(context).getString(REPORTS, "[]"));
            JSONArray remaining = new JSONArray();
            for (int index = 0; index < stored.length(); index++) {
                JSONObject report = stored.optJSONObject(index);
                if (report != null && !contains(reportIds, report.optString("id"))) {
                    remaining.put(report);
                }
            }
            preferences(context).edit().putString(REPORTS, remaining.toString()).commit();
            JSONArray newestFirst = new JSONArray();
            for (int index = remaining.length() - 1; index >= 0; index--) {
                newestFirst.put(remaining.opt(index));
            }
            return newestFirst;
        }
    }

    private static void recordThrowable(
            Context context,
            String kind,
            Throwable error,
            Thread thread,
            JSONObject metadata) {
        synchronized (LOCK) {
            try {
                StringWriter writer = new StringWriter();
                error.printStackTrace(new PrintWriter(writer));
                JSONObject safeMetadata = sanitizeMetadata(metadata);
                JSONObject report = baseReport(context, kind, System.currentTimeMillis())
                        .put("thread", sanitize(thread == null ? "" : thread.getName(), 120))
                        .put("exception_type", error.getClass().getName())
                        .put("message", sanitize(error.getMessage(), 2000))
                        .put("stack_trace", sanitize(writer.toString(), MAX_STACK_CHARS))
                        .put("breadcrumbs", breadcrumbs(context));
                if (safeMetadata.length() > 0) report.put("metadata", safeMetadata);
                appendReport(context, report);
                String level = "java_crash".equals(kind) ? LEVEL_CRASH : LEVEL_ERROR;
                String traceId = safeMetadata.optString("trace_id",
                        safeMetadata.optString("request_id", ""));
                JSONObject logMetadata = new JSONObject()
                        .put("diagnostic_report_id", report.optString("id"))
                        .put("exception_type", error.getClass().getName());
                appendLog(context, new JSONObject()
                        .put("id", UUID.randomUUID().toString())
                        .put("timestamp", Instant.now().toString())
                        .put("level", level)
                        .put("module", "runtime")
                        .put("event", sanitize(kind, 120))
                        .put("message", sanitize(error.getMessage(), 2000))
                        .put("trace_id", sanitize(traceId, 160))
                        .put("thread", sanitize(thread == null ? "" : thread.getName(), 120))
                        .put("metadata", logMetadata));
            } catch (Exception ignored) {
                // Crash reporting is best effort.
            }
        }
    }

    private static void captureHistoricalExits(Context context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return;
        synchronized (LOCK) {
            try {
                SharedPreferences prefs = preferences(context);
                long lastTimestamp = prefs.getLong(LAST_EXIT_TIMESTAMP, 0L);
                ActivityManager manager =
                        (ActivityManager) context.getSystemService(Context.ACTIVITY_SERVICE);
                if (manager == null) return;
                List<ApplicationExitInfo> exits = manager.getHistoricalProcessExitReasons(
                        context.getPackageName(), 0, 8);
                long newestTimestamp = lastTimestamp;
                for (int index = exits.size() - 1; index >= 0; index--) {
                    ApplicationExitInfo exit = exits.get(index);
                    long timestamp = exit.getTimestamp();
                    newestTimestamp = Math.max(newestTimestamp, timestamp);
                    if (timestamp <= lastTimestamp || !isDiagnosticExit(exit.getReason())) continue;
                    if (exit.getReason() == ApplicationExitInfo.REASON_CRASH
                            && hasNearbyReport(context, "java_crash", timestamp, 10_000L)) {
                        continue;
                    }
                    String kind = exitKind(exit.getReason());
                    JSONObject report = baseReport(context, kind, timestamp)
                            .put("process", sanitize(exit.getProcessName(), 200))
                            .put("reason", exit.getReason())
                            .put("description", sanitize(exit.getDescription(), 2000))
                            .put("importance", exit.getImportance())
                            .put("pss_kb", exit.getPss())
                            .put("rss_kb", exit.getRss())
                            .put("status", exit.getStatus())
                            .put("breadcrumbs", breadcrumbs(context));
                    if (exit.getReason() == ApplicationExitInfo.REASON_ANR) {
                        String trace = readTrace(exit.getTraceInputStream());
                        if (!trace.isEmpty()) report.put("stack_trace", trace);
                    }
                    appendReport(context, report);
                    appendLog(context, new JSONObject()
                            .put("id", UUID.randomUUID().toString())
                            .put("timestamp", Instant.ofEpochMilli(timestamp).toString())
                            .put("level", exitLogLevel(exit.getReason()))
                            .put("module", "runtime")
                            .put("event", kind)
                            .put("message", sanitize(exit.getDescription(), 2000))
                            .put("trace_id", "")
                            .put("thread", "")
                            .put("metadata", new JSONObject()
                                    .put("diagnostic_report_id", report.optString("id"))));
                }
                if (newestTimestamp > lastTimestamp) {
                    prefs.edit().putLong(LAST_EXIT_TIMESTAMP, newestTimestamp).commit();
                }
            } catch (Throwable ignored) {
                // OEMs may omit or restrict historical exit data.
            }
        }
    }

    private static boolean isDiagnosticExit(int reason) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return false;
        return reason == ApplicationExitInfo.REASON_ANR
                || reason == ApplicationExitInfo.REASON_CRASH
                || reason == ApplicationExitInfo.REASON_CRASH_NATIVE
                || reason == ApplicationExitInfo.REASON_LOW_MEMORY
                || reason == ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE
                || reason == ApplicationExitInfo.REASON_INITIALIZATION_FAILURE;
    }

    private static String exitKind(int reason) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            if (reason == ApplicationExitInfo.REASON_ANR) return "anr";
            if (reason == ApplicationExitInfo.REASON_CRASH_NATIVE) return "native_crash";
            if (reason == ApplicationExitInfo.REASON_LOW_MEMORY) return "low_memory";
            if (reason == ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE) {
                return "excessive_resource_usage";
            }
            if (reason == ApplicationExitInfo.REASON_INITIALIZATION_FAILURE) {
                return "initialization_failure";
            }
        }
        return "process_crash";
    }

    private static String exitLogLevel(int reason) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R
                && (reason == ApplicationExitInfo.REASON_LOW_MEMORY
                || reason == ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE)) {
            return LEVEL_WARNING;
        }
        return LEVEL_CRASH;
    }

    private static JSONObject baseReport(Context context, String kind, long timestamp)
            throws Exception {
        PackageInfo info = context.getPackageManager().getPackageInfo(context.getPackageName(), 0);
        long versionCode = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P
                ? info.getLongVersionCode()
                : info.versionCode;
        return new JSONObject()
                .put("id", UUID.randomUUID().toString())
                .put("protocol_version", 1)
                .put("kind", kind)
                .put("timestamp", Instant.ofEpochMilli(timestamp).toString())
                .put("app_package", context.getPackageName())
                .put("version_name", info.versionName == null ? "" : info.versionName)
                .put("version_code", versionCode)
                .put("sdk_int", Build.VERSION.SDK_INT)
                .put("manufacturer", sanitize(Build.MANUFACTURER, 80))
                .put("model", sanitize(Build.MODEL, 120));
    }

    private static void appendReport(Context context, JSONObject report) {
        JSONArray reports = parseArray(preferences(context).getString(REPORTS, "[]"));
        reports.put(report);
        reports = tail(reports, MAX_REPORTS);
        preferences(context).edit().putString(REPORTS, reports.toString()).commit();
    }

    private static void appendLog(Context context, JSONObject entry) {
        SharedPreferences prefs = preferences(context);
        JSONArray logs = pruneExpiredLogs(parseArray(prefs.getString(LOGS, "[]")));
        logs.put(entry);
        while (logs.length() > MAX_LOGS
                || (logs.length() > 1 && utf8Length(logs.toString()) > MAX_LOG_STORAGE_BYTES)) {
            logs.remove(0);
        }
        prefs.edit().putString(LOGS, logs.toString()).commit();
    }

    private static JSONArray pruneExpiredLogs(JSONArray logs) {
        JSONArray current = new JSONArray();
        long cutoff = System.currentTimeMillis() - LOG_RETENTION_MILLIS;
        for (int index = 0; index < logs.length(); index++) {
            JSONObject entry = logs.optJSONObject(index);
            if (entry == null) continue;
            try {
                if (Instant.parse(entry.optString("timestamp")).toEpochMilli() >= cutoff) {
                    current.put(entry);
                }
            } catch (Exception ignored) {
                // Drop malformed records rather than retaining them indefinitely.
            }
        }
        return current;
    }

    private static boolean hasNearbyReport(
            Context context, String kind, long timestamp, long toleranceMillis) {
        JSONArray reports = parseArray(preferences(context).getString(REPORTS, "[]"));
        for (int index = reports.length() - 1; index >= 0; index--) {
            JSONObject report = reports.optJSONObject(index);
            if (report == null || !kind.equals(report.optString("kind"))) continue;
            try {
                long reportTimestamp = Instant.parse(report.optString("timestamp")).toEpochMilli();
                if (Math.abs(timestamp - reportTimestamp) <= toleranceMillis) return true;
                if (reportTimestamp < timestamp - toleranceMillis) return false;
            } catch (Exception ignored) {
                // Ignore malformed older records and keep scanning.
            }
        }
        return false;
    }

    private static JSONArray breadcrumbs(Context context) {
        return parseArray(preferences(context).getString(BREADCRUMBS, "[]"));
    }

    private static SharedPreferences preferences(Context context) {
        return context.getApplicationContext().getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    private static JSONObject sanitizeMetadata(JSONObject metadata) {
        if (metadata == null || metadata.length() == 0) return new JSONObject();
        JSONObject sanitized = sanitizeObject(metadata, 0);
        String encoded = sanitized.toString();
        if (encoded.length() <= MAX_METADATA_CHARS) return sanitized;
        try {
            return new JSONObject().put("summary", sanitize(encoded, MAX_METADATA_CHARS));
        } catch (Exception ignored) {
            return new JSONObject();
        }
    }

    private static JSONObject sanitizeObject(JSONObject source, int depth) {
        JSONObject result = new JSONObject();
        if (source == null || depth > 2) return result;
        Iterator<String> keys = source.keys();
        int count = 0;
        while (keys.hasNext() && count < 30) {
            String key = keys.next();
            Object value = source.opt(key);
            try {
                result.put(sanitize(key, 100), sanitizeValue(key, value, depth + 1));
                count++;
            } catch (Exception ignored) {
                // Skip values that cannot be represented safely.
            }
        }
        return result;
    }

    private static Object sanitizeValue(String key, Object value, int depth) {
        if (value == null || value == JSONObject.NULL) return JSONObject.NULL;
        if (isSensitiveKey(key)) return "[redacted]";
        if (value instanceof JSONObject) return sanitizeObject((JSONObject) value, depth);
        if (value instanceof JSONArray) {
            JSONArray result = new JSONArray();
            JSONArray source = (JSONArray) value;
            for (int index = 0; index < Math.min(source.length(), 20); index++) {
                result.put(sanitizeValue(key, source.opt(index), depth + 1));
            }
            return result;
        }
        if (value instanceof Number || value instanceof Boolean) return value;
        return sanitize(String.valueOf(value), 1000);
    }

    private static boolean isSensitiveKey(String key) {
        String normalized = key == null ? "" : key.toLowerCase(Locale.ROOT);
        return normalized.contains("authorization")
                || normalized.contains("password")
                || normalized.contains("passwd")
                || normalized.contains("token")
                || normalized.contains("secret")
                || normalized.contains("cookie")
                || normalized.contains("phone")
                || normalized.contains("mobile");
    }

    private static String normalizeLevel(String level) {
        String normalized = level == null ? "" : level.trim().toLowerCase(Locale.ROOT);
        if (LEVEL_DEBUG.equals(normalized)
                || LEVEL_INFO.equals(normalized)
                || LEVEL_WARNING.equals(normalized)
                || LEVEL_ERROR.equals(normalized)
                || LEVEL_CRASH.equals(normalized)) {
            return normalized;
        }
        return LEVEL_INFO;
    }

    private static JSONArray parseArray(String raw) {
        try {
            return new JSONArray(raw == null ? "[]" : raw);
        } catch (Exception ignored) {
            return new JSONArray();
        }
    }

    private static JSONArray tail(JSONArray source, int limit) {
        JSONArray result = new JSONArray();
        int start = Math.max(0, source.length() - limit);
        for (int index = start; index < source.length(); index++) {
            result.put(source.opt(index));
        }
        return result;
    }

    private static boolean contains(JSONArray values, String expected) {
        for (int index = 0; index < values.length(); index++) {
            if (expected.equals(values.optString(index))) return true;
        }
        return false;
    }

    private static String readTrace(InputStream input) {
        if (input == null) return "";
        try (InputStream source = input; ByteArrayOutputStream output = new ByteArrayOutputStream()) {
            byte[] buffer = new byte[4096];
            int remaining = MAX_TRACE_BYTES;
            while (remaining > 0) {
                int read = source.read(buffer, 0, Math.min(buffer.length, remaining));
                if (read < 0) break;
                output.write(buffer, 0, read);
                remaining -= read;
            }
            return sanitize(output.toString("UTF-8"), MAX_STACK_CHARS);
        } catch (Exception ignored) {
            return "";
        }
    }

    private static int utf8Length(String value) {
        return value.getBytes(StandardCharsets.UTF_8).length;
    }

    private static String sanitize(String value, int maxChars) {
        if (value == null) return "";
        String sanitized = value
                .replaceAll("(?i)(authorization|password|passwd|token|secret|cookie)\\s*[:=]\\s*[^\\s,;]+", "$1=[redacted]")
                .replaceAll("(?<!\\d)(?:\\+?86[- ]?)?1[3-9]\\d{9}(?!\\d)", "[redacted-phone]")
                .replaceAll("[\\u0000-\\u0008\\u000B\\u000C\\u000E-\\u001F]", "");
        return sanitized.length() <= maxChars
                ? sanitized
                : sanitized.substring(0, maxChars) + "\n[truncated]";
    }
}
