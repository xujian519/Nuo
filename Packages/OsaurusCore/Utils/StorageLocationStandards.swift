//
//  StorageLocationStandards.swift
//  osaurus
//
//  Storage-location standards audit for issue #1422.
//
//  The app keeps its data in the home dot-directory `~/.nuo/` (see
//  `OsaurusPaths`), which follows neither Apple's file-system guidance
//  (`~/Library/Application Support/...`) nor the XDG base-directory spec
//  (`~/.local/share/...`). Staying there is a deliberate decision — the
//  Keychain data-encryption key is paired with the existing tree, the HKDF
//  salt sidecar lives inside it, sandbox tooling references the root
//  literally, and plugin/container trees can be large — so this module
//  performs **no migration**. The one-time migration it describes belongs to
//  `OsaurusPaths`: an older install's data is cloned forward from
//  `~/Library/Application Support/com.dinoki.osaurus` to `~/.osaurus` and from
//  `~/.osaurus` to `~/.nuo`, and the old trees are kept intact.
//
//  This module only classifies the current layout and reports stable reason
//  codes through `/admin/cache-stats`, so users and maintainers can see
//  exactly where data lives and why. Classification is a pure function over
//  `Inputs`; the live probe is read-only and never mutates the filesystem.
//

import Foundation
import OsaurusRepository

public enum StorageLocationStandards {

    // MARK: - Model

    /// Where the active app-data root was resolved from.
    public enum RootSource: String, Sendable {
        case standard
        case testOverride = "test_override"
        case environmentOverride = "environment_override"
    }

    /// Classification of the active app-data root against platform
    /// storage-location conventions.
    public enum RootClassification: String, Sendable {
        case appleApplicationSupport = "apple_application_support"
        case homeDotDirectory = "home_dot_directory"
        case testOverride = "test_override"
        case environmentOverride = "environment_override"
        case custom
    }

    /// Classification of the model-weights root, reported separately from
    /// the app-data root because user-managed weights are home-visible by
    /// design today.
    public enum ModelsRootClassification: String, Sendable {
        case applicationSupport = "application_support"
        case homeVisible = "home_visible"
        case externalOrCustom = "external_or_custom"
    }

    /// Stable, machine-readable reason codes. These are part of the
    /// diagnostic surface — do not rename existing raw values.
    public enum ReasonCode: String, CaseIterable, Sendable {
        case rootHomeDotDirectoryNotAppleSpec = "root_home_dot_directory_not_apple_spec"
        case rootOverriddenForTests = "root_overridden_for_tests"
        case rootEnvironmentOverride = "root_environment_override"
        case rootCustomLocation = "root_custom_location"
        /// The pre-`~/.nuo` home dot-directory (`~/.osaurus`) still exists.
        /// Its data was cloned forward once; the tree itself stays untouched.
        case legacyHomeDotRootPresent = "legacy_home_dot_root_present"
        /// The oldest pre-home-dot root under Application Support still
        /// exists.
        case legacyApplicationSupportRootPresent = "legacy_application_support_root_present"
        /// The root stays a home dot-directory on purpose; relocation is not
        /// pending a decision.
        case rootRelocationDeferred = "root_relocation_deferred"
        case modelsRootHomeVisibleByDesign = "models_root_home_visible_by_design"
    }

    public enum Severity: String, Sendable {
        case info
        case warning
    }

    /// One audited fact with a stable code and a human-readable explanation.
    public struct Finding: Equatable, Sendable {
        public let code: ReasonCode
        public let severity: Severity
        public let message: String

        public init(code: ReasonCode, severity: Severity, message: String) {
            self.code = code
            self.severity = severity
            self.message = message
        }
    }

