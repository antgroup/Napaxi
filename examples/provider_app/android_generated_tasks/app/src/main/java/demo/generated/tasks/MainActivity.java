package demo.generated.tasks;

import android.app.Activity;
import android.os.Bundle;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;

import org.json.JSONArray;

public final class MainActivity extends Activity {
    private LinearLayout taskList;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(32, 32, 32, 32);

        TextView title = new TextView(this);
        title.setText("Generated Tasks");
        title.setTextSize(26);
        root.addView(title);

        EditText input = new EditText(this);
        input.setHint("Task title");
        root.addView(input, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT));

        Button add = new Button(this);
        add.setText("Add task");
        root.addView(add);

        taskList = new LinearLayout(this);
        taskList.setOrientation(LinearLayout.VERTICAL);
        root.addView(taskList);
        add.setOnClickListener(view -> {
            String value = input.getText().toString().trim();
            if (value.isEmpty()) return;
            try {
                TaskStore.add(this, value);
                input.setText("");
                refresh();
            } catch (Exception error) {
                input.setError(error.getMessage());
            }
        });
        setContentView(root);
        refresh();
    }

    private void refresh() {
        taskList.removeAllViews();
        try {
            JSONArray tasks = TaskStore.list(this, null);
            for (int index = 0; index < tasks.length(); index++) {
                TextView row = new TextView(this);
                boolean completed = tasks.getJSONObject(index).optBoolean("completed");
                row.setText((completed ? "✓ " : "○ ")
                        + tasks.getJSONObject(index).optString("title"));
                row.setTextSize(18);
                row.setPadding(0, 16, 0, 16);
                taskList.addView(row);
            }
        } catch (Exception error) {
            TextView row = new TextView(this);
            row.setText("Unable to load tasks: " + error.getMessage());
            taskList.addView(row);
        }
    }
}
