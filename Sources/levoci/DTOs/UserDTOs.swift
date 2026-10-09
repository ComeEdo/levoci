import Vapor

// MARK: - Profilo Utente
struct UserProfileDTO: Content {
    let userId: UUID
    let firstName: String
    let lastName: String
    let username: String
    let roleId: Int?
    let profileImageId: UUID?
    let schoolClass: SchoolClassDTO?
}

// MARK: - Raggruppamento per Ruolo (usato in Login)
struct RoleGroupDTO: Content {
    let roleId: Int
    let users: [UserProfileDTO]
}

// MARK: - Risposta Generica Utente
struct StandardUserResponseDTO: Content {
    let success: Bool
    let message: String
}
