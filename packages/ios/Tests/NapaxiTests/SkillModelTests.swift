import XCTest
@testable import Napaxi

final class SkillModelTests: XCTestCase {
    func testSkillFacadeAliasesMirrorFlutterAPISurface() {
        let unpin: (NapaxiSkillAPI, String) throws -> String = { api, skillName in
            try api.unpin(skillName: skillName)
        }
        let unpinJSON: (NapaxiSkillAPI, String) throws -> NapaxiJSONValue = { api, skillName in
            try api.unpinJSON(skillName: skillName)
        }
        let runConsolidationReview: (NapaxiSkillAPI, String, NapaxiConfig, Bool) throws -> NapaxiSkillConsolidationReviewResult = { api, agentId, config, dryRun in
            try api.runConsolidationReview(agentId: agentId, config: config, dryRun: dryRun)
        }
        let runConsolidationReviewJSON: (NapaxiSkillAPI, String, String, Bool) throws -> NapaxiJSONValue = { api, agentId, configJSON, dryRun in
            try api.runConsolidationReviewJSON(agentId: agentId, configJSON: configJSON, dryRun: dryRun)
        }
        let sources: (NapaxiSkillAPI, String) throws -> NapaxiSkillSourceReport = { api, agentId in
            try api.sources(agentId: agentId)
        }
        let snapshots: (NapaxiSkillAPI, String, Int, Int) throws -> NapaxiSkillSnapshotList = { api, agentId, limit, offset in
            try api.snapshots(agentId: agentId, limit: limit, offset: offset)
        }
        let secretRequirements: (NapaxiSkillAPI, String, String?) throws -> NapaxiSkillSecretRequirementReport = { api, agentId, skillName in
            try api.secretRequirements(agentId: agentId, skillName: skillName)
        }
        let remediationRuns: (NapaxiSkillAPI, String, String?, Int, Int) throws -> NapaxiSkillRemediationRunList = { api, agentId, skillName, limit, offset in
            try api.remediationRuns(agentId: agentId, skillName: skillName, limit: limit, offset: offset)
        }

        XCTAssertNotNil(unpin)
        XCTAssertNotNil(unpinJSON)
        XCTAssertNotNil(runConsolidationReview)
        XCTAssertNotNil(runConsolidationReviewJSON)
        XCTAssertNotNil(sources)
        XCTAssertNotNil(snapshots)
        XCTAssertNotNil(secretRequirements)
        XCTAssertNotNil(remediationRuns)
    }

    func testSkillFacadePositionalOverloadsMirrorFlutterAPISurface() {
        let recordSourceChanged: (NapaxiSkillAPI, String, String) throws -> NapaxiSkillRefreshResult = { api, sourceId, agentId in
            try api.recordSourceChanged(sourceId, agentId: agentId)
        }
        let getStatus: (NapaxiSkillAPI, String, String) throws -> NapaxiSkillStatusEntry? = { api, skillName, agentId in
            try api.getStatus(skillName, agentId: agentId)
        }
        let setEnabled: (NapaxiSkillAPI, String, String, Bool) throws -> String = { api, skillName, agentId, enabled in
            try api.setEnabled(skillName, agentId: agentId, enabled: enabled)
        }
        let updateConfig: (NapaxiSkillAPI, String, [String: NapaxiJSONValue], String) throws -> String = { api, skillKey, patch, agentId in
            try api.updateConfig(skillKey, patch, agentId: agentId)
        }
        let remediationActions: (NapaxiSkillAPI, String, String) throws -> [NapaxiSkillRemediationAction] = { api, skillName, agentId in
            try api.remediationActions(skillName, agentId: agentId)
        }
        let recordSecretAvailability: (NapaxiSkillAPI, String, String, String, Bool, String) throws -> NapaxiSkillStatusReport = { api, skillName, key, agentId, available, source in
            try api.recordSecretAvailability(skillName, key, agentId: agentId, available: available, source: source)
        }
        let requestRemediation: (NapaxiSkillAPI, String, String, String) throws -> NapaxiSkillRemediationRun = { api, skillName, actionId, agentId in
            try api.requestRemediation(skillName, actionId, agentId: agentId)
        }
        let updateRemediationRun: (NapaxiSkillAPI, String, String, String, [String: NapaxiJSONValue]?) throws -> NapaxiSkillRemediationRun = { api, runId, status, agentId, result in
            try api.updateRemediationRun(runId, status, agentId: agentId, result: result)
        }
        let recordRequirementResolution: (NapaxiSkillAPI, String, String, [String: NapaxiJSONValue], String) throws -> String = { api, skillName, actionId, result, agentId in
            try api.recordRequirementResolution(skillName, actionId, result, agentId: agentId)
        }
        let installContent: (NapaxiSkillAPI, String, String) throws -> NapaxiSkillInstallResult = { api, skillContent, agentId in
            try api.install(skillContent, agentId: agentId)
        }
        let installInput: (NapaxiSkillAPI, NapaxiSkillInstallInput, String) throws -> NapaxiSkillInstallResult = { api, input, agentId in
            try api.install(input, agentId: agentId)
        }
        let remove: (NapaxiSkillAPI, String, String) throws -> Bool = { api, skillName, agentId in
            try api.remove(skillName, agentId: agentId)
        }
        let get: (NapaxiSkillAPI, String, String) throws -> NapaxiSkillInfo? = { api, skillName, agentId in
            try api.get(skillName, agentId: agentId)
        }
        let pin: (NapaxiSkillAPI, String, String) throws -> String = { api, skillName, agentId in
            try api.pin(skillName, agentId: agentId)
        }
        let unpin: (NapaxiSkillAPI, String, String) throws -> String = { api, skillName, agentId in
            try api.unpin(skillName, agentId: agentId)
        }
        let archive: (NapaxiSkillAPI, String, String) throws -> String = { api, skillName, agentId in
            try api.archive(skillName, agentId: agentId)
        }
        let restore: (NapaxiSkillAPI, String, String) throws -> String = { api, skillName, agentId in
            try api.restore(skillName, agentId: agentId)
        }
        let readSupportFile: (NapaxiSkillAPI, String, String, String) throws -> NapaxiSkillSupportFileReadResult = { api, skillName, filePath, agentId in
            try api.readSupportFile(skillName, filePath, agentId: agentId)
        }
        let searchCatalog: (NapaxiSkillAPI, String) throws -> NapaxiCatalogSearchResult = { api, query in
            try api.searchCatalog(query)
        }
        let getCatalogSkill: (NapaxiSkillAPI, String) throws -> NapaxiCatalogSkillInfo = { api, slug in
            try api.getCatalogSkill(slug)
        }
        let installFromCatalog: (NapaxiSkillAPI, String, String) throws -> NapaxiSkillInstallResult = { api, slug, agentId in
            try api.installFromCatalog(slug, agentId: agentId)
        }

        XCTAssertNotNil(recordSourceChanged)
        XCTAssertNotNil(getStatus)
        XCTAssertNotNil(setEnabled)
        XCTAssertNotNil(updateConfig)
        XCTAssertNotNil(remediationActions)
        XCTAssertNotNil(recordSecretAvailability)
        XCTAssertNotNil(requestRemediation)
        XCTAssertNotNil(updateRemediationRun)
        XCTAssertNotNil(recordRequirementResolution)
        XCTAssertNotNil(installContent)
        XCTAssertNotNil(installInput)
        XCTAssertNotNil(remove)
        XCTAssertNotNil(get)
        XCTAssertNotNil(pin)
        XCTAssertNotNil(unpin)
        XCTAssertNotNil(archive)
        XCTAssertNotNil(restore)
        XCTAssertNotNil(readSupportFile)
        XCTAssertNotNil(searchCatalog)
        XCTAssertNotNil(getCatalogSkill)
        XCTAssertNotNil(installFromCatalog)
    }

