import Foundation
import Vapor
import JWT

/// Token di verifica email sanificato e protetto da limiti di lunghezza.
/// Firma, scadenza, claim e formato li controlla direttamente JWTKit al momento dell'uso.
struct VerificationToken: ValidatedField, Equatable, Sendable {
    static let minLength = 10
    /// I JWT firmati con chiavi asimmetriche superano il limite di default di 255 caratteri.
    static let maxLength = 2048
    
    /// Valore canonico (sanificato) da passare alla verifica JWT.
    let value: String
    
    init(raw: String) throws {
        let clean = Sanitizer.text(raw)
        let field = InputField.token
        
        guard !clean.isEmpty else {
            throw APIError.badRequest("The \(field) is required")
        }
        try Self.validateLength(clean, field: field)
        
        self.value = clean
    }
    
    /// Verifica la firma e la validità del token JWT tramite Vapor JWT, restituendo il payload di verifica email.
    @discardableResult
    func verify(on req: Request) async throws -> EmailVerificationPayload {
        try await req.jwt.verify(self.value, as: EmailVerificationPayload.self)
    }
    
    /// Il token autorizza una verifica: non deve finire nei log.
    var description: String { "<redacted>" }
}
