package agent.provider.lite;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.net.Uri;

/** Initializes diagnostics before the generated app's launcher Activity runs. */
public final class AgentProviderDiagnosticsInitializer extends ContentProvider {
    @Override
    public boolean onCreate() {
        if (getContext() != null) {
            AgentProviderDiagnostics.install(getContext());
        }
        return true;
    }

    @Override public Cursor query(Uri uri, String[] projection, String selection,
            String[] selectionArgs, String sortOrder) { return null; }
    @Override public String getType(Uri uri) { return null; }
    @Override public Uri insert(Uri uri, ContentValues values) { return null; }
    @Override public int delete(Uri uri, String selection, String[] selectionArgs) { return 0; }
    @Override public int update(Uri uri, ContentValues values, String selection,
            String[] selectionArgs) { return 0; }
}
