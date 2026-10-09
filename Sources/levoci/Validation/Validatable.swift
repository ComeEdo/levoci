import Vapor

/// REGOLA DEL PROGETTO: ogni DTO che riceve input dal client deve conformarsi a questo protocollo.
///
/// - Il DTO resta una struct con `String` grezze (è il formato JSON sul filo).
/// - `validated()` costruisce i tipi validati (`Username`, `PersonName`, `Password`, ...) e restituisce
///   un oggetto `Validated` che contiene SOLO quelli.
/// - Il controller legge il body esclusivamente con `req.validatedBody(...)`: così non può mai usare
///   dati grezzi non sanificati. Non usare `req.content.decode(...)` nei controller
///   (lo verifica `ArchitectureRulesTests`).
///
/// Regola per i campi: un tipo per ogni campo con regole proprie, con `init(raw:) throws` che
/// sanifica e valida nello stesso posto (vedi cartella `Validation/`).
protocol ValidatableRequest: Content {
    associatedtype Validated: Sendable
    func validated() throws -> Validated
}

extension Request {
    /// Decodifica il body JSON e restituisce solo il valore sanificato e validato.
    func validatedBody<T: ValidatableRequest>(_ type: T.Type) throws -> T.Validated {
        try content.decode(T.self).validated()
    }
}

/// Protocollo comune per tutti i campi validati che incapsulano un valore primitivo (`String`).
/// Garantisce che il tipo sia `Sendable`, abbia una proprietà `value` canonica e adotti `CustomStringConvertible`.
protocol ValidatedField: Sendable, CustomStringConvertible {
    /// Lunghezza minima consentita per il valore del campo.
    static var minLength: Int { get }

    /// Lunghezza massima consentita per il valore del campo.
    static var maxLength: Int { get }

    /// Valore canonico (sanificato e validato) pronto per l'uso e la persistenza.
    var value: String { get }
}

extension ValidatedField {
    static var minLength: Int { 1 }
    static var maxLength: Int { 255 }

    var description: String {
        value
    }

    /// Valida che la lunghezza della stringa rispetti i limiti `minLength` e `maxLength` del campo.
    static func validateLength(_ string: String, field: InputField) throws {
        guard string.count >= minLength && string.count <= maxLength else {
            throw APIError.badRequest("The \(field) must be between \(minLength) and \(maxLength) characters long")
        }
    }
}
