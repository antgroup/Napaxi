package demo.generated.tasks;

import android.content.Context;
import android.content.SharedPreferences;

import org.json.JSONArray;
import org.json.JSONObject;

import java.time.Instant;
import java.util.UUID;

final class TaskStore {
    private static final String PREFS = "generated_tasks";
    private static final String TASKS = "tasks";

    private TaskStore() {}

    static JSONObject add(Context context, String title) throws Exception {
        JSONArray tasks = read(context);
        JSONObject task = new JSONObject()
                .put("id", UUID.randomUUID().toString())
                .put("title", title)
                .put("completed", false)
                .put("created_at", Instant.now().toString());
        tasks.put(task);
        write(context, tasks);
        return task;
    }

    static JSONArray list(Context context, Boolean completed) throws Exception {
        JSONArray tasks = read(context);
        if (completed == null) return tasks;
        JSONArray filtered = new JSONArray();
        for (int index = 0; index < tasks.length(); index++) {
            JSONObject task = tasks.getJSONObject(index);
            if (task.optBoolean("completed") == completed) filtered.put(task);
        }
        return filtered;
    }

    static JSONObject complete(Context context, String id) throws Exception {
        JSONArray tasks = read(context);
        JSONObject found = null;
        for (int index = 0; index < tasks.length(); index++) {
            JSONObject task = tasks.getJSONObject(index);
            if (id.equals(task.optString("id"))) {
                task.put("completed", true).put("completed_at", Instant.now().toString());
                found = task;
                break;
            }
        }
        if (found != null) write(context, tasks);
        return found;
    }

    static boolean delete(Context context, String id) throws Exception {
        JSONArray tasks = read(context);
        JSONArray kept = new JSONArray();
        boolean deleted = false;
        for (int index = 0; index < tasks.length(); index++) {
            JSONObject task = tasks.getJSONObject(index);
            if (id.equals(task.optString("id"))) deleted = true;
            else kept.put(task);
        }
        if (deleted) write(context, kept);
        return deleted;
    }

    private static JSONArray read(Context context) {
        String raw = preferences(context).getString(TASKS, "[]");
        try {
            return new JSONArray(raw == null ? "[]" : raw);
        } catch (Exception ignored) {
            return new JSONArray();
        }
    }

    private static void write(Context context, JSONArray tasks) {
        if (!preferences(context).edit().putString(TASKS, tasks.toString()).commit()) {
            throw new IllegalStateException("task_store_write_failed");
        }
    }

    private static SharedPreferences preferences(Context context) {
        return context.getApplicationContext()
                .getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }
}
