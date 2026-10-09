import Vapor

/// Payload JSON restituito al client in caso di errore.
/// Il codice di stato HTTP porta la semantica; il body fornisce dettagli.
///
/// Esempi:
/// ```json
/// HTTP 401 Unauthorized (Account logout)
/// {
///     "error": "unauthorized",
///     "message": "Auth token expired or invalid",
///     "logOut": true
/// }
///
/// HTTP 401 Unauthorized (User profile logout)
/// {
///     "error": "unauthorized",
///     "message": "Unauthorized - Invalid token version",
///     "userLogOut": true
/// }
/// ```
struct ErrorResponse: Content {
    /// Codice errore machine-readable derivato dallo status HTTP (es. "unauthorized", "bad_request")
    let error: String
    /// Descrizione human-readable dell'errore
    let message: String
    /// Flag opzionale per il client: forzare il logout globale dell'account
    let logOut: Bool?
    /// Flag opzionale per il client: forzare il logout dello specifico profilo utente attivo
    let userLogOut: Bool?
}

/// Errore applicativo personalizzato conforme ad `AbortError` e `Sendable`.
/// Utilizzato da middleware e controller per restituire risposte d'errore semantiche.
struct APIError: AbortError, Sendable {
    var status: HTTPResponseStatus
    var reason: String
    var logOut: Bool?
    var userLogOut: Bool?

    init(
        _ status: HTTPResponseStatus,
        message: String,
        logOut: Bool? = nil,
        userLogOut: Bool? = nil
    ) {
        self.status = status
        self.reason = message
        self.logOut = logOut
        
        // REGOLA DI INTEGRITÀ:
        // Se c'è un logout globale dell'account, il profilo utente non ha senso di esistere
        if self.logOut == true {
            self.userLogOut = nil
        } else {
            self.userLogOut = userLogOut
        }
    }

    static func badRequest(_ message: String) -> APIError {
        APIError(.badRequest, message: message)
    }

    static func unauthorized(_ message: String, logOut: Bool = false, userLogOut: Bool = false) -> APIError {
        APIError(.unauthorized, message: message, logOut: logOut ? true : nil, userLogOut: userLogOut ? true : nil)
    }

    static func forbidden(_ message: String, logOut: Bool = false, userLogOut: Bool = false) -> APIError {
        APIError(.forbidden, message: message, logOut: logOut ? true : nil, userLogOut: userLogOut ? true : nil)
    }

    static func notFound(_ message: String) -> APIError {
        APIError(.notFound, message: message)
    }

    static func conflict(_ message: String) -> APIError {
        APIError(.conflict, message: message)
    }

    static func internalServerError(_ message: String = "Internal Server Error") -> APIError {
        APIError(.internalServerError, message: message)
    }
}

/// Converte un `HTTPResponseStatus` nel codice errore machine-readable snake_case
/// (es. `.unauthorized` → `"unauthorized"`, `.badRequest` → `"bad_request"`)
private func errorCode(for status: HTTPResponseStatus) -> String {
    switch status {
    case .badRequest:          return "bad_request"
    case .unauthorized:        return "unauthorized"
    case .forbidden:           return "forbidden"
    case .notFound:            return "not_found"
    case .conflict:            return "conflict"
    case .unprocessableEntity: return "unprocessable_entity"
    case .tooManyRequests:     return "too_many_requests"
    case .internalServerError: return "internal_server_error"
    default:                   return "error"
    }
}

/// Middleware globale che intercetta tutti gli errori e li serializza in un
/// formato JSON uniforme con il codice di stato HTTP appropriato.
///
/// Deve essere registrato come primo middleware in `configure.swift`:
/// ```swift
/// app.middleware.use(CustomErrorMiddleware())
/// ```
struct CustomErrorMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        do {
            return try await next.respond(to: request)
        } catch let apiError as APIError {
            let errorBody = ErrorResponse(
                error: errorCode(for: apiError.status),
                message: apiError.reason,
                logOut: apiError.logOut,
                userLogOut: apiError.userLogOut
            )
            return try await errorBody.encodeResponse(status: apiError.status, for: request)
        } catch let abort as any AbortError {
            let errorBody = ErrorResponse(
                error: errorCode(for: abort.status),
                message: abort.reason,
                logOut: nil,
                userLogOut: nil
            )
            return try await errorBody.encodeResponse(status: abort.status, for: request)
        } catch {
            request.logger.error("Errore imprevisto non gestito: \(error)")
            let errorBody = ErrorResponse(
                error: "internal_server_error",
                message: "Internal Server Error",
                logOut: nil,
                userLogOut: nil
            )
            return try await errorBody.encodeResponse(status: .internalServerError, for: request)
        }
    }
}
