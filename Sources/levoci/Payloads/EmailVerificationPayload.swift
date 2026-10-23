import Foundation
import JWT
import JWTKit

/// Payload per il token di verifica email (1 ora)
struct EmailVerificationPayload: JWTPayload, Sendable {
    var credentialsId: UUID
    /// Versione dei token al momento dell'emissione. Se le credenziali vengono invalidate
    /// (cambio password, cambio email, logout-all), il `tokenVersion` sul database cambia
    /// e questo token viene rifiutato dalla POST di conferma.
    var credentialsTokenVersion: UUID
    var exp: ExpirationClaim
    var iat: IssuedAtClaim
    
    init(
        credentialsId: UUID,
        credentialsTokenVersion: UUID,
        expirationDuration: TimeInterval = 60 * 60 // 1 ora (1h)
    ) {
        let now = Date()
        self.credentialsId = credentialsId
        self.credentialsTokenVersion = credentialsTokenVersion
        self.iat = IssuedAtClaim(value: now)
        self.exp = ExpirationClaim(value: now.addingTimeInterval(expirationDuration))
    }
    
    func verify(using algorithm: some JWTAlgorithm) async throws {
        try self.exp.verifyNotExpired()
    }
}