    func testSkillEngineHelpersMirrorFlutterAPISurface() {
        let listSkills: (NapaxiEngine, String) throws -> [NapaxiSkillInfo] = { engine, agentId in
            try engine.listSkills(agentId: agentId)
        }
        let listStatus: (NapaxiEngine, String) throws -> NapaxiSkillStatusReport = { engine, agentId in
            try engine.listSkillStatus(agentId: agentId)
        }
        let getStatus: (NapaxiEngine, String, String) throws -> NapaxiSkillStatusEntry? = { engine, skillName, agentId in
            try engine.getSkillStatus(skillName, agentId: agentId)
        }
        let checkSkills: (NapaxiEngine, String) throws -> NapaxiSkillStatusReport = { engine, agentId in
            try engine.checkSkills(agentId: agentId)
        }
        let listSources: (NapaxiEngine, String) throws -> NapaxiSkillSourceReport = { engine, agentId in
            try engine.listSkillSources(agentId: agentId)
        }
        let recordSourceChanged: (NapaxiEngine, String, String) throws -> NapaxiSkillRefreshResult = { engine, sourceId, agentId in
            try engine.recordSkillSourceChanged(sourceId, agentId: agentId)
        }
        let listCommands: (NapaxiEngine, String) throws -> NapaxiSkillCommandReport = { engine, agentId in
            try engine.listSkillCommands(agentId: agentId)
        }
        let resolveCommand: (NapaxiEngine, String, String) throws -> NapaxiSkillCommandResolution = { engine, text, agentId in
            try engine.resolveSkillCommand(text, agentId: agentId)
        }
        let runCommand: (NapaxiEngine, String, String, String?, NapaxiSessionKey?) throws -> NapaxiSkillCommandRun = { engine, commandName, agentId, args, sessionKey in
            try engine.runSkillCommand(commandName, agentId: agentId, args: args, sessionKey: sessionKey)
        }
        let setEnabled: (NapaxiEngine, String, String, Bool) throws -> String = { engine, skillName, agentId, enabled in
            try engine.setSkillEnabled(skillName, agentId: agentId, enabled: enabled)
        }
        let updateConfig: (NapaxiEngine, String, [String: NapaxiJSONValue], String) throws -> String = { engine, skillKey, patch, agentId in
            try engine.updateSkillConfig(skillKey, patch: patch, agentId: agentId)
        }
        let listRemediation: (NapaxiEngine, String, String) throws -> [NapaxiSkillRemediationAction] = { engine, skillName, agentId in
            try engine.listSkillRemediationActions(skillName, agentId: agentId)
        }
        let recordResolution: (NapaxiEngine, String, String, [String: NapaxiJSONValue], String) throws -> String = { engine, skillName, actionId, result, agentId in
            try engine.recordSkillRequirementResolution(skillName, actionId: actionId, result: result, agentId: agentId)
        }
        let listSnapshots: (NapaxiEngine, String, Int, Int) throws -> NapaxiSkillSnapshotList = { engine, agentId, limit, offset in
            try engine.listSkillSnapshots(agentId: agentId, limit: limit, offset: offset)
        }
        let getSnapshot: (NapaxiEngine, String) throws -> NapaxiSkillSnapshot? = { engine, snapshotId in
            try engine.getSkillSnapshot(snapshotId)
        }
        let listSecrets: (NapaxiEngine, String, String?) throws -> NapaxiSkillSecretRequirementReport = { engine, agentId, skillName in
            try engine.listSkillSecretRequirements(agentId: agentId, skillName: skillName)
        }
        let recordSecretAvailability: (NapaxiEngine, String, String, String, Bool, String) throws -> NapaxiSkillStatusReport = { engine, skillName, key, agentId, available, source in
            try engine.recordSkillSecretAvailability(skillName, key, agentId: agentId, available: available, source: source)
        }
        let requestRemediation: (NapaxiEngine, String, String, String) throws -> NapaxiSkillRemediationRun = { engine, skillName, actionId, agentId in
            try engine.requestSkillRemediation(skillName, actionId, agentId: agentId)
        }
        let updateRemediationRun: (NapaxiEngine, String, String, String, [String: NapaxiJSONValue]?) throws -> NapaxiSkillRemediationRun = { engine, runId, status, agentId, result in
            try engine.updateSkillRemediationRun(runId, status, agentId: agentId, result: result)
        }
        let listRemediationRuns: (NapaxiEngine, String, String?, Int, Int) throws -> NapaxiSkillRemediationRunList = { engine, agentId, skillName, limit, offset in
            try engine.listSkillRemediationRuns(agentId: agentId, skillName: skillName, limit: limit, offset: offset)
        }
        let getSkill: (NapaxiEngine, String, String) throws -> NapaxiSkillInfo? = { engine, skillName, agentId in
            try engine.getSkill(skillName, agentId: agentId)
        }
        let installSkillContent: (NapaxiEngine, String, String) throws -> NapaxiSkillInstallResult = { engine, skillContent, agentId in
            try engine.installSkill(skillContent, agentId: agentId)
        }
        let installSkillInput: (NapaxiEngine, NapaxiSkillInstallInput, String) throws -> NapaxiSkillInstallResult = { engine, input, agentId in
            try engine.installSkill(input, agentId: agentId)
        }
        let removeSkill: (NapaxiEngine, String, String) throws -> Bool = { engine, skillName, agentId in
            try engine.removeSkill(skillName, agentId: agentId)
        }
        let reloadSkills: (NapaxiEngine, String) throws -> [String] = { engine, agentId in
            try engine.reloadSkills(agentId: agentId)
        }
        let listUsage: (NapaxiEngine, String) throws -> [NapaxiSkillUsageRecord] = { engine, agentId in
            try engine.listSkillUsage(agentId: agentId)
        }
        let pinSkill: (NapaxiEngine, String, String, Bool) throws -> String = { engine, skillName, agentId, pinned in
            try engine.pinSkill(skillName, agentId: agentId, pinned: pinned)
        }
        let archiveSkill: (NapaxiEngine, String, String) throws -> String = { engine, skillName, agentId in
            try engine.archiveSkill(skillName, agentId: agentId)
        }
        let restoreSkill: (NapaxiEngine, String, String) throws -> String = { engine, skillName, agentId in
            try engine.restoreSkill(skillName, agentId: agentId)
        }
        let runCurator: (NapaxiEngine, String, Bool) throws -> NapaxiCuratorRunSummary = { engine, agentId, dryRun in
            try engine.runSkillCurator(agentId: agentId, dryRun: dryRun)
        }
        let readSupportFile: (NapaxiEngine, String, String, String) throws -> NapaxiSkillSupportFileReadResult = { engine, skillName, filePath, agentId in
            try engine.readSkillSupportFile(skillName, filePath, agentId: agentId)
        }
        let searchCatalog: (NapaxiEngine, String) throws -> NapaxiCatalogSearchResult = { engine, query in
            try engine.searchCatalog(query)
        }
        let listCatalogPackages: (NapaxiEngine, Int, String?, NapaxiClawHubSkillCatalogClient) async throws -> NapaxiCatalogPackagePage = { engine, limit, cursor, client in
            try await engine.listCatalogPackages(limit: limit, cursor: cursor, catalogClient: client)
        }
        let getCatalogSkill: (NapaxiEngine, String) throws -> NapaxiCatalogSkillInfo = { engine, slug in
            try engine.getCatalogSkill(slug)
        }
        let installFromCatalog: (NapaxiEngine, String, String) throws -> NapaxiSkillInstallResult = { engine, slug, agentId in
            try engine.installFromCatalog(slug, agentId: agentId)
        }

        XCTAssertNotNil(listSkills)
        XCTAssertNotNil(listStatus)
        XCTAssertNotNil(getStatus)
        XCTAssertNotNil(checkSkills)
        XCTAssertNotNil(listSources)
        XCTAssertNotNil(recordSourceChanged)
        XCTAssertNotNil(listCommands)
        XCTAssertNotNil(resolveCommand)
        XCTAssertNotNil(runCommand)
        XCTAssertNotNil(setEnabled)
        XCTAssertNotNil(updateConfig)
        XCTAssertNotNil(listRemediation)
        XCTAssertNotNil(recordResolution)
        XCTAssertNotNil(listSnapshots)
        XCTAssertNotNil(getSnapshot)
        XCTAssertNotNil(listSecrets)
        XCTAssertNotNil(recordSecretAvailability)
        XCTAssertNotNil(requestRemediation)
        XCTAssertNotNil(updateRemediationRun)
        XCTAssertNotNil(listRemediationRuns)
        XCTAssertNotNil(getSkill)
        XCTAssertNotNil(installSkillContent)
        XCTAssertNotNil(installSkillInput)
        XCTAssertNotNil(removeSkill)
        XCTAssertNotNil(reloadSkills)
        XCTAssertNotNil(listUsage)
        XCTAssertNotNil(pinSkill)
        XCTAssertNotNil(archiveSkill)
        XCTAssertNotNil(restoreSkill)
        XCTAssertNotNil(runCurator)
        XCTAssertNotNil(readSupportFile)
        XCTAssertNotNil(searchCatalog)
        XCTAssertNotNil(listCatalogPackages)
        XCTAssertNotNil(getCatalogSkill)
        XCTAssertNotNil(installFromCatalog)
    }

