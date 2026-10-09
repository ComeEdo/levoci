import Vapor
import Fluent
import JWT

/// Middleware per validare l'AuthToken (associato alle credenziali)
struct AuthTokenMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard let token = request.headers.bearerAuthorization?.token ?? request.headers.first(name: .authorization) else {
            throw APIError.badRequest("Unauthorized - No token provided")
        }

        let payload: AuthTokenPayload
        do {
            payload = try await request.jwt.verify(token)
        } catch {
            throw APIError.unauthorized("Unauthorized - Auth token expired or invalid", logOut: true)
        }

        guard let credentials = try await Credentials.find(payload.credentialsId, on: request.db) else {
            throw APIError.unauthorized("Unauthorized - Credentials not found", logOut: true)
        }

        if !credentials.isEmailVerified {
            try await credentials.sendVerificationEmailIfNeeded(req: request)
            throw APIError.forbidden("Email not verified check you inbox", logOut: true)
        }

        if credentials.tokenVersion != payload.tokenVersion {
            throw APIError.forbidden("Forbidden - Invalid auth token version", logOut: true)
        }

        request.auth.login(credentials)

        return try await next.respond(to: request)
    }
}
