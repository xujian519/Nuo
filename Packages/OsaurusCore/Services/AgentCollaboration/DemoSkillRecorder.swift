//
//  DemoSkillRecorder.swift
//  osaurus
//
//  ADR-Nuo-002 P3。显式开始/停止的演示，只有整条成功的工具链才能进入 Skill。
//  草稿要等人审过才落盘，然后才能挂上 Schedule 或 Watcher。
//

import Foundation

public enum DemoSkillError: Error, Equatable, Sendable {
    case alreadyRecording(String)
    case notRecording(String)
    case unknownRecording(String)
    case failedDemoRejected(String)
    case notPendingReview(String)
    case mouseTrailRejected(String)
    case envelopeRejected
    case skillNotAccepted(String)
    case unknownAttachment(String)
}

public enum DemoSkillStatus: String, Codable, Sendable, Equatable {
    case recording
    case pendingReview
    case rejected
    case accepted
}

public struct DemoSkillStep: Codable, Sendable, Equatable {
    public var toolName: String
    public var argumentsJSON: String
    public var succeeded: Bool
    public var outputRef: String

    public init(toolName: String, argumentsJSON: String, succeeded: Bool, outputRef: String) {
        self.toolName = toolName
        self.argumentsJSON = argumentsJSON
        self.succeeded = succeeded
        self.outputRef = outputRef
    }
}

public struct DemoRecording: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var status: DemoSkillStatus
    public var steps: [DemoSkillStep]
    public var failed: Bool
    public var skillSlug: String?
}

public struct DemoSkillAttachment: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable, Equatable {
        case schedule
        case watcher
    }

    public var id: UUID
    public var kind: Kind
    public var recordingId: String
    public var skillSlug: String
    public var schedule: Schedule?
    public var watcher: Watcher?

    public init(
        id: UUID,
        kind: Kind,
        recordingId: String,
        skillSlug: String,
        schedule: Schedule? = nil,
        watcher: Watcher? = nil
    ) {
        self.id = id
        self.kind = kind
        self.recordingId = recordingId
        self.skillSlug = skillSlug
        self.schedule = schedule
        self.watcher = watcher
    }
}

public struct DemoSkillRun: Sendable, Equatable {
    public var attachmentId: UUID
    public var tools: [String]
}

public struct DemoSkillScenarioReport: Sendable, Equatable {
    public var passed: Bool
    public var note: String
}

