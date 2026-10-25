import Vapor
import Fluent
import JWT

/// Controller per la gestione dell'autenticazione e delle credenziali
struct AuthController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        // Gruppo /auth pubblico
        let auth = routes.grouped("auth")
        auth.post("registrations", use: register)
        auth.post("sessions", use: login)

        // Gruppo /usernames pubblico
        let usernames = routes.grouped("usernames")
        usernames.post("availability", use: isUsernameAvailable)

        // Gruppo /auth protetto da AuthToken
        let authProtected = auth.grouped(AuthTokenMiddleware())
        authProtected.get("session", use: isAuthTokenValid)
        authProtected.post("userSessions", use: getTokenAndUser)
        authProtected.post("tokens", "refresh", use: refreshAuthToken)
        authProtected.delete("sessions", use: logoutAll)
    }
    
    @Sendable
    func register(req: Request) async throws -> Response {
        let body = try req.validatedBody(RegisterRequest.self)

        let role = body.email.role

        let validClassId: UUID?
        if role == .student {
            guard let classId = body.classId else {
                throw APIError.badRequest("For a student, the class is required")
            }
            guard try await SchoolClass.find(classId, on: req.db) != nil else {
                throw APIError.badRequest("Class UUID does not exist")
            }
            validClassId = classId
        } else {
            validClassId = nil
        }

        async let emailExists = Credentials.query(on: req.db).filter(\.$email == body.email.value).first() != nil
        async let usernameExists = User.query(on: req.db).filter(\.$username == body.username.value).first() != nil

        let (emailTaken, usernameTaken) = try await (emailExists, usernameExists)

        if emailTaken && usernameTaken {
            throw APIError.conflict("Username and email already exist")
        } else if emailTaken {
            throw APIError.conflict("Email already exists")
        } else if usernameTaken {
            throw APIError.conflict("Username already exists")
        }

        let passwordHash = try await body.password.hashed(on: req)

        let credentials: Credentials
        let user: User
        do {
            (credentials, user) = try await req.db.transaction { db -> (Credentials, User) in
                let credentials = Credentials(
                    email: body.email,
                    passwordHash: passwordHash
                )
                try await credentials.save(on: db)
                let credId = try credentials.requireID()

                let user = User(
                    name: body.name,
                    surname: body.surname,
                    username: body.username,
                    role: role,
                    classId: validClassId,
                    credentialsId: credId
                )
                try await user.save(on: db)

                return (credentials, user)
            }
        } catch let error as any DatabaseError where error.isConstraintFailure {
            // Race: un'altra richiesta ha registrato gli stessi dati dopo il controllo preliminare.
            // I vincoli UNIQUE su email e username garantiscono l'integrità; qui si risponde 409 invece di 500.
            throw APIError.conflict("Username or email already exists")
        }

        let userId = try user.requireID()

        let userDir = URL(fileURLWithPath: req.application.directory.workingDirectory).appendingPathComponent("users").appendingPathComponent(userId.uuidString)
        try? FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)

        try await credentials.sendVerificationEmailIfNeeded(req: req)

        req.logger.info("Registrazione completata con successo per userId: \(userId)")

        let response = RegisterResponse(username: user.username)
        return try await response.encodeResponse(status: .created, for: req)
    }

    @Sendable
    func isUsernameAvailable(req: Request) async throws -> HTTPStatus {
        let username = try req.validatedBody(CheckUsernameRequest.self)

        let exists = try await User.query(on: req.db).filter(\.$username == username.value).first() != nil

        guard !exists else {
            throw APIError.conflict("Username already exists")
        }

        return .noContent
    }

    @Sendable
    func login(req: Request) async throws -> Response {
        let body = try req.validatedBody(LoginRequest.self)

        // 1. Carichiamo solo le credenziali: include già passwordHash, isEmailVerified e tokenVersion.
        let credentials = try await Credentials.query(on: req.db)
            .filter(\.$email == body.email.value)
            .first()

        guard let credentials else {
            throw APIError.unauthorized("Unauthorized - Email or password incorrect")
        }

        // 2. Verifica hash della password
        let isPasswordValid: Bool
        do {
            isPasswordValid = try await PasswordHash.verify(body.password, against: credentials.passwordHash, on: req)
        } catch let error as BcryptError {
            // L'hash salvato non è un bcrypt valido (dati corrotti o inseriti a mano): per l'utente è un normale rifiuto,
            // ma va segnalato nei log perché indica un problema sui dati
            req.logger.error("Hash della password non valido per credentialsId \(credentials.id?.uuidString ?? "sconosciuto"): \(error)")
            throw APIError.unauthorized("Unauthorized - Email or password incorrect")
        }
        guard isPasswordValid else {
            throw APIError.unauthorized("Unauthorized - Email or password incorrect")
        }

        // 3. Verifica email: il flag isEmailVerified è già presente sul record credentials (nessuna query extra)
        guard credentials.isEmailVerified else {
            try await credentials.sendVerificationEmailIfNeeded(req: req)
            throw APIError.forbidden("Email not verified, check your inbox")
        }

        let credId = try credentials.requireID()

        // 4. Carichiamo i profili e le relazioni solo per un login autenticato e verificato
        let users = try await User.query(on: req.db)
            .filter(\.$credentials.$id == credId)
            .with(\.$schoolClass) { $0.with(\.$studyField) }
            .all()

        let payload = AuthTokenPayload(credentialsId: credId, authTokenVersion: credentials.tokenVersion)
        let authToken = try await req.jwt.sign(payload)

        let userProfiles = try users.map { user in
            try UserProfileDTO(from: user)
        }

        let roleGroups = Dictionary(grouping: userProfiles, by: { $0.roleId ?? 0 })
            .map { RoleGroupDTO(roleId: $0.key, users: $0.value) }
            .sorted { $0.roleId < $1.roleId }

        req.logger.info("Login completato con successo per credentialsId: \(credId)")

        let response = LoginResponse(authToken: authToken, roleGroups: roleGroups)
        return try await response.encodeResponse(status: .ok, for: req)
    }

    @Sendable
    func isAuthTokenValid(req: Request) async throws -> HTTPStatus {
        let credentialId = try req.auth.require(Credentials.self).requireID()
        req.logger.notice("Auth token verificato con successo per credentialsId: \(credentialId)")
        return .noContent
    }

    @Sendable
    func getTokenAndUser(req: Request) async throws -> Response {
        // TODO: Implementare rilascio UserToken per lo specifico profilo selezionato
        throw Abort(.notImplemented)
    }

    @Sendable
    func refreshAuthToken(req: Request) async throws -> Response {
        // TODO: Implementare refresh dell'AuthToken
        throw Abort(.notImplemented)
    }

    @Sendable
    func logoutAll(req: Request) async throws -> HTTPStatus {
        let credentials = try req.auth.require(Credentials.self)
        let credentialsId = try credentials.requireID()

        try await credentials.invalidateAllSessions(on: req.db)

        req.logger.info("Logout da tutti i dispositivi completato per credentialsId: \(credentialsId)")

        return .noContent
    }
}
