import Foundation

/// Internal text helpers shared by entity initializers.
enum DomainText {
    /// Trims surrounding whitespace and rejects names that are empty once trimmed.
    static func validatedName(_ raw: String, context: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ValidationError.emptyName(context: context) }
        return trimmed
    }
}
