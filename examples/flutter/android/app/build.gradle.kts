plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android Gradle plugin.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.napa.app.test"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.napa.app.test"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    buildTypes {
        release {
            // The demo keeps debug signing for local release runs; downstream
            // apps should provide their own release signing config.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

// Built-in Kotlin migration: the Kotlin JVM target now lives in the top-level
// kotlin{} extension instead of android{ kotlinOptions{} }, and kotlin-android
// was dropped from the plugins block. On AGP 8.x Kotlin is still supplied by KGP
// applied transitively via the Flutter Gradle plugin; android.builtInKotlin only
// takes effect on AGP 9.0+, so the gradle.properties flags stay false for now.
kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
