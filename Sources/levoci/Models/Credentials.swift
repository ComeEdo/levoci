import Fluent
import Vapor

/// Modello Fluent per la tabella `credentials`
final class Credentials: Model, @unchecked Sendable, Authenticatable {
    static let schema = "credentials"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "email")
    private(set) var email: String

    @Field(key: "password")
    private(set) var passwordHash: String

    /// Versione dei token emessi. Generato automaticamente alla creazione e modificabile solo tramite `invalidateAllSessions(on:)`.
    @Field(key: "tokenVersion")
    private(set) var tokenVersion: UUID

    /// Email verificata. Alla creazione è sempre `false`; si imposta a `true` solo con `markEmailAsVerified(on:)`.
    @Field(key: "isEmailVerified")
    private(set) var isEmailVerified: Bool

    @Timestamp(key: "dateOfCreation", on: .create)
    var dateOfCreation: Date?

    @Timestamp(key: "lastUpdated", on: .update)
    var lastUpdated: Date?

    @Children(for: \.$credentials)
    var users: [User]

    init() {}
    
    init(id: UUID? = nil, email: some ValidatedEmail, passwordHash: PasswordHash) {
        self.id = id
        self.email = email.value
        self.passwordHash = passwordHash.value
        self.tokenVersion = UUID()
        self.isEmailVerified = false
    }
}

extension Credentials {
    /// Invia l'email di verifica solo se sono trascorsi almeno 5 minuti dall'ultimo invio (o se non è mai stata inviata).
    func sendVerificationEmailIfNeeded(req: Request) async throws {
        try await self.sendVerificationEmailIfNeeded(on: req.db, emailService: req.emailService, logger: req.logger)
    }

    /// Invia l'email di verifica con controllo di rate-limit (5 minuti) a livello di database e servizio email.
    func sendVerificationEmailIfNeeded(on db: any Database, emailService: any EmailServiceProtocol, logger: Logger? = nil) async throws {
        try await self.$users.load(on: db)
        let username = self.users.first?.username ?? self.email

        let fiveMinutesAgo = Date().addingTimeInterval(-5 * 60)     // 5 minuti fa
        let shouldSend = self.lastUpdated.map { $0 < fiveMinutesAgo } ?? true

        if shouldSend {
            try await emailService.sendVerificationEmail(to: self.email, credentialsId: self.requireID(), username: username)
            self.lastUpdated = Date()
            try await self.save(on: db)
        }
    }

    /// Invalida istantaneamente tutti gli AuthToken e UserToken emessi per questo account
    /// rigenerando il `tokenVersion` sul database.
    func invalidateAllSessions(on db: any Database) async throws {
        self.tokenVersion = UUID()
        try await self.save(on: db)
    }

    /// Segna l'email come verificata e salva sul database.
    /// È l'unico punto che può impostare `isEmailVerified` a `true`.
    func markEmailAsVerified(on db: any Database) async throws {
        self.isEmailVerified = true
        try await self.save(on: db)
    }

    /// Aggiorna l'hash della password da un `PasswordHash` tipizzato e invalida tutte le sessioni attive su database.
    func changePassword(to newHash: PasswordHash, on db: any Database) async throws {
        self.passwordHash = newHash.value
        try await self.invalidateAllSessions(on: db)
    }

    /// Aggiorna l'email a partire da qualsiasi tipo conforme a `ValidatedEmail`, reimposta `isEmailVerified` a `false`
    /// e invalida tutte le sessioni attive su database.
    func updateEmail(to newEmail: some ValidatedEmail, on db: any Database) async throws {
        self.email = newEmail.value
        self.isEmailVerified = false
        try await self.invalidateAllSessions(on: db)
    }
}
