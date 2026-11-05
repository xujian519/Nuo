/// Shared 1–80 character workspace-name validation used by Create/Activate.
enum WorkspaceNameValidation {
    static let maxLength = 80

    static func isValid(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= maxLength
    }
}
