//
//  StorageLocationStandardsTests.swift
//
//  Pin the #1422 storage-location audit: classification of the active
//  app-data root, both legacy roots, the models root, and the stable
//  reason-code / JSON diagnostic surface. The classifier is a pure function
//  over `Inputs`, so every case here is hermetic — no real home directory, no
//  filesystem mutation, no `OsaurusPaths` global state.
//

import Foundation
import Testing

@testable import OsaurusCore

@Suite
struct StorageLocationStandardsTests {

    private func makeInputs(
        activeRootPath: String = "/Users/sam/.nuo",
        rootSource: StorageLocationStandards.RootSource = .standard,
        home: String = "/Users/sam",
        support: String? = "/Users/sam/Library/Application Support",
        legacyHomePresent: Bool = false,
        legacyHomeMergeMarked: Bool = false,
        legacySupportPresent: Bool = false,
        legacySupportMergeMarked: Bool = false,
        candidatePresent: Bool = false,
        modelsRootPath: String = "/Users/sam/MLXModels"
    ) -> StorageLocationStandards.Inputs {
        let markerName = OsaurusPaths.legacyApplicationSupportMergeMarkerName
        let legacyHomeRoot = "\(home)/.osaurus"
        return StorageLocationStandards.Inputs(
            activeRootPath: activeRootPath,
            rootSource: rootSource,
            homeDirectoryPath: home,
            applicationSupportPath: support,
            legacyHomeDotRootPath: legacyHomeRoot,
            legacyHomeDotRootPresent: legacyHomePresent,
            legacyHomeDotRootMergeMarkerPath: "\(activeRootPath)/\(markerName)",
            legacyHomeDotRootMergeMarked: legacyHomeMergeMarked,
            legacyApplicationSupportRootPath: support.map { "\($0)/com.dinoki.osaurus" },
            legacyApplicationSupportRootPresent: legacySupportPresent,
            legacyApplicationSupportMergeMarkerPath: "\(legacyHomeRoot)/\(markerName)",
            legacyApplicationSupportMergeMarked: legacySupportMergeMarked,
            appleSpecCandidateRootPath: support.map { "\($0)/Nuo" },
            appleSpecCandidateRootPresent: candidatePresent,
            modelsRootPath: modelsRootPath
        )
    }

    // MARK: - Root classification