    func testSkillInfoTypedAccessorsPreserveRawFields() throws {
        let json = """
        {
          "name": "calendar",
          "version": "1.0.0",
          "description": "Calendar helper",
          "always": true,
          "allowed_agents": ["napaxi"],
          "trust": "Trusted",
          "source": "bundled",
          "keywords": ["meetings"],
          "tags": ["productivity"],
          "prompt_content": "Use calendar",
          "content_hash": "hash",
          "lifecycle": {
            "state": "active",
            "pinned": true,
            "use_count": 4
          },
          "support_files": ["README.md"],
          "unknown_future_field": {"nested": true}
        }
        """

        let skill = try JSONDecoder().decode(NapaxiSkillInfo.self, from: Data(json.utf8))

        XCTAssertEqual(skill.name, "calendar")
        XCTAssertEqual(skill.version, "1.0.0")
        XCTAssertEqual(skill.description, "Calendar helper")
        XCTAssertTrue(skill.always)
        XCTAssertEqual(skill.allowedAgents, ["napaxi"])
        XCTAssertEqual(skill.trust, "Trusted")
        XCTAssertEqual(skill.keywords, ["meetings"])
        XCTAssertEqual(skill.tags, ["productivity"])
        XCTAssertEqual(skill.promptContent, "Use calendar")
        XCTAssertEqual(skill.contentHash, "hash")
        XCTAssertTrue(skill.lifecycle.pinned)
        XCTAssertEqual(skill.lifecycle.useCount, 4)
        XCTAssertEqual(skill.supportFiles, ["README.md"])
        XCTAssertEqual(skill.raw["unknown_future_field"], .object(["nested": .bool(true)]))
    }

    func testSkillInfoTypedDecodersSurfaceFlutterFactoryErrors() throws {
        let valid: [String: NapaxiJSONValue] = [
            "name": .string("calendar"),
            "version": .string("1.0.0"),
            "description": .string("Calendar helper"),
            "always": .bool(true),
            "allowed_agents": .array([.string("napaxi")]),
            "keywords": .array([.string("meetings")]),
            "tags": .array([.string("productivity")]),
            "lifecycle": .object([
                "state": .string("active"),
                "pinned": .bool(true),
                "use_count": .number(4),
            ]),
            "support_files": .array([.string("README.md")]),
        ]
        let skills = try NapaxiSkillAPI.decodeSkillInfos(from: .array([
            .string("ignored"),
            .object(valid),
        ]))
        XCTAssertEqual(skills.map(\.name), ["calendar"])
        XCTAssertTrue(try NapaxiSkillAPI.decodeSkillInfo(from: .object(valid)).lifecycle.pinned)

        var malformedName = valid
        malformedName["name"] = .number(7)
        XCTAssertThrowsError(try NapaxiSkillAPI.decodeSkillInfo(from: .object(malformedName)))

        var malformedAgents = valid
        malformedAgents["allowed_agents"] = .array([.string("napaxi"), .number(7)])
        XCTAssertThrowsError(try NapaxiSkillAPI.decodeSkillInfos(from: .array([.object(malformedAgents)])))

        var malformedAlways = valid
        malformedAlways["always"] = .string("true")
        XCTAssertThrowsError(try NapaxiSkillAPI.decodeSkillInfo(from: .object(malformedAlways)))

        var malformedLifecycle = valid
        malformedLifecycle["lifecycle"] = .array([])
        XCTAssertThrowsError(try NapaxiSkillAPI.decodeSkillInfo(from: .object(malformedLifecycle)))

        var malformedLifecycleCount = valid
        malformedLifecycleCount["lifecycle"] = .object(["use_count": .string("4")])
        XCTAssertThrowsError(try NapaxiSkillAPI.decodeSkillInfo(from: .object(malformedLifecycleCount)))

        var malformedSupportFiles = valid
        malformedSupportFiles["support_files"] = .array([.string("README.md"), .bool(true)])
        XCTAssertThrowsError(try NapaxiSkillAPI.decodeSkillInfo(from: .object(malformedSupportFiles)))
    }

