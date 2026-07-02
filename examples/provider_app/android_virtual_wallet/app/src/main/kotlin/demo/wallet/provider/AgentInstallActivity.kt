package demo.wallet.provider

import android.app.Activity
import android.os.Bundle
import agent.provider.sdk.AgentProviderSecurity
import agent.provider.sdk.TrustedHostStore

class AgentInstallActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setResult(
            RESULT_OK,
            AgentProviderSecurity.handleTrustedInstallRequest(
                this,
                WalletPackage.packageDef,
                TrustedHostStore(this, WalletPackage.PROVIDER_ID),
            ),
        )
        finish()
    }
}