    @Test("Default ~/.nuo root classifies as home dot-directory, not spec-compliant")
    func homeDotDirectoryRoot() {
        let report = StorageLocationStandards.audit(makeInputs())

        #expect(report.classification == .homeDotDirectory)
        #expect(!report.specCompliant)
        #expect(
            report.reasonCodes == [
                "root_home_dot_directory_not_apple_spec",
                "root_relocation_deferred",
                "models_root_home_visible_by_design",
            ]
        )
        #expect(report.findings[0].severity == .warning)
        #expect(report.findings[0].message.contains("~/Library/Application Support"))
        #expect(report.findings[0].message.contains("~/.local/share"))
    }

    @Test("Relocation finding states the decision is made, not pending")
    func relocationDeferredIsNotPending() {
        let report = StorageLocationStandards.audit(makeInputs())
        let finding = report.findings.first { $0.code == .rootRelocationDeferred }

        #expect(finding?.severity == .info)
        #expect(finding?.message.contains("deliberately deferred") == true)
        #expect(finding?.message.contains("pending") == false)
        #expect(finding?.message.contains(".nuo") == true)
    }

    @Test("Application Support root classifies as Apple-spec compliant with no findings")
    func applicationSupportRoot() {
        let report = StorageLocationStandards.audit(
            makeInputs(
                activeRootPath: "/Users/sam/Library/Application Support/Nuo",
                modelsRootPath: "/Users/sam/Library/Application Support/Nuo/models"
            )
        )

        #expect(report.classification == .appleApplicationSupport)
        #expect(report.specCompliant)
        #expect(report.modelsRootClassification == .applicationSupport)
        #expect(report.findings.isEmpty)
        #expect(report.reasonCodes.isEmpty)
    }

    @Test("Root equal to the Application Support directory itself counts as under it")
    func rootEqualToApplicationSupport() {
        let report = StorageLocationStandards.audit(
            makeInputs(activeRootPath: "/Users/sam/Library/Application Support")
        )

        #expect(report.classification == .appleApplicationSupport)
        #expect(report.specCompliant)
    }

    @Test("Dot-directory below a subfolder of home is custom, not home dot-directory")
    func nestedDotDirectoryIsCustom() {
        // Models root is placed off-home so the case stays about the storage
        // root alone: the default `~/MLXModels` adds
        // `models_root_home_visible_by_design` on top of the root finding.
        let report = StorageLocationStandards.audit(
            makeInputs(
                activeRootPath: "/Users/sam/Documents/.nuo",
                modelsRootPath: "/Volumes/External/MLXModels"
            )
        )

        #expect(report.classification == .custom)
        #expect(!report.specCompliant)
        #expect(report.reasonCodes == ["root_custom_location"])
    }

    @Test("External-volume root is custom and models on the same volume are external")
    func externalVolumeRoot() {
        let report = StorageLocationStandards.audit(
            makeInputs(
                activeRootPath: "/Volumes/External/nuo-data",
                modelsRootPath: "/Volumes/External/MLXModels"
            )
        )

        #expect(report.classification == .custom)
        #expect(report.modelsRootClassification == .externalOrCustom)
        #expect(report.reasonCodes == ["root_custom_location"])
    }

    @Test("Trailing slashes and dot segments normalize before comparison")
    func pathNormalization() {
        let report = StorageLocationStandards.audit(
            makeInputs(
                activeRootPath: "/Users/sam/Library/Application Support/./Nuo/",
                modelsRootPath: "/Users/sam/Library/Application Support/Nuo/models"
            )
        )

        #expect(report.classification == .appleApplicationSupport)
        #expect(report.specCompliant)
    }

    // MARK: - Overrides

    @Test("Test override reports test_override and suppresses spec assessment")
    func testOverrideClassification() {
        let report = StorageLocationStandards.audit(
            makeInputs(
                activeRootPath: "/tmp/nuo-test",
                rootSource: .testOverride
            )
        )

        #expect(report.classification == .testOverride)
        #expect(!report.specCompliant)
        #expect(report.reasonCodes == ["root_overridden_for_tests"])
        #expect(report.findings[0].severity == .info)
    }

    @Test("Environment override reports environment_override and suppresses spec assessment")
    func environmentOverrideClassification() {
        let report = StorageLocationStandards.audit(
            makeInputs(
                activeRootPath: "/tmp/nuo-test-env",
                rootSource: .environmentOverride
            )
        )

        #expect(report.classification == .environmentOverride)
        #expect(report.reasonCodes == ["root_environment_override"])
    }

    // MARK: - Legacy ~/.osaurus root

    @Test("Legacy ~/.osaurus root present adds a warning and the re-clone caveat")
    func legacyHomeDotRootPresent() {
        let report = StorageLocationStandards.audit(makeInputs(legacyHomePresent: true))

        #expect(report.legacyHomeDotRootPresent)
        #expect(
            report.reasonCodes == [
                "root_home_dot_directory_not_apple_spec",
                "legacy_home_dot_root_present",
                "root_relocation_deferred",
                "models_root_home_visible_by_design",
            ]
        )
        let legacy = report.findings.first {
            $0.code == .legacyHomeDotRootPresent
        }
        #expect(legacy?.severity == .warning)
        #expect(legacy?.message.contains(".osaurus") == true)
        #expect(legacy?.message.contains("marker") == true)
        #expect(legacy?.message.contains("missing") == true)
        #expect(legacy?.message.contains("not deleted") == true)
    }

    @Test("Legacy ~/.osaurus with merge marker reports as consumed, not repeatedly re-cloned")
    func legacyHomeDotRootWithMergeMarker() {
        let report = StorageLocationStandards.audit(
            makeInputs(legacyHomePresent: true, legacyHomeMergeMarked: true)
        )

        #expect(report.legacyHomeDotRootMergeMarked)
        let legacy = report.findings.first {
            $0.code == .legacyHomeDotRootPresent
        }
        #expect(legacy?.severity == .info)
        #expect(legacy?.message.contains("will not re-merge") == true)
    }

    // MARK: - Legacy Application Support root

    @Test("Legacy com.dinoki.osaurus root present adds a warning and the re-merge caveat")
    func legacySupportRootPresent() {
        let report = StorageLocationStandards.audit(makeInputs(legacySupportPresent: true))

        #expect(report.legacyApplicationSupportRootPresent)
        #expect(
            report.reasonCodes == [
                "root_home_dot_directory_not_apple_spec",
                "legacy_application_support_root_present",
                "root_relocation_deferred",
                "models_root_home_visible_by_design",
            ]
        )
        let legacy = report.findings.first {
            $0.code == .legacyApplicationSupportRootPresent
        }
        #expect(legacy?.severity == .warning)
        #expect(legacy?.message.contains("marker") == true)
        #expect(legacy?.message.contains("missing") == true)
        #expect(legacy?.message.contains("com.dinoki.osaurus") == true)
        #expect(legacy?.message.contains(".osaurus") == true)
    }

    @Test("Legacy Application Support root with merge marker reports as consumed")
    func legacySupportRootWithMergeMarker() {
        let report = StorageLocationStandards.audit(
            makeInputs(legacySupportPresent: true, legacySupportMergeMarked: true)
        )

        #expect(report.legacyApplicationSupportMergeMarked)
        let legacy = report.findings.first {
            $0.code == .legacyApplicationSupportRootPresent
        }
        #expect(legacy?.severity == .info)
        #expect(legacy?.message.contains("will not re-merge") == true)
    }

    @Test("Both legacy roots present report one finding each, oldest last")
    func bothLegacyRootsPresent() {
        let report = StorageLocationStandards.audit(
            makeInputs(legacyHomePresent: true, legacySupportPresent: true)
        )

        #expect(
            report.findings.map(\.code) == [
                .rootHomeDotDirectoryNotAppleSpec,
                .legacyHomeDotRootPresent,
                .legacyApplicationSupportRootPresent,
                .rootRelocationDeferred,
                .modelsRootHomeVisibleByDesign,
            ]
        )
    }

    @Test("Legacy root present alongside a compliant root still reports the deferred relocation")
    func legacyRootWithCompliantActive() {
        let report = StorageLocationStandards.audit(
            makeInputs(
                activeRootPath: "/Users/sam/Library/Application Support/Nuo",
                legacySupportPresent: true,
                modelsRootPath: "/Volumes/External/MLXModels"
            )
        )

        #expect(report.specCompliant)
        #expect(
            report.reasonCodes == [
                "legacy_application_support_root_present",
                "root_relocation_deferred",
            ]
        )
    }

    // MARK: - Models root

    @Test("Home-visible models root is an info-level by-design finding, not a violation")
    func modelsRootHomeVisible() {
        let report = StorageLocationStandards.audit(makeInputs())
        let finding = report.findings.first {
            $0.code == .modelsRootHomeVisibleByDesign
        }

        #expect(report.modelsRootClassification == .homeVisible)
        #expect(finding?.severity == .info)
    }

    @Test("Models finding is suppressed under test and environment overrides")
    func modelsFindingSuppressedForOverrides() {
        let report = StorageLocationStandards.audit(
            makeInputs(rootSource: .testOverride)
        )

        #expect(report.modelsRootClassification == .homeVisible)
        #expect(!report.reasonCodes.contains("models_root_home_visible_by_design"))
    }

    // MARK: - Diagnostic surface stability

    @Test("Reason-code raw values are pinned")
    func reasonCodeRawValuesPinned() {
        let expected: [StorageLocationStandards.ReasonCode: String] = [
            .rootHomeDotDirectoryNotAppleSpec: "root_home_dot_directory_not_apple_spec",
            .rootOverriddenForTests: "root_overridden_for_tests",
            .rootEnvironmentOverride: "root_environment_override",
            .rootCustomLocation: "root_custom_location",
            .legacyHomeDotRootPresent: "legacy_home_dot_root_present",
            .legacyApplicationSupportRootPresent: "legacy_application_support_root_present",
            .rootRelocationDeferred: "root_relocation_deferred",
            .modelsRootHomeVisibleByDesign: "models_root_home_visible_by_design",
        ]

        #expect(StorageLocationStandards.ReasonCode.allCases.count == expected.count)
        for (code, raw) in expected {
            #expect(code.rawValue == raw)
        }
    }

    @Test("JSON object carries the full snake_case diagnostic surface")
    func jsonObjectShape() throws {
        let report = StorageLocationStandards.audit(
            makeInputs(legacyHomePresent: true, legacySupportPresent: true)
        )
        let json = StorageLocationStandards.jsonObject(for: report)

        #expect(
            Set(json.keys) == [
                "classification",
                "spec_compliant",
                "active_root",
                "apple_spec_candidate_root",
                "apple_spec_candidate_root_present",
                "legacy_home_dot_root",
                "legacy_home_dot_root_present",
                "legacy_home_dot_root_merge_marker",
                "legacy_home_dot_root_merge_marked",
                "legacy_application_support_root",
                "legacy_application_support_root_present",
                "legacy_application_support_merge_marker",
                "legacy_application_support_merge_marked",
                "models_root",
                "models_root_classification",
                "reason_codes",
                "findings",
                "summary",
            ]
        )
        #expect(json["classification"] as? String == "home_dot_directory")
        #expect(json["spec_compliant"] as? Bool == false)
        #expect(json["legacy_home_dot_root_present"] as? Bool == true)
        #expect(json["legacy_home_dot_root_merge_marked"] as? Bool == false)
        #expect(json["legacy_application_support_root_present"] as? Bool == true)
        #expect(json["legacy_application_support_merge_marked"] as? Bool == false)
        #expect(json["models_root_classification"] as? String == "home_visible")

        let findings = try #require(json["findings"] as? [[String: Any]])
        #expect(findings.count == report.findings.count)
        for entry in findings {
            #expect(entry["code"] is String)
            #expect(entry["severity"] is String)
            #expect(entry["message"] is String)
        }

        // The block must serialize with the same canonical options the
        // endpoint uses.
        #expect(JSONSerialization.isValidJSONObject(json))
    }

    @Test("JSON object uses NSNull for absent Application Support paths")
    func jsonObjectNullability() {
        let report = StorageLocationStandards.audit(makeInputs(support: nil))
        let json = StorageLocationStandards.jsonObject(for: report)

        #expect(json["apple_spec_candidate_root"] is NSNull)
        #expect(json["legacy_application_support_root"] is NSNull)
        #expect(json["legacy_home_dot_root"] as? String == "/Users/sam/.osaurus")
    }

    // MARK: - Legacy Application Support merge marker

    @Test("Legacy Application Support migration writes marker and skips later merges")
    func legacyApplicationSupportMigrationIsOneShot() throws {
        let fm = FileManager.default
        let sandbox = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let legacy = sandbox.appendingPathComponent("Library/Application Support/com.dinoki.osaurus")
        let active = sandbox.appendingPathComponent(".osaurus")
        defer { try? fm.removeItem(at: sandbox) }

        try fm.createDirectory(at: legacy, withIntermediateDirectories: true)
        try "first".write(
            to: legacy.appendingPathComponent("settings.json"),
            atomically: true,
            encoding: .utf8
        )

        let first = OsaurusPaths.migrateLegacyApplicationSupportRootIfNeeded(
            fileManager: fm,
            legacyRoot: legacy,
            activeRoot: active
        )
        #expect(first == .copied(OsaurusPaths.legacyApplicationSupportMergeMarker(for: active)))
        #expect(fm.fileExists(atPath: active.appendingPathComponent("settings.json").path))
        #expect(
            fm.fileExists(
                atPath: OsaurusPaths.legacyApplicationSupportMergeMarker(for: active).path
            )
        )

        try "second".write(
            to: legacy.appendingPathComponent("new-after-marker.json"),
            atomically: true,
            encoding: .utf8
        )

        let second = OsaurusPaths.migrateLegacyApplicationSupportRootIfNeeded(
            fileManager: fm,
            legacyRoot: legacy,
            activeRoot: active
        )
        #expect(second == .alreadyMarked(OsaurusPaths.legacyApplicationSupportMergeMarker(for: active)))
        #expect(!fm.fileExists(atPath: active.appendingPathComponent("new-after-marker.json").path))
    }

    @Test("Legacy Application Support merge keeps newer active files before writing marker")
    func legacyApplicationSupportMergePreservesNewerActiveFiles() throws {
        let fm = FileManager.default
        let sandbox = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let legacy = sandbox.appendingPathComponent("Library/Application Support/com.dinoki.osaurus")
        let active = sandbox.appendingPathComponent(".osaurus")
        defer { try? fm.removeItem(at: sandbox) }

        try fm.createDirectory(at: legacy, withIntermediateDirectories: true)
        try fm.createDirectory(at: active, withIntermediateDirectories: true)
        let legacyFile = legacy.appendingPathComponent("config.json")
        let activeFile = active.appendingPathComponent("config.json")
        try "legacy".write(to: legacyFile, atomically: true, encoding: .utf8)
        try "active".write(to: activeFile, atomically: true, encoding: .utf8)
        try fm.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 100)],
            ofItemAtPath: legacyFile.path
        )
        try fm.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 200)],
            ofItemAtPath: activeFile.path
        )

        let result = OsaurusPaths.migrateLegacyApplicationSupportRootIfNeeded(
            fileManager: fm,
            legacyRoot: legacy,
            activeRoot: active
        )

        #expect(result == .merged(OsaurusPaths.legacyApplicationSupportMergeMarker(for: active)))
        #expect(try String(contentsOf: activeFile, encoding: .utf8) == "active")
        #expect(
            fm.fileExists(
                atPath: OsaurusPaths.legacyApplicationSupportMergeMarker(for: active).path
            )
        )
    }

    @Test("Summary stays one stable line")
    func summaryShape() {
        let report = StorageLocationStandards.audit(
            makeInputs(legacyHomePresent: true, legacySupportPresent: true)
        )

        #expect(
            report.summary
                == "root=home_dot_directory (non-compliant); legacy_home_root=present; "
                + "legacy_root=present; models_root=home_visible"
        )
        #expect(!report.summary.contains("\n"))
    }

    @Test("Missing Application Support directory still classifies the home dot-directory")
    func missingApplicationSupport() {
        let report = StorageLocationStandards.audit(makeInputs(support: nil))

        #expect(report.classification == .homeDotDirectory)
        #expect(report.appleSpecCandidateRootPath == nil)
        #expect(!report.appleSpecCandidateRootPresent)
    }
}