    func testSkillStatusReportAccessorsMatchFlutterDefaults() throws {
        let json = """
        {
          "entries": [
            {
              "name": "shell",
              "description": "Shell",
              "source_kind": "bundled",
              "enabled": true,
              "eligible": false,
              "status": "missing_requirements",
              "requirements": {"bins": ["sh", 7], "any_bins": ["bash", false, "zsh"]},
              "missing": {"capabilities": ["napaxi.tool.shell", null]},
              "install_options": [{"kind": "brew"}],
              "warnings": ["missing", 42],
              "error": 42,
              "metadata": {"user_invocable": false, "command_tool": "shell", "command_arg_mode": false},
              "provenance": {
                "source_kind": "catalog_installed",
                "trust": "installed",
                "managed_by": true,
                "legacy": false
              },
              "remediation_actions": [
                {
                  "id": 7,
                  "kind": "env",
                  "label": "Configure TOKEN",
                  "requirement": "TOKEN",
                  "host_handled": true,
                  "danger_level": "medium"
                }
              ]
            }
          ],
          "ready": "1",
          "missing_requirements": 1,
          "top_blockers": [
            {"name": "shell", "status": "missing_requirements"}
          ]
        }
        """

        let report = try JSONDecoder().decode(NapaxiSkillStatusReport.self, from: Data(json.utf8))
        let entry = try XCTUnwrap(report.entries.first)

        XCTAssertEqual(report.ready, 1)
        XCTAssertEqual(report.missingRequirements, 1)
        XCTAssertEqual(report.topBlockers.first?.name, "shell")
        XCTAssertEqual(entry.name, "shell")
        XCTAssertTrue(entry.enabled)
        XCTAssertFalse(entry.eligible)
        XCTAssertTrue(entry.isBlocked)
        XCTAssertEqual(entry.requirements.bins, ["sh"])
        XCTAssertEqual(entry.requirements.anyBins, ["bash", "zsh"])
        XCTAssertEqual(entry.missing.capabilities, ["napaxi.tool.shell"])
        XCTAssertEqual(entry.installOptions.first?["kind"], .string("brew"))
        XCTAssertEqual(entry.warnings, ["missing"])
        XCTAssertEqual(entry.error, "42")
        XCTAssertFalse(entry.metadata.userInvocable)
        XCTAssertEqual(entry.metadata.commandTool, "shell")
        XCTAssertEqual(entry.metadata.commandArgMode, "false")
        XCTAssertEqual(entry.provenance.sourceKind, "catalog_installed")
        XCTAssertEqual(entry.provenance.managedBy, "true")
        XCTAssertEqual(entry.remediationActions.first?.id, "7")
        XCTAssertEqual(entry.remediationActions.first?.kind, "env")
        XCTAssertEqual(entry.remediationActions.first?.dangerLevel, "medium")
    }

    func testSkillStatusTypedDecodersSurfaceFlutterFactoryErrors() throws {
        let validEntry: [String: NapaxiJSONValue] = [
            "name": .string("shell"),
            "description": .string("Shell"),
            "source_kind": .string("bundled"),
            "source": .string("core"),
            "trust": .string("Trusted"),
            "enabled": .bool(true),
            "eligible": .bool(false),
            "status": .string("missing_requirements"),
            "install_options": .array([
                .string("ignored"),
                .object(["kind": .string("brew")]),
            ]),
            "lifecycle": .object([
                "state": .string("active"),
                "pinned": .bool(false),
                "use_count": .number(1),
            ]),
            "metadata": .object([
                "user_invocable": .bool(false),
            ]),
            "provenance": .object([
                "legacy": .bool(false),
            ]),
            "remediation_actions": .array([
                .number(7),
                .object([
                    "id": .number(1),
                    "host_handled": .bool(true),
                ]),
            ]),
        ]
        let report = try NapaxiSkillAPI.decodeSkillStatusReport(from: .object([
            "entries": .array([
                .string("ignored"),
                .object(validEntry),
            ]),
            "ready": .string("1"),
            "top_blockers": .array([
                .number(7),
                .object(validEntry),
            ]),
        ]))

        XCTAssertEqual(report.entries.map(\.name), ["shell"])
        XCTAssertEqual(report.topBlockers.map(\.name), ["shell"])
        XCTAssertEqual(report.ready, 1)
        XCTAssertEqual(report.entries.first?.remediationActions.map(\.id), ["1"])

        var malformedName = validEntry
        malformedName["name"] = .number(7)
        XCTAssertThrowsError(try NapaxiSkillAPI.decodeSkillStatusEntry(from: .object(malformedName)))

        var malformedEnabled = validEntry
        malformedEnabled["enabled"] = .string("true")
        XCTAssertThrowsError(try NapaxiSkillAPI.decodeSkillStatusEntry(from: .object(malformedEnabled)))

        var malformedInstallOptions = validEntry
        malformedInstallOptions["install_options"] = .object(["kind": .string("brew")])
        XCTAssertThrowsError(try NapaxiSkillAPI.decodeSkillStatusEntry(from: .object(malformedInstallOptions)))

        var malformedLifecycle = validEntry
        malformedLifecycle["lifecycle"] = .object(["pinned": .string("false")])
        XCTAssertThrowsError(try NapaxiSkillAPI.decodeSkillStatusEntry(from: .object(malformedLifecycle)))

        var malformedMetadata = validEntry
        malformedMetadata["metadata"] = .object(["user_invocable": .string("false")])
        XCTAssertThrowsError(try NapaxiSkillAPI.decodeSkillStatusEntry(from: .object(malformedMetadata)))

        var malformedProvenance = validEntry
        malformedProvenance["provenance"] = .object(["legacy": .string("false")])
        XCTAssertThrowsError(try NapaxiSkillAPI.decodeSkillStatusEntry(from: .object(malformedProvenance)))

        var malformedRemediation = validEntry
        malformedRemediation["remediation_actions"] = .array([
            .object(["host_handled": .string("true")]),
        ])
        XCTAssertThrowsError(try NapaxiSkillAPI.decodeSkillStatusEntry(from: .object(malformedRemediation)))

        XCTAssertThrowsError(try NapaxiSkillAPI.decodeSkillStatusReport(from: .object([
            "entries": .object(["name": .string("shell")]),
        ])))
    }

    func testSkillCommandModelsDecodeFlutterCompatibleFields() throws {
        let report = try JSONDecoder().decode(NapaxiSkillCommandReport.self, from: Data("""
        {
          "total": 1,
          "snapshot_id": "snap-1",
          "commands": [
            {
              "name": 9,
              "skill_name": "calendar-skill",
              "description": "Calendar helper",
              "dispatch": {"kind": false, "tool_name": 12},
              "arg_mode": false,
              "eligible": true
            }
          ]
        }
        """.utf8))
        let command = try XCTUnwrap(report.commands.first)

        XCTAssertEqual(report.total, 1)
        XCTAssertEqual(report.snapshotId, "snap-1")
        XCTAssertEqual(command.name, "9")
        XCTAssertEqual(command.skillName, "calendar-skill")
        XCTAssertEqual(command.dispatch?.kind, "false")
        XCTAssertEqual(command.dispatch?.toolName, "12")
        XCTAssertEqual(command.argMode, "false")
        XCTAssertTrue(command.eligible)

        let resolution = try JSONDecoder().decode(NapaxiSkillCommandResolution.self, from: Data("""
        {
          "matched": true,
          "command": {
            "name": "calendar",
            "skillName": "calendar-skill",
            "description": "Calendar helper",
            "eligible": true
          },
          "args": true,
          "error": 5
        }
        """.utf8))
        XCTAssertTrue(resolution.matched)
        XCTAssertEqual(resolution.command?.skillName, "calendar-skill")
        XCTAssertEqual(resolution.args, "true")
        XCTAssertEqual(resolution.error, "5")

        let run = try JSONDecoder().decode(NapaxiSkillCommandRun.self, from: Data("""
        {
          "success": true,
          "status": "agent_turn_required",
          "command_name": "calendar",
          "skill_name": "calendar-skill",
          "args": "today",
          "message": false
        }
        """.utf8))
        XCTAssertTrue(run.success)
        XCTAssertEqual(run.status, "agent_turn_required")
        XCTAssertEqual(run.commandName, "calendar")
        XCTAssertEqual(run.skillName, "calendar-skill")
        XCTAssertEqual(run.message, "false")
    }

