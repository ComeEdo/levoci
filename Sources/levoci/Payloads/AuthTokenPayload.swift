import Foundation
import JWT
import JWTKit

/// Payload per il token di autenticazione a lungo termine (7 giorni) associato a `credentials`
struct AuthTokenPayload: JWTPayload, Sendable {
    var credentialsId: UUID
    var authTokenVersion: UUID
    var exp: ExpirationClaim
    var iat: IssuedAtClaim
    
    init(
        credentialsId: UUID,
        authTokenVersion: UUID,
        expirationDuration: TimeInterval = 7 * 24 * 60 * 60 // 7 giorni (1w)
    ) {
        let now = Date()
        self.credentialsId = credentialsId
        self.authTokenVersion = authTokenVersion
        self.iat = IssuedAtClaim(value: now)
        self.exp = ExpirationClaim(value: now.addingTimeInterval(expirationDuration))
    }
    
    func verify(using algorithm: some JWTAlgorithm) async throws {
        try self.exp.verifyNotExpired()
    }
}
