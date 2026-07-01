plugins {
    id("com.android.library") version "8.11.1"
    id("org.jetbrains.kotlin.android") version "2.2.20"
}

android {
    namespace = "com.napaxi.android"
    compileSdk = 35

    defaultConfig {
        minSdk = 26
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    sourceSets {
        getByName("main") {
            manifest.srcFile("src/main/AndroidManifest.xml")
            java.srcDirs("src/main/kotlin")
            assets.srcDirs("../flutter/android/assets")
            jniLibs.srcDirs("../flutter/android/jniLibs")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    testOptions {
        unitTests.all {
            it.jvmArgs("-Dnet.bytebuddy.experimental=true")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

val flutterAndroidDir = file("../flutter/android")
val repoRoot = file("../..")

tasks.register("verifySdkNativeInputs") {
    doLast {
        val requiredFiles = listOf(
            file("${flutterAndroidDir}/assets/alpine-rootfs.bin"),
            file("${flutterAndroidDir}/assets/libtalloc.so.2"),
            file("${flutterAndroidDir}/jniLibs/arm64-v8a/libproot.so"),
            file("${flutterAndroidDir}/jniLibs/arm64-v8a/libldmusl.so"),
            file("${flutterAndroidDir}/jniLibs/arm64-v8a/libloader.so"),
        )
        requiredFiles.forEach { requiredFile ->
            if (!requiredFile.exists()) {
                throw GradleException("Missing Napaxi Android runtime asset: ${requiredFile}")
            }
        }
    }
}

tasks.register<Exec>("buildRust") {
    val soFile = file("${flutterAndroidDir}/jniLibs/arm64-v8a/libnapaxi_api_bridge.so")
    onlyIf { !soFile.exists() }
    dependsOn("verifySdkNativeInputs")
    workingDir = repoRoot
    commandLine("${repoRoot}/tools/scripts/build.sh", "fast", "android")
}

tasks.register("verifySdkNativeOutputs") {
    dependsOn("buildRust")
    doLast {
        val soFile = file("${flutterAndroidDir}/jniLibs/arm64-v8a/libnapaxi_api_bridge.so")
        if (!soFile.exists()) {
            throw GradleException("Missing Napaxi Android JNI library: ${soFile}")
        }
    }
}

tasks.named("preBuild") {
    dependsOn("verifySdkNativeOutputs")
}

dependencies {
    api("agent.provider:android_agent_provider:0.1.0")
    api("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
}
