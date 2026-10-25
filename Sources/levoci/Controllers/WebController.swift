import Vapor
import Fluent

/// Pagine web servite dal server. Non fanno parte dell'API JSON.
struct WebController: RouteCollection {
    /// Percorso base unico (Single Source of Truth) per la verifica email
    static let emailVerificationPath = "emailVerifications"

    func boot(routes: any RoutesBuilder) throws {
        let verifications = routes.grouped(.constant(Self.emailVerificationPath))
        verifications.get(use: beginEmailVerification)
        verifications.get("confirmation", use: emailVerificationConfirmationPage)
        verifications.get("duplicate", use: emailVerificationDuplicatePage)
        verifications.post("confirmation", use: confirmEmailVerification)
        verifications.get("success", use: emailVerificationSuccessPage)
    }

    private static let emailVerificationCookieName = "emailVerificationToken"
    private static let emailVerificationCookieLifetime = 10 * 60

    /// Valida il link senza modificare le credenziali e sposta il JWT in un cookie HttpOnly.
    /// Se la mail è già verificata, facciamo un redirect verso la pagina dedicata e rimuoviamo ogni token dal link.
    @Sendable
    func beginEmailVerification(req: Request) async throws -> Response {
        let token: VerificationToken
        let payload: EmailVerificationPayload
        do {
            token = try req.validatedQuery(EmailVerificationQuery.self)
            payload = try await token.verify(on: req)
        } catch {
            return try await renderedResponse(named: "verifyEmailInvalid", status: .badRequest, for: req)
        }

        guard let credentials = try await Credentials.find(payload.credentialsId, on: req.db) else {
            return try await renderedResponse(named: "verifyEmailInvalid", status: .badRequest, for: req)
        }

        guard payload.credentialsTokenVersion == credentials.tokenVersion else {
            return try await renderedResponse(named: "verifyEmailInvalid", status: .badRequest, for: req)
        }

        guard !credentials.isEmailVerified else {
            var response = req.redirect(to: "/\(Self.emailVerificationPath)/duplicate")
            response.cookies[Self.emailVerificationCookieName] = expiredVerificationCookie(for: req)
            addSensitiveResponseHeaders(to: &response)
            return response
        }

        var response = req.redirect(to: "/\(Self.emailVerificationPath)/confirmation")
        response.cookies[Self.emailVerificationCookieName] = .init(
            string: token.value,
            maxAge: Self.emailVerificationCookieLifetime,
            path: "/\(Self.emailVerificationPath)",
            isSecure: Self.isSecure(for: req),
            isHTTPOnly: true,
            sameSite: .lax
        )
        addSensitiveResponseHeaders(to: &response)
        return response
    }

    @Sendable
    func emailVerificationConfirmationPage(req: Request) async throws -> Response {
        guard req.cookies[Self.emailVerificationCookieName] != nil else {
            return try await renderedResponse(named: "verifyEmailInvalid", status: .badRequest, for: req)
        }
        return try await renderedResponse(named: "verifyEmail", for: req)
    }

    /// La POST è l'unica richiesta che modifica in modo permanente lo stato della verifica.
    @Sendable
    func confirmEmailVerification(req: Request) async throws -> Response {
        guard let cookie = req.cookies[Self.emailVerificationCookieName] else {
            return try await renderedResponse(named: "verifyEmailInvalid", status: .badRequest, for: req)
        }

        let payload: EmailVerificationPayload
        do {
            payload = try await VerificationToken(raw: cookie.string).verify(on: req)
        } catch {
            return try await renderedResponse(named: "verifyEmailInvalid", status: .badRequest, for: req)
        }

        guard let credentials = try await Credentials.find(payload.credentialsId, on: req.db) else {
            return try await renderedResponse(named: "verifyEmailInvalid", status: .badRequest, for: req)
        }

        // Se il tokenVersion nel JWT non corrisponde a quello attuale delle credenziali,
        // il token è stato invalidato (cambio password, cambio email o logout-all).
        guard payload.credentialsTokenVersion == credentials.tokenVersion else {
            return try await renderedResponse(named: "verifyEmailInvalid", status: .badRequest, for: req)
        }

        guard !credentials.isEmailVerified else {
            var response = req.redirect(to: "/\(Self.emailVerificationPath)/duplicate")
            response.cookies[Self.emailVerificationCookieName] = expiredVerificationCookie(for: req)
            addSensitiveResponseHeaders(to: &response)
            return response
        }

        try await credentials.markEmailAsVerified(on: req.db)
        req.logger.info("Email verificata con successo per credentialsId: \(payload.credentialsId)")

        var response = req.redirect(to: "/\(Self.emailVerificationPath)/success")
        response.cookies[Self.emailVerificationCookieName] = expiredVerificationCookie(for: req)
        addSensitiveResponseHeaders(to: &response)
        return response
    }

    @Sendable
    func emailVerificationDuplicatePage(req: Request) async throws -> Response {
        try await renderedResponse(named: "verifyEmailAlreadyVerified", for: req)
    }

    @Sendable
    func emailVerificationSuccessPage(req: Request) async throws -> Response {
        try await renderedResponse(named: "verifyEmailSuccess", for: req)
    }

    private func renderedResponse(named viewName: String, status: HTTPResponseStatus = .ok, for req: Request) async throws -> Response {
        let view = try await req.view.render(viewName)
        var response = try await view.encodeResponse(for: req)
        response.status = status
        addSensitiveResponseHeaders(to: &response)
        return response
    }

    private func addSensitiveResponseHeaders(to response: inout Response) {
        response.headers.replaceOrAdd(name: .cacheControl, value: "no-store, private")
        response.headers.replaceOrAdd(name: "Pragma", value: "no-cache")
        response.headers.replaceOrAdd(name: "Referrer-Policy", value: "no-referrer")
    }

    private func expiredVerificationCookie(for req: Request) -> HTTPCookies.Value {
        .init(
            string: "",
            expires: Date(timeIntervalSince1970: 0),
            maxAge: 0,
            path: "/\(Self.emailVerificationPath)",
            isSecure: Self.isSecure(for: req),
            isHTTPOnly: true,
            sameSite: .lax
        )
    }
    
    /// `Secure` dipende dall'URL pubblico (`PUBLIC_BASE_URL`), non dall'ambiente: dietro Apache l'app vede solo HTTP,
    /// ma sono gli utenti, collegati in HTTPS, a ricevere il cookie.
    private static func isSecure(for req: Request) -> Bool {
        req.publicBaseURL.isSecure
    }
}
