package com.napaxi.android

import org.json.JSONArray
import org.junit.Assert.assertEquals
import org.junit.Test
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths

// Adapter-parity guard: the Android platform-tool name set
// (AndroidPlatformToolExecutor.TOOL_NAMES / platformToolNames) must agree with
// the shared cross-adapter fixture, which is generated from and pinned to Rust
// core (crates/core/src/platform_capabilities.rs) by the Rust test
// `descriptors_match_shared_contract_fixture`. This stops the Android copy of
// the tool-name list from silently drifting from core.
//
// Android carries tool names only (execution is a switch; it does not copy
// descriptions or parameter schemas), so this guard checks the name set only.
// The iOS guard (PlatformToolContractTests.swift) additionally pins
// descriptions, and core pins the full descriptor set.
//
// contract-fixture: fixtures/platform_tools/tool_descriptors.json
class PlatformToolContractTest {
    @Test
    fun platformToolNamesMatchSharedContract() {
        val fixtureNames = fixtureToolNames()
        assertEquals(15, fixtureNames.size)
        assertEquals(fixtureNames, AndroidPlatformToolExecutor.platformToolNames)
    }

    private fun fixtureToolNames(): Set<String> {
        val root = repoRoot()
        val text = String(
            Files.readAllBytes(
                root.resolve("packages/api_contract/fixtures/platform_tools/tool_descriptors.json"),
            ),
            Charsets.UTF_8,
        )
        val array = JSONArray(text)
        return (0 until array.length())
            .map { array.getJSONObject(it).getString("name") }
            .toSet()
    }

    private fun repoRoot(): Path {
        val cwd = Paths.get("").toAbsolutePath()
        return generateSequence(cwd) { it.parent }
            .firstOrNull { Files.exists(it.resolve("packages/api_bridge/android_jni.rs")) }
            ?: error("Could not locate Napaxi repository root from $cwd")
    }
}
