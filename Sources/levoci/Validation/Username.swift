import Foundation

/// Username già sanificato e validato.
/// ⚠️ È CASE-SENSITIVE per scelta di progetto: `Mario` e `mario` sono due username diversi.
/// Non applicare `lowercased()` qui.
struct Username: ValidatedField, Equatable, Sendable {
    static let minLength = 2
    static let maxLength = 40

    /// Valore canonico (sanificato) da salvare e usare.
    let value: String

    init(raw: String) throws {
        let clean = Sanitizer.text(raw)
        let field = InputField.username

        guard !clean.isEmpty else {
            throw APIError.badRequest("The \(field) is required")
        }
        // Alfanumerico, punto, underscore
        guard clean.range(of: "^[a-zA-Z0-9._]+$", options: .regularExpression) != nil else {
            throw APIError.badRequest("The \(field) contains invalid characters")
        }
        try Self.validateLength(clean, field: field)

        self.value = clean
    }
}
