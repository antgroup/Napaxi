package agent.provider.sdk

object AgentProviderContract {
    const val ACTION_INSTALL_AGENT = "agent.provider.action.INSTALL_AGENT"
    const val ACTION_HANDLE_PROPOSAL = "agent.provider.action.HANDLE_PROPOSAL"
    const val ACTION_RESULT = "agent.provider.action.RESULT"
    const val ACTION_HOST_INSTALL_PROVIDER_AGENT = "agent.host.action.INSTALL_PROVIDER_AGENT"
    const val ACTION_HOST_TRIGGER_AGENT = "agent.host.action.TRIGGER_AGENT"

    const val EXTRA_INSTALL_REQUEST_JSON = "agent.provider.extra.INSTALL_REQUEST_JSON"
    const val EXTRA_INSTALL_RESULT_JSON = "agent.provider.extra.INSTALL_RESULT_JSON"
    const val EXTRA_TRIGGER_REQUEST_JSON = "agent.provider.extra.TRIGGER_REQUEST_JSON"
    const val EXTRA_PROPOSAL_JSON = "agent.provider.extra.PROPOSAL_JSON"
    const val EXTRA_PACKAGE_JSON = "agent.provider.extra.PACKAGE_JSON"
    const val EXTRA_ACTION_JSON = "agent.provider.extra.ACTION_JSON"
    const val EXTRA_RESULT_JSON = "agent.provider.extra.RESULT_JSON"
}

object ActionRisk {
    const val LOW = "low"
    const val MEDIUM = "medium"
    const val HIGH = "high"
    const val CRITICAL = "critical"
}

object ConfirmationPolicy {
    const val NONE = "none"
    const val PROVIDER_REQUIRED = "provider_required"
}

object ExecutionMode {
    const val APP_HANDOFF = "app_handoff"
    const val BACKEND_API = "backend_api"
    const val ANDROID_ACTIVITY_RESULT = "android_activity_result"
}

object ActionResultStatus {
    const val SUCCEEDED = "succeeded"
    const val FAILED = "failed"
    const val CANCELED = "canceled"
}

object AgentInstallStatus {
    const val SUCCEEDED = "succeeded"
    const val FAILED = "failed"
    const val CANCELED = "canceled"
}
