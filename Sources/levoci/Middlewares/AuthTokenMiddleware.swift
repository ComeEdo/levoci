import Vapor
import Fluent
import JWT

/// Middleware per validare l'AuthToken (associato alle credenziali)
struct AuthTokenMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard let token = request.headers.bearerAuthorization?.token ?? request.headers.first(name: .authorization) else {
            throw APIError.unauthorized("Unauthorized - No token provided")
        }

        let payload: AuthTokenPayload
        do {
            payload = try await AuthToken(raw: token).verify(on: request)
        } catch {
            throw APIError.unauthorized("Unauthorized - Auth token expired or invalid", logOut: true)
        }

        guard let credentials = try await Credentials.find(payload.credentialsId, on: request.db) else {
            throw APIError.unauthorized("Unauthorized - Credentials not found", logOut: true)
        }

        // La versione si controlla PRIMA dello stato dell'email: un token revocato (es. dopo `updateEmail`, che incrementa
        // `tokenVersion`) deve essere rifiutato subito, senza far partire email né rivelare lo stato dell'account.
        guard credentials.tokenVersion == payload.authTokenVersion else {
            throw APIError.unauthorized("Unauthorized - Invalid auth token version", logOut: true)
        }

        guard credentials.isEmailVerified else {
            try await credentials.sendVerificationEmailIfNeeded(req: request)
            throw APIError.forbidden("Email not verified, check your inbox", logOut: true)
        }

        request.auth.login(credentials)

        return try await next.respond(to: request)
    }
}
