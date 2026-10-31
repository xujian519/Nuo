//
//  ToolsPaths.swift
//  osaurus
//
//  Path management for plugin storage and specifications.
//  Mirrors OsaurusPaths.root() for use in the OsaurusRepository package.
//

import Foundation

public enum ToolsPaths {
    /// Optional root directory override for tests
    /// Note: nonisolated(unsafe) since this is only set during test setup before any concurrent access
    public nonisolated(unsafe) static var overrideRoot: URL?

    /// The root data directory: `~/.nuo/`
    public static func root() -> URL {
        if let override = overrideRoot {
            return override
        }
        // Honor the same test-root redirect as `OsaurusPaths.root()` (this
        // type's documented contract is to mirror it). Without this, CLI
        // verbs that WRITE config (e.g. `bench --tune-prefill`) target the
        // real `~/.nuo` while a test-rooted server process reads its
        // hermetic root — the sweep then measures the default value for
        // every candidate.
        if let envRoot = ProcessInfo.processInfo.environment["OSAURUS_TEST_ROOT"],
            !envRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return URL(fileURLWithPath: envRoot, isDirectory: true)
        }
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let current = home.appendingPathComponent(Brand.dataRootName, isDirectory: true)
        // The app owns the one-time legacy-root migration (`OsaurusPaths.root()`).
        // The CLI can run on a machine that has not launched the renamed app yet,
        // so read the pre-rename root until the new one exists instead of
        // reporting an empty install.
        if !fm.fileExists(atPath: current.path) {
            let legacy = home.appendingPathComponent(Brand.Legacy.dataRootName, isDirectory: true)
            if fm.fileExists(atPath: legacy.path) {
                return legacy
            }
        }
        return current
    }

    /// Tools directory (plugins)
    /// `~/.nuo/Tools/`
    public static func toolsRootDirectory() -> URL {
        root().appendingPathComponent("Tools", isDirectory: true)
    }

    /// Plugin specifications directory
    /// `~/.nuo/PluginSpecs/`
    public static func pluginSpecsRoot() -> URL {
        root().appendingPathComponent("PluginSpecs", isDirectory: true)
    }

    /// Ensures a directory exists, creating it if necessary
    /// - Parameter url: The directory URL to ensure exists
    public static func ensureExists(_ url: URL) {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if !fm.fileExists(atPath: url.path, isDirectory: &isDir) {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
