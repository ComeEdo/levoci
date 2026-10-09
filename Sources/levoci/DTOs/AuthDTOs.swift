import Vapor

// MARK: - Registrazione
struct RegisterRequest: Content {
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

extension RegisterRequest: ValidatableRequest {
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

// MARK: - Login
struct LoginRequestDTO: Content {
    let email: String
    let password: String
}

struct LoginResponseDTO: Content {
    let success: Bool
    let message: String
    let data: LoginData?
    
    struct LoginData: Content {
        let roleGroups: [RoleGroupDTO]
        let authToken: String
    }
}

// MARK: - Verifica Username
struct CheckUsernameRequestDTO: Content {
    let username: String
}

struct CheckUsernameResponseDTO: Content {
    let success: Bool
    let message: String
    let data: CheckUsernameData
    
    struct CheckUsernameData: Content {
        let exists: Bool
        let username: String?
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
