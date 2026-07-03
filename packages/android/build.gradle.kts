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

fun Project.resolveWindowsBashPath(): String {
    val candidates = linkedSetOf<String>()

    fun addCandidate(path: String?) {
        if (!path.isNullOrBlank()) {
            candidates += path.trim()
        }
    }

    fun collectWhereResults(executable: String) {
        try {
            val output = java.io.ByteArrayOutputStream()
            exec {
                commandLine("where.exe", executable)
                standardOutput = output
                errorOutput = java.io.ByteArrayOutputStream()
                isIgnoreExitValue = true
            }
            output.toString(Charsets.UTF_8.name())
                .lineSequence()
                .map { it.trim() }
                .filter { it.isNotEmpty() }
                .forEach(::addCandidate)
        } catch (_: Exception) {
        }
    }

    addCandidate(System.getenv("NAPAXI_BASH"))
    collectWhereResults("bash")

    try {
        val output = java.io.ByteArrayOutputStream()
        exec {
            commandLine("where.exe", "git")
            standardOutput = output
            errorOutput = java.io.ByteArrayOutputStream()
            isIgnoreExitValue = true
        }
        output.toString(Charsets.UTF_8.name())
            .lineSequence()
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .forEach { gitPath ->
                val gitExe = file(gitPath)
                val gitRoot = gitExe.parentFile?.parentFile
                if (gitRoot != null) {
                    addCandidate(java.io.File(gitRoot, "bin/bash.exe").path)
                    addCandidate(java.io.File(gitRoot, "usr/bin/bash.exe").path)
                }
            }
    } catch (_: Exception) {
    }

    listOf("ProgramFiles", "ProgramFiles(x86)")
        .mapNotNull { System.getenv(it) }
        .filter { it.isNotBlank() }
        .forEach { root ->
            addCandidate(java.io.File(root, "Git/bin/bash.exe").path)
            addCandidate(java.io.File(root, "Git/usr/bin/bash.exe").path)
        }

    System.getenv("LocalAppData")
        ?.takeIf { it.isNotBlank() }
        ?.let { localAppData ->
            addCandidate(java.io.File(localAppData, "Programs/Git/bin/bash.exe").path)
            addCandidate(java.io.File(localAppData, "Programs/Git/usr/bin/bash.exe").path)
        }

    val windowsBash = file("${System.getenv("WINDIR") ?: "C:/Windows"}/System32/bash.exe")
    val windowsBashPath = windowsBash.takeIf { it.exists() }?.canonicalPath

    val bashPath = candidates
        .map { file(it) }
        .firstOrNull { candidate ->
            candidate.exists() &&
                candidate.name.equals("bash.exe", ignoreCase = true) &&
                (windowsBashPath == null || !candidate.canonicalPath.equals(windowsBashPath, ignoreCase = true))
        }

    return bashPath?.absolutePath
        ?: throw GradleException("No usable Git Bash executable found for tools/scripts/build.sh. Set NAPAXI_BASH to your Git Bash path.")
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
    val buildScript = file("${repoRoot}/tools/scripts/build.sh")
    if (org.gradle.internal.os.OperatingSystem.current().isWindows) {
        doFirst {
            commandLine(resolveWindowsBashPath(), buildScript.absolutePath, "fast", "android")
        }
    } else {
        commandLine(buildScript.absolutePath, "fast", "android")
    }
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
