package demo.smartdesk.provider

import android.app.Activity
import android.os.Bundle
import agent.provider.sdk.AgentProviderSecurity
import agent.provider.sdk.TrustedHostStore

class AgentInstallActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        AppContext.context = applicationContext
        setResult(
            RESULT_OK,
            AgentProviderSecurity.handleTrustedInstallRequest(
                this,
                SmartDeskPackage.packageDef,
                TrustedHostStore(this, SmartDeskPackage.PROVIDER_ID),
            ),
        )
        finish()
    }
}
