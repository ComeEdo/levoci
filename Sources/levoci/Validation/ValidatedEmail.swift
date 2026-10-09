import Foundation

/// Protocollo comune per tutti i tipi che rappresentano un indirizzo email validato e sanificato.
/// Eredita da `ValidatedField`, fornendo lunghezze limite e validazione comune della parte locale.
protocol ValidatedEmail: ValidatedField {
    static var field: InputField { get }
    
    /// Inizializza e valida l'email a partire da una stringa grezza ricevuta dal client.
    init(raw: String) throws
}

extension ValidatedEmail {
    static var field: InputField { InputField.email }
    
    // MARK: - Limiti di Default
    static var minLength: Int { 2 }
    static var maxLength: Int { 128 }

    // MARK: - Componenti dell'Indirizzo
    /// Parte locale dell'email (prima della '@').
    var localPart: String {
        String(value.prefix(while: { $0 != "@" }))
    }

    /// Dominio dell'email (dopo la '@').
    var domain: String {
        let parts = value.split(separator: "@", maxSplits: 1)
        return parts.count == 2 ? String(parts[1]) : ""
    }

    // MARK: - Parsing & Validazione Base
    /// Sanifica la stringa grezza e valida i vincoli universali di qualsiasi indirizzo email:
    /// non vuota, presenza di esattamente una '@', lunghezze min/max e parti locali/dominio conformi.
    /// Restituisce la tupla `(clean: String, localPart: String, domain: String)`.
    static func parseBase(_ raw: String) throws -> (clean: String, localPart: String, domain: String) {
        let clean = Sanitizer.email(raw)

        guard !clean.isEmpty else {
            throw APIError.badRequest("The \(field) is required")
        }

        try validateLength(clean, field: field)

        let parts = clean.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            throw APIError.badRequest("The \(field) must contain exactly one '@'")
        }

        let local = String(parts[0])
        let domain = String(parts[1])

        try validateLocalPart(local)
        try validateDomainPart(domain)

        return (clean, local, domain)
    }

    // MARK: - Validatori Specifici
    /// Controlla la conformità sintattica della sola parte locale (prima della '@').
    static func validateLocalPart(_ local: String) throws {
        guard !local.isEmpty else {
            throw APIError.badRequest("The \(field) local part cannot be empty")
        }
        // Standard WHATWG HTML5 / RFC 5322: caratteri unquoted consentiti per la parte locale (atext e punto)
        guard local.range(of: "^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+$", options: .regularExpression) != nil else {
            throw APIError.badRequest("The \(field) local part contains invalid characters")
        }
        let edgeCharacters: [Character] = [".", "_", "-"]
        if let first = local.first, edgeCharacters.contains(first) {
            throw APIError.badRequest("The \(field) cannot start with '.', '_' or '-'")
        }
        if let last = local.last, edgeCharacters.contains(last) {
            throw APIError.badRequest("The \(field) local part cannot end with '.', '_' or '-'")
        }
        if local.contains("..") || local.contains("__") {
            throw APIError.badRequest("The \(field) contains consecutive special characters")
        }
    }

    /// Controlla la conformità sintattica del dominio DNS (dopo la '@'):
    /// non vuoto, deve contenere almeno un punto (TLD), solo caratteri alfanumerici e trattini (niente underscore),
    /// le singole etichette non possono iniziare o finire con '-' e il TLD deve avere almeno 2 lettere.
    static func validateDomainPart(_ domain: String) throws {
        guard !domain.isEmpty else {
            throw APIError.badRequest("The \(field) domain cannot be empty")
        }
        if domain.contains("_") {
            throw APIError.badRequest("The \(field) domain cannot contain underscores")
        }
        if domain.contains("..") {
            throw APIError.badRequest("The \(field) domain contains consecutive special characters")
        }

        let labels = domain.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, !labels.contains(where: { $0.isEmpty }) else {
            throw APIError.badRequest("The \(field) domain must contain a valid domain extension")
        }
        for label in labels {
            if label.hasPrefix("-") || label.hasSuffix("-") {
                throw APIError.badRequest("The \(field) domain labels cannot start or end with a hyphen")
            }
            // Standard RFC 1034 / 1035 / WHATWG: le etichette di dominio consentono solo caratteri alfanumerici e trattini (incluso doppio trattino come Punycode xn--)
            guard label.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil else {
                throw APIError.badRequest("The \(field) domain contains invalid characters")
            }
        }
        guard let tld = labels.last, tld.count >= 2, tld.range(of: "^[a-z]{2,}$", options: .regularExpression) != nil else {
            throw APIError.badRequest("The \(field) domain extension is invalid")
        }
    }
}
