import Foundation
import Fluent
import Vapor
import VaporTesting
import Testing
@testable import levoci

enum TestProjectPaths {
    enum Error: Swift.Error, CustomStringConvertible {
        case projectRootNotFound(filePath: String)

        var description: String {
            switch self {
            case .projectRootNotFound(let filePath):
                return "Unable to locate Package.swift above test file: \(filePath)"
            }
        }
    }

    static func root(from filePath: String = #filePath) throws -> URL {
        var directory = URL(fileURLWithPath: filePath).deletingLastPathComponent()

        while directory.path != "/" {
            let packageManifest = directory.appendingPathComponent("Package.swift")
            let sourcesDirectory = directory.appendingPathComponent("Sources", isDirectory: true)

            if FileManager.default.fileExists(atPath: packageManifest.path),
               FileManager.default.fileExists(atPath: sourcesDirectory.path) {
                return directory
            }

            directory.deleteLastPathComponent()
        }

        throw Error.projectRootNotFound(filePath: filePath)
    }
}

struct TestEmail: ValidatedEmail {
    let value: String

    init(_ value: String) { self.value = value }
    init(raw: String) throws { self.value = raw }
}

final class MockEmailService: EmailServiceProtocol, @unchecked Sendable {
    struct SentEmail: Sendable {
        let email: String
        let credentialsId: UUID
        let tokenVersion: UUID
        let username: String
    }

    private let lock = NSLock()
    private var _sentEmails: [SentEmail] = []

    var sentEmails: [SentEmail] {
        lock.withLock { _sentEmails }
    }

    private func recordSentEmail(_ item: SentEmail) {
        lock.withLock {
            _sentEmails.append(item)
        }
    }

    func sendVerificationEmail(to email: String, credentialsId: UUID, tokenVersion: UUID, username: String) async throws {
        recordSentEmail(SentEmail(email: email, credentialsId: credentialsId, tokenVersion: tokenVersion, username: username))
    }
}

extension Application {
    var mockEmailService: MockEmailService? {
        self.emailService as? MockEmailService
    }
}

func makeTestUser(
    name: String = "Mario",
    surname: String = "Rossi",
    username: String,
    role: UserRole = .student,
    classId: UUID? = nil,
    credentialsId: UUID? = nil
) throws -> User {
    User(
        name: try PersonName(raw: name, field: .name),
        surname: try PersonName(raw: surname, field: .surname),
        username: try Username(raw: username),
        role: role,
        classId: classId,
        credentialsId: credentialsId
    )
}

func withTestApp(_ test: (Application) async throws -> Void) async throws {
    let projectDir = try TestProjectPaths.root(from: #filePath).path
    let app = try await Application.make(.testing)
    app.directory = DirectoryConfiguration(workingDirectory: projectDir)
    await DotEnvFile.load(path: "\(projectDir)/.env", fileio: app.fileio, logger: app.logger)
    do {
        try await configure(app)
        app.emailService = MockEmailService()
        try await test(app)
    } catch {
        do {
            try await app.asyncShutdown()
        } catch {
            Issue.record("Application shutdown failed after test error: \(error)")
        }
        throw error
    }
    try await app.asyncShutdown()
}

/// Esegue un'applicazione minimale (non completamente configurata) garantendone sempre lo shutdown asincrono.
func withBareApp(
    environment: Environment = .testing,
    _ test: (Application) async throws -> Void
) async throws {
    let app = try await Application.make(environment)
    do {
        try await test(app)
    } catch {
        do {
            try await app.asyncShutdown()
        } catch {
            Issue.record("Application shutdown failed after test error: \(error)")
        }
        throw error
    }
    try await app.asyncShutdown()
}

/// Helper per test di validazione password che necessitano di Vapor PasswordHasher con Bcrypt a costo ridotto.
func withBcryptApp(_ test: (Application, Request) async throws -> Void) async throws {
    try await withBareApp { app in
        app.passwords.use(.bcrypt(cost: 4))
        let req = Request(application: app, on: app.eventLoopGroup.next())
        try await test(app, req)
    }
}

func cleanupTest(_ operation: () async throws -> Void) async {
    do {
        try await operation()
    } catch {
        Issue.record("Test cleanup failed: \(error)")
    }
}

func cleanupTestCredentials(_ id: UUID?, on database: any Database) async {
    guard let id else { return }
    await cleanupTest {
        if let credentials = try await Credentials.find(id, on: database) {
            try await credentials.delete(on: database)
        }
    }
}

func cleanupTestUser(_ id: UUID?, on database: any Database) async {
    guard let id else { return }

    do {
        guard let user = try await User.find(id, on: database) else { return }
        let credentialsId = user.$credentials.id
        await cleanupTest { try await user.delete(on: database) }

        guard let credentialsId else { return }
        await cleanupTestCredentials(credentialsId, on: database)
    } catch {
        Issue.record("Test cleanup lookup failed for user \(id): \(error)")
    }
}

/// Crea credenziali per il test, esegue l'operazione e garantisce la rimozione delle credenziali al termine.
func withTestCredentials(
    on app: Application,
    email: String = "test_\(UUID().uuidString.prefix(8))@example.com",
    verified: Bool = true,
    passwordHash: PasswordHash = PasswordHash.dummy(),
    _ operation: (Credentials) async throws -> Void
) async throws {
    let credentials = Credentials(
        email: TestEmail(email),
        passwordHash: passwordHash
    )
    try await credentials.save(on: app.db)
    if verified {
        try await credentials.markEmailAsVerified(on: app.db)
    }
    let credId = try credentials.requireID()

    do {
        try await operation(credentials)
        await cleanupTestCredentials(credId, on: app.db)
    } catch {
        await cleanupTestCredentials(credId, on: app.db)
        throw error
    }
}

/// Crea credenziali e utente per il test, esegue l'operazione e garantisce la pulizia completa al termine.
func withTestUser(
    on app: Application,
    name: String = "Mario",
    surname: String = "Rossi",
    username: String = "user_\(UUID().uuidString.prefix(8))",
    email: String = "test_user_\(UUID().uuidString.prefix(8))@example.com",
    role: UserRole = .student,
    verified: Bool = true,
    passwordHash: PasswordHash = PasswordHash.dummy(),
    classId: UUID? = nil,
    _ operation: (User, Credentials) async throws -> Void
) async throws {
    let credentials = Credentials(
        email: TestEmail(email),
        passwordHash: passwordHash
    )
    try await credentials.save(on: app.db)
    if verified {
        try await credentials.markEmailAsVerified(on: app.db)
    }
    let credId = try credentials.requireID()

    let user = try makeTestUser(
        name: name,
        surname: surname,
        username: username,
        role: role,
        classId: classId,
        credentialsId: credId
    )
    try await user.save(on: app.db)
    let userId = try user.requireID()

    do {
        try await operation(user, credentials)
        await cleanupTestUser(userId, on: app.db)
    } catch {
        await cleanupTestUser(userId, on: app.db)
        throw error
    }
}
