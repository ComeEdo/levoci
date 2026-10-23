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

func cleanupTest(_ operation: () async throws -> Void) async {
    do {
        try await operation()
    } catch {
        Issue.record("Test cleanup failed: \(error)")
    }
}

func cleanupTestUser(_ id: UUID?, on database: any Database) async {
    guard let id else { return }

    do {
        guard let user = try await User.find(id, on: database) else { return }
        let credentialsId = user.$credentials.id
        await cleanupTest { try await user.delete(on: database) }

        guard let credentialsId else { return }
        do {
            if let credentials = try await Credentials.find(credentialsId, on: database) {
                await cleanupTest { try await credentials.delete(on: database) }
            }
        } catch {
            Issue.record("Test cleanup lookup failed for credentials \(credentialsId): \(error)")
        }
    } catch {
        Issue.record("Test cleanup lookup failed for user \(id): \(error)")
    }
}
