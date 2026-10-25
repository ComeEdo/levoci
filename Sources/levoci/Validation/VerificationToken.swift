import Foundation
import Vapor
import JWT

/// Token JWT sanificato e protetto da limiti di lunghezza.
/// Firma, scadenza, claim e formato li controlla direttamente JWTKit al momento dell'uso.
struct JWTToken<Payload: JWTPayload>: ValidatedField, Equatable, Sendable {
    static var minLength: Int { 10 }
    /// I JWT firmati con chiavi asimmetriche superano il limite di default di 255 caratteri.
    static var maxLength: Int { 2048 }
    
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
    
    /// Verifica la firma e la validità del token JWT tramite Vapor JWT.
    @discardableResult
    func verify(on req: Request) async throws -> Payload {
        try await req.jwt.verify(self.value, as: Payload.self)
    }

    /// I token non devono finire nei log.
    var description: String { "<redacted>" }
}

typealias VerificationToken = JWTToken<EmailVerificationPayload>
typealias AuthToken = JWTToken<AuthTokenPayload>
typealias UserToken = JWTToken<UserTokenPayload>