    /// Everything the pure classifier needs. Built by `currentInputs()` in
    /// production; built by hand in tests.
    public struct Inputs: Equatable, Sendable {
        public let activeRootPath: String
        public let rootSource: RootSource
        public let homeDirectoryPath: String
        public let applicationSupportPath: String?
        /// Pre-`~/.nuo` home dot-directory (`~/.osaurus`) and the marker that
        /// records it was cloned into the active root.
        public let legacyHomeDotRootPath: String?
        public let legacyHomeDotRootPresent: Bool
        public let legacyHomeDotRootMergeMarkerPath: String?
        public let legacyHomeDotRootMergeMarked: Bool
        /// Pre-home-dot root under Application Support
        /// (`com.dinoki.osaurus`) and the marker that records it was cloned
        /// into `~/.osaurus`.
        public let legacyApplicationSupportRootPath: String?
        public let legacyApplicationSupportRootPresent: Bool
        public let legacyApplicationSupportMergeMarkerPath: String?
        public let legacyApplicationSupportMergeMarked: Bool
        public let appleSpecCandidateRootPath: String?
        public let appleSpecCandidateRootPresent: Bool
        public let modelsRootPath: String

        public init(
            activeRootPath: String,
            rootSource: RootSource,
            homeDirectoryPath: String,
            applicationSupportPath: String?,
            legacyHomeDotRootPath: String?,
            legacyHomeDotRootPresent: Bool,
            legacyHomeDotRootMergeMarkerPath: String?,
            legacyHomeDotRootMergeMarked: Bool,
            legacyApplicationSupportRootPath: String?,
            legacyApplicationSupportRootPresent: Bool,
            legacyApplicationSupportMergeMarkerPath: String?,
            legacyApplicationSupportMergeMarked: Bool,
            appleSpecCandidateRootPath: String?,
            appleSpecCandidateRootPresent: Bool,
            modelsRootPath: String
        ) {
            self.activeRootPath = activeRootPath
            self.rootSource = rootSource
            self.homeDirectoryPath = homeDirectoryPath
            self.applicationSupportPath = applicationSupportPath
            self.legacyHomeDotRootPath = legacyHomeDotRootPath
            self.legacyHomeDotRootPresent = legacyHomeDotRootPresent
            self.legacyHomeDotRootMergeMarkerPath = legacyHomeDotRootMergeMarkerPath
            self.legacyHomeDotRootMergeMarked = legacyHomeDotRootMergeMarked
            self.legacyApplicationSupportRootPath = legacyApplicationSupportRootPath
            self.legacyApplicationSupportRootPresent = legacyApplicationSupportRootPresent
            self.legacyApplicationSupportMergeMarkerPath = legacyApplicationSupportMergeMarkerPath
            self.legacyApplicationSupportMergeMarked = legacyApplicationSupportMergeMarked
            self.appleSpecCandidateRootPath = appleSpecCandidateRootPath
            self.appleSpecCandidateRootPresent = appleSpecCandidateRootPresent
            self.modelsRootPath = modelsRootPath
        }
    }

    /// Audit result. `reasonCodes` mirrors `findings` for compact consumers.
    public struct Report: Equatable, Sendable {
        public let classification: RootClassification
        public let specCompliant: Bool
        public let activeRootPath: String
        public let appleSpecCandidateRootPath: String?
        public let appleSpecCandidateRootPresent: Bool
        public let legacyHomeDotRootPath: String?
        public let legacyHomeDotRootPresent: Bool
        public let legacyHomeDotRootMergeMarkerPath: String?
        public let legacyHomeDotRootMergeMarked: Bool
        public let legacyApplicationSupportRootPath: String?
        public let legacyApplicationSupportRootPresent: Bool
        public let legacyApplicationSupportMergeMarkerPath: String?
        public let legacyApplicationSupportMergeMarked: Bool
        public let modelsRootPath: String
        public let modelsRootClassification: ModelsRootClassification
        public let findings: [Finding]

        public var reasonCodes: [String] {
            findings.map { $0.code.rawValue }
        }

