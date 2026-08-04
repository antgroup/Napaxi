package demo.generated.notes;

import android.content.Context;
import android.content.SharedPreferences;

import org.json.JSONArray;
import org.json.JSONObject;

import java.time.Instant;
import java.util.UUID;

final class NoteStore {
    private static final String PREFS = "generated_notes";
    private static final String NOTES = "notes";

    private NoteStore() {}

    static synchronized JSONObject create(Context context, String title, String content)
            throws Exception {
        JSONArray notes = load(context);
        String now = Instant.now().toString();
        JSONObject note = new JSONObject()
                .put("id", UUID.randomUUID().toString())
                .put("title", title == null ? "" : title)
                .put("content", content)
                .put("created_at", now)
                .put("updated_at", now);
        notes.put(note);
        save(context, notes);
        return copy(note);
    }

    static synchronized JSONArray list(Context context, String query) throws Exception {
        JSONArray notes = load(context);
        JSONArray result = new JSONArray();
        String needle = query == null ? "" : query.trim().toLowerCase();
        for (int index = notes.length() - 1; index >= 0; index--) {
            JSONObject note = notes.getJSONObject(index);
            if (needle.isEmpty()
                    || note.optString("title").toLowerCase().contains(needle)
                    || note.optString("content").toLowerCase().contains(needle)) {
                result.put(copy(note));
            }
        }
        return result;
    }

    static synchronized JSONObject get(Context context, String id) throws Exception {
        JSONArray notes = load(context);
        for (int index = 0; index < notes.length(); index++) {
            JSONObject note = notes.getJSONObject(index);
            if (id.equals(note.optString("id"))) return copy(note);
        }
        return null;
    }

    static synchronized JSONObject update(
            Context context, String id, String title, String content) throws Exception {
        JSONArray notes = load(context);
        for (int index = 0; index < notes.length(); index++) {
            JSONObject note = notes.getJSONObject(index);
            if (!id.equals(note.optString("id"))) continue;
            if (title != null) note.put("title", title);
            if (content != null) note.put("content", content);
            note.put("updated_at", Instant.now().toString());
            save(context, notes);
            return copy(note);
        }
        return null;
    }

    static synchronized boolean delete(Context context, String id) throws Exception {
        JSONArray notes = load(context);
        for (int index = 0; index < notes.length(); index++) {
            if (!id.equals(notes.getJSONObject(index).optString("id"))) continue;
            notes.remove(index);
            save(context, notes);
            return true;
        }
        return false;
    }

    private static JSONArray load(Context context) throws Exception {
        String raw = prefs(context).getString(NOTES, "[]");
        return new JSONArray(raw == null ? "[]" : raw);
    }

    private static void save(Context context, JSONArray notes) {
        prefs(context).edit().putString(NOTES, notes.toString()).apply();
    }

    private static SharedPreferences prefs(Context context) {
        return context.getApplicationContext().getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    private static JSONObject copy(JSONObject value) throws Exception {
        return new JSONObject(value.toString());
    }
}
