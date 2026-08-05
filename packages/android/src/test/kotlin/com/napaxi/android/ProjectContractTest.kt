package com.napaxi.android

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths

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

    private fun fixture(name: String): JSONObject = JSONObject(
        Files.readString(repoRoot().resolve("packages/api_contract/fixtures/project/$name")),
    )

    private fun repoRoot(): Path {
        val cwd = Paths.get("").toAbsolutePath()
        return generateSequence(cwd) { it.parent }
            .firstOrNull { Files.exists(it.resolve("packages/api_bridge/android_jni.rs")) }
            ?: error("Could not locate Napaxi repository root from $cwd")
    }
}
