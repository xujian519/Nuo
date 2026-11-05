//
//  DemoSkillRecorderTests.swift
//  osaurusTests
//
//  ADR-Nuo-002 P3：成功演示进入待审 Skill，失败演示不入库。
//

import Foundation
import Testing

@testable import OsaurusCore

@Suite
struct DemoSkillRecorderTests {
    private let scenarios = [
        "success_to_schedule",
        "failed_demo_rejected",
        "empty_recording_rejected",
        "review_reject_does_not_store",
        "mouse_trail_rejected",
        "envelope_cannot_accept",
        "watcher_runs_chain",
        "pending_review_not_in_store",
        "stop_requires_start",
    ]

    @Test("golden demo paths promote only a reviewed successful chain")
    func goldenPaths() async throws {
        for scenario in scenarios {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(
                "demo-skill-\(scenario)-\(UUID().uuidString)",
                isDirectory: true
            )
            defer {
                do {
                    try FileManager.default.removeItem(at: root)
                } catch let error {
                    // 临时目录可能已经不在。
                    _ = error
                }
            }
            let report = try await DemoSkillRecorder.runScenario(named: scenario, root: root)
            if !report.passed {
                Issue.record("\(scenario): \(report.note)")
            }
            #expect(report.passed)
        }
    }
}
