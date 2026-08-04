package agent.provider.lite;

import android.app.Activity;
import android.os.Bundle;

/** Default trusted install entry point for generated Agent App providers. */
public final class AgentProviderInstallActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setResult(RESULT_OK, AgentProviderLite.handleTrustedInstall(this));
        finish();
    }
}
