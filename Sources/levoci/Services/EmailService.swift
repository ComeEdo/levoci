import Vapor
import Smtp
import JWT

/// Protocollo per l'invio delle email di verifica istituzionale
protocol EmailServiceProtocol: Sendable {
    func sendVerificationEmail(to email: String, credentialsId: UUID, tokenVersion: UUID, username: String) async throws
}

/// Implementazione del servizio email tramite SMTP (Gmail)
final class EmailService: EmailServiceProtocol, Sendable {
    private let app: Application
    private let fromAddress: String
    private let fromName: String
    
    init(app: Application, fromAddress: String, fromName: String) {
        self.app = app
        self.fromAddress = fromAddress
        self.fromName = fromName
    }
    
    func sendVerificationEmail(to email: String, credentialsId: UUID, tokenVersion: UUID, username: String) async throws {
        let payload = EmailVerificationPayload(credentialsId: credentialsId, credentialsTokenVersion: tokenVersion)
        let token = try await app.jwt.keys.sign(payload)
        
        let verificationLink = app.publicBaseURL.endpoint(WebController.emailVerificationPath, queryItems: [URLQueryItem(name: "token", value: token)]).absoluteString
        
        struct VerificationEmailContext: Encodable {
            let username: String
            let verificationLink: String
        }
        
        let context = VerificationEmailContext(username: username, verificationLink: verificationLink)
        let view = try await app.view.render("Emails/verificationEmail", context)
        let htmlBody = String(buffer: view.data)
        
        let plainBody = """
        Ciao \(username),
        
        Grazie per esserti registrato a Voci di Corridoio! Per completare la registrazione conferma il tuo indirizzo email visitando il link seguente:
        
        \(verificationLink)
        
        Il link scade dopo un'ora. Se non hai richiesto tu la registrazione, ignora questa email.
        """
        
        let verificationEmail = try Email(
            from: EmailAddress(address: fromAddress, name: fromName),
            to: [EmailAddress(address: email, name: username)],
            subject: "Conferma il tuo indirizzo email",
            body: htmlBody,
            plain: plainBody,
            isBodyHtml: true
        )
        
        app.logger.info("[Email] Invio email di verifica per credentialsId \(credentialsId)")
        try await app.smtp.send(verificationEmail)
    }
}

// MARK: - Application & Request Extensions

extension Application {
    struct EmailServiceKey: StorageKey {
        typealias Value = any EmailServiceProtocol
    }
    
    var emailService: any EmailServiceProtocol {
        get {
            guard let service = self.storage[EmailServiceKey.self] else {
                fatalError("EmailService non registrato in Application. Chiamare configureSmtp in configure.swift prima dell'uso.")
            }
            return service
        }
        set {
            self.storage[EmailServiceKey.self] = newValue
        }
    }
}

extension Request {
    var emailService: any EmailServiceProtocol {
        self.application.emailService
    }
}
