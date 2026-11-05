//
//  EvalRunnerDemoSkill.swift
//  OsaurusEvalsKit
//
//  Deterministic `demo_skill` lane. Replays a golden recording through
//  `DemoSkillRecorder`. No model, no network, no keychain.
//

import Foundation
import OsaurusCore

extension EvalRunner {
    static func runDemoSkillCase(
        _ testCase: EvalCase,
        modelId: String
    ) async -> EvalCaseReport {
        let label = testCase.label ?? testCase.id
        guard let scenario = testCase.expect.demoSkill?.scenario else {
            return errored(
                testCase,
                label: label,
                modelId: modelId,
                note: "missing `expect.demoSkill`"
            )
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "demo-skill-eval-\(UUID().uuidString)",
            isDirectory: true
        )
        defer {
            do {
                try FileManager.default.removeItem(at: root)
            } catch {
                // 用例目录可能还没建出来。清理失败不影响这一行的分数。
                _ = error
            }
        }
        do {
            let report = try await DemoSkillRecorder.runScenario(named: scenario, root: root)
            return .terminal(
                id: testCase.id,
                label: label,
                domain: testCase.domain,
                outcome: report.passed ? .passed : .failed,
                notes: [report.note],
                modelId: modelId
            )
        } catch {
            return errored(
                testCase,
                label: label,
                modelId: modelId,
                note: String(describing: error)
            )
        }
    }
}