        public var summary: String {
            let compliance = specCompliant ? "apple-spec" : "non-compliant"
            let legacyHome = legacyHomeDotRootPresent ? "present" : "absent"
            let legacySupport = legacyApplicationSupportRootPresent ? "present" : "absent"
            return "root=\(classification.rawValue) (\(compliance)); "
                + "legacy_home_root=\(legacyHome); "
                + "legacy_root=\(legacySupport); "
                + "models_root=\(modelsRootClassification.rawValue)"
        }

        public init(
            classification: RootClassification,
            specCompliant: Bool,
            activeRootPath: String,
            appleSpecCandidateRootPath: String?,
            appleSpecCandidateRootPresent: Bool,
            legacyHomeDotRootPath: String?,
            legacyHomeDotRootPresent: Bool,
            legacyHomeDotRootMergeMarkerPath: String?,
            legacyHomeDotRootMergeMarked: Bool,
            legacyApplicationSupportRootPath: String?,
            legacyApplicationSupportRootPresent: Bool,
            legacyApplicationSupportMergeMarkerPath: String?,
            legacyApplicationSupportMergeMarked: Bool,
            modelsRootPath: String,
            modelsRootClassification: ModelsRootClassification,
            findings: [Finding]
        ) {
            self.classification = classification
            self.specCompliant = specCompliant
            self.activeRootPath = activeRootPath
            self.appleSpecCandidateRootPath = appleSpecCandidateRootPath
            self.appleSpecCandidateRootPresent = appleSpecCandidateRootPresent
            self.legacyHomeDotRootPath = legacyHomeDotRootPath
            self.legacyHomeDotRootPresent = legacyHomeDotRootPresent
            self.legacyHomeDotRootMergeMarkerPath = legacyHomeDotRootMergeMarkerPath
            self.legacyHomeDotRootMergeMarked = legacyHomeDotRootMergeMarked
            self.legacyApplicationSupportRootPath = legacyApplicationSupportRootPath
            self.legacyApplicationSupportRootPresent = legacyApplicationSupportRootPresent
            self.legacyApplicationSupportMergeMarkerPath = legacyApplicationSupportMergeMarkerPath
            self.legacyApplicationSupportMergeMarked = legacyApplicationSupportMergeMarked
            self.modelsRootPath = modelsRootPath
            self.modelsRootClassification = modelsRootClassification
            self.findings = findings
        }
    }

    // MARK: - Live probe (read-only)

    /// Name of the pre-`~/.osaurus` root under Application Support. Frozen
    /// upstream identifier: it points at data an older install already has.
    public static let legacyApplicationSupportFolderName = Brand.Legacy.appSupportDirectoryName

    /// Apple-spec folder name under Application Support, reported as a
    /// candidate only. Nothing is created or relocated: the root stays a home
    /// dot-directory by decision.
    public static let appleSpecCandidateFolderName = Brand.display

