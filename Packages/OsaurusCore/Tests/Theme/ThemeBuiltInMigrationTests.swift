//
//  ThemeBuiltInMigrationTests.swift
//  OsaurusCoreTests
//

import Foundation
import Testing

@testable import OsaurusCore

/// 内建预设目录收缩到 Light/Dark 之后的存量迁移。
///
/// 删掉预设定义还不够：存量安装的 `~/.nuo/themes/` 里还躺着那些旧 JSON。
/// 它们仍会被 `listThemes()` 读出来，于是用户的主题库里多出六个
/// 已经"下线"却仍可选、配色还停在上一代的旧主题。
///
/// 这条测试走真实的落盘路径（`OSAURUS_TEST_ROOT` 指向临时目录），
/// 不 mock 文件系统——迁移的 bug 恰恰发生在"文件还在不在"这一层。
///
/// `.serialized` 是必需的：这两个测试会改进程级的 `OSAURUS_TEST_ROOT`
/// 与 `UserDefaults`，并行跑会互相踩。
@Suite("Built-in theme migration", .serialized)
@MainActor
struct ThemeBuiltInMigrationTests {

    /// 已下线的六个内建预设（Neon / Nord / Paper / Terminal / Nuo Dark / Nuo Light）。
    private static let retiredIDs = [
        "00000000-0000-0000-0000-000000000003",
        "00000000-0000-0000-0000-000000000004",
        "00000000-0000-0000-0000-000000000005",
        "00000000-0000-0000-0000-000000000006",
        "00000000-0000-0000-0000-000000000007",
        "00000000-0000-0000-0000-000000000008",
    ]

    private static let canonicalDarkID = "00000000-0000-0000-0000-000000000001"
    private static let canonicalLightID = "00000000-0000-0000-0000-000000000002"

    private static let schemaKey = "builtInThemeSchemaVersion"
    private static let activeKey = "activeThemeId"

    @Test("retired built-in theme files are deleted and the catalog is reinstalled")
    func retiredFilesAreRemovedOnUpgrade() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nuo-theme-migration-\(UUID().uuidString)")
        let themesDir = root.appendingPathComponent("themes")
        try FileManager.default.createDirectory(at: themesDir, withIntermediateDirectories: true)

        let previousRoot = ProcessInfo.processInfo.environment["OSAURUS_TEST_ROOT"]
        let previousSchema = UserDefaults.standard.integer(forKey: Self.schemaKey)
        let previousActive = UserDefaults.standard.string(forKey: Self.activeKey)
        defer {
            if let previousRoot {
                setenv("OSAURUS_TEST_ROOT", previousRoot, 1)
            } else {
                unsetenv("OSAURUS_TEST_ROOT")
            }
            UserDefaults.standard.set(previousSchema, forKey: Self.schemaKey)
            if let previousActive {
                UserDefaults.standard.set(previousActive, forKey: Self.activeKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.activeKey)
            }
            try? FileManager.default.removeItem(at: root)
        }

        setenv("OSAURUS_TEST_ROOT", root.path, 1)
        // 假装这是一次从旧 schema 升上来的安装。
        UserDefaults.standard.set(0, forKey: Self.schemaKey)

        // 存量安装的磁盘状态：六个已下线的内建预设 + 一个用户自己的主题。
        for id in Self.retiredIDs {
            try Data("{}".utf8).write(to: themesDir.appendingPathComponent("\(id).json"))
        }
        let userThemeID = UUID()
        try Data("{}".utf8).write(to: themesDir.appendingPathComponent("\(userThemeID.uuidString).json"))

        // 用户当时正用其中一个已下线的预设。
        UserDefaults.standard.set(Self.retiredIDs[0], forKey: Self.activeKey)

        ThemeConfigurationStore.installBuiltInThemesIfNeeded()

        for id in Self.retiredIDs {
            #expect(
                !FileManager.default.fileExists(atPath: themesDir.appendingPathComponent("\(id).json").path),
                "已下线的内建主题 \(id) 的落盘文件必须被清掉"
            )
        }
        #expect(
            FileManager.default.fileExists(atPath: themesDir.appendingPathComponent("\(userThemeID.uuidString).json").path),
            "用户自己的主题文件不能被迁移误删"
        )
        #expect(
            FileManager.default.fileExists(atPath: themesDir.appendingPathComponent("\(Self.canonicalDarkID).json").path),
            "Dark 内建主题必须落盘"
        )
        #expect(
            FileManager.default.fileExists(atPath: themesDir.appendingPathComponent("\(Self.canonicalLightID).json").path),
            "Light 内建主题必须落盘"
        )
        #expect(
            UserDefaults.standard.string(forKey: Self.activeKey) == nil,
            "活动主题指向已下线的预设时必须清空，让界面回落到外观模式"
        )
    }

    @Test("the shipped built-in themes are the only ones the store installs")
    func storeInstallsOnlyTheCanonicalPair() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nuo-theme-install-\(UUID().uuidString)")
        let themesDir = root.appendingPathComponent("themes")
        try FileManager.default.createDirectory(at: themesDir, withIntermediateDirectories: true)

        let previousRoot = ProcessInfo.processInfo.environment["OSAURUS_TEST_ROOT"]
        let previousSchema = UserDefaults.standard.integer(forKey: Self.schemaKey)
        defer {
            if let previousRoot {
                setenv("OSAURUS_TEST_ROOT", previousRoot, 1)
            } else {
                unsetenv("OSAURUS_TEST_ROOT")
            }
            UserDefaults.standard.set(previousSchema, forKey: Self.schemaKey)
            try? FileManager.default.removeItem(at: root)
        }

        setenv("OSAURUS_TEST_ROOT", root.path, 1)
        UserDefaults.standard.set(0, forKey: Self.schemaKey)

        ThemeConfigurationStore.installBuiltInThemesIfNeeded()

        let installed = try FileManager.default
            .contentsOfDirectory(atPath: themesDir.path)
            .filter { $0.hasSuffix(".json") }
            .sorted()
        #expect(installed == ["\(Self.canonicalDarkID).json", "\(Self.canonicalLightID).json"])
    }
}
