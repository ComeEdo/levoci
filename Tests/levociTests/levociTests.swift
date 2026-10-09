@testable import levoci
import VaporTesting
import Testing
import Fluent
import JWT
import JWTKit

import Foundation

/// Email fittizia conforme a `ValidatedEmail` per i test di integrazione e middleware.
struct TestEmail: ValidatedEmail {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    init(raw: String) throws {
        self.value = raw
    }
}

@Suite("App Tests", .serialized)
struct levociTests {
    private func makeUser(
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

    private func withApp(_ test: (Application) async throws -> Void) async throws {
        let projectDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
        let app = try await Application.make(.testing)
        app.directory = DirectoryConfiguration(workingDirectory: projectDir)
        await DotEnvFile.load(path: "\(projectDir)/.env", fileio: app.fileio, logger: app.logger)
        do {
            try await configure(app)
            try await test(app)
        } catch {
            try await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }
    
    @Test("Test Health Check Route")
    func healthCheck() async throws {
        try await withApp { app in
            try await app.testing().test(.GET, "", afterResponse: { res async throws in
                #expect(res.status == .ok)
                let body = try res.content.decode([String: String].self)
                #expect(body["status"] == "ok")
                #expect(body["message"] == "Voci di Corridoio API")
            })
        }
    }

    @Test("Test Classes Info Route Exists")
    func classesInfoRouteExists() async throws {
        try await withApp { app in
            try await app.testing().test(.GET, "classes/info", afterResponse: { res async in
                #expect(res.status == .notImplemented)
            })
        }
    }

    @Test("Test Auth Register Validation Rejections")
    func authRegisterValidationRejections() async throws {
        try await withApp { app in
            // 1. Chiamata con body JSON vuoto -> 400 Bad Request
            var emptyHeaders = HTTPHeaders()
            emptyHeaders.contentType = .json
            try await app.testing().test(.POST, "register", headers: emptyHeaders, beforeRequest: { req in
                req.body = ByteBuffer(string: "{}")
            }, afterResponse: { res async in
                #expect(res.status == .badRequest)
            })

            // 2. Email non scolastica (@gmail.com) -> 400 Bad Request
            let nonSchoolBody = RegisterRequest(
                name: "Mario",
                surname: "Rossi",
                username: "mario_\(UUID().uuidString.prefix(6))",
                email: "mario@gmail.com",
                password: "Password123!"
            )
            try await app.testing().test(.POST, "register", beforeRequest: { req async throws in
                try req.content.encode(nonSchoolBody)
            }, afterResponse: { res async throws in
                #expect(res.status == .badRequest)
                let errorBody = try res.content.decode(ErrorResponse.self)
                #expect(errorBody.message == "The Email must belong to the @itisgalileiroma.it domain")
            })

            // 3. Nome con caratteri non ammessi (numeri) -> 400 Bad Request
            let invalidNameBody = RegisterRequest(
                name: "Mario123",
                surname: "Rossi",
                username: "mario_\(UUID().uuidString.prefix(6))",
                email: "mario.stud@itisgalileiroma.it",
                password: "Password123!"
            )
            try await app.testing().test(.POST, "register", beforeRequest: { req async throws in
                try req.content.encode(invalidNameBody)
            }, afterResponse: { res async throws in
                #expect(res.status == .badRequest)
                let errorBody = try res.content.decode(ErrorResponse.self)
                #expect(errorBody.message == "The Name contains invalid characters")
            })

            // 4. Studente senza classe -> 400 Bad Request
            let studentNoClassBody = RegisterRequest(
                name: "Mario",
                surname: "Rossi",
                username: "mario_\(UUID().uuidString.prefix(6))",
                email: "stud_noclass_\(UUID().uuidString.prefix(6)).stud@itisgalileiroma.it",
                password: "Password123!"
            )
            try await app.testing().test(.POST, "register", beforeRequest: { req async throws in
                try req.content.encode(studentNoClassBody)
            }, afterResponse: { res async throws in
                #expect(res.status == .badRequest)
                let errorBody = try res.content.decode(ErrorResponse.self)
                #expect(errorBody.message == "For a student, the class is required")
            })
        }
    }

    @Test("Test Auth Register Student Success and 409 Conflict Handling")
    func authRegisterStudentSuccessAndConflict() async throws {
        try await withApp { app in
            // Recupera una classe esistente sul DB o ne crea una temporanea
            let schoolClass: SchoolClass
            if let existing = try await SchoolClass.query(on: app.db).first() {
                schoolClass = existing
            } else {
                let studyField = StudyField(name: "Informatica_\(UUID().uuidString.prefix(6))")
                try await studyField.save(on: app.db)
                let sfId = try studyField.requireID()
                let sc = SchoolClass(
                    name: "5IA_\(UUID().uuidString.prefix(6))",
                    studyFieldId: sfId,
                    beginDate: Date(),
                    endDate: Date().addingTimeInterval(365 * 24 * 3600),
                    classYear: 2026
                )
                try await sc.save(on: app.db)
                schoolClass = sc
            }
            let classId = try schoolClass.requireID()

            let username = "stud_\(UUID().uuidString.prefix(8))"
            let email = "stud_\(UUID().uuidString.prefix(8)).stud@itisgalileiroma.it"

            let registerBody = RegisterRequest(
                name: "Mario",
                surname: "Rossi",
                username: username,
                email: email,
                password: "ValidPassword123!",
                classId: classId
            )

            var createdUserId: UUID? = nil

            do {
                // 1. Registrazione con successo -> HTTP 201 Created
                try await app.testing().test(.POST, "register", beforeRequest: { req async throws in
                    try req.content.encode(registerBody)
                }, afterResponse: { res async throws in
                    #expect(res.status == .created)
                    let response = try res.content.decode(RegisterResponse.self)
                    #expect(response.username == username)
                })

                // Recupero l'utente creato dal DB (la risposta non espone l'id) per verifica e cleanup
                let createdUser = try await User.query(on: app.db).filter(\.$username == username).first()
                #expect(createdUser != nil)
                createdUserId = try createdUser?.requireID()

                // 2. Conflitto sia email che username -> HTTP 409 Conflict
                try await app.testing().test(.POST, "register", beforeRequest: { req async throws in
                    try req.content.encode(registerBody)
                }, afterResponse: { res async throws in
                    #expect(res.status == .conflict)
                    let errorBody = try res.content.decode(ErrorResponse.self)
                    #expect(errorBody.error == "conflict")
                    #expect(errorBody.message == "Username and email already exist")
                })

                // 3. Conflitto solo email -> HTTP 409 Conflict
                let diffUsernameBody = RegisterRequest(
                    name: "Luigi",
                    surname: "Verdi",
                    username: "diff_user_\(UUID().uuidString.prefix(6))",
                    email: email,
                    password: "ValidPassword123!",
                    classId: classId
                )
                try await app.testing().test(.POST, "register", beforeRequest: { req async throws in
                    try req.content.encode(diffUsernameBody)
                }, afterResponse: { res async throws in
                    #expect(res.status == .conflict)
                    let errorBody = try res.content.decode(ErrorResponse.self)
                    #expect(errorBody.error == "conflict")
                    #expect(errorBody.message == "Email already exists")
                })
            } catch {
                if let userId = createdUserId, let user = try? await User.find(userId, on: app.db) {
                    let credId = user.$credentials.id
                    _ = try? await user.delete(on: app.db)
                    if let credId, let creds = try? await Credentials.find(credId, on: app.db) {
                        _ = try? await creds.delete(on: app.db)
                    }
                }
                throw error
            }

            // Cleanup DB
            if let userId = createdUserId, let user = try? await User.find(userId, on: app.db) {
                let credId = user.$credentials.id
                _ = try? await user.delete(on: app.db)
                if let credId, let creds = try? await Credentials.find(credId, on: app.db) {
                    _ = try? await creds.delete(on: app.db)
                }
            }
        }
    }

    @Test("Test All 12 Fluent Models Query DB")
    func verifyAllModelsQuery() async throws {
        try await withApp { app in
            _ = try await Role.query(on: app.db).first()
            _ = try await StudyField.query(on: app.db).first()
            _ = try await SchoolClass.query(on: app.db).first()
            _ = try await Credentials.query(on: app.db).first()
            _ = try await User.query(on: app.db).first()
            _ = try await Post.query(on: app.db).first()
            _ = try await Vote.query(on: app.db).first()
            _ = try await Timetable.query(on: app.db).first()
            _ = try await Subject.query(on: app.db).first()
            _ = try await RealSubject.query(on: app.db).first()
            _ = try await TimetableProfessor.query(on: app.db).first()
            _ = try await TimetableSubject.query(on: app.db).first()
        }
    }

    @Test("Test AuthTokenPayload Sign and Verify via Vapor JWT")
    func authTokenPayloadSignAndVerify() async throws {
        try await withApp { app in
            let credentialsId = UUID()
            let tokenVersion = UUID()

            let payload = AuthTokenPayload(credentialsId: credentialsId, tokenVersion: tokenVersion)
            let token = try await app.jwt.keys.sign(payload)
            #expect(!token.isEmpty)

            let verified = try await app.jwt.keys.verify(token, as: AuthTokenPayload.self)
            #expect(verified.credentialsId == credentialsId)
            #expect(verified.tokenVersion == tokenVersion)
        }
    }

    @Test("Test UserTokenPayload Sign and Verify via Vapor JWT")
    func userTokenPayloadSignAndVerify() async throws {
        try await withApp { app in
            let userId = UUID()
            let userVersion = UUID()
            let credentialsId = UUID()
            let tokenVersion = UUID()
            let roleId = 2

            let payload = UserTokenPayload(
                userId: userId,
                userVersion: userVersion,
                credentialsId: credentialsId,
                tokenVersion: tokenVersion,
                roleId: roleId
            )
            let token = try await app.jwt.keys.sign(payload)
            #expect(!token.isEmpty)

            let verified: UserTokenPayload = try await app.jwt.keys.verify(token, as: UserTokenPayload.self)
            #expect(verified.userId == userId)
            #expect(verified.userVersion == userVersion)
            #expect(verified.credentialsId == credentialsId)
            #expect(verified.tokenVersion == tokenVersion)
            #expect(verified.roleId == roleId)
        }
    }

    @Test("Test EmailVerificationPayload Sign and Verify via Vapor JWT")
    func emailVerificationPayloadSignAndVerify() async throws {
        try await withApp { app in
            let credentialsId = UUID()

            let payload = EmailVerificationPayload(credentialsId: credentialsId)
            let token = try await app.jwt.keys.sign(payload)
            #expect(!token.isEmpty)

            let verified = try await app.jwt.keys.verify(token, as: EmailVerificationPayload.self)
            #expect(verified.credentialsId == credentialsId)
        }
    }

    @Test("Test Vapor JWT Rejects Tampered Token")
    func jwtRejectsTamperedToken() async throws {
        try await withApp { app in
            let credentialsId = UUID()
            let tokenVersion = UUID()

            let payload = AuthTokenPayload(credentialsId: credentialsId, tokenVersion: tokenVersion)
            let token = try await app.jwt.keys.sign(payload)
            let tamperedToken = token + "corrupted"

            await #expect(throws: (any Error).self) {
                _ = try await app.jwt.keys.verify(tamperedToken, as: AuthTokenPayload.self)
            }
        }
    }

    @Test("Test Configuration Throws If JWT Key File Is Missing")
    func configurationThrowsIfJWTKeyMissing() async throws {
        let projectDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
        let app = try await Application.make(.testing)
        app.directory = DirectoryConfiguration(workingDirectory: projectDir)
        do {
            await DotEnvFile.load(path: "\(projectDir)/.env", fileio: app.fileio, logger: app.logger)
            
            let originalKeyPath = unsafe getenv("JWT_PRIVATE_KEY_PATH").flatMap { unsafe String(cString: $0) }
            defer {
                if let originalKeyPath {
                    unsafe setenv("JWT_PRIVATE_KEY_PATH", originalKeyPath, 1)
                }
            }
            
            // Override with a non-existent key path
            unsafe setenv("JWT_PRIVATE_KEY_PATH", "./non_existent_key.pem", 1)
            
            do {
                try await configure(app)
                Issue.record("configure() should have thrown ConfigurationError.missingKeyFile")
            } catch let error as ConfigurationError {
                switch error {
                case .missingKeyFile(let name, _):
                    #expect(name == "JWT_PRIVATE_KEY_PATH")
                default:
                    Issue.record("Unexpected ConfigurationError: \(error)")
                }
            } catch {
                Issue.record("Expected ConfigurationError, got \(error)")
            }
        }
        try await app.asyncShutdown()
    }

    @Test("Test EmailService Is Registered In Application")
    func emailServiceIsRegistered() async throws {
        try await withApp { app in
            _ = app.emailService
        }
    }

    @Test("Test AuthTokenMiddleware Fails If No Token (HTTP 400)")
    func authTokenMiddlewareNoToken() async throws {
        try await withApp { app in
            let protectedGroup = app.grouped(AuthTokenMiddleware())
            protectedGroup.get("test-protected-no-token") { req -> MessageResponse in
                _ = try req.auth.require(Credentials.self)
                return MessageResponse("Success")
            }

            try await app.testing().test(.GET, "test-protected-no-token", afterResponse: { res async throws in
                #expect(res.status == .badRequest)
                let errorBody = try res.content.decode(ErrorResponse.self)
                #expect(errorBody.error == "bad_request")
                #expect(errorBody.message == "Unauthorized - No token provided")
            })
        }
    }

    @Test("Test AuthTokenMiddleware Fails If Invalid Token (HTTP 401 with logOut)")
    func authTokenMiddlewareInvalidToken() async throws {
        try await withApp { app in
            let protectedGroup = app.grouped(AuthTokenMiddleware())
            protectedGroup.get("test-protected-invalid-token") { req -> MessageResponse in
                _ = try req.auth.require(Credentials.self)
                return MessageResponse("Success")
            }

            var headers = HTTPHeaders()
            headers.bearerAuthorization = BearerAuthorization(token: "invalid.jwt.token")

            try await app.testing().test(.GET, "test-protected-invalid-token", headers: headers, afterResponse: { res async throws in
                #expect(res.status == .unauthorized)
                let errorBody = try res.content.decode(ErrorResponse.self)
                #expect(errorBody.error == "unauthorized")
                #expect(errorBody.logOut == true)
            })
        }
    }

    @Test("Test AuthTokenMiddleware Succeeds with Valid Token and Injects Credentials")
    func authTokenMiddlewareValidTokenAndAuthenticatableLogin() async throws {
        try await withApp { app in
            let testEmail = "test_auth_\(UUID().uuidString.prefix(8))@example.com"
            let credentials = Credentials(
                email: TestEmail(testEmail),
                passwordHash: PasswordHash.dummy()
            )
            try await credentials.save(on: app.db)
            try await credentials.markEmailAsVerified(on: app.db)
            do {
                let credId = try credentials.requireID()
                let payload = AuthTokenPayload(credentialsId: credId, tokenVersion: credentials.tokenVersion)
                let token = try await app.jwt.keys.sign(payload)

                let protectedGroup = app.grouped(AuthTokenMiddleware())
                protectedGroup.get("test-protected-valid") { req -> MessageResponse in
                    let authenticated = try req.auth.require(Credentials.self)
                    #expect(authenticated.email == testEmail)
                    return MessageResponse("Access granted")
                }

                var headers = HTTPHeaders()
                headers.bearerAuthorization = BearerAuthorization(token: token)

                try await app.testing().test(.GET, "test-protected-valid", headers: headers, afterResponse: { res async throws in
                    #expect(res.status == .ok)
                    let body = try res.content.decode(MessageResponse.self)
                    #expect(body.message == "Access granted")
                })
            } catch {
                _ = try? await credentials.delete(on: app.db)
                throw error
            }
            _ = try? await credentials.delete(on: app.db)
        }
    }

    @Test("Test AuthController logoutAll Invalidates Active Tokens")
    func authControllerLogoutAll() async throws {
        try await withApp { app in
            let testEmail = "logout_all_\(UUID().uuidString.prefix(8))@example.com"
            let credentials = Credentials(
                email: TestEmail(testEmail),
                passwordHash: PasswordHash.dummy()
            )
            try await credentials.save(on: app.db)
            try await credentials.markEmailAsVerified(on: app.db)
            let credId = try credentials.requireID()
            let initialTokenVersion = credentials.tokenVersion

            do {
                let payload = AuthTokenPayload(credentialsId: credId, tokenVersion: initialTokenVersion)
                let token = try await app.jwt.keys.sign(payload)

                var headers = HTTPHeaders()
                headers.bearerAuthorization = BearerAuthorization(token: token)

                // 1. Chiamata a logoutAll -> 204 No Content
                try await app.testing().test(.POST, "auth/logoutAll", headers: headers, afterResponse: { res async throws in
                    #expect(res.status == .noContent)
                    #expect(res.body.readableBytes == 0)
                })

                // 2. Verifica su DB: tokenVersion deve essere cambiata
                guard let updatedCreds = try await Credentials.find(credId, on: app.db) else {
                    Issue.record("Credentials not found on DB")
                    return
                }
                #expect(updatedCreds.tokenVersion != initialTokenVersion)

                // 3. Il vecchio token ora DEVE essere rifiutato (HTTP 403 Forbidden con logOut: true)
                try await app.testing().test(.GET, "auth/isAuthTokenValid", headers: headers, afterResponse: { res async throws in
                    #expect(res.status == .forbidden)
                    let errorBody = try res.content.decode(ErrorResponse.self)
                    #expect(errorBody.logOut == true)
                })
            } catch {
                _ = try? await credentials.delete(on: app.db)
                throw error
            }

            _ = try? await credentials.delete(on: app.db)
        }
    }

    @Test("Test AuthTokenMiddleware Fails If Email Not Verified (HTTP 403 with logOut)")
    func authTokenMiddlewareEmailNotVerified() async throws {
        try await withApp { app in
            let testEmail = "unverified_\(UUID().uuidString.prefix(8))@example.com"
            let credentials = Credentials(
                email: TestEmail(testEmail),
                passwordHash: PasswordHash.dummy()
            )
            try await credentials.save(on: app.db)
            do {
                let credId = try credentials.requireID()
                let payload = AuthTokenPayload(credentialsId: credId, tokenVersion: credentials.tokenVersion)
                let token = try await app.jwt.keys.sign(payload)

                let protectedGroup = app.grouped(AuthTokenMiddleware())
                protectedGroup.get("test-protected-unverified") { req -> MessageResponse in
                    _ = try req.auth.require(Credentials.self)
                    return MessageResponse("Success")
                }

                var headers = HTTPHeaders()
                headers.bearerAuthorization = BearerAuthorization(token: token)

                try await app.testing().test(.GET, "test-protected-unverified", headers: headers, afterResponse: { res async throws in
                    #expect(res.status == .forbidden)
                    let errorBody = try res.content.decode(ErrorResponse.self)
                    #expect(errorBody.error == "forbidden")
                    #expect(errorBody.message == "Email not verified check you inbox")
                    #expect(errorBody.logOut == true)
                })
            } catch {
                _ = try? await credentials.delete(on: app.db)
                throw error
            }
            _ = try? await credentials.delete(on: app.db)
        }
    }

    @Test("Test AuthTokenMiddleware Fails If Token Version Mismatch (HTTP 403 with logOut)")
    func authTokenMiddlewareTokenVersionMismatch() async throws {
        try await withApp { app in
            let testEmail = "mismatch_\(UUID().uuidString.prefix(8))@example.com"
            let credentials = Credentials(
                email: TestEmail(testEmail),
                passwordHash: PasswordHash.dummy()
            )
            try await credentials.save(on: app.db)
            try await credentials.markEmailAsVerified(on: app.db)
            do {
                let credId = try credentials.requireID()
                let outdatedTokenVersion = UUID()
                let payload = AuthTokenPayload(credentialsId: credId, tokenVersion: outdatedTokenVersion)
                let token = try await app.jwt.keys.sign(payload)

                let protectedGroup = app.grouped(AuthTokenMiddleware())
                protectedGroup.get("test-protected-mismatch") { req -> MessageResponse in
                    _ = try req.auth.require(Credentials.self)
                    return MessageResponse("Success")
                }

                var headers = HTTPHeaders()
                headers.bearerAuthorization = BearerAuthorization(token: token)

                try await app.testing().test(.GET, "test-protected-mismatch", headers: headers, afterResponse: { res async throws in
                    #expect(res.status == .forbidden)
                    let errorBody = try res.content.decode(ErrorResponse.self)
                    #expect(errorBody.error == "forbidden")
                    #expect(errorBody.message == "Forbidden - Invalid auth token version")
                    #expect(errorBody.logOut == true)
                })
            } catch {
                _ = try? await credentials.delete(on: app.db)
                throw error
            }
            _ = try? await credentials.delete(on: app.db)
        }
    }

    @Test("Test Credentials sendVerificationEmailIfNeeded Skips If Under 5 Minutes")
    func emailVerificationSkipsIfUnder5Minutes() async throws {
        try await withApp { app in
            let testEmail = "rate_limit_\(UUID().uuidString.prefix(8))@example.com"
            let credentials = Credentials(
                email: TestEmail(testEmail),
                passwordHash: PasswordHash.dummy()
            )
            // Impostiamo lastUpdated a 2 minuti fa (< 5 minuti fa)
            credentials.lastUpdated = Date().addingTimeInterval(-2 * 60)
            try await credentials.save(on: app.db)
            do {
                let initialLastUpdated = credentials.lastUpdated

                // Chiamata con lastUpdated recente (< 5 min) -> non deve reinviare
                try await credentials.sendVerificationEmailIfNeeded(on: app.db, emailService: app.emailService, logger: app.logger)
                #expect(credentials.lastUpdated == initialLastUpdated)
            } catch {
                _ = try? await credentials.delete(on: app.db)
                throw error
            }
            _ = try? await credentials.delete(on: app.db)
        }
    }

    @Test("Test UserTokenMiddleware Fails If No Token (HTTP 400)")
    func userTokenMiddlewareNoToken() async throws {
        try await withApp { app in
            let protectedGroup = app.grouped(UserTokenMiddleware())
            protectedGroup.get("test-user-no-token") { req -> MessageResponse in
                _ = try req.auth.require(User.self)
                return MessageResponse("Success")
            }

            try await app.testing().test(.GET, "test-user-no-token", afterResponse: { res async throws in
                #expect(res.status == .badRequest)
                let errorBody = try res.content.decode(ErrorResponse.self)
                #expect(errorBody.error == "bad_request")
                #expect(errorBody.message == "Unauthorized - No token provided")
            })
        }
    }

    @Test("Test UserTokenMiddleware Fails If Invalid Token (HTTP 401 with userLogOut)")
    func userTokenMiddlewareInvalidToken() async throws {
        try await withApp { app in
            let protectedGroup = app.grouped(UserTokenMiddleware())
            protectedGroup.get("test-user-invalid-token") { req -> MessageResponse in
                _ = try req.auth.require(User.self)
                return MessageResponse("Success")
            }

            var headers = HTTPHeaders()
            headers.bearerAuthorization = BearerAuthorization(token: "invalid.user.token")

            try await app.testing().test(.GET, "test-user-invalid-token", headers: headers, afterResponse: { res async throws in
                #expect(res.status == .unauthorized)
                let errorBody = try res.content.decode(ErrorResponse.self)
                #expect(errorBody.error == "unauthorized")
                #expect(errorBody.userLogOut == true)
            })
        }
    }

    @Test("Test UserTokenMiddleware Succeeds with Valid Token and Injects User & Credentials")
    func userTokenMiddlewareValidTokenSuccess() async throws {
        try await withApp { app in
            let testEmail = "test_user_mw_\(UUID().uuidString.prefix(8))@example.com"
            let credentials = Credentials(
                email: TestEmail(testEmail),
                passwordHash: PasswordHash.dummy()
            )
            try await credentials.save(on: app.db)
            try await credentials.markEmailAsVerified(on: app.db)
            let credId = try credentials.requireID()
            let testTokenVersion = credentials.tokenVersion

            let testUsername = "user_\(UUID().uuidString.prefix(8))"
            let user = try makeUser(
                name: "Mario",
                surname: "Rossi",
                username: testUsername,
                role: .student,
                credentialsId: credId
            )
            try await user.save(on: app.db)
            let userId = try user.requireID()
            let testUserVersion = user.userVersion

            do {
                let payload = UserTokenPayload(
                    userId: userId,
                    userVersion: testUserVersion,
                    credentialsId: credId,
                    tokenVersion: testTokenVersion,
                    roleId: 2
                )
                let token = try await app.jwt.keys.sign(payload)

                let protectedGroup = app.grouped(UserTokenMiddleware())
                protectedGroup.get("test-user-valid") { req -> MessageResponse in
                    let authUser = try req.auth.require(User.self)
                    let authCreds = try req.auth.require(Credentials.self)
                    #expect(authUser.username == testUsername)
                    #expect(authCreds.email == testEmail)
                    #expect(req.shouldUpdateUserToken == false)
                    return MessageResponse("User access granted")
                }

                var headers = HTTPHeaders()
                headers.bearerAuthorization = BearerAuthorization(token: token)

                try await app.testing().test(.GET, "test-user-valid", headers: headers, afterResponse: { res async throws in
                    #expect(res.status == .ok)
                    let body = try res.content.decode(MessageResponse.self)
                    #expect(body.message == "User access granted")
                })
            } catch {
                _ = try? await user.delete(on: app.db)
                _ = try? await credentials.delete(on: app.db)
                throw error
            }

            _ = try? await user.delete(on: app.db)
            _ = try? await credentials.delete(on: app.db)
        }
    }

    @Test("Test UserTokenMiddleware Sets shouldUpdateUserToken If userVersion Changed")
    func userTokenMiddlewareUserVersionMismatchFlagsUpdate() async throws {
        try await withApp { app in
            let testEmail = "test_uv_\(UUID().uuidString.prefix(8))@example.com"
            let credentials = Credentials(
                email: TestEmail(testEmail),
                passwordHash: PasswordHash.dummy()
            )
            try await credentials.save(on: app.db)
            try await credentials.markEmailAsVerified(on: app.db)
            let credId = try credentials.requireID()
            let testTokenVersion = credentials.tokenVersion

            let user = try makeUser(
                name: "Luigi",
                surname: "Verdi",
                username: "luigi_\(UUID().uuidString.prefix(8))",
                role: .student,
                credentialsId: credId
            )
            try await user.save(on: app.db)
            let userId = try user.requireID()

            do {
                let outdatedUserVersion = UUID()
                let payload = UserTokenPayload(
                    userId: userId,
                    userVersion: outdatedUserVersion,
                    credentialsId: credId,
                    tokenVersion: testTokenVersion,
                    roleId: 2
                )
                let token = try await app.jwt.keys.sign(payload)

                let protectedGroup = app.grouped(UserTokenMiddleware())
                protectedGroup.get("test-user-version-flag") { req -> MessageResponse in
                    #expect(req.shouldUpdateUserToken == true)
                    return MessageResponse("OK")
                }

                var headers = HTTPHeaders()
                headers.bearerAuthorization = BearerAuthorization(token: token)

                try await app.testing().test(.GET, "test-user-version-flag", headers: headers, afterResponse: { res async throws in
                    #expect(res.status == .ok)
                    #expect(res.headers.first(name: "X-Update-User-And-Token") == "true")
                })
            } catch {
                _ = try? await user.delete(on: app.db)
                _ = try? await credentials.delete(on: app.db)
                throw error
            }

            _ = try? await user.delete(on: app.db)
            _ = try? await credentials.delete(on: app.db)
        }
    }

    @Test("Test UserTokenMiddleware Fails If Credentials Mismatch (HTTP 403 with logOut)")
    func userTokenMiddlewareCredentialsMismatchFails() async throws {
        try await withApp { app in
            let testEmail = "test_cm_\(UUID().uuidString.prefix(8))@example.com"
            let credentials = Credentials(
                email: TestEmail(testEmail),
                passwordHash: PasswordHash.dummy()
            )
            try await credentials.save(on: app.db)
            try await credentials.markEmailAsVerified(on: app.db)
            let realCredId = try credentials.requireID()
            let testTokenVersion = credentials.tokenVersion

            let user = try makeUser(
                name: "Mario",
                surname: "Rossi",
                username: "mario_\(UUID().uuidString.prefix(8))",
                role: .student,
                credentialsId: realCredId
            )
            try await user.save(on: app.db)
            let userId = try user.requireID()

            do {
                let fakeCredId = UUID()
                let payload = UserTokenPayload(
                    userId: userId,
                    userVersion: user.userVersion,
                    credentialsId: fakeCredId,
                    tokenVersion: testTokenVersion,
                    roleId: 2
                )
                let token = try await app.jwt.keys.sign(payload)

                let protectedGroup = app.grouped(UserTokenMiddleware())
                protectedGroup.get("test-user-cred-mismatch") { req -> MessageResponse in
                    return MessageResponse("Should not reach")
                }

                var headers = HTTPHeaders()
                headers.bearerAuthorization = BearerAuthorization(token: token)

                try await app.testing().test(.GET, "test-user-cred-mismatch", headers: headers, afterResponse: { res async throws in
                    #expect(res.status == .forbidden)
                    let errorBody = try res.content.decode(ErrorResponse.self)
                    #expect(errorBody.error == "forbidden")
                    #expect(errorBody.message == "Forbidden - Invalid credentials")
                    #expect(errorBody.userLogOut == true)
                })
            } catch {
                _ = try? await user.delete(on: app.db)
                _ = try? await credentials.delete(on: app.db)
                throw error
            }

            _ = try? await user.delete(on: app.db)
            _ = try? await credentials.delete(on: app.db)
        }
    }

    @Test("Test UserTokenMiddleware Fails If tokenVersion Mismatch (HTTP 401 with logOut)")
    func userTokenMiddlewareTokenVersionMismatchFails() async throws {
        try await withApp { app in
            let testEmail = "test_tvm_\(UUID().uuidString.prefix(8))@example.com"
            let credentials = Credentials(
                email: TestEmail(testEmail),
                passwordHash: PasswordHash.dummy()
            )
            try await credentials.save(on: app.db)
            try await credentials.markEmailAsVerified(on: app.db)
            let credId = try credentials.requireID()

            let user = try makeUser(
                name: "Mario",
                surname: "Rossi",
                username: "mario_tvm_\(UUID().uuidString.prefix(8))",
                role: .student,
                credentialsId: credId
            )
            try await user.save(on: app.db)
            let userId = try user.requireID()

            do {
                let outdatedTokenVersion = UUID()
                let payload = UserTokenPayload(
                    userId: userId,
                    userVersion: user.userVersion,
                    credentialsId: credId,
                    tokenVersion: outdatedTokenVersion,
                    roleId: 2
                )
                let token = try await app.jwt.keys.sign(payload)

                let protectedGroup = app.grouped(UserTokenMiddleware())
                protectedGroup.get("test-user-tv-mismatch") { req -> MessageResponse in
                    return MessageResponse("Should not reach")
                }

                var headers = HTTPHeaders()
                headers.bearerAuthorization = BearerAuthorization(token: token)

                try await app.testing().test(.GET, "test-user-tv-mismatch", headers: headers, afterResponse: { res async throws in
                    #expect(res.status == .unauthorized)
                    let errorBody = try res.content.decode(ErrorResponse.self)
                    #expect(errorBody.error == "unauthorized")
                    #expect(errorBody.message == "Unauthorized - Invalid token version")
                    #expect(errorBody.logOut == true)
                })
            } catch {
                _ = try? await user.delete(on: app.db)
                _ = try? await credentials.delete(on: app.db)
                throw error
            }

            _ = try? await user.delete(on: app.db)
            _ = try? await credentials.delete(on: app.db)
        }
    }

    @Test("Test APIError Integrity: logOut True Forces userLogOut Nil")
    func apiErrorIntegrityRule() {
        let error = APIError(.unauthorized, message: "Test", logOut: true, userLogOut: true)
        #expect(error.logOut == true)
        #expect(error.userLogOut == nil)
    }

    @Test("Test RoleMiddleware Blocks Unauthenticated User (HTTP 401)")
    func roleMiddlewareBlocksUnauthenticated() async throws {
        try await withApp { app in
            let protectedGroup = app.grouped(RoleMiddleware(.student))
            protectedGroup.get("test-role-no-auth") { req -> MessageResponse in
                return MessageResponse("OK")
            }

            try await app.testing().test(.GET, "test-role-no-auth", afterResponse: { res async throws in
                #expect(res.status == .unauthorized)
                let errorBody = try res.content.decode(ErrorResponse.self)
                #expect(errorBody.error == "unauthorized")
                #expect(errorBody.message == "Unauthorized - Profile authentication required")
            })
        }
    }

    @Test("Test RoleMiddleware Allows Matching Role and Rejects Unauthorized Role (HTTP 403)")
    func roleMiddlewareEnforcesRoles() async throws {
        try await withApp { app in
            let testEmail = "test_role_\(UUID().uuidString.prefix(8))@example.com"
            let credentials = Credentials(
                email: TestEmail(testEmail),
                passwordHash: PasswordHash.dummy()
            )
            try await credentials.save(on: app.db)
            try await credentials.markEmailAsVerified(on: app.db)
            let credId = try credentials.requireID()
            let testTokenVersion = credentials.tokenVersion

            let student = try makeUser(
                name: "Student",
                surname: "User",
                username: "student_\(UUID().uuidString.prefix(8))",
                role: .student,
                credentialsId: credId
            )
            try await student.save(on: app.db)
            let studentId = try student.requireID()

            do {
                let payload = UserTokenPayload(
                    userId: studentId,
                    userVersion: student.userVersion,
                    credentialsId: credId,
                    tokenVersion: testTokenVersion,
                    roleId: UserRole.student.rawValue
                )
                let token = try await app.jwt.keys.sign(payload)

                let userGroup = app.grouped(UserTokenMiddleware())

                let studentGroup = userGroup.grouped(RoleMiddleware(.student))
                studentGroup.get("test-role-student-only") { req -> MessageResponse in
                    return MessageResponse("Student access granted")
                }

                let teacherGroup = userGroup.grouped(RoleMiddleware(.teacher, .admin))
                teacherGroup.get("test-role-teacher-only") { req -> MessageResponse in
                    return MessageResponse("Teacher access granted")
                }

                var headers = HTTPHeaders()
                headers.bearerAuthorization = BearerAuthorization(token: token)

                try await app.testing().test(.GET, "test-role-student-only", headers: headers, afterResponse: { res async throws in
                    #expect(res.status == .ok)
                    let body = try res.content.decode(MessageResponse.self)
                    #expect(body.message == "Student access granted")
                })

                try await app.testing().test(.GET, "test-role-teacher-only", headers: headers, afterResponse: { res async throws in
                    #expect(res.status == .forbidden)
                    let errorBody = try res.content.decode(ErrorResponse.self)
                    #expect(errorBody.error == "forbidden")
                    #expect(errorBody.message == "Forbidden - Insufficient permissions")
                })
            } catch {
                _ = try? await student.delete(on: app.db)
                _ = try? await credentials.delete(on: app.db)
                throw error
            }

            _ = try? await student.delete(on: app.db)
            _ = try? await credentials.delete(on: app.db)
        }
    }

    @Test("Test AuthController isAuthTokenValid Endpoint")
    func authControllerIsAuthTokenValid() async throws {
        try await withApp { app in
            let testEmail = "is_auth_\(UUID().uuidString.prefix(8))@example.com"
            let credentials = Credentials(
                email: TestEmail(testEmail),
                passwordHash: PasswordHash.dummy()
            )
            try await credentials.save(on: app.db)
            try await credentials.markEmailAsVerified(on: app.db)
            let credId = try credentials.requireID()
            let testTokenVersion = credentials.tokenVersion

            do {
                let payload = AuthTokenPayload(credentialsId: credId, tokenVersion: testTokenVersion)
                let token = try await app.jwt.keys.sign(payload)

                var headers = HTTPHeaders()
                headers.bearerAuthorization = BearerAuthorization(token: token)

                // 1. Success con token valido -> 204 No Content
                try await app.testing().test(.GET, "auth/isAuthTokenValid", headers: headers, afterResponse: { res async throws in
                    #expect(res.status == .noContent)
                    #expect(res.body.readableBytes == 0)
                })

                // 2. Chiamata senza token -> 400 Bad Request
                try await app.testing().test(.GET, "auth/isAuthTokenValid", afterResponse: { res async throws in
                    #expect(res.status == .badRequest)
                })
            } catch {
                _ = try? await credentials.delete(on: app.db)
                throw error
            }

            _ = try? await credentials.delete(on: app.db)
        }
    }

    @Test("Test Credentials Are Created Unverified And markEmailAsVerified Persists")
    func credentialsCreatedUnverifiedAndMarkVerified() async throws {
        try await withApp { app in
            let credentials = Credentials(
                email: TestEmail("verify_\(UUID().uuidString.prefix(8))@example.com"),
                passwordHash: PasswordHash.dummy()
            )
            #expect(credentials.isEmailVerified == false)
            try await credentials.save(on: app.db)

            do {
                let credId = try credentials.requireID()

                // 1. Sul DB nasce non verificata
                let created = try #require(try await Credentials.find(credId, on: app.db))
                #expect(created.isEmailVerified == false)

                // 2. Dopo markEmailAsVerified risulta verificata anche rileggendo dal DB
                try await credentials.markEmailAsVerified(on: app.db)
                let verified = try #require(try await Credentials.find(credId, on: app.db))
                #expect(verified.isEmailVerified == true)
            } catch {
                _ = try? await credentials.delete(on: app.db)
                throw error
            }

            _ = try? await credentials.delete(on: app.db)
        }
    }

    @Test("Test User userVersion Created Automatically And bumpVersion Persists")
    func userCreatedWithVersionAndBumpVersion() async throws {
        try await withApp { app in
            let credentials = Credentials(
                email: TestEmail("user_version_\(UUID().uuidString.prefix(8))@example.com"),
                passwordHash: PasswordHash.dummy()
            )
            try await credentials.save(on: app.db)
            let credId = try credentials.requireID()

            let user = try makeUser(
                name: "Test",
                surname: "User",
                username: "uv_\(UUID().uuidString.prefix(8))",
                role: .student,
                credentialsId: credId
            )
            let initialVersion = user.userVersion
            try await user.save(on: app.db)

            do {
                let userId = try user.requireID()
                let created = try #require(try await User.find(userId, on: app.db))
                #expect(created.userVersion == initialVersion)

                try await user.bumpVersion(on: app.db)
                let updated = try #require(try await User.find(userId, on: app.db))
                #expect(updated.userVersion != initialVersion)
                #expect(updated.userVersion == user.userVersion)
            } catch {
                _ = try? await user.delete(on: app.db)
                _ = try? await credentials.delete(on: app.db)
                throw error
            }

            _ = try? await user.delete(on: app.db)
            _ = try? await credentials.delete(on: app.db)
        }
    }

    @Test("Test Credentials changePassword Updates Hash And Invalidates Sessions")
    func credentialsChangePassword() async throws {
        try await withApp { app in
            let credentials = Credentials(
                email: TestEmail("pwd_change_\(UUID().uuidString.prefix(8))@example.com"),
                passwordHash: PasswordHash.dummy("oldHash")
            )
            try await credentials.save(on: app.db)
            let credId = try credentials.requireID()
            let initialTokenVersion = credentials.tokenVersion

            do {
                try await credentials.changePassword(to: PasswordHash.dummy("newHash"), on: app.db)

                let updated = try #require(try await Credentials.find(credId, on: app.db))
                #expect(updated.passwordHash == "newHash")
                #expect(updated.tokenVersion != initialTokenVersion)
                #expect(updated.tokenVersion == credentials.tokenVersion)
            } catch {
                _ = try? await credentials.delete(on: app.db)
                throw error
            }

            _ = try? await credentials.delete(on: app.db)
        }
    }

    @Test("Test Credentials updateEmail Resets Verification And Invalidates Sessions")
    func credentialsUpdateEmail() async throws {
        try await withApp { app in
            let credentials = Credentials(
                email: TestEmail("initial_\(UUID().uuidString.prefix(8))@itisgalileiroma.it"),
                passwordHash: PasswordHash.dummy("someHash")
            )
            try await credentials.save(on: app.db)
            try await credentials.markEmailAsVerified(on: app.db)
            let credId = try credentials.requireID()
            let initialTokenVersion = credentials.tokenVersion

            #expect(credentials.isEmailVerified == true)

            do {
                let newEmail = "updated_\(UUID().uuidString.prefix(8))@itisgalileiroma.it"
                try await credentials.updateEmail(to: TestEmail(newEmail), on: app.db)

                let updated = try #require(try await Credentials.find(credId, on: app.db))
                #expect(updated.email == newEmail)
                #expect(updated.isEmailVerified == false)
                #expect(updated.tokenVersion != initialTokenVersion)
                #expect(updated.tokenVersion == credentials.tokenVersion)
            } catch {
                _ = try? await credentials.delete(on: app.db)
                throw error
            }

            _ = try? await credentials.delete(on: app.db)
        }
    }

    @Test("Test User changeRole Updates Role And Bumps UserVersion")
    func userChangeRoleUpdatesRoleAndBumpsVersion() async throws {
        try await withApp { app in
            let credentials = Credentials(
                email: TestEmail("role_change_\(UUID().uuidString.prefix(8))@example.com"),
                passwordHash: PasswordHash.dummy()
            )
            try await credentials.save(on: app.db)
            let credId = try credentials.requireID()

            let user = try makeUser(
                name: "Role",
                surname: "Tester",
                username: "roletest_\(UUID().uuidString.prefix(8))",
                role: .student,
                credentialsId: credId
            )
            try await user.save(on: app.db)
            let userId = try user.requireID()
            let initialVersion = user.userVersion

            do {
                try await user.changeRole(to: .teacher, on: app.db)

                let updated = try #require(try await User.find(userId, on: app.db))
                #expect(updated.$role.id == UserRole.teacher.rawValue)
                #expect(updated.roleType == .teacher)
                #expect(updated.userVersion != initialVersion)
                #expect(updated.userVersion == user.userVersion)
            } catch {
                _ = try? await user.delete(on: app.db)
                _ = try? await credentials.delete(on: app.db)
                throw error
            }

            _ = try? await user.delete(on: app.db)
            _ = try? await credentials.delete(on: app.db)
        }
    }

    @Test("Test User changeUsername Updates Username And Bumps UserVersion")
    func userChangeUsernameUpdatesUsernameAndBumpsVersion() async throws {
        try await withApp { app in
            let credentials = Credentials(
                email: TestEmail("username_change_\(UUID().uuidString.prefix(8))@example.com"),
                passwordHash: PasswordHash.dummy()
            )
            try await credentials.save(on: app.db)
            let credId = try credentials.requireID()

            let user = try makeUser(
                name: "Username",
                surname: "Tester",
                username: "initial_\(UUID().uuidString.prefix(8))",
                role: .student,
                credentialsId: credId
            )
            try await user.save(on: app.db)
            let userId = try user.requireID()
            let initialVersion = user.userVersion

            do {
                let newUsername = try Username(raw: "new_\(UUID().uuidString.prefix(8))")
                try await user.changeUsername(to: newUsername, on: app.db)

                let updated = try #require(try await User.find(userId, on: app.db))
                #expect(updated.username == newUsername.value)
                #expect(updated.userVersion != initialVersion)
                #expect(updated.userVersion == user.userVersion)
            } catch {
                _ = try? await user.delete(on: app.db)
                _ = try? await credentials.delete(on: app.db)
                throw error
            }

            _ = try? await user.delete(on: app.db)
            _ = try? await credentials.delete(on: app.db)
        }
    }
}
