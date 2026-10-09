import Foundation
import JWT
import JWTKit

/// Payload per il token di verifica email (1 ora)
struct EmailVerificationPayload: JWTPayload, Sendable {
    var credentialsId: UUID
    var exp: ExpirationClaim
    var iat: IssuedAtClaim

    init(
        credentialsId: UUID,
        expirationDuration: TimeInterval = 60 * 60 // 1 ora (1h)
    ) {
        let now = Date()
        self.credentialsId = credentialsId
        self.iat = IssuedAtClaim(value: now)
        self.exp = ExpirationClaim(value: now.addingTimeInterval(expirationDuration))
    }

    func verify(using algorithm: some JWTAlgorithm) async throws {
        try self.exp.verifyNotExpired()
    }
}
