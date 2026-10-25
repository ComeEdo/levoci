import Vapor

// MARK: - Registrazione
struct RegisterRequest: ValidatableRequest {
    let name: String
    let surname: String
    let username: String
    let email: String
    private let password: String
    let classId: UUID?

    init(name: String, surname: String, username: String, email: String, password: String, classId: UUID? = nil) {
        self.name = name
        self.surname = surname
        self.username = username
        self.email = email
        self.password = password
        self.classId = classId
    }
    
    // MARK: - Validazione RegisterRequest

    /// Dati di registrazione già sanificati e validati: è l'unico tipo che `register` può usare.
    struct ValidatedRegistration: Sendable {
        let name: PersonName
        let surname: PersonName
        let username: Username
        let email: SchoolEmail
        let password: Password
        let classId: UUID?
    }
    
    /// Sanifica e valida tutti i campi. L'ordine dei controlli determina quale errore vede il client per primo.
    func validated() throws -> ValidatedRegistration {
        let validName = try PersonName(raw: name, field: .name)
        let validSurname = try PersonName(raw: surname, field: .surname)
        let validUsername = try Username(raw: username)
        let validPassword = try Password(raw: password)
        let validEmail = try SchoolEmail(raw: email)

        return ValidatedRegistration(
            name: validName,
            surname: validSurname,
            username: validUsername,
            email: validEmail,
            password: validPassword,
            classId: classId
        )
    }
}

struct RegisterResponse: Content {
    // TODO: valutare se rimuovere `username` dalla risposta (il client lo conosce già, il server lo restituisce solo sanificato con il trim)
    let username: String
}

// MARK: - Verifica Email
/// Query di `GET /emailVerifications?token=...`.
struct EmailVerificationQuery: ValidatableRequest {
    let token: String

    func validated() throws -> VerificationToken {
        try VerificationToken(raw: token)
    }
}

// MARK: - Login
struct LoginRequest: ValidatableRequest {
    let email: String
    private let password: String

    init(email: String, password: String) {
        self.email = email
        self.password = password
    }
    
    struct ValidatedLogin: Sendable {
        let email: SchoolEmail
        let password: LoginPassword
    }
    
    func validated() throws -> ValidatedLogin {
        let validEmail = try SchoolEmail(raw: email)
        let validPassword = try LoginPassword(raw: password)
        return ValidatedLogin(email: validEmail, password: validPassword)
    }
}

struct LoginResponse: Content {
    let authToken: String
    let roleGroups: [RoleGroupDTO]
}

// MARK: - Verifica Username
struct CheckUsernameRequest: ValidatableRequest {
    let username: String
    
    func validated() throws -> Username {
        try Username(raw: username)
    }
}

// MARK: - Selezione Profilo / Get User Token
struct GetTokenAndUserRequestDTO: Content {
    let userId: UUID
}

struct GetTokenAndUserResponseDTO: Content {
    let success: Bool
    let message: String
    let data: UserTokenData
    
    struct UserTokenData: Content {
        let userToken: String
        let mainUser: MainUserData
    }
    
    struct MainUserData: Content {
        let roleId: Int
        let user: UserProfileDTO
    }
}

// MARK: - Token Refresh
struct RefreshTokenResponseDTO: Content {
    let success: Bool
    let message: String
    let data: TokenData
    
    struct TokenData: Content {
        let token: String
    }
}
