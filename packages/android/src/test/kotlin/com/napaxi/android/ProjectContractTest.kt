package com.napaxi.android

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.File

// contract-fixture: fixtures/project/project_record.json
// contract-fixture: fixtures/project/session_placement.json
class ProjectContractTest {
    @Test
    fun projectFixturesDecodeThroughPublicModels() {
        val project = NapaxiProject.fromJsonObject(fixture("project_record.json"))
        val placement = NapaxiSessionPlacement.fromJsonObject(fixture("session_placement.json"))

        assertEquals("project-release", project.id)
        assertEquals(project.id, placement.projectId)
        assertEquals(project.defaultWorkspaceId, placement.runtimeWorkspaceId)
        assertEquals(4L, placement.revision)
    }

    // Use java.io.File rather than java.nio.file.Files: Files.readString /
    // Files.exists were Unresolved on the Android unit-test classpath (android.jar
    // stub lacks them), while File.readText / File.exists are available on every
    // API level. Functionally equivalent fixture read.
    private fun fixture(name: String): JSONObject = JSONObject(
        File(repoRoot(), "packages/api_contract/fixtures/project/$name").readText(Charsets.UTF_8),
    )

    private fun repoRoot(): File {
        var cwd: File = File(".").absoluteFile
        while (cwd != null) {
            if (File(cwd, "packages/api_bridge/android_jni.rs").exists()) return cwd
            cwd = cwd.parentFile
        }
        error("Could not locate Napaxi repository root from ${File(".").absoluteFile}")
    }
}
