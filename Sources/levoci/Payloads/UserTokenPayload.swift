import Foundation
import JWT
import JWTKit

/// Payload per il token di accesso utente a breve termine (15 minuti) associato a `users`
struct UserTokenPayload: JWTPayload, Sendable {
    var userId: UUID
    var userVersion: UUID
    var credentialsId: UUID
    var tokenVersion: UUID
    var roleId: Int
    var exp: ExpirationClaim
    var iat: IssuedAtClaim

    init(
        userId: UUID,
        userVersion: UUID,
        credentialsId: UUID,
        tokenVersion: UUID,
        roleId: Int,
        expirationDuration: TimeInterval = 15 * 60 // 15 minuti (15m)
    ) {
        let now = Date()
        self.userId = userId
        self.userVersion = userVersion
        self.credentialsId = credentialsId
        self.tokenVersion = tokenVersion
        self.roleId = roleId
        self.iat = IssuedAtClaim(value: now)
        self.exp = ExpirationClaim(value: now.addingTimeInterval(expirationDuration))
    }

    func verify(using algorithm: some JWTAlgorithm) async throws {
        try self.exp.verifyNotExpired()
    }
}
