import Foundation

/// Nome o cognome già sanificato e validato.
/// Se hai in mano un `PersonName`, il valore è garantito valido: l'unico modo di crearlo è `init(raw:field:)`.
struct PersonName: ValidatedField, Equatable, Sendable {
    static let minLength = 1
    static let maxLength = 128

    /// Valore canonico (sanificato) da salvare e usare.
    let value: String

    /// - Parameters:
    ///   - raw: stringa grezza ricevuta dal client
    ///   - field: `.name` oppure `.surname`, usato per i messaggi di errore
    init(raw: String, field: InputField) throws {
        let clean = Sanitizer.personName(raw)

        guard !clean.isEmpty else {
            throw APIError.badRequest("The \(field) is required")
        }
        // Supporta lettere accentate, apostrofi singoli e spazi
        guard clean.range(of: "^[\\p{L}' ]+$", options: .regularExpression) != nil else {
            throw APIError.badRequest("The \(field) contains invalid characters")
        }
        guard clean.range(of: "\\s{2,}", options: .regularExpression) == nil else {
            throw APIError.badRequest("The \(field) cannot have repeating spaces")
        }
        try Self.validateLength(clean, field: field)
        if clean.contains("''") {
            throw APIError.badRequest("The \(field) contains consecutive apostrophes")
        }
        if clean.contains(" '") || clean.contains("' ") {
            throw APIError.badRequest("The \(field) contains isolated apostrophes")
        }
        if clean.hasPrefix("'") || clean.hasSuffix("'") {
            throw APIError.badRequest("The \(field) cannot start or end with an apostrophe")
        }

        self.value = clean
    }
}
