pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "napaxi_android_integration"

include(":app")

includeBuild("../../../packages/agent_provider/android") {
    name = "napaxi_android_agent_provider"
    dependencySubstitution {
        substitute(module("agent.provider:android_agent_provider")).using(project(":"))
    }
}

includeBuild("../../../packages/android") {
    name = "napaxi_android_sdk"
    dependencySubstitution {
        substitute(module("com.napaxi:napaxi_android_sdk")).using(project(":"))
    }
}