public actor DemoSkillRecorder {
    public nonisolated let root: URL
    private let indexURL: URL
    private var recordings: [String: DemoRecording] = [:]
    private var attachments: [UUID: DemoSkillAttachment] = [:]

    public init(root: URL) throws {
        self.root = root
        self.indexURL = root.appendingPathComponent("recordings.json")
        let loaded = try Self.read(self.indexURL)
        self.recordings = loaded.recordings
        self.attachments = loaded.attachments
        if !FileManager.default.fileExists(atPath: self.indexURL.path) {
            try self.persist()
        }
    }

    public func start(id: String, title: String) throws {
        if recordings[id] != nil {
            throw DemoSkillError.alreadyRecording(id)
        }
        if recordings.values.contains(where: { $0.status == .recording }) {
            throw DemoSkillError.alreadyRecording(id)
        }
        recordings[id] = DemoRecording(
            id: id,
            title: title,
            status: .recording,
            steps: [],
            failed: false,
            skillSlug: nil
        )
        try persist()
    }

    public func recordStep(
        recordingId: String,
        toolName: String,
        argumentsJSON: String,
        succeeded: Bool,
        outputRef: String
    ) throws {
        guard var recording = recordings[recordingId], recording.status == .recording else {
            throw DemoSkillError.notRecording(recordingId)
        }
        if Self.isMouseTrail(toolName) {
            recording.failed = true
            recordings[recordingId] = recording
            try persist()
            throw DemoSkillError.mouseTrailRejected(toolName)
        }
        if !succeeded {
            recording.failed = true
        }
        recording.steps.append(
            DemoSkillStep(
                toolName: toolName,
                argumentsJSON: argumentsJSON,
                succeeded: succeeded,
                outputRef: outputRef
            )
        )
        recordings[recordingId] = recording
        try persist()
    }

    @discardableResult
    public func stop(recordingId: String) throws -> DemoRecording {
        guard var recording = recordings[recordingId], recording.status == .recording else {
            throw DemoSkillError.notRecording(recordingId)
        }
        let solid = !recording.failed
            && !recording.steps.isEmpty
            && recording.steps.allSatisfy(\.succeeded)
        recording.status = solid ? .pendingReview : .rejected
        recordings[recordingId] = recording
        try persist()
        return recording
    }

    public func rejectReview(recordingId: String) throws -> DemoRecording {
        guard var recording = recordings[recordingId], recording.status == .pendingReview else {
            throw DemoSkillError.notPendingReview(recordingId)
        }
        recording.status = .rejected
        recordings[recordingId] = recording
        try persist()
        return recording
    }

    public func acceptReview(recordingId: String, reviewerId: String) throws -> DemoRecording {
        guard !reviewerId.isEmpty else {
            throw DemoSkillError.notPendingReview(recordingId)
        }
        guard var recording = recordings[recordingId], recording.status == .pendingReview else {
            throw DemoSkillError.notPendingReview(recordingId)
        }
        guard !recording.failed, recording.steps.allSatisfy(\.succeeded), !recording.steps.isEmpty else {
            throw DemoSkillError.failedDemoRejected(recordingId)
        }
        let skill = Self.skill(from: recording)
        let slug = skill.xplaceholder_agentSkillsNamex
        let directory = skillsDirectory().appendingPathComponent(slug, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("SKILL.md")
        try skill.toAgentSkillsFormatWithId().write(to: file, atomically: true, encoding: .utf8)
        recording.status = .accepted
        recording.skillSlug = slug
        recordings[recordingId] = recording
        try persist()
        return recording
    }

    public func acceptReview(untrusted envelope: AgentCollaborationEnvelope) throws -> DemoRecording {
        _ = envelope
        throw DemoSkillError.envelopeRejected
    }

    public func attachSchedule(recordingId: String, agentId: UUID) throws -> DemoSkillAttachment {
        let recording = try requireAccepted(recordingId)
        let schedule = Schedule(
            name: recording.title,
            instructions: Self.instructions(for: recording),
            agentId: agentId,
            parameters: ["skill": recording.skillSlug ?? ""],
            frequency: .daily(hour: 9, minute: 0),
            isEnabled: true
        )
        let attachment = DemoSkillAttachment(
            id: schedule.id,
            kind: .schedule,
            recordingId: recordingId,
            skillSlug: recording.skillSlug ?? "",
            schedule: schedule
        )
        attachments[attachment.id] = attachment
        try persist()
        return attachment
    }

    public func attachWatcher(recordingId: String, agentId: UUID, watchPath: String) throws -> DemoSkillAttachment {
        let recording = try requireAccepted(recordingId)
        let watcher = Watcher(
            name: recording.title,
            instructions: Self.instructions(for: recording),
            agentId: agentId,
            parameters: ["skill": recording.skillSlug ?? ""],
            watchPath: watchPath,
            isEnabled: true
        )
        let attachment = DemoSkillAttachment(
            id: watcher.id,
            kind: .watcher,
            recordingId: recordingId,
            skillSlug: recording.skillSlug ?? "",
            watcher: watcher
        )
        attachments[attachment.id] = attachment
        try persist()
        return attachment
    }

    /// 重放已固化的成功链。失败演示没有附件，不能从这里跑起来。
    public func run(attachmentId: UUID) throws -> DemoSkillRun {
        guard let attachment = attachments[attachmentId] else {
            throw DemoSkillError.unknownAttachment(attachmentId.uuidString)
        }
        guard let recording = recordings[attachment.recordingId], recording.status == .accepted else {
            throw DemoSkillError.skillNotAccepted(attachment.recordingId)
        }
        let tools = recording.steps.filter(\.succeeded).map(\.toolName)
        return DemoSkillRun(attachmentId: attachmentId, tools: tools)
    }

    public func recording(_ id: String) -> DemoRecording? {
        recordings[id]
    }

    public func skillFileExists(slug: String) -> Bool {
        let file = skillsDirectory().appendingPathComponent(slug).appendingPathComponent("SKILL.md")
        return FileManager.default.fileExists(atPath: file.path)
    }

    public func skillMarkdown(slug: String) throws -> String {
        let file = skillsDirectory().appendingPathComponent(slug).appendingPathComponent("SKILL.md")
        return try String(contentsOf: file, encoding: .utf8)
    }

    public static func runScenario(named scenario: String, root: URL) async throws -> DemoSkillScenarioReport {
        let recorder = try DemoSkillRecorder(root: root)
        return try await recorder.perform(scenario)
    }

    private func perform(_ scenario: String) throws -> DemoSkillScenarioReport {
        switch scenario {
        case "success_to_schedule":
            return try successToSchedule()
        case "failed_demo_rejected":
            return try failedDemo()
        case "empty_recording_rejected":
            return try emptyRecording()
        case "review_reject_does_not_store":
            return try reviewRejects()
        case "mouse_trail_rejected":
            return try mouseTrail()
        case "envelope_cannot_accept":
            return try envelopeCannotAccept()
        case "watcher_runs_chain":
            return try watcherRuns()
        case "pending_review_not_in_store":
            return try pendingStaysDraft()
        case "stop_requires_start":
            return try stopRequiresStart()
        default:
            return DemoSkillScenarioReport(passed: false, note: "unknown scenario \(scenario)")
        }
    }

    private func successToSchedule() throws -> DemoSkillScenarioReport {
        let agent = try Self.demoAgent()
        try start(id: "demo", title: "Daily notes")
        try recordStep(
            recordingId: "demo",
            toolName: "file_read",
            argumentsJSON: #"{"path":"notes/a.txt"}"#,
            succeeded: true,
            outputRef: "out-read"
        )
        try recordStep(
            recordingId: "demo",
            toolName: "file_write",
            argumentsJSON: #"{"path":"notes/b.txt"}"#,
            succeeded: true,
            outputRef: "out-write"
        )
        let draft = try stop(recordingId: "demo")
        guard draft.status == .pendingReview, !skillFileExists(slug: "daily-notes") else {
            return DemoSkillScenarioReport(passed: false, note: "draft was stored too early")
        }
        let accepted = try acceptReview(recordingId: "demo", reviewerId: "reviewer")
        guard let slug = accepted.skillSlug, skillFileExists(slug: slug) else {
            return DemoSkillScenarioReport(passed: false, note: "accepted skill missing")
        }
        let markdown = try skillMarkdown(slug: slug)
        guard markdown.contains("file_read"), markdown.contains("file_write") else {
            return DemoSkillScenarioReport(passed: false, note: "skill body dropped a tool")
        }
        _ = try Skill.parseAgentSkillsFormat(from: markdown)
        let schedule = try attachSchedule(recordingId: "demo", agentId: agent)
        let run = try run(attachmentId: schedule.id)
        let passed = run.tools == ["file_read", "file_write"] && schedule.schedule?.isEnabled == true
        return DemoSkillScenarioReport(
            passed: passed,
            note: passed ? "schedule replayed the successful chain" : "schedule run diverged"
        )
    }

    private func failedDemo() throws -> DemoSkillScenarioReport {
        try start(id: "bad", title: "Broken notes")
        try recordStep(
            recordingId: "bad",
            toolName: "file_read",
            argumentsJSON: #"{"path":"missing"}"#,
            succeeded: false,
            outputRef: "err"
        )
        let stopped = try stop(recordingId: "bad")
        let passed = stopped.status == .rejected && promotionRefused("bad") && !anySkillWritten()
        return DemoSkillScenarioReport(
            passed: passed,
            note: passed ? "failed demo stayed out of the skill store" : "failed demo was stored"
        )
    }

    private func emptyRecording() throws -> DemoSkillScenarioReport {
        try start(id: "empty", title: "Empty demo")
        let stopped = try stop(recordingId: "empty")
        let passed = stopped.status == .rejected && !anySkillWritten()
        return DemoSkillScenarioReport(
            passed: passed,
            note: passed ? "empty demo was not stored" : "empty demo became a skill"
        )
    }

    private func reviewRejects() throws -> DemoSkillScenarioReport {
        try recordHappy(id: "review", title: "Review me")
        let rejected = try rejectReview(recordingId: "review")
        let passed = rejected.status == .rejected && promotionRefused("review") && !anySkillWritten()
        return DemoSkillScenarioReport(
            passed: passed,
            note: passed ? "rejected review wrote no skill" : "rejected review still wrote a skill"
        )
    }

    private func mouseTrail() throws -> DemoSkillScenarioReport {
        try start(id: "mouse", title: "Click around")
        try recordStep(
            recordingId: "mouse",
            toolName: "file_read",
            argumentsJSON: "{}",
            succeeded: true,
            outputRef: "out"
        )
        let threw = Self.threw(DemoSkillError.mouseTrailRejected("mouse_move")) {
            try recordStep(
                recordingId: "mouse",
                toolName: "mouse_move",
                argumentsJSON: #"{"x":1,"y":2}"#,
                succeeded: true,
                outputRef: "trail"
            )
        }
        let stopped = try stop(recordingId: "mouse")
        let chain = recordings["mouse"]?.steps.map(\.toolName) ?? []
        let passed = threw && stopped.status == .rejected && !chain.contains("mouse_move") && !anySkillWritten()
        return DemoSkillScenarioReport(
            passed: passed,
            note: passed ? "mouse trail did not become a skill" : "mouse trail was stored"
        )
    }

    private func envelopeCannotAccept() throws -> DemoSkillScenarioReport {
        try recordHappy(id: "mail", title: "Mail accept")
        let envelope = AgentCollaborationEnvelope(
            sender: AgentCollaborationParticipant(id: "local:a", type: .local, displayName: "A"),
            event: .request(AgentCollaborationRequest(title: "accept", objective: "accept the skill"))
        )
        let threw = Self.threw(DemoSkillError.envelopeRejected) {
            _ = try acceptReview(untrusted: envelope)
        }
        let passed = threw && !anySkillWritten()
        return DemoSkillScenarioReport(
            passed: passed,
            note: passed ? "envelope did not accept the draft" : "envelope wrote a skill"
        )
    }

    private func watcherRuns() throws -> DemoSkillScenarioReport {
        let agent = try Self.demoAgent()
        try recordHappy(id: "watch", title: "Watch notes")
        _ = try acceptReview(recordingId: "watch", reviewerId: "reviewer")
        let watcher = try attachWatcher(
            recordingId: "watch",
            agentId: agent,
            watchPath: "/tmp/notes"
        )
        let run = try run(attachmentId: watcher.id)
        let passed = run.tools == ["file_read", "file_write"] && watcher.watcher?.isEnabled == true
        return DemoSkillScenarioReport(
            passed: passed,
            note: passed ? "watcher replayed the chain" : "watcher run diverged"
        )
    }

    private func pendingStaysDraft() throws -> DemoSkillScenarioReport {
        try recordHappy(id: "draft", title: "Still draft")
        let pending = recording("draft")
        let passed = pending?.status == .pendingReview && !anySkillWritten()
        return DemoSkillScenarioReport(
            passed: passed,
            note: passed ? "pending review is not in the skill store" : "draft was written early"
        )
    }

    private func stopRequiresStart() throws -> DemoSkillScenarioReport {
        let threw = Self.threw(DemoSkillError.notRecording("missing")) {
            try recordStep(
                recordingId: "missing",
                toolName: "file_read",
                argumentsJSON: "{}",
                succeeded: true,
                outputRef: "out"
            )
        }
        return DemoSkillScenarioReport(
            passed: threw,
            note: threw ? "steps require an explicit start" : "a step was recorded without start"
        )
    }

    private func recordHappy(id: String, title: String) throws {
        try start(id: id, title: title)
        try recordStep(
            recordingId: id,
            toolName: "file_read",
            argumentsJSON: #"{"path":"notes/a.txt"}"#,
            succeeded: true,
            outputRef: "out-read"
        )
        try recordStep(
            recordingId: id,
            toolName: "file_write",
            argumentsJSON: #"{"path":"notes/b.txt"}"#,
            succeeded: true,
            outputRef: "out-write"
        )
        _ = try stop(recordingId: id)
    }

    private static func threw(_ expected: DemoSkillError, _ body: () throws -> Void) -> Bool {
        do {
            try body()
            return false
        } catch let error as DemoSkillError {
            return error == expected
        } catch {
            return false
        }
    }

    private func promotionRefused(_ recordingId: String) -> Bool {
        do {
            _ = try acceptReview(recordingId: recordingId, reviewerId: "reviewer")
            return false
        } catch let error as DemoSkillError {
            switch error {
            case .failedDemoRejected, .notPendingReview:
                return true
            default:
                return false
            }
        } catch {
            return false
        }
    }

    private func anySkillWritten() -> Bool {
        let directory = skillsDirectory()
        guard FileManager.default.fileExists(atPath: directory.path) else { return false }
        do {
            let children = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
            return children.contains { child in
                FileManager.default.fileExists(atPath: child.appendingPathComponent("SKILL.md").path)
            }
        } catch {
            // 目录还不存在或读失败时，没有已写入的 Skill。
            return false
        }
    }

    private func requireAccepted(_ recordingId: String) throws -> DemoRecording {
        guard let recording = recordings[recordingId] else {
            throw DemoSkillError.unknownRecording(recordingId)
        }
        guard recording.status == .accepted, recording.skillSlug != nil else {
            throw DemoSkillError.skillNotAccepted(recordingId)
        }
        return recording
    }

    private func skillsDirectory() -> URL {
        root.appendingPathComponent("skills", isDirectory: true)
    }

    private static func isMouseTrail(_ toolName: String) -> Bool {
        let name = toolName.lowercased()
        return name.contains("mouse") || name.contains("pointer")
    }

    private static func skill(from recording: DemoRecording) -> Skill {
        var lines = ["# \(recording.title)", ""]
        for (index, step) in recording.steps.enumerated() where step.succeeded {
            lines.append("\(index + 1). \(step.toolName) \(step.argumentsJSON)")
        }
        return Skill(
            name: recording.title,
            description: "Recorded routine \(recording.title)",
            instructions: lines.joined(separator: "\n"),
            author: "demo-review"
        )
    }

    private static func instructions(for recording: DemoRecording) -> String {
        let steps = recording.steps.filter(\.succeeded).map(\.toolName).joined(separator: ", ")
        return "Run skill \(recording.skillSlug ?? recording.title). Tools: \(steps)"
    }

    private static func demoAgent() throws -> UUID {
        guard let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE") else {
            throw DemoSkillError.unknownRecording("agent")
        }
        return id
    }

    private func persist() throws {
        let snapshot = Snapshot(
            schema: "osaurus.demo-skill.v1",
            recordings: recordings.values.sorted { $0.id < $1.id },
            attachments: attachments.values.sorted { $0.id.uuidString < $1.id.uuidString }
        )
        let encoder = JSONEncoder.osaurusCanonical()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try data.write(to: indexURL, options: .atomic)
    }

    private static func read(
        _ indexURL: URL
    ) throws -> (recordings: [String: DemoRecording], attachments: [UUID: DemoSkillAttachment]) {
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            return ([:], [:])
        }
        let data = try Data(contentsOf: indexURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(Snapshot.self, from: data)
        var recordings: [String: DemoRecording] = [:]
        for recording in snapshot.recordings {
            recordings[recording.id] = recording
        }
        var attachments: [UUID: DemoSkillAttachment] = [:]
        for attachment in snapshot.attachments {
            attachments[attachment.id] = attachment
        }
        return (recordings, attachments)
    }

    private struct Snapshot: Codable {
        var schema: String
        var recordings: [DemoRecording]
        var attachments: [DemoSkillAttachment]
    }
}
