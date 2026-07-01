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

rootProject.name = "android_smart_desk_provider"

include(":app")

includeBuild("../../../packages/agent_provider/android") {
    dependencySubstitution {
        substitute(module("agent.provider:android_agent_provider")).using(project(":"))
    }
}
