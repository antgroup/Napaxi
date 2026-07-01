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

rootProject.name = "napaxi_android_sdk"

includeBuild("../agent_provider/android") {
    dependencySubstitution {
        substitute(module("agent.provider:android_agent_provider")).using(project(":"))
    }
}