    func testSkillCommandTypedDecodersSurfaceFlutterFactoryErrors() throws {
        let validCommand: [String: NapaxiJSONValue] = [
            "name": .number(9),
            "skill_name": .string("calendar-skill"),
            "description": .string("Calendar helper"),
            "dispatch": .object([
                "kind": .bool(false),
                "tool_name": .number(12),
            ]),
            "arg_mode": .bool(false),
            "eligible": .bool(true),
        ]

        let report = try NapaxiSkillAPI.decodeSkillCommandReport(from: .object([
            "total": .string("2"),
            "snapshot_id": .number(42),
            "commands": .array([
                .string("ignored"),
                .object(validCommand),
            ]),
        ]))
        let command = try XCTUnwrap(report.commands.first)

        XCTAssertEqual(report.commands.count, 1)
        XCTAssertEqual(report.total, 2)
        XCTAssertEqual(report.snapshotId, "42")
        XCTAssertEqual(command.name, "9")
        XCTAssertEqual(command.skillName, "calendar-skill")
        XCTAssertEqual(command.dispatch?.kind, "false")
        XCTAssertEqual(command.dispatch?.toolName, "12")
        XCTAssertEqual(command.argMode, "false")
        XCTAssertTrue(command.eligible)

        let emptyReport = try NapaxiSkillAPI.decodeSkillCommandReport(from: .object([
            "commands": .object(["name": .string("not-a-list")]),
        ]))
        XCTAssertTrue(emptyReport.commands.isEmpty)
        XCTAssertEqual(emptyReport.total, 0)

        var malformedCommand = validCommand
        malformedCommand["eligible"] = .string("true")
        XCTAssertThrowsError(try NapaxiSkillAPI.decodeSkillCommandReport(from: .object([
            "commands": .array([.object(malformedCommand)]),
        ])))

        let resolution = try NapaxiSkillAPI.decodeSkillCommandResolution(from: .object([
            "matched": .bool(true),
            "command": .object(validCommand),
            "args": .bool(true),
            "error": .number(5),
        ]))
        XCTAssertTrue(resolution.matched)
        XCTAssertEqual(resolution.command?.skillName, "calendar-skill")
        XCTAssertEqual(resolution.args, "true")
        XCTAssertEqual(resolution.error, "5")

        XCTAssertThrowsError(try NapaxiSkillAPI.decodeSkillCommandResolution(from: .object([
            "matched": .string("true"),
        ])))
        XCTAssertThrowsError(try NapaxiSkillAPI.decodeSkillCommandResolution(from: .object([
            "command": .object(malformedCommand),
        ])))

        let unmatched = try NapaxiSkillAPI.decodeSkillCommandResolution(from: .object([
            "command": .string("ignored"),
        ]))
        XCTAssertFalse(unmatched.matched)
        XCTAssertNil(unmatched.command)

        let run = try NapaxiSkillAPI.decodeSkillCommandRun(from: .object([
            "success": .bool(true),
            "status": .string("agent_turn_required"),
            "command_name": .string("calendar"),
            "skill_name": .string("calendar-skill"),
            "args": .string("today"),
            "message": .bool(false),
            "dispatch": .string("ignored"),
        ]))
        XCTAssertTrue(run.success)
        XCTAssertEqual(run.status, "agent_turn_required")
        XCTAssertEqual(run.commandName, "calendar")
        XCTAssertEqual(run.skillName, "calendar-skill")
        XCTAssertEqual(run.message, "false")
        XCTAssertNil(run.dispatch)

        XCTAssertThrowsError(try NapaxiSkillAPI.decodeSkillCommandRun(from: .object([
            "success": .string("true"),
        ])))
    }

    func testSkillSourceSnapshotSecretAndRemediationModelsMirrorFlutter() throws {
        let sourceReport = try SkillSourceReport.fromJson("""
        {
          "agent_id": "napaxi",
          "sources": [
            {
              "id": "bundled",
              "kind": "filesystem",
              "root": "/skills",
              "priority": "10",
              "trust": "Trusted",
              "exists": true,
              "version": 3,
              "updated_at": "2026-01-01T00:00:00Z"
            }
          ]
        }
        """)
        let source = try XCTUnwrap(sourceReport.sources.first)
        XCTAssertEqual(sourceReport.agentId, "napaxi")
        XCTAssertEqual(source.id, "bundled")
        XCTAssertEqual(source.priority, 10)
        XCTAssertTrue(source.exists)
        XCTAssertEqual(source.version, 3)
        XCTAssertEqual(source.updatedAt, "2026-01-01T00:00:00Z")

        let refresh = try SkillRefreshResult.fromJson("""
        {
          "success": true,
          "agentId": "napaxi",
          "sourceId": "bundled",
          "version": "4",
          "recordedAt": "2026-01-01T00:01:00Z"
        }
        """)
        XCTAssertTrue(refresh.success)
        XCTAssertEqual(refresh.agentId, "napaxi")
        XCTAssertEqual(refresh.sourceId, "bundled")
        XCTAssertEqual(refresh.version, 4)
        XCTAssertEqual(refresh.recordedAt, "2026-01-01T00:01:00Z")

        let snapshotList = try SkillSnapshotList.fromJson("""
        {
          "snapshots": [
            {
              "snapshot_id": "snap-1",
              "agent_id": "napaxi",
              "purpose": "check",
              "created_at": "2026-01-01T00:00:00Z"
            }
          ]
        }
        """)
        let indexEntry = try XCTUnwrap(snapshotList.snapshots.first)
        XCTAssertEqual(snapshotList.total, 1)
        XCTAssertEqual(indexEntry.snapshotId, "snap-1")
        XCTAssertEqual(indexEntry.agentId, "napaxi")

        let snapshot = try SkillSnapshot.fromJson("""
        {
          "snapshotId": "snap-1",
          "agentId": "napaxi",
          "purpose": "check",
          "createdAt": "2026-01-01T00:00:00Z",
          "sourceVersions": {"bundled": "4"},
          "catalogEntries": [
            {
              "name": "calendar",
              "version": "1.0",
              "description": "Calendar",
              "trust": "Trusted",
              "activationHint": "always",
              "contentHash": "hash"
            }
          ],
          "commandEntries": [
            {"name": "calendar", "skillName": "calendar-skill"}
          ],
          "statusCounts": {"ready": 1},
          "catalogPlan": {"mode": "merge"}
        }
        """)
        XCTAssertEqual(snapshot.snapshotId, "snap-1")
        XCTAssertEqual(snapshot.sourceVersions["bundled"], 4)
        XCTAssertEqual(snapshot.catalogEntries.first?.activationHint, "always")
        XCTAssertEqual(snapshot.catalogEntries.first?.contentHash, "hash")
        XCTAssertEqual(snapshot.commandEntries.first?.skillName, "calendar-skill")
        XCTAssertEqual(snapshot.statusCounts["ready"], .number(1))
        XCTAssertEqual(snapshot.catalogPlan["mode"], .string("merge"))

        let secretReport = try SkillSecretRequirementReport.fromJson("""
        {
          "requirements": [
            {
              "skill_name": "calendar",
              "skill_key": "calendar",
              "key": "TOKEN",
              "source": "host",
              "available": true
            }
          ]
        }
        """)
        let secret = try XCTUnwrap(secretReport.requirements.first)
        XCTAssertEqual(secret.skillName, "calendar")
        XCTAssertEqual(secret.skillKey, "calendar")
        XCTAssertEqual(secret.key, "TOKEN")
        XCTAssertTrue(secret.available)

        let run = try SkillRemediationRun.fromJson("""
        {
          "runId": "run-1",
          "agentId": "napaxi",
          "skillName": "calendar",
          "actionId": "env:TOKEN",
          "status": "completed",
          "requestedAt": "2026-01-01T00:00:00Z",
          "updatedAt": "2026-01-01T00:02:00Z",
          "result": {"configured": true}
        }
        """)
        XCTAssertEqual(run.runId, "run-1")
        XCTAssertEqual(run.skillName, "calendar")
        XCTAssertEqual(run.result?["configured"], .bool(true))

        let runs = SkillRemediationRunList.fromMap([
            "runs": .array([.object(run.raw)]),
        ])
        XCTAssertEqual(runs.total, 1)
        XCTAssertEqual(runs.runs.first?.runId, "run-1")
    }