    /// Gather live inputs. Read-only: performs `fileExists` probes plus the
    /// same root resolution `OsaurusPaths.root()` already performed for the
    /// running process; it never creates, copies, or deletes anything.
    public static func currentInputs(fileManager fm: FileManager = .default) -> Inputs {
        let testRootOverride = ProcessInfo.processInfo.environment["OSAURUS_TEST_ROOT"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rootSource: RootSource
        if OsaurusPaths.overrideRoot != nil {
            rootSource = .testOverride
        } else if testRootOverride?.isEmpty == false {
            rootSource = .environmentOverride
        } else {
            rootSource = .standard
        }
        let home = fm.homeDirectoryForCurrentUser
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let legacyHomeDotRoot = home.appendingPathComponent(
            Brand.Legacy.dataRootName,
            isDirectory: true
        )
        let legacySupportRoot = support?.appendingPathComponent(
            legacyApplicationSupportFolderName,
            isDirectory: true
        )
        let candidate = support?.appendingPathComponent(
            appleSpecCandidateFolderName,
            isDirectory: true
        )
        let activeRoot = OsaurusPaths.root()
        // Each hop records its marker inside its *destination* root:
        //   support/com.dinoki.osaurus -> ~/.osaurus  (marker in ~/.osaurus)
        //   ~/.osaurus                 -> ~/.nuo       (marker in ~/.nuo)
        let legacyHomeDotMarker = OsaurusPaths.legacyApplicationSupportMergeMarker(
            for: activeRoot
        )
        let legacySupportMarker = OsaurusPaths.legacyApplicationSupportMergeMarker(
            for: legacyHomeDotRoot
        )
        return Inputs(
            activeRootPath: activeRoot.path,
            rootSource: rootSource,
            homeDirectoryPath: home.path,
            applicationSupportPath: support?.path,
            legacyHomeDotRootPath: legacyHomeDotRoot.path,
            legacyHomeDotRootPresent: exists(legacyHomeDotRoot, fm),
            legacyHomeDotRootMergeMarkerPath: legacyHomeDotMarker.path,
            legacyHomeDotRootMergeMarked: exists(legacyHomeDotMarker, fm),
            legacyApplicationSupportRootPath: legacySupportRoot?.path,
            legacyApplicationSupportRootPresent: legacySupportRoot.map { exists($0, fm) } ?? false,
            legacyApplicationSupportMergeMarkerPath: legacySupportMarker.path,
            legacyApplicationSupportMergeMarked: exists(legacySupportMarker, fm),
            appleSpecCandidateRootPath: candidate?.path,
            appleSpecCandidateRootPresent: candidate.map { exists($0, fm) } ?? false,
            modelsRootPath: DirectoryPickerService.effectiveModelsDirectory().path
        )
    }

    /// Convenience: live probe + pure classification.
    public static func currentReport(fileManager: FileManager = .default) -> Report {
        audit(currentInputs(fileManager: fileManager))
    }

    // MARK: - Pure classification

    public static func audit(_ inputs: Inputs) -> Report {
        let classification = classifyRoot(inputs)
        let modelsClassification = classifyModelsRoot(inputs)
        var findings: [Finding] = []

        switch classification {
        case .appleApplicationSupport:
            break
        case .homeDotDirectory:
            findings.append(
                Finding(
                    code: .rootHomeDotDirectoryNotAppleSpec,
                    severity: .warning,
                    message:
                        "App data root \(inputs.activeRootPath) is a home dot-directory. "
                        + "Apple's file-system guidance places app data under "
                        + "~/Library/Application Support; the XDG equivalent is "
                        + "~/.local/share. See docs/STORAGE.md (Storage Location Standards)."
                )
            )
        case .testOverride:
            findings.append(
                Finding(
                    code: .rootOverriddenForTests,
                    severity: .info,
                    message:
                        "Storage root is overridden via OsaurusPaths.overrideRoot for tests; "
                        + "spec compliance was not assessed."
                )
            )
        case .environmentOverride:
            findings.append(
                Finding(
                    code: .rootEnvironmentOverride,
                    severity: .info,
                    message:
                        "Storage root is overridden via OSAURUS_TEST_ROOT; "
                        + "spec compliance was not assessed."
                )
            )
        case .custom:
            findings.append(
                Finding(
                    code: .rootCustomLocation,
                    severity: .info,
                    message:
                        "Storage root \(inputs.activeRootPath) is neither the default home "
                        + "dot-directory nor under Application Support."
                )
            )
        }

        if inputs.legacyHomeDotRootPresent {
            let legacyPath = inputs.legacyHomeDotRootPath ?? ".\(Brand.Legacy.slug)"
            let markerPath =
                inputs.legacyHomeDotRootMergeMarkerPath
                ?? OsaurusPaths.legacyApplicationSupportMergeMarkerName
            let severity: Severity = inputs.legacyHomeDotRootMergeMarked ? .info : .warning
            let message: String
            if inputs.legacyHomeDotRootMergeMarked {
                message =
                    "Legacy root \(legacyPath) still exists, but the one-shot migration marker "
                    + "\(markerPath) is present. OsaurusPaths will not re-merge it into the "
                    + "active root on future launches; the legacy tree is kept intact."
            } else {
                message =
                    "Legacy root \(legacyPath) still exists and the one-shot migration marker "
                    + "\(markerPath) is missing. OsaurusPaths will clone it into the active "
                    + "root once, then write the marker so future launches do not resurrect "
                    + "stale legacy files. The legacy tree is not deleted."
            }
            findings.append(
                Finding(
                    code: .legacyHomeDotRootPresent,
                    severity: severity,
                    message: message
                )
            )
        }

        if inputs.legacyApplicationSupportRootPresent {
            let legacyPath =
                inputs.legacyApplicationSupportRootPath
                ?? legacyApplicationSupportFolderName
            let markerPath =
                inputs.legacyApplicationSupportMergeMarkerPath
                ?? OsaurusPaths.legacyApplicationSupportMergeMarkerName
            let severity: Severity = inputs.legacyApplicationSupportMergeMarked ? .info : .warning
            let message: String
            if inputs.legacyApplicationSupportMergeMarked {
                message =
                    "Legacy root \(legacyPath) still exists, but the one-shot migration marker "
                    + "\(markerPath) is present. OsaurusPaths will not re-merge it into "
                    + "\(Brand.Legacy.dataRootName) on future launches."
            } else {
                message =
                    "Legacy root \(legacyPath) still exists and the one-shot migration marker "
                    + "\(markerPath) is missing. OsaurusPaths will clone or merge it into "
                    + "\(Brand.Legacy.dataRootName) once, then write the marker so future "
                    + "launches do not resurrect stale legacy files."
            }
            findings.append(
                Finding(
                    code: .legacyApplicationSupportRootPresent,
                    severity: severity,
                    message: message
                )
            )
        }

        if classification == .homeDotDirectory
            || inputs.legacyHomeDotRootPresent
            || inputs.legacyApplicationSupportRootPresent
        {
            findings.append(
                Finding(
                    code: .rootRelocationDeferred,
                    severity: .info,
                    message:
                        "Relocating the storage root is deliberately deferred: the root stays "
                        + "a home dot-directory (\(Brand.dataRootName)) instead of moving under "
                        + "~/Library/Application Support. The Keychain data-encryption key and "
                        + "its HKDF salt are paired with the existing tree, sandbox tooling "
                        + "references the root literally, and plugin/container trees can be "
                        + "large, so legacy trees are cloned forward once and never moved or "
                        + "deleted."
                )
            )
        }

        let usesStandardRoot = classification != .testOverride && classification != .environmentOverride
        if usesStandardRoot && modelsClassification == .homeVisible {
            findings.append(
                Finding(
                    code: .modelsRootHomeVisibleByDesign,
                    severity: .info,
                    message:
                        "Model weights root \(inputs.modelsRootPath) is a home-visible "
                        + "folder (user-managed weights by design); it is a separate "
                        + "decision from the app-data root."
                )
            )
        }

        return Report(
            classification: classification,
            specCompliant: classification == .appleApplicationSupport,
            activeRootPath: inputs.activeRootPath,
            appleSpecCandidateRootPath: inputs.appleSpecCandidateRootPath,
            appleSpecCandidateRootPresent: inputs.appleSpecCandidateRootPresent,
            legacyHomeDotRootPath: inputs.legacyHomeDotRootPath,
            legacyHomeDotRootPresent: inputs.legacyHomeDotRootPresent,
            legacyHomeDotRootMergeMarkerPath: inputs.legacyHomeDotRootMergeMarkerPath,
            legacyHomeDotRootMergeMarked: inputs.legacyHomeDotRootMergeMarked,
            legacyApplicationSupportRootPath: inputs.legacyApplicationSupportRootPath,
            legacyApplicationSupportRootPresent: inputs.legacyApplicationSupportRootPresent,
            legacyApplicationSupportMergeMarkerPath: inputs.legacyApplicationSupportMergeMarkerPath,
            legacyApplicationSupportMergeMarked: inputs.legacyApplicationSupportMergeMarked,
            modelsRootPath: inputs.modelsRootPath,
            modelsRootClassification: modelsClassification,
            findings: findings
        )
    }

    // MARK: - JSON

    /// Snake-case JSON object for `/admin/cache-stats`. Mirrors the
    /// `memory_safety` block conventions (NSNull for absent optionals).
    public static func jsonObject(for report: Report) -> [String: Any] {
        [
            "classification": report.classification.rawValue,
            "spec_compliant": report.specCompliant,
            "active_root": report.activeRootPath,
            "apple_spec_candidate_root": report.appleSpecCandidateRootPath as Any? ?? NSNull(),
            "apple_spec_candidate_root_present": report.appleSpecCandidateRootPresent,
            "legacy_home_dot_root": report.legacyHomeDotRootPath as Any? ?? NSNull(),
            "legacy_home_dot_root_present": report.legacyHomeDotRootPresent,
            "legacy_home_dot_root_merge_marker":
                report.legacyHomeDotRootMergeMarkerPath as Any? ?? NSNull(),
            "legacy_home_dot_root_merge_marked": report.legacyHomeDotRootMergeMarked,
            "legacy_application_support_root": report.legacyApplicationSupportRootPath as Any?
                ?? NSNull(),
            "legacy_application_support_root_present": report.legacyApplicationSupportRootPresent,
            "legacy_application_support_merge_marker":
                report.legacyApplicationSupportMergeMarkerPath as Any? ?? NSNull(),
            "legacy_application_support_merge_marked": report.legacyApplicationSupportMergeMarked,
            "models_root": report.modelsRootPath,
            "models_root_classification": report.modelsRootClassification.rawValue,
            "reason_codes": report.reasonCodes,
            "findings": report.findings.map { finding in
                [
                    "code": finding.code.rawValue,
                    "severity": finding.severity.rawValue,
                    "message": finding.message,
                ]
            },
            "summary": report.summary,
        ]
    }

    // MARK: - Helpers

    private static func exists(_ url: URL, _ fm: FileManager) -> Bool {
        fm.fileExists(atPath: url.path)
    }

    private static func classifyRoot(_ inputs: Inputs) -> RootClassification {
        switch inputs.rootSource {
        case .testOverride:
            return .testOverride
        case .environmentOverride:
            return .environmentOverride
        case .standard:
            break
        }
        let activeRootIsInApplicationSupport =
            inputs.applicationSupportPath.map { isSubpath(inputs.activeRootPath, of: $0) } ?? false
        if activeRootIsInApplicationSupport {
            return .appleApplicationSupport
        }
        let root = URL(fileURLWithPath: normalizedPath(inputs.activeRootPath))
        let rootParentPath = root.deletingLastPathComponent().path
        let normalizedHomePath = normalizedPath(inputs.homeDirectoryPath)
        if root.lastPathComponent.hasPrefix(".") && rootParentPath == normalizedHomePath {
            return .homeDotDirectory
        }
        return .custom
    }

    private static func classifyModelsRoot(_ inputs: Inputs) -> ModelsRootClassification {
        let modelsRootIsInApplicationSupport =
            inputs.applicationSupportPath.map { isSubpath(inputs.modelsRootPath, of: $0) } ?? false
        if modelsRootIsInApplicationSupport {
            return .applicationSupport
        }
        if isSubpath(inputs.modelsRootPath, of: inputs.homeDirectoryPath) {
            return .homeVisible
        }
        return .externalOrCustom
    }

    private static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private static func isSubpath(_ path: String, of parent: String) -> Bool {
        let child = normalizedPath(path)
        let base = normalizedPath(parent)
        if child == base {
            return true
        }
        let prefix = base.hasSuffix("/") ? base : base + "/"
        return child.hasPrefix(prefix)
    }
}
