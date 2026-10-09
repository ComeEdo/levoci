import Vapor
import Smtp
import JWT

/// Protocollo per l'invio delle email di verifica istituzionale
protocol EmailServiceProtocol: Sendable {
    func sendVerificationEmail(to email: String, credentialsId: UUID, username: String) async throws
}

/// Implementazione del servizio email tramite SMTP (Gmail)
final class EmailService: EmailServiceProtocol, Sendable {
    private let app: Application

    init(app: Application) {
        self.app = app
    }

    func sendVerificationEmail(to email: String, credentialsId: UUID, username: String) async throws {
        let payload = EmailVerificationPayload(credentialsId: credentialsId)
        let token = try await app.jwt.keys.sign(payload)
        
        let baseURL = "http://\(app.http.server.configuration.hostname):\(app.http.server.configuration.port)"
        let verificationLink = "\(baseURL)/verifyEmail/\(token)"

        let fromAddress = try requireEnv("SMTP_USERNAME")
        let fromName = Environment.get("SMTP_FROM_NAME") ?? "Levoci"
        let verificationEmail = try Email(
            from: EmailAddress(address: fromAddress, name: fromName),
            to: [EmailAddress(address: email, name: username)],
            subject: "Conferma il tuo indirizzo email",
            body: """
            Ciao \(username),
            
            Per completare la registrazione conferma il tuo indirizzo email visitando il link seguente:
            
            \(verificationLink)
            
            Il link scade dopo un'ora. Se non hai richiesto tu la registrazione, ignora questa email.
            <div style="font-family: Arial, sans-serif;">
                <h1 style="text-align: center;">Ciao, \(username)!</h1>
                <p>Grazie per esserti registrato! Verifica il tuo indirizzo email cliccando sul link qui sotto, il link scade dopo un'ora. Se non sei tu ad aver richiesto la registrazione, ignora questa email.</p>
                <p><a href="\(verificationLink)" style="color:rgb(255, 255, 0); text-decoration: none;">Verifica Email</a></p>
                <p style="margin-top: 20px;">Questo link scadrà tra 1 ora.</p>
                <hr />
                <div style="text-align: center; margin-top: 20px;">
                    <img src="cid:logo" alt="Le Voci Logo" style="width: 150px; height: auto;" />
                </div>
            </div>
            """,
            isBodyHtml: true
        )

        app.logger.info("[Email] Invio email di verifica a \(email) (Username: \(username))")
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