    func testSkillManagementTypedDecodersSurfaceFlutterFactoryErrors() throws {
        let validSource: [String: NapaxiJSONValue] = [
            "id": .number(1),
            "kind": .bool(false),
            "root": .string("/skills"),
            "priority": .string("10"),
            "trust": .string("Trusted"),
            "exists": .bool(true),
            "version": .string("3"),
            "updated_at": .number(42),
        ]

        let sourceReport = try NapaxiSkillAPI.decodeSkillSourceReport(from: .object([
            "agent_id": .number(7),
            "sources": .array([
                .string("ignored"),
                .object(validSource),
            ]),
        ]))
        let source = try XCTUnwrap(sourceReport.sources.first)
        XCTAssertEqual(sourceReport.agentId, "7")
        XCTAssertEqual(sourceReport.sources.count, 1)
        XCTAssertEqual(source.id, "1")
        XCTAssertEqual(source.kind, "false")
        XCTAssertEqual(source.priority, 10)
        XCTAssertTrue(source.exists)
        XCTAssertEqual(source.updatedAt, "42")

        let emptySourceReport = try NapaxiSkillAPI.decodeSkillSourceReport(from: .object([
            "sources": .object(["id": .string("not-a-list")]),
        ]))
        XCTAssertTrue(emptySourceReport.sources.isEmpty)

        var malformedSource = validSource
        malformedSource["exists"] = .string("true")
        XCTAssertThrowsError(try NapaxiSkillAPI.decodeSkillSourceReport(from: .object([
            "sources": .array([.object(malformedSource)]),
        ])))

        let refresh = try NapaxiSkillAPI.decodeSkillRefreshResult(from: .object([
            "success": .bool(true),
            "agentId": .number(7),
            "sourceId": .number(8),
            "version": .string("4"),
            "recordedAt": .bool(false),
        ]))
        XCTAssertTrue(refresh.success)
        XCTAssertEqual(refresh.agentId, "7")
        XCTAssertEqual(refresh.sourceId, "8")
        XCTAssertEqual(refresh.version, 4)
        XCTAssertEqual(refresh.recordedAt, "false")
        XCTAssertThrowsError(try NapaxiSkillAPI.decodeSkillRefreshResult(from: .object([
            "success": .string("true"),
        ])))

        let actions = try NapaxiSkillAPI.decodeSkillRemediationActions(from: .array([
            .string("ignored"),
            .object([
                "id": .number(1),
                "host_handled": .bool(false),
                "danger_level": .bool(true),
            ]),
        ]))
        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions.first?.id, "1")
        XCTAssertFalse(actions.first?.hostHandled ?? true)
        XCTAssertEqual(actions.first?.dangerLevel, "true")
        XCTAssertThrowsError(try NapaxiSkillAPI.decodeSkillRemediationActions(from: .object([:])))
        XCTAssertThrowsError(try NapaxiSkillAPI.decodeSkillRemediationActions(from: .array([
            .object(["host_handled": .string("false")]),
        ])))

        let snapshotList = try NapaxiSkillAPI.decodeSkillSnapshotList(from: .object([
            "snapshots": .array([
                .number(1),
                .object([
                    "snapshot_id": .number(1),
                    "agent_id": .number(2),
                    "purpose": .bool(true),
                    "created_at": .number(3),
                ]),
            ]),
        ]))
        let snapshotEntry = try XCTUnwrap(snapshotList.snapshots.first)
        XCTAssertEqual(snapshotList.total, 1)
        XCTAssertEqual(snapshotEntry.snapshotId, "1")
        XCTAssertEqual(snapshotEntry.agentId, "2")
        XCTAssertEqual(snapshotEntry.purpose, "true")
        XCTAssertEqual(snapshotEntry.createdAt, "3")

        let emptySnapshotList = try NapaxiSkillAPI.decodeSkillSnapshotList(from: .object([
            "snapshots": .object(["snapshot_id": .string("ignored")]),
        ]))
        XCTAssertTrue(emptySnapshotList.snapshots.isEmpty)

        let snapshot = try NapaxiSkillAPI.decodeSkillSnapshot(from: .object([
            "snapshot_id": .number(1),
            "agent_id": .number(2),
            "purpose": .bool(true),
            "created_at": .number(3),
            "source_versions": .object([
                "bundled": .string("4"),
                "broken": .string("not-int"),
            ]),
            "catalog_entries": .array([
                .string("ignored"),
                .object([
                    "name": .number(9),
                    "activation_hint": .bool(false),
                ]),
            ]),
            "command_entries": .array([
                .string("ignored"),
                .object([
                    "name": .number(9),
                    "eligible": .bool(true),
                ]),
            ]),
            "status_counts": .string("ignored"),
            "catalog_plan": .string("ignored"),
        ]))
        XCTAssertEqual(snapshot.snapshotId, "1")
        XCTAssertEqual(snapshot.sourceVersions["bundled"], 4)
        XCTAssertEqual(snapshot.sourceVersions["broken"], 0)
        XCTAssertEqual(snapshot.catalogEntries.count, 1)
        XCTAssertEqual(snapshot.catalogEntries.first?.name, "9")
        XCTAssertEqual(snapshot.catalogEntries.first?.activationHint, "false")
        XCTAssertEqual(snapshot.commandEntries.count, 1)
        XCTAssertEqual(snapshot.commandEntries.first?.name, "9")
        XCTAssertTrue(snapshot.commandEntries.first?.eligible ?? false)
        XCTAssertTrue(snapshot.statusCounts.isEmpty)
        XCTAssertTrue(snapshot.catalogPlan.isEmpty)

        XCTAssertThrowsError(try NapaxiSkillAPI.decodeSkillSnapshot(from: .object([
            "command_entries": .array([
                .object(["eligible": .string("true")]),
            ]),
        ])))

        let secretReport = try NapaxiSkillAPI.decodeSkillSecretRequirementReport(from: .object([
            "requirements": .array([
                .bool(false),
                .object([
                    "skill_name": .number(1),
                    "skill_key": .number(2),
                    "key": .bool(true),
                    "source": .number(3),
                    "available": .bool(true),
                ]),
            ]),
        ]))
        let secret = try XCTUnwrap(secretReport.requirements.first)
        XCTAssertEqual(secretReport.requirements.count, 1)
        XCTAssertEqual(secret.skillName, "1")
        XCTAssertEqual(secret.skillKey, "2")
        XCTAssertEqual(secret.key, "true")
        XCTAssertEqual(secret.source, "3")
        XCTAssertTrue(secret.available)
        XCTAssertThrowsError(try NapaxiSkillAPI.decodeSkillSecretRequirementReport(from: .object([
            "requirements": .array([
                .object(["available": .string("true")]),
            ]),
        ])))

