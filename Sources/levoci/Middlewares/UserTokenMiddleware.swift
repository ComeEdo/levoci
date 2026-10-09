import Vapor
import Fluent
import JWT

/// Middleware per validare lo UserToken (associato al profilo utente attivo)
struct UserTokenMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard let token = request.headers.bearerAuthorization?.token ?? request.headers.first(name: .authorization) else {
            throw APIError.badRequest("Unauthorized - No token provided")
        }

        let payload: UserTokenPayload
        do {
            payload = try await request.jwt.verify(token)
        } catch {
            throw APIError.unauthorized("Unauthorized - Token expired", userLogOut: true)
        }

        guard let user = try await User.query(on: request.db)
            .filter(\.$id == payload.userId)
            .with(\.$credentials)
            .first() else {
            throw APIError.unauthorized("Unauthorized - User not found", userLogOut: true)
        }

        guard let credentials = user.credentials, try credentials.requireID() == payload.credentialsId else {
            throw APIError.forbidden("Forbidden - Invalid credentials", userLogOut: true)
        }

        guard credentials.tokenVersion == payload.tokenVersion else {
            throw APIError.unauthorized("Unauthorized - Invalid token version", logOut: true)
        }

        request.shouldUpdateUserToken = (user.userVersion != payload.userVersion)

        request.auth.login(user)
        request.auth.login(credentials)

        let response = try await next.respond(to: request)

        if request.shouldUpdateUserToken {
            response.headers.add(name: "X-Update-User-And-Token", value: "true")
        }

        return response
    }
}

// MARK: - Request Extension per UserToken

extension Request {
    struct ShouldUpdateUserTokenKey: StorageKey {
        typealias Value = Bool
    }

    /// Indica se lo userVersion sul DB differisce da quello nel token e richiede aggiornamento al client
    var shouldUpdateUserToken: Bool {
        get { self.storage[ShouldUpdateUserTokenKey.self] ?? false }
        set { self.storage[ShouldUpdateUserTokenKey.self] = newValue }
    }
}
