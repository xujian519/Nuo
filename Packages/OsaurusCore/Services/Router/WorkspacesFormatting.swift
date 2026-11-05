//
//  WorkspacesFormatting.swift
//  osaurus
//
//  ISO-8601 timestamp helpers shared by the workspace surfaces. Lived inside
//  the deleted `WorkspacesView`; re-homed here because `WorkspacesService`
//  still parses router timestamps with it.
//

import Foundation

enum WorkspacesFormatting {
    /// ISO-8601 timestamp → "Aug 23, 2026"; nil when unparseable.
    static func date(_ raw: String) -> String? {
        guard let date = parse(raw) else { return nil }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    /// ISO-8601 timestamp (with or without fractional seconds) → `Date`.
    nonisolated static func parse(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return fractional.date(from: raw) ?? plain.date(from: raw)
    }
}
