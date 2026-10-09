import Vapor

/// Risposta leggera con solo un messaggio informativo.
/// Utilizzata per conferme di operazioni senza payload dati
/// (es. "Password aggiornata", "Email inviata").
///
/// Esempio:
/// ```swift
/// return MessageResponse("Password aggiornata con successo")
/// ```
/// Produce:
/// ```json
/// HTTP 200 OK
/// { "message": "Password aggiornata con successo" }
/// ```
struct MessageResponse: Content {       ///probabilmente verra tolto
    let message: String

    init(_ message: String) {
        self.message = message
    }
}
