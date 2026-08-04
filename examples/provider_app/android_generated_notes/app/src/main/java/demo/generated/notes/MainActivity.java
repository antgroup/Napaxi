package demo.generated.notes;

import android.app.Activity;
import android.graphics.Color;
import android.os.Bundle;
import android.view.Gravity;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;

import org.json.JSONArray;
import org.json.JSONObject;

public final class MainActivity extends Activity {
    private EditText input;
    private TextView notes;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(40, 48, 40, 40);
        root.setBackgroundColor(Color.WHITE);

        TextView title = new TextView(this);
        title.setText("Generated Notes");
        title.setTextSize(28);
        title.setTextColor(Color.rgb(30, 40, 58));
        root.addView(title);

        input = new EditText(this);
        input.setHint("Write a note");
        root.addView(input, new LinearLayout.LayoutParams(-1, -2));

        Button save = new Button(this);
        save.setText("Save note");
        save.setGravity(Gravity.CENTER);
        save.setOnClickListener(view -> createNote());
        root.addView(save, new LinearLayout.LayoutParams(-1, -2));

        notes = new TextView(this);
        notes.setTextSize(17);
        notes.setTextColor(Color.rgb(50, 60, 75));
        root.addView(notes, new LinearLayout.LayoutParams(-1, 0, 1));

        setContentView(root);
        refresh();
    }

    private void createNote() {
        String content = input.getText().toString().trim();
        if (content.isEmpty()) return;
        try {
            NoteStore.create(this, "", content);
            input.setText("");
            refresh();
        } catch (Exception error) {
            notes.setText(error.getMessage());
        }
    }

    private void refresh() {
        try {
            JSONArray values = NoteStore.list(this, "");
            StringBuilder text = new StringBuilder();
            for (int index = 0; index < values.length(); index++) {
                JSONObject note = values.getJSONObject(index);
                text.append("\n• ").append(note.optString("content"));
            }
            notes.setText(text.length() == 0 ? "No notes yet." : text.toString());
        } catch (Exception error) {
            notes.setText(error.getMessage());
        }
    }
}