        let run = try NapaxiSkillAPI.decodeSkillRemediationRun(from: .object([
            "run_id": .number(1),
            "agent_id": .number(2),
            "skill_name": .number(3),
            "action_id": .number(4),
            "status": .bool(true),
            "requested_at": .number(5),
            "updated_at": .number(6),
            "result": .string("ignored"),
        ]))
        XCTAssertEqual(run.runId, "1")
        XCTAssertEqual(run.status, "true")
        XCTAssertNil(run.result)

        let runList = try NapaxiSkillAPI.decodeSkillRemediationRunList(from: .object([
            "runs": .array([
                .string("ignored"),
                .object(run.raw),
            ]),
        ]))
        XCTAssertEqual(runList.total, 1)
        XCTAssertEqual(runList.runs.first?.runId, "1")

        let emptyRunList = try NapaxiSkillAPI.decodeSkillRemediationRunList(from: .object([
            "runs": .object(["run_id": .string("ignored")]),
        ]))
        XCTAssertTrue(emptyRunList.runs.isEmpty)
    }

    func testSkillInstallInputAndResultUseFlutterCompatiblePayload() throws {
        let input = NapaxiSkillInstallInput(
            skillMd: "# Skill",
            extraFiles: [NapaxiSkillInstallExtraFile(path: "data.txt", bytes: Data("hello".utf8))]
        )

        let payload = try NapaxiRawJSON(jsonString: input.toInstallPayloadJson()).value
        guard case .object(let object) = payload else {
            return XCTFail("install input should encode as object")
        }

        XCTAssertEqual(object["skill_md"], .string("# Skill"))
        if case .array(let extraFiles)? = object["extra_files"],
           case .object(let first)? = extraFiles.first {
            XCTAssertEqual(first["path"], .string("data.txt"))
            XCTAssertEqual(first["content_base64"], .string(Data("hello".utf8).base64EncodedString()))
        } else {
            XCTFail("extra files should encode as object array")
        }

        let result = try JSONDecoder().decode(NapaxiSkillInstallResult.self, from: Data(#"{"name":"calendar","success":true}"#.utf8))
        XCTAssertEqual(result.name, "calendar")
        XCTAssertTrue(result.success)
        XCTAssertNil(result.error)

        let errorResult = try JSONDecoder().decode(
            NapaxiSkillInstallResult.self,
            from: Data(#"{"name":"calendar","success":true,"error":"denied"}"#.utf8)
        )
        XCTAssertNil(errorResult.name)
        XCTAssertFalse(errorResult.success)
        XCTAssertEqual(errorResult.error, "denied")
    }

    func testSkillLifecycleAndCatalogTypedDecodersSurfaceFlutterFactoryErrors() throws {
        let installResult = try NapaxiSkillAPI.decodeSkillInstallResult(from: .object([
            "name": .string("calendar"),
            "success": .bool(true),
        ]))
        XCTAssertEqual(installResult.name, "calendar")
        XCTAssertTrue(installResult.success)
        XCTAssertNil(installResult.error)

        let installError = try NapaxiSkillAPI.decodeSkillInstallResult(from: .object([
            "name": .string("ignored"),
            "success": .bool(true),
            "error": .string("denied"),
        ]))
        XCTAssertNil(installError.name)
        XCTAssertFalse(installError.success)
        XCTAssertEqual(installError.error, "denied")

        XCTAssertThrowsError(try NapaxiSkillAPI.decodeSkillInstallResult(from: .object([
            "name": .number(1),
        ])))
        XCTAssertThrowsError(try NapaxiSkillAPI.decodeSkillInstallResult(from: .object([
            "success": .string("true"),
        ])))
        XCTAssertThrowsError(try NapaxiSkillAPI.decodeSkillInstallResult(from: .object([
            "error": .null,
        ])))

        let usage = try NapaxiSkillAPI.decodeSkillUsageRecords(from: .array([
            .string("ignored"),
            .object([
                "skill_name": .string("calendar"),
                "created_at": .string("2026-01-01T00:00:00Z"),
                "state": .string("active"),
                "pinned": .bool(true),
                "created_by": .string("host"),
                "use_count": .number(2),
                "view_count": .number(3),
                "patch_count": .number(4),
                "last_used_at": .string("2026-01-01T00:01:00Z"),
            ]),
        ]))
        let usageRecord = try XCTUnwrap(usage.first)
        XCTAssertEqual(usage.count, 1)
        XCTAssertEqual(usageRecord.skillName, "calendar")
        XCTAssertTrue(usageRecord.pinned)
        XCTAssertEqual(usageRecord.useCount, 2)
        XCTAssertEqual(usageRecord.lastUsedAt, "2026-01-01T00:01:00Z")
        XCTAssertThrowsError(try NapaxiSkillAPI.decodeSkillUsageRecords(from: .object([:])))
        XCTAssertThrowsError(try NapaxiSkillAPI.decodeSkillUsageRecords(from: .array([
            .object(["skill_name": .number(1)]),
        ])))
        XCTAssertThrowsError(try NapaxiSkillAPI.decodeSkillUsageRecords(from: .array([
            .object(["use_count": .string("2")]),
        ])))
        XCTAssertThrowsError(try NapaxiSkillAPI.decodeSkillUsageRecords(from: .array([
            .object(["pinned": .string("true")]),
        ])))

        let curator = try NapaxiSkillAPI.decodeSkillCuratorRunSummary(from: .object([
            "dry_run": .bool(false),
            "checked": .number(10),
            "marked_stale": .number(2),
            "archived": .number(1),
            "restored_active": .number(3),
            "actions": .array([.string("archive:old")]),
        ]))
        XCTAssertFalse(curator.dryRun)
        XCTAssertEqual(curator.checked, 10)
        XCTAssertEqual(curator.markedStale, 2)
        XCTAssertEqual(curator.restoredActive, 3)
        XCTAssertEqual(curator.actions, ["archive:old"])
        XCTAssertThrowsError(try NapaxiSkillAPI.decodeSkillCuratorRunSummary(from: .object([
            "dry_run": .string("false"),
        ])))
        XCTAssertThrowsError(try NapaxiSkillAPI.decodeSkillCuratorRunSummary(from: .object([
            "checked": .string("10"),
        ])))
        XCTAssertThrowsError(try NapaxiSkillAPI.decodeSkillCuratorRunSummary(from: .object([
            "actions": .array([.string("ok"), .number(1)]),
        ])))

        let supportFile = try NapaxiSkillAPI.decodeSkillSupportFileReadResult(from: .object([
            "success": .bool(true),
            "skill_name": .string("calendar"),
            "file_path": .string("README.md"),
            "content": .string("hello"),
        ]))
        XCTAssertTrue(supportFile.success)
        XCTAssertEqual(supportFile.skillName, "calendar")
        XCTAssertEqual(supportFile.filePath, "README.md")
        XCTAssertEqual(supportFile.content, "hello")
        XCTAssertThrowsError(try NapaxiSkillAPI.decodeSkillSupportFileReadResult(from: .object([
            "success": .string("true"),
        ])))
        XCTAssertThrowsError(try NapaxiSkillAPI.decodeSkillSupportFileReadResult(from: .object([
            "content": .bool(false),
        ])))

        let catalog = try NapaxiSkillAPI.decodeCatalogSearchResult(from: .object([
            "results": .array([
                .object([
                    "slug": .number(1),
                    "displayName": .bool(false),
                    "latestVersion": .object(["version": .number(2)]),
                    "stats": .object(["stars": .string("5")]),
                    "owner": .object(["handle": .number(7)]),
                    "tags": .array([.string("time"), .number(9)]),
                    "score": .string("1.5"),
                ]),
            ]),
            "error": .number(404),
        ]))
        let catalogSkill = try XCTUnwrap(catalog.results.first)
        XCTAssertEqual(catalog.results.count, 1)
        XCTAssertEqual(catalogSkill.slug, "1")
        XCTAssertEqual(catalogSkill.name, "false")
        XCTAssertEqual(catalogSkill.version, "2")
        XCTAssertEqual(catalogSkill.stars, 5)
        XCTAssertEqual(catalogSkill.owner, "7")
        XCTAssertEqual(catalogSkill.tags, ["time"])
        XCTAssertEqual(catalogSkill.score, 1.5)
        XCTAssertEqual(catalog.error, "404")
        XCTAssertThrowsError(try NapaxiSkillAPI.decodeCatalogSearchResult(from: .object([
            "results": .string("not-a-list"),
        ])))
        XCTAssertThrowsError(try NapaxiSkillAPI.decodeCatalogSearchResult(from: .object([
            "results": .array([.string("not-a-map")]),
        ])))

        let page = try NapaxiSkillAPI.decodeCatalogPackagePage(from: .object([
            "items": .array([.object(["slug": .string("calendar")])]),
            "nextCursor": .number(123),
        ]))
        XCTAssertEqual(page.items.first?.slug, "calendar")
        XCTAssertEqual(page.nextCursor, "123")
        XCTAssertThrowsError(try NapaxiSkillAPI.decodeCatalogPackagePage(from: .object([
            "items": .object(["slug": .string("calendar")]),
        ])))

        let catalogInfo = try decodeSkillCatalogInfo(from: .object([
            "slug": .string("calendar"),
        ]))
        XCTAssertEqual(catalogInfo.slug, "calendar")
        XCTAssertThrowsError(try decodeSkillCatalogInfo(from: .string("calendar")))
    }

    func testCatalogModelsDecodeFlutterCompatibleFields() throws {
        let json = """
        {
          "results": [
            {
              "slug": "calendar",
              "displayName": "Calendar",
              "summary": "Plan",
              "latestVersion": {"version": "2.0"},
              "stats": {"stars": 5, "downloads": 7, "installsCurrent": 3, "installsAllTime": 9},
              "owner": {"handle": "team", "displayName": "Team"},
              "capabilityTags": ["time"],
              "updatedAt": 1000
            }
          ]
        }
        """

        let result = try JSONDecoder().decode(NapaxiCatalogSearchResult.self, from: Data(json.utf8))
        let skill = try XCTUnwrap(result.results.first)

        XCTAssertEqual(skill.slug, "calendar")
        XCTAssertEqual(skill.name, "Calendar")
        XCTAssertEqual(skill.description, "Plan")
        XCTAssertEqual(skill.version, "2.0")
        XCTAssertEqual(skill.stars, 5)
        XCTAssertEqual(skill.downloads, 7)
        XCTAssertEqual(skill.installsCurrent, 3)
        XCTAssertEqual(skill.installsAllTime, 9)
        XCTAssertEqual(skill.owner, "team")
        XCTAssertEqual(skill.ownerName, "Team")
        XCTAssertEqual(skill.tags, ["time"])
        XCTAssertEqual(skill.updatedAtMilliseconds, 1000)
    }

    func testListCatalogPackagesUsesFlutterClawHubRequestShape() async throws {
        let transport = CapturingCatalogTransport(body: """
        {
          "items": [
            {
              "slug": "calendar",
              "displayName": "Calendar",
              "summary": "Calendar helper",
              "latestVersion": {"version": "1.2.3"},
              "stats": {"stars": 9}
            }
          ],
          "nextCursor": "next-1"
        }
        """)
        let client = NapaxiClawHubSkillCatalogClient(
            baseURL: URL(string: "https://catalog.example/root")!,
            transport: transport
        )

        let page = try await client.listPackages(limit: 500, cursor: "  abc  ")

        XCTAssertEqual(transport.lastRequest?.url?.scheme, "https")
        XCTAssertEqual(transport.lastRequest?.url?.host, "catalog.example")
        XCTAssertEqual(transport.lastRequest?.url?.path, "/api/v1/packages")
        let url = try XCTUnwrap(transport.lastRequest?.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "limit" })?.value, "100")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "cursor" })?.value, "abc")
        XCTAssertEqual(transport.lastRequest?.value(forHTTPHeaderField: "User-Agent"), "napaxi-sdk/1.0")
        XCTAssertEqual(page.items.first?.slug, "calendar")
        XCTAssertEqual(page.items.first?.version, "1.2.3")
        XCTAssertEqual(page.items.first?.stars, 9)
        XCTAssertEqual(page.nextCursor, "next-1")
    }

    func testListCatalogPackagesDefaultAndClampMirrorFlutter() async throws {
        XCTAssertEqual(NapaxiClawHubSkillCatalogClient.defaultListLimit, 50)
        XCTAssertEqual(NapaxiSkillAPI.defaultCatalogPackageLimit, 24)
        XCTAssertEqual(NapaxiClawHubSkillCatalogClient.clampedListLimit(0), 1)
        XCTAssertEqual(NapaxiClawHubSkillCatalogClient.clampedListLimit(101), 100)

        let transport = CapturingCatalogTransport(body: #"{"items":[]}"#)
        let client = NapaxiClawHubSkillCatalogClient(
            baseURL: URL(string: "https://catalog.example")!,
            transport: transport
        )

        _ = try await client.listPackages()

        let url = try XCTUnwrap(transport.lastRequest?.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "limit" })?.value, "50")
    }

    func testSkillFacadeCatalogDefaultMirrorsFlutterSkillApi() async throws {
        let transport = CapturingCatalogTransport(body: #"{"items":[]}"#)
        let client = NapaxiClawHubSkillCatalogClient(
            baseURL: URL(string: "https://catalog.example")!,
            transport: transport
        )
        let api = NapaxiSkillAPI(rawAPI: NapaxiRawAPI(handle: 0))

        _ = try await api.listCatalogPackages(catalogClient: client)

        let url = try XCTUnwrap(transport.lastRequest?.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "limit" })?.value, "24")
    }

    func testListCatalogPackagesReturnsFlutterCompatibleErrorPageForHTTPFailure() async throws {
        let transport = CapturingCatalogTransport(
            statusCode: 503,
            body: "service unavailable"
        )
        let client = NapaxiClawHubSkillCatalogClient(transport: transport)

        let page = try await client.listPackages()

        XCTAssertEqual(page.items.count, 0)
        XCTAssertEqual(page.error, "HTTP 503: service unavailable")
    }
}

private final class CapturingCatalogTransport: NapaxiCatalogHTTPTransport, @unchecked Sendable {
    private let statusCode: Int
    private let body: String
    private(set) var lastRequest: URLRequest?

    init(statusCode: Int = 200, body: String) {
        self.statusCode = statusCode
        self.body = body
    }

    func load(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = request
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://catalog.example")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data(body.utf8), response)
    }
}
