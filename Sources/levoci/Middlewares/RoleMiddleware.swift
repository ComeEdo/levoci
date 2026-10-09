import Vapor

/// Middleware per autorizzare l'accesso alle tratte in base al ruolo dell'utente (`UserRole`).
/// Viene applicato a valle di `UserTokenMiddleware` che inietta il profilo `User` in `request.auth`.
struct RoleMiddleware: AsyncMiddleware {
    /// Insieme di ruoli autorizzati ad accedere alla risorsa
    let allowedRoles: Set<UserRole>

    /// Inizializza il middleware con uno o più ruoli ammessi tramite sintassi variadica.
    /// Esempio: `RoleMiddleware(.student)` o `RoleMiddleware(.teacher, .admin)`
    init(_ roles: UserRole...) {
        self.allowedRoles = Set(roles)
    }

    /// Inizializza il middleware con un array di ruoli ammessi
    init(_ roles: [UserRole]) {
        self.allowedRoles = Set(roles)
    }

    /// Inizializza il middleware con un set di ruoli ammessi
    init(_ roles: Set<UserRole>) {
        self.allowedRoles = roles
    }

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard let user: User = request.auth.get() else {
            throw APIError.unauthorized("Unauthorized - Profile authentication required")
        }

        guard let userRole = user.roleType, allowedRoles.contains(userRole) else {
            throw APIError.forbidden("Forbidden - Insufficient permissions")
        }

        return try await next.respond(to: request)
    }
}
