plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "demo.smarthome.provider"
    compileSdk = 35

    defaultConfig {
        applicationId = "demo.smarthome.provider"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    implementation("agent.provider:android_agent_provider:0.1.0")
    implementation("com.napaxi:android:0.1.0")
    // kotlinx-coroutines-core is exposed transitively (api) by com.napaxi:android;
    // the android artifact adds Dispatchers.Main for collecting the SDK event flow.
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
}
