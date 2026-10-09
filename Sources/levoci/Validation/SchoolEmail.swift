import Foundation

/// Costanti di business dell'istituto. Per cambiare scuola/dominio si modifica solo qui.
enum SchoolPolicy {
    static let domain = "itisgalileiroma.it"
    static let studentSuffix = ".stud@\(domain)"
    static let staffSuffix = "@\(domain)"
}

/// Email istituzionale già sanificata e validata, con il ruolo che ne deriva:
/// - `nome.cognome.stud@itisgalileiroma.it` → `.student`
/// - `nome.cognome@itisgalileiroma.it`       → `.teacher`
/// Se hai in mano una `SchoolEmail`, valore e ruolo sono garantiti coerenti.
struct SchoolEmail: ValidatedEmail, Equatable, Sendable {
    /// Valore canonico (trim + lowercase) da salvare e usare.
    let value: String
    /// Ruolo dedotto dal formato dell'email.
    let role: UserRole

    init(raw: String) throws {
        let (validatedEmail, _, _) = try Self.parseBase(raw)

        let escapedDomain = NSRegularExpression.escapedPattern(for: SchoolPolicy.domain)
        let role: UserRole

        if validatedEmail.hasSuffix(SchoolPolicy.studentSuffix) {
            guard validatedEmail.range(of: "^[a-z0-9._-]+\\.stud@\(escapedDomain)$", options: .regularExpression) != nil else {
                throw APIError.badRequest("Student \(Self.field) contains invalid characters")
            }
            role = .student
        } else if validatedEmail.hasSuffix(SchoolPolicy.staffSuffix) {
            guard validatedEmail.range(of: "^[a-z0-9._-]+@\(escapedDomain)$", options: .regularExpression) != nil else {
                throw APIError.badRequest("School \(Self.field) contains invalid characters")
            }
            role = .teacher
        } else {
            throw APIError.badRequest("The \(Self.field) must belong to the @\(SchoolPolicy.domain) domain")
        }

        self.value = validatedEmail
        self.role = role
    }
}
